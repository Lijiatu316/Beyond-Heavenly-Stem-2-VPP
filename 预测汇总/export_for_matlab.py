# -*- coding: utf-8 -*-
"""
export_for_matlab.py — 将预测汇总中的模型参数和预测数据导出为 MATLAB 可读的 CSV
==================================================================================
用法: python export_for_matlab.py
输出:
  - 预测汇总/matlab_input/pv_params.csv         光伏模型物理参数
  - 预测汇总/matlab_input/tidal_params.csv       潮汐电站参数
  - 预测汇总/matlab_input/wind_model_config.csv  风电模型配置摘要
  - 预测汇总/matlab_input/scenario_24h.csv       24h仿真场景数据(辐照度/风速/温度/负荷/潮汐)
  - 预测汇总/matlab_input/wind_power_24h.csv     24h风电LightGBM预测值(参考)
  - 预测汇总/matlab_input/pv_power_24h.csv       24h光伏物理模型预测值(参考)
"""

import json
import os
import struct
import sys
import zlib
from pathlib import Path

import numpy as np
import pandas as pd

# ---- 路径配置 ----
BASE_DIR = Path(__file__).resolve().parent
OUT_DIR = BASE_DIR / "matlab_input"
OUT_DIR.mkdir(exist_ok=True)


# ---- 内联函数 (从 最终模型.py 提取，避免中文文件名导入问题) ----
def _apply_limit_equation(pred_arr, wind_arr, limit_dict, train_max_wind, global_max_p):
    """风电预测功率物理上限截断"""
    pred_cut = np.array(pred_arr, dtype=float).copy()
    step = 0.05  # WIND_BIN_WIDTH
    global_max = float(global_max_p)
    max_wind = float(train_max_wind)
    for idx, wind_v in enumerate(wind_arr):
        w_scalar = float(wind_v)
        bin_v = np.round(w_scalar / step) * step
        bin_scalar = float(bin_v)
        if bin_scalar in limit_dict:
            _, wind_upper = limit_dict[bin_scalar]
        else:
            wind_upper = global_max
        if w_scalar < 0.5:
            wind_upper = 0.0
        elif w_scalar > max_wind:
            wind_upper = global_max
        final_upper = min(float(wind_upper), global_max)
        pred_cut[idx] = np.clip(pred_cut[idx], 0.0, final_upper)
    return pred_cut

# ============================================================
# 1. 提取光伏模型物理参数 (从 pv_power_model.bin)
# ============================================================
def extract_pv_params():
    print("【1/5】提取光伏模型物理参数...")
    bin_path = BASE_DIR / "光伏" / "pv_power_model.bin"
    raw = bin_path.read_bytes()

    MAGIC = b"PVPHYMODEL01"
    HEADER_FORMAT = ">12sI32s"
    HEADER_SIZE = struct.calcsize(HEADER_FORMAT)

    magic, payload_length, _digest = struct.unpack(HEADER_FORMAT, raw[:HEADER_SIZE])
    if magic != MAGIC:
        raise ValueError("光伏模型文件格式不正确")

    payload = raw[HEADER_SIZE:]
    model_data = json.loads(zlib.decompress(payload).decode("utf-8"))
    params = model_data["parameters"]
    metadata = model_data.get("metadata", {})

    # 导出为CSV
    df = pd.DataFrame([
        {"参数名": k, "数值": v, "说明": metadata.get(k, "")}
        for k, v in params.items()
    ])
    df.to_csv(OUT_DIR / "pv_params.csv", index=False, encoding="utf-8-sig")
    print(f"  光伏参数已导出: {OUT_DIR / 'pv_params.csv'} ({len(params)} 项)")
    return params


# ============================================================
# 2. 提取潮汐电站参数 (从 电站参数.xlsx)
# ============================================================
def extract_tidal_params():
    print("【2/5】提取潮汐电站参数...")
    import zipfile
    import xml.etree.ElementTree as ET

    xlsx_path = BASE_DIR / "潮汐" / "电站参数.xlsx"
    z = zipfile.ZipFile(xlsx_path)

    # 读取共享字符串
    shared = z.read("xl/sharedStrings.xml")
    ns = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    ss = ET.fromstring(shared)
    strings = []
    for si in ss.findall(".//s:si", ns):
        t = si.find(".//s:t", ns)
        strings.append(t.text if t is not None else "")

    # 读取sheet数据
    sheet = z.read("xl/worksheets/sheet1.xml")
    rows = ET.fromstring(sheet).findall(".//s:row", ns)

    params = {}
    for row in rows:
        cells = row.findall("s:c", ns)
        key_cell = cells[0]
        val_cell = cells[1] if len(cells) > 1 else None
        key = strings[int(key_cell.find("s:v", ns).text)] if key_cell.get("t") == "s" else key_cell.find("s:v", ns).text
        if val_cell is not None:
            val = strings[int(val_cell.find("s:v", ns).text)] if val_cell.get("t") == "s" else val_cell.find("s:v", ns).text
            try:
                params[key] = float(val)
            except ValueError:
                params[key] = val

    df = pd.DataFrame([{"参数名": k, "数值": v} for k, v in params.items()])
    df.to_csv(OUT_DIR / "tidal_params.csv", index=False, encoding="utf-8-sig")
    print(f"  潮汐参数已导出: {OUT_DIR / 'tidal_params.csv'} ({len(params)} 项)")
    return params


# ============================================================
# 3. 提取风电模型配置摘要
# ============================================================
def extract_wind_config():
    print("【3/5】提取风电模型配置...")
    import pickle
    config_path = BASE_DIR / "风电" / "model" / "model_config.pkl"
    with open(config_path, "rb") as f:
        config = pickle.load(f)

    # 仅导出标量配置（非dict/list的项）
    scalar_config = {}
    for k, v in config.items():
        if isinstance(v, (int, float, str, bool)):
            scalar_config[k] = v

    df = pd.DataFrame([{"参数名": k, "数值": v} for k, v in scalar_config.items()])
    df.to_csv(OUT_DIR / "wind_model_config.csv", index=False, encoding="utf-8-sig")
    print(f"  风电配置已导出: {OUT_DIR / 'wind_model_config.csv'} ({len(scalar_config)} 项)")
    return config


# ============================================================
# 4. 生成24h仿真场景数据
# ============================================================
def generate_scenario_24h(wind_config, pv_params):
    print("【4/5】生成24h仿真场景数据...")

    N = 240  # 每6分钟, 24h
    dt = 0.1  # h
    t = np.linspace(0, 24, N, endpoint=False)

    rng = np.random.RandomState(42)

    # ---- 辐照度 (W/m²) ----
    # 基于光伏模型参考辐照度 G_std 缩放
    G_std = pv_params.get("G_std", 1000)
    G_peak = 900  # 峰值辐照度
    irradiance = G_peak * np.maximum(np.sin(np.pi * (t - 6) / 12), 0) ** 1.5
    irradiance += rng.normal(0, 15, N)  # 云层扰动
    irradiance = np.maximum(irradiance, 0)

    # ---- 温度 (℃) ----
    temperature = 23.5 + 8.5 * np.sin(np.pi * (t - 8) / 12) + rng.normal(0, 1.5, N)
    temperature = np.clip(temperature, -10, 34)  # 光伏模型要求-30~35℃

    # ---- 风速 (m/s) ----
    # 基于风电模型训练集分布：均值~7.7m/s, 范围 0~20.5m/s
    wind_mean = wind_config.get("mean_wind_lag1", 7.7)
    wind_speed = wind_mean + 3 * np.sin(np.pi * (t - 10) / 14)  # 日变化
    # 一阶低通滤波模拟惯性
    alpha = 0.3
    wind_filt = np.zeros(N)
    wind_filt[0] = wind_mean
    noise = rng.normal(0, 1.2, N)
    for k in range(1, N):
        wind_filt[k] = alpha * (wind_speed[k] + noise[k]) + (1 - alpha) * wind_filt[k - 1]
    wind_speed = np.maximum(wind_filt, 0)

    # ---- 刚性负荷 (kW) ----
    # 双峰曲线：早峰10h(85%) + 晚峰18h(100%)
    P_base = 350
    load = P_base + 400 * 0.85 * np.exp(-((t - 10) / 3) ** 2) \
           + 400 * 1.00 * np.exp(-((t - 18) / 3) ** 2) \
           + 400 * 0.60 * np.exp(-((t - 13) / 2) ** 2)
    load += rng.normal(0, 8, N)

    # ---- 潮汐 ----
    # 半日潮 (周期12.42h) + 日不等
    tide_height = 3.5 + 2.5 * np.sin(2 * np.pi * t / 12.42) \
                  + 1.0 * np.sin(2 * np.pi * t / 24.0 + 1.5) \
                  + 0.3 * rng.normal(0, 1, N)

    # ---- 组装DataFrame ----
    df = pd.DataFrame({
        "time_h": t,
        "irradiance_Wm2": np.round(irradiance, 1),
        "temperature_C": np.round(temperature, 1),
        "wind_speed_ms": np.round(wind_speed, 2),
        "load_kW": np.round(load, 1),
        "tide_height_m": np.round(tide_height, 2),
    })
    df.to_csv(OUT_DIR / "scenario_24h.csv", index=False, encoding="utf-8-sig")
    print(f"  场景数据已导出: {OUT_DIR / 'scenario_24h.csv'} ({N} 行 × {len(df.columns)} 列)")
    return df


# ============================================================
# 5. 用训练好的模型生成24h功率预测参考值
# ============================================================
def generate_forecast_reference(scenario_df, wind_config):
    print("【5/5】用训练模型生成24h功率预测...")

    N = len(scenario_df)
    wind_speed = scenario_df["wind_speed_ms"].values
    irradiance = scenario_df["irradiance_Wm2"].values
    temperature = scenario_df["temperature_C"].values

    # ---- 光伏预测 (物理模型) ----
    sys.path.insert(0, str(BASE_DIR / "光伏"))
    from pv_model_engine import load_model
    try:
        pv_model = load_model(str(BASE_DIR / "光伏" / "pv_power_model.bin"))
        pv_power = np.zeros(N)
        for i in range(N):
            # angle ~ 30° midday, 60° morning/evening
            hour = scenario_df["time_h"].iloc[i]
            angle = 60 - 30 * np.cos(np.pi * (hour - 12) / 8)
            angle = np.clip(angle, 5, 85)
            pv_power[i] = pv_model.predict(
                irradiance=float(irradiance[i]),
                incidence_angle=float(angle),
                ambient_temperature=float(temperature[i]),
                wind_speed=float(wind_speed[i]),
            )
    except Exception as e:
        print(f"  光伏预测模型调用失败: {e}")
        print("  将使用简化物理模型替代")
        # 简化模型
        G_std = 1000.0
        Pn = 500.0  # kWp
        eta = 0.92
        pv_power = Pn * np.maximum(irradiance / G_std, 0) * eta

    df_pv = pd.DataFrame({
        "time_h": scenario_df["time_h"],
        "pv_power_kW": np.round(pv_power, 2),
    })
    df_pv.to_csv(OUT_DIR / "pv_power_24h.csv", index=False, encoding="utf-8-sig")

    # ---- 风电预测 (LightGBM模型) ----
    try:
        import pickle
        import lightgbm as lgb

        model_path = BASE_DIR / "风电" / "model" / "wind_power_lgbm_model.pkl"
        with open(model_path, "rb") as f:
            wind_model_lgb = pickle.load(f)

        feat_cols = wind_config["feature_columns"]
        cat_cols = wind_config.get("cat_cols", ["hour", "month", "day_of_week", "quarter"])

        # 构建特征矩阵 (需要滞后特征 → 用地步均值填充前几步)
        X_pred = pd.DataFrame(index=range(N))

        # 时间特征
        hours = scenario_df["time_h"].values
        X_pred["hour"] = (hours % 24).astype(int)
        X_pred["month"] = 7  # July
        X_pred["day_of_week"] = 0  # Monday
        X_pred["quarter"] = 3

        # 风速和衍生特征
        X_pred["Wind Speed (m/s)"] = wind_speed
        wind_dir = 180 + 60 * np.sin(np.pi * hours / 12)  # 模拟风向
        X_pred["wind_dir_sin"] = np.sin(np.radians(wind_dir))
        X_pred["wind_dir_cos"] = np.cos(np.radians(wind_dir))
        X_pred["effective_wind_speed"] = wind_speed * X_pred["wind_dir_cos"]

        # 理论功率曲线 (简化: P_theo ∝ v³ with cut-in/cut-out)
        theo_power = np.zeros(N)
        for i in range(N):
            v = wind_speed[i]
            if v < 3:
                theo_power[i] = 0
            elif v < 12:
                theo_power[i] = v ** 3 * 3600 / (12 ** 3)
            elif v < 25:
                theo_power[i] = 3600
        X_pred["Theoretical_Power_Curve (KWh)"] = theo_power
        X_pred["wind_speed_x_theoretical"] = wind_speed * theo_power

        # 滞后特征 (用地步均值)
        for lag in [1, 2, 3]:
            X_pred[f"wind_speed_lag{lag}"] = wind_config.get(f"mean_wind_lag{lag}", wind_speed.mean())
            X_pred[f"power_lag{lag}"] = wind_config.get(f"mean_power_lag{lag}", theo_power.mean())
            X_pred[f"effective_wind_lag{lag}"] = wind_config.get(f"mean_eff_lag{lag}", wind_speed.mean())

        # 确保特征列完整
        for col in feat_cols:
            if col not in X_pred.columns:
                X_pred[col] = 0

        X_pred = X_pred[feat_cols].copy()

        # 分类特征
        for col in cat_cols:
            if col in X_pred.columns:
                X_pred[col] = X_pred[col].astype("category")

        # 预测
        wind_power_lgb = wind_model_lgb.predict(X_pred)

        # 应用物理限幅（内联自最终模型.py）
        wind_power_lgb = _apply_limit_equation(
            wind_power_lgb, wind_speed,
            wind_config["wind_power_range_dict"],
            wind_config["train_max_wind"],
            wind_config["max_theo_train"],
        )

    except Exception as e:
        print(f"  风电LightGBM预测失败: {e}")
        print("  将使用简化物理模型替代")
        # 简化三段式功率曲线
        wind_power_lgb = np.zeros(N)
        for i in range(N):
            v = wind_speed[i]
            if v < 3:
                wind_power_lgb[i] = 0
            elif v < 12:
                wind_power_lgb[i] = 0.5 * 1.225 * 5000 * 0.45 * v ** 3 * 0.95 / 1000
            elif v < 25:
                wind_power_lgb[i] = 600  # 额定
            else:
                wind_power_lgb[i] = 0

    df_wind = pd.DataFrame({
        "time_h": scenario_df["time_h"],
        "wind_power_kW": np.round(wind_power_lgb, 2),
    })
    df_wind.to_csv(OUT_DIR / "wind_power_24h.csv", index=False, encoding="utf-8-sig")

    print(f"  光伏预测已导出: {OUT_DIR / 'pv_power_24h.csv'} ({N} 行)")
    print(f"  风电预测已导出: {OUT_DIR / 'wind_power_24h.csv'} ({N} 行)")
    print(f"\n==== 全部数据导出完成 ====")
    print(f"输出目录: {OUT_DIR}")


# ============================================================
# 主流程
# ============================================================
if __name__ == "__main__":
    print("=" * 60)
    print("  预测汇总 → MATLAB 仿真数据导出")
    print("=" * 60)

    pv_params = extract_pv_params()
    tidal_params = extract_tidal_params()
    wind_config = extract_wind_config()
    scenario_df = generate_scenario_24h(wind_config, pv_params)
    generate_forecast_reference(scenario_df, wind_config)

    print("\n下一步: 在MATLAB中运行 run_mode_island()")
    print(f"仿真将自动读取 {OUT_DIR} 中的数据")
