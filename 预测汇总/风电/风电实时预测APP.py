# -*- coding: utf-8 -*-
"""
Created on Fri Jul 20 23:06:20 2026

@author: yukai

风电10分钟功率预测GUI

缓存规则：3组时序，按输入先后顺序存储 [最新lag1, lag2, lag3]

无缓存lag时统一填充0
"""
import sys
import os
import warnings
import numpy as np
import pandas as pd
import joblib
import tkinter as tk
from tkinter import ttk, messagebox

warnings.filterwarnings('ignore')

# ===================== 全局缓存：保存历史[风速,预测功率]，充当滞后特征 =====================
history_cache = []  # 按输入顺序存储，最新数据在列表末尾

# ===================== 路径配置：当前GUI文件同级model文件夹 =====================
CUR_FILE_PATH = os.path.abspath(__file__)
CUR_DIR = os.path.dirname(CUR_FILE_PATH)
MODEL_DIR = os.path.join(CUR_DIR, "model")
MODEL_FILE = os.path.join(MODEL_DIR, "wind_power_lgbm_model.pkl")
CONFIG_FILE = os.path.join(MODEL_DIR, "model_config.pkl")

# 校验模型文件是否存在
if not os.path.exists(MODEL_FILE) or not os.path.exists(CONFIG_FILE):
    msg = f"模型文件缺失！\n检索路径：{MODEL_DIR}\n需要两个文件：\n1. wind_power_lgbm_model.pkl\n2. model_config.pkl"
    messagebox.showerror("文件错误", msg)
    sys.exit(1)

# 加载模型与训练配置
try:
    model = joblib.load(MODEL_FILE)
    cfg = joblib.load(CONFIG_FILE)
except Exception as e:
    messagebox.showerror("模型加载失败", f"读取pkl文件异常：{str(e)}")
    sys.exit(1)

# 提取训练固定参数
WIND_BIN_WIDTH = cfg["WIND_BIN_WIDTH"]
wind_power_range_dict = cfg["wind_power_range_dict"]
train_max_wind = cfg["train_max_wind"]
max_theo_train = cfg["max_theo_train"]

# ===================== 功率上下限截断函数（与训练代码完全一致） =====================
def apply_limit_equation(pred_val, wind_v):
    pred_cut = float(pred_val)
    step = float(WIND_BIN_WIDTH)
    global_max = float(max_theo_train)
    w_scalar = float(wind_v)
    bin_v = np.round(w_scalar / step) * step
    bin_scalar = float(bin_v)

    if bin_scalar in wind_power_range_dict:
        _, wind_upper = wind_power_range_dict[bin_scalar]
    else:
        wind_upper = global_max

    if w_scalar < 0.5:
        wind_upper = 0.0
    elif w_scalar > train_max_wind:
        wind_upper = global_max

    final_upper = min(float(wind_upper), global_max)
    pred_cut = np.clip(pred_cut, 0.0, final_upper)
    return pred_cut

# ===================== 特征构造函数 =====================
def build_single_feature(wind_speed, wind_dir, theo_power,
                         lag1_wind, lag2_wind, lag3_wind,
                         lag1_pow, lag2_pow, lag3_pow):
    wind_dir_sin = np.sin(np.radians(wind_dir))
    wind_dir_cos = np.cos(np.radians(wind_dir))
    effective_wind_speed = wind_speed * wind_dir_cos
    wind_speed_x_theoretical = wind_speed * theo_power

    wind_speed_lag1 = lag1_wind
    wind_speed_lag2 = lag2_wind
    wind_speed_lag3 = lag3_wind

    effective_wind_lag1 = lag1_wind * wind_dir_cos
    effective_wind_lag2 = lag2_wind * wind_dir_cos
    effective_wind_lag3 = lag3_wind * wind_dir_cos

    power_lag1 = lag1_pow
    power_lag2 = lag2_pow
    power_lag3 = lag3_pow

    feat_data = {
        'Wind Speed (m/s)': [wind_speed],
        'effective_wind_speed': [effective_wind_speed],
        'Theoretical_Power_Curve (KWh)': [theo_power],
        'hour': [0],
        'month': [0],
        'day_of_week': [0],
        'quarter': [0],
        'wind_dir_sin': [wind_dir_sin],
        'wind_dir_cos': [wind_dir_cos],
        'wind_speed_x_theoretical': [wind_speed_x_theoretical],
        'wind_speed_lag1': [wind_speed_lag1],
        'wind_speed_lag2': [wind_speed_lag2],
        'wind_speed_lag3': [wind_speed_lag3],
        'effective_wind_lag1': [effective_wind_lag1],
        'effective_wind_lag2': [effective_wind_lag2],
        'effective_wind_lag3': [effective_wind_lag3],
        'power_lag1': [power_lag1],
        'power_lag2': [power_lag2],
        'power_lag3': [power_lag3],
    }
    X = pd.DataFrame(feat_data)
    for col in ['hour', 'month', 'day_of_week', 'quarter']:
        X[col] = X[col].astype('category')
    return X

# ===================== 预测统一入口 =====================
def get_predict_result(wind_speed, wind_dir, theo_power,
                        lag1_wind, lag2_wind, lag3_wind,
                        lag1_pow, lag2_pow, lag3_pow):
    X_input = build_single_feature(wind_speed, wind_dir, theo_power,
                                   lag1_wind, lag2_wind, lag3_wind,
                                   lag1_pow, lag2_pow, lag3_pow)
    pred_raw = model.predict(X_input)[0]
    pred_final = apply_limit_equation(pred_raw, wind_speed)
    return round(pred_raw, 2), round(pred_final, 2)

# ===================== GUI界面类 =====================
class WindPredictGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("风电实时功率预测系统（自动缓存历史）")
        self.root.geometry("620x420")

        main_frame = ttk.Frame(root, padding=15)
        main_frame.pack(fill=tk.BOTH, expand=True)

        row = 0
        # 仅3项必填输入
        ttk.Label(main_frame, text="当前风速(m/s)：").grid(row=row, column=0, sticky="w", pady=6)
        self.ent_ws = ttk.Entry(main_frame, width=24)
        self.ent_ws.grid(row=row, column=1, padx=12)
        row += 1

        ttk.Label(main_frame, text="风向(°)：").grid(row=row, column=0, sticky="w", pady=6)
        self.ent_wd = ttk.Entry(main_frame, width=24)
        self.ent_wd.grid(row=row, column=1, padx=12)
        row += 1

        ttk.Label(main_frame, text="理论功率曲线值(kW)：").grid(row=row, column=0, sticky="w", pady=6)
        self.ent_theo = ttk.Entry(main_frame, width=24)
        self.ent_theo.grid(row=row, column=1, padx=12)
        row += 1

        # 预测按钮
        ttk.Button(main_frame, text="开始预测", command=self.do_predict).grid(row=row, column=0, columnspan=2, pady=15)
        row += 1

        # 单次预测结果
        ttk.Label(main_frame, text="本次预测结果：", font=("微软雅黑", 10, "bold")).grid(row=row, column=0, sticky="w")
        self.res_text = tk.StringVar()
        ttk.Label(main_frame, textvariable=self.res_text, font=("微软雅黑", 10)).grid(row=row, column=1, sticky="w")
        row += 2

        # 历史3条数据展示
        ttk.Label(main_frame, text="最近3条历史缓存数据（风速m/s | 预测功率kW）：", font=("微软雅黑", 10, "bold")).grid(row=row, column=0, columnspan=2, sticky="w")
        row += 1
        self.history_text = tk.StringVar(value="暂无历史数据")
        ttk.Label(main_frame, textvariable=self.history_text, foreground="#222").grid(row=row, column=0, columnspan=2, sticky="w")

    def do_predict(self):
        global history_cache
        try:
            # 读取当前输入
            ws = float(self.ent_ws.get().strip())
            wd = float(self.ent_wd.get().strip())
            theo = float(self.ent_theo.get().strip())

            # 从缓存取历史，不足补0
            lag1_wind, lag1_pow = history_cache[-1] if len(history_cache)>=1 else (0.0, 0.0)
            lag2_wind, lag2_pow = history_cache[-2] if len(history_cache)>=2 else (0.0, 0.0)
            lag3_wind, lag3_pow = history_cache[-3] if len(history_cache)>=3 else (0.0, 0.0)

            # 执行预测
            raw_out, final_out = get_predict_result(
                ws, wd, theo,
                lag1_wind, lag2_wind, lag3_wind,
                lag1_pow, lag2_pow, lag3_pow
            )

            # 将本次【当前风速 + 预测功率】存入缓存，作为下一轮的滞后数据
            history_cache.append([ws, final_out])

            # 更新本次预测结果
            self.res_text.set(f"约束后预测功率：{final_out} kW | 原始输出：{raw_out} kW")

            # 组装最近3条历史展示文本
            display_list = history_cache[-3:]
            display_str = ""
            for idx, item in enumerate(display_list, 1):
                wind_val, pow_val = item
                display_str += f"第{len(display_list)-idx+1}条：风速{wind_val}m/s，出力{pow_val}kW\n"
            self.history_text.set(display_str.strip())

            # 不清除输入框，保留上次输入内容

        except ValueError:
            messagebox.showerror("输入错误", "风速、风向、理论功率必须填写有效数字！")
        except Exception as e:
            messagebox.showerror("预测失败", f"程序异常：{str(e)}")

if __name__ == "__main__":
    root = tk.Tk()
    app = WindPredictGUI(root)
    root.mainloop()
