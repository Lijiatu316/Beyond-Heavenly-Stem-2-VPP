# -*- coding: utf-8 -*-
"""
Created on Tue Jul 21 14:39:12 2026
@author: 42042
潮汐电站发电量预测模型
功能：
1. 弹窗录入电站名称+物理参数，支持一键填充默认值
2. 读取Excel【某某水电站信息】自动加载电站名称与全部参数
3. 主界面潮汐数据输入框空白手动填写
4. 未加载电站参数禁止计算
"""
import tkinter as tk
from tkinter import messagebox, Toplevel
import pandas as pd

# ======================== 默认基准物理参数（一键填充用） ========================
default_rho = 1025        # 海水密度 kg/m3
default_g = 9.81          # 重力加速度 m/s2
default_S = 5.3e6         # 库区面积 m2
default_eta = 0.78        # 综合效率
default_loss_factor = 0.95# 综合损耗系数
default_unit_num = 5      # 机组台数
default_unit_pow = 640    # 单机额定功率 kW
default_H_min = 1.0       # 最小启动水头 m
default_Q_max = 120       # 最大过流流量 m3/s

# Excel配置
EXCEL_FILE_PATH = "电站参数.xlsx"
SHEET_NAME = "某某水电站信息"

# 全局存储电站参数（Excel读取后自动更新station_name）
station_name = ""
rho = default_rho
g = default_g
S = default_S
eta = default_eta
loss_factor = default_loss_factor
unit_number = default_unit_num
unit_power = default_unit_pow
H_min = default_H_min
Q_max = default_Q_max
P_rated = unit_number * unit_power
# ======================================================================

def open_station_param_window(main_win):
    """模态弹窗：手动录入电站名称与物理参数，支持填充默认值"""
    global station_name, rho, g, S, eta, loss_factor, unit_number, unit_power, H_min, Q_max, P_rated
    param_win = Toplevel(main_win)
    param_win.title("录入水电站基础信息")
    param_win.geometry("530x490")
    param_win.grab_set()

    frame_input = tk.Frame(param_win)
    frame_input.pack(pady=12)

    # 电站名称
    tk.Label(frame_input, text="水电站名称", width=21).grid(row=0, column=0, pady=4)
    entry_name = tk.Entry(frame_input, width=23)
    entry_name.grid(row=0, column=1)

    tk.Label(frame_input, text="海水密度 rho(kg/m³)", width=21).grid(row=1, column=0, pady=4)
    entry_rho = tk.Entry(frame_input, width=23)
    entry_rho.grid(row=1, column=1)

    tk.Label(frame_input, text="重力加速度 g(m/s²)", width=21).grid(row=2, column=0, pady=4)
    entry_g = tk.Entry(frame_input, width=23)
    entry_g.grid(row=2, column=1)

    tk.Label(frame_input, text="库区面积 S(m²)", width=21).grid(row=3, column=0, pady=4)
    entry_S = tk.Entry(frame_input, width=23)
    entry_S.grid(row=3, column=1)

    tk.Label(frame_input, text="综合效率 eta", width=21).grid(row=4, column=0, pady=4)
    entry_eta = tk.Entry(frame_input, width=23)
    entry_eta.grid(row=4, column=1)

    tk.Label(frame_input, text="损耗系数 loss_factor", width=21).grid(row=5, column=0, pady=4)
    entry_loss = tk.Entry(frame_input, width=23)
    entry_loss.grid(row=5, column=1)

    tk.Label(frame_input, text="机组台数", width=21).grid(row=6, column=0, pady=4)
    entry_unit_num = tk.Entry(frame_input, width=23)
    entry_unit_num.grid(row=6, column=1)

    tk.Label(frame_input, text="单机功率(kW)", width=21).grid(row=7, column=0, pady=4)
    entry_unit_pow = tk.Entry(frame_input, width=23)
    entry_unit_pow.grid(row=7, column=1)

    tk.Label(frame_input, text="最小启动水头(m)", width=21).grid(row=8, column=0, pady=4)
    entry_Hmin = tk.Entry(frame_input, width=23)
    entry_Hmin.grid(row=8, column=1)

    tk.Label(frame_input, text="最大允许流量(m³/s)", width=21).grid(row=9, column=0, pady=4)
    entry_Qmax = tk.Entry(frame_input, width=23)
    entry_Qmax.grid(row=9, column=1)

    # 一键填充默认参数
    def fill_all_default():
        entry_name.delete(0, tk.END)
        entry_rho.delete(0, tk.END)
        entry_g.delete(0, tk.END)
        entry_S.delete(0, tk.END)
        entry_eta.delete(0, tk.END)
        entry_loss.delete(0, tk.END)
        entry_unit_num.delete(0, tk.END)
        entry_unit_pow.delete(0, tk.END)
        entry_Hmin.delete(0, tk.END)
        entry_Qmax.delete(0, tk.END)

        entry_rho.insert(0, str(default_rho))
        entry_g.insert(0, str(default_g))
        entry_S.insert(0, str(default_S))
        entry_eta.insert(0, str(default_eta))
        entry_loss.insert(0, str(default_loss_factor))
        entry_unit_num.insert(0, str(default_unit_num))
        entry_unit_pow.insert(0, str(default_unit_pow))
        entry_Hmin.insert(0, str(default_H_min))
        entry_Qmax.insert(0, str(default_Q_max))

    # 保存手动输入参数
    def save_param_data():
        global station_name, rho, g, S, eta, loss_factor, unit_number, unit_power, H_min, Q_max, P_rated
        name = entry_name.get().strip()
        if not name:
            messagebox.showwarning("填写提示", "请输入水电站名称！")
            return
        try:
            station_name = name
            rho = float(entry_rho.get())
            g = float(entry_g.get())
            S = float(entry_S.get())
            eta = float(entry_eta.get())
            loss_factor = float(entry_loss.get())
            unit_number = int(entry_unit_num.get())
            unit_power = float(entry_unit_pow.get())
            H_min = float(entry_Hmin.get())
            Q_max = float(entry_Qmax.get())
            P_rated = unit_number * unit_power
            messagebox.showinfo("参数加载成功", f"已载入电站：{station_name}\n返回主窗口输入潮汐数据计算")
            param_win.destroy()
        except ValueError:
            messagebox.showerror("数值错误", "所有物理参数必须填写有效数字！")

    btn_box = tk.Frame(param_win)
    btn_box.pack(pady=12)
    tk.Button(btn_box, text="一键填充默认参数", command=fill_all_default, width=15).grid(row=0, column=0, padx=5)
    tk.Button(btn_box, text="确认保存参数", command=save_param_data, width=15).grid(row=0, column=1, padx=5)
    tk.Button(btn_box, text="关闭窗口", command=param_win.destroy, width=10).grid(row=0, column=2, padx=5)

def load_excel_station():
    """读取Excel，自动更新电站名称station_name与全部物理参数"""
    global station_name, rho, g, S, eta, loss_factor, unit_number, unit_power, H_min, Q_max, P_rated
    try:
        df = pd.read_excel(EXCEL_FILE_PATH, sheet_name=SHEET_NAME)
        data_dict = dict(zip(df["参数名称"], df["数值"]))
        # Excel中读取电站名称，自动覆盖全局station_name
        station_name = str(data_dict["station_name"])
        rho = float(data_dict["rho"])
        g = float(data_dict["g"])
        S = float(data_dict["S"])
        eta = float(data_dict["eta"])
        loss_factor = float(data_dict["loss_factor"])
        unit_number = int(data_dict["unit_number"])
        unit_power = float(data_dict["unit_power"])
        H_min = float(data_dict["H_min"])
        Q_max = float(data_dict["Q_max"])
        P_rated = unit_number * unit_power
        messagebox.showinfo("Excel导入成功", f"电站名称：{station_name}\n总装机：{P_rated} kW")
    except FileNotFoundError:
        messagebox.showerror("文件错误", f"未找到文件：{EXCEL_FILE_PATH}")
    except KeyError as err:
        messagebox.showerror("表格缺失字段", f"Excel缺少参数：{err}\n请确认包含 station_name 字段")
    except Exception as err:
        messagebox.showerror("读取异常", str(err))

def tidal_power_calc(H, dHdt, time):
    if H < H_min:
        return 0, 0, 0
    dhdt_s = abs(dHdt) / 3600
    Q = S * dhdt_s
    if Q > Q_max:
        Q = Q_max
    P = eta * rho * g * Q * H / 1000
    P = P * loss_factor
    if P > P_rated:
        P = P_rated
    if P < 0:
        P = 0
    E = P * time
    return P, E, Q

def calc_result():
    if not station_name:
        messagebox.showwarning("操作提醒", "请先录入电站参数（手动填写/读取Excel）！")
        return
    try:
        H = float(entry_H.get())
        dHdt = float(entry_dHdt.get())
        time = float(entry_time.get())
        P, E, Q = tidal_power_calc(H, dHdt, time)
        output_box.delete("1.0", tk.END)
        text = f"""
========================
{station_name} 潮汐发电预测结果
========================
潮汐自然输入数据：
有效潮差: {H:.3f} m
潮差变化速度: {dHdt:.3f} m/h
发电时长: {time:.2f} h
------------------------
水力计算结果：
过流流量: {Q:.2f} m³/s
输出功率: {P:.2f} kW
总发电量: {E:.2f} kWh
------------------------
当前电站配置参数：
总装机容量: {P_rated} kW
综合效率: {eta}
最大允许流量: {Q_max} m³/s
最小启动水头: {H_min} m
库区面积: {S:.0f} m²
========================
"""
        output_box.insert(tk.END, text)
    except ValueError:
        messagebox.showerror("输入错误", "潮差、潮速、发电时间必须填写有效数字！")

# 主窗口
root = tk.Tk()
root.title("潮汐电站发电量预测工具")
root.geometry("590x590")

tk.Label(root, text="潮汐发电计算工具", font=("微软雅黑", 16)).pack(pady=8)

top_btn_frame = tk.Frame(root)
top_btn_frame.pack(pady=6)
tk.Button(top_btn_frame, text="手动录入电站参数", width=19, height=2, command=lambda: open_station_param_window(root)).grid(row=0, column=0, padx=7)
tk.Button(top_btn_frame, text="读取Excel电站参数", width=19, height=2, command=load_excel_station, bg="#cce5ff").grid(row=0, column=1, padx=7)

tk.Label(root, text="===== 输入潮汐自然数据 =====", font=("微软雅黑", 13)).pack(pady=9)
tide_frame = tk.Frame(root)
tide_frame.pack()

tk.Label(tide_frame, text="有效潮差 H(m)", width=23).grid(row=0, column=0, pady=5)
entry_H = tk.Entry(tide_frame, width=19)
entry_H.grid(row=0, column=1)

tk.Label(tide_frame, text="潮差变化速度 dH/dt(m/h)", width=23).grid(row=1, column=0, pady=5)
entry_dHdt = tk.Entry(tide_frame, width=19)
entry_dHdt.grid(row=1, column=1)

tk.Label(tide_frame, text="发电时间(h)", width=23).grid(row=2, column=0, pady=5)
entry_time = tk.Entry(tide_frame, width=19)
entry_time.grid(row=2, column=1)

tk.Button(root, text="开始计算发电量", width=17, height=2, command=calc_result).pack(pady=16)

tk.Label(root, text="计算输出结果", font=("微软雅黑", 14)).pack()
output_box = tk.Text(root, height=17, width=70)
output_box.pack()

root.mainloop()