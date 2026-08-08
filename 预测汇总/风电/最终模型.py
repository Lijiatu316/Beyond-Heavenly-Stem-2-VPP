# -*- coding: utf-8 -*-
"""
Created on Mon Jul 20 23:41:50 2026

@author: yukai

最终版本（我希望）：根据不同数据，训练各自的预测模型，并且人机交互，
弄出APP的感觉
"""
import sys
import os
import warnings
warnings.filterwarnings('ignore')
# 依赖校验
required = {
    'pandas': 'pandas', 'numpy': 'numpy', 'lightgbm': 'lightgbm',
    'sklearn': 'scikit-learn', 'matplotlib': 'matplotlib',
}
missing = []
for mod, pkg in required.items():
    try:
        __import__(mod)
    except ImportError:
        missing.append(pkg)
if missing:
    print(f"缺失依赖，请执行: pip install {' '.join(missing)}")
    sys.exit(1)

import pandas as pd
import numpy as np
import lightgbm as lgb
import matplotlib.pyplot
from sklearn.metrics import r2_score, mean_absolute_error, mean_squared_error

# ===================== 全局路径与可调参数 =====================
BASE_DIR = 'C:/Users/yukai/Desktop/新能源虚拟电站/风力输出'
TRAIN_DATA_PATH = f'{BASE_DIR}/DATA/整理_风力发电机SCADA数据集改.xlsx'
TEST_DATA_PATH = f'{BASE_DIR}/DATA/测试集数据.xlsx'
OUTPUT_DIR = f'{BASE_DIR}/output'
os.makedirs(OUTPUT_DIR, exist_ok=True)

# 绘图中文设置
plt = matplotlib.pyplot
plt.rcParams['font.sans-serif'] = ['SimHei', 'Microsoft YaHei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

# 可调业务参数（易懂命名）
ERROR_THRESHOLD = 100        # 功率误差阈值(kW)
WIND_BIN_WIDTH = 0.05         # 风速分档宽度(m/s)
POWER_LOW_PERCENT = 0.005    # 同风速正常功率下限1%分位数
POWER_HIGH_PERCENT = 0.995   # 同风速正常功率上限99%分位数
# 统一功率完整列名
POWER_COL = 'LV ActivePower (kW)'

# ===================== 模型评估指标计算 =====================
def calculate_metrics(y_true, y_pred, name):
    r2 = r2_score(y_true, y_pred)
    mae = mean_absolute_error(y_true, y_pred)
    rmse = np.sqrt(mean_squared_error(y_pred, y_true))
    mask_nonzero = (y_true > 1e-6)
    yt_valid = y_true[mask_nonzero].copy()
    yp_valid = y_pred[mask_nonzero].copy()
    mape = np.mean(np.abs((yt_valid - yp_valid) / yt_valid)) * 100
    abs_err = np.abs(y_true - y_pred)
    correct = np.sum(abs_err <= ERROR_THRESHOLD)
    total = len(y_true)
    acc = correct / total * 100
    return {
        "name": name,
        "r2": r2,
        "mae": mae,
        "rmse": rmse,
        "mape": mape,
        "acc_75kw": acc,
        "correct": correct,
        "total": total
    }

# ===================== 数据读取、特征工程 =====================
def load_and_process_data(file_path):
    excel_file = pd.ExcelFile(file_path)
    print(f"\n文件 {file_path} 工作表列表：{excel_file.sheet_names}")
    df = pd.read_excel(file_path)
    df['datetime'] = pd.to_datetime(df['Date/Time'], format='%d %m %Y %H:%M')
    df = df.sort_values('datetime').reset_index(drop=True)

    # 时间周期分类特征
    df['hour'] = df['datetime'].dt.hour.astype('category')
    df['month'] = df['datetime'].dt.month.astype('category')
    df['day_of_week'] = df['datetime'].dt.dayofweek.astype('category')
    df['quarter'] = df['datetime'].dt.quarter.astype('category')

    # 风向三角函数、垂直有效风速
    df['wind_dir_sin'] = np.sin(np.radians(df['Wind Direction (°)']))
    df['wind_dir_cos'] = np.cos(np.radians(df['Wind Direction (°)']))
    df['effective_wind_speed'] = df['Wind Speed (m/s)'] * df['wind_dir_cos']
    df['wind_speed_x_theoretical'] = df['Wind Speed (m/s)'] * df['Theoretical_Power_Curve (KWh)']

    # 生成10/20/30分钟滞后特征
    for lag in [1, 2, 3]:
        df[f'wind_speed_lag{lag}'] = df['Wind Speed (m/s)'].shift(lag)
        df[f'power_lag{lag}'] = df[POWER_COL].shift(lag)
        df[f'effective_wind_lag{lag}'] = df['effective_wind_speed'].shift(lag)

    df = df.dropna(axis=0, how='any').reset_index(drop=True)

    feature_columns = [
        'Wind Speed (m/s)', 'effective_wind_speed', 'Theoretical_Power_Curve (KWh)',
        'hour', 'month', 'day_of_week', 'quarter',
        'wind_dir_sin', 'wind_dir_cos', 'wind_speed_x_theoretical',
        'wind_speed_lag1', 'wind_speed_lag2', 'wind_speed_lag3',
        'effective_wind_lag1', 'effective_wind_lag2', 'effective_wind_lag3',
        'power_lag1', 'power_lag2', 'power_lag3',
    ]
    target = POWER_COL
    X = df[feature_columns].copy()
    y = df[target].copy()
    max_theo = df['Theoretical_Power_Curve (KWh)'].max()
    wind_series = df['Wind Speed (m/s)'].values.copy()
    return X, y, df, max_theo, feature_columns, wind_series

# ===================== 基于训练集构建各风速正常功率上下限 =====================
def build_wind_power_range(train_df, bin_width):
    df_copy = train_df.copy()
    df_copy['wind_bin'] = np.round(df_copy['Wind Speed (m/s)'] / bin_width) * bin_width
    stat_df = df_copy.groupby('wind_bin')[POWER_COL].agg(
        power_low=lambda x: float(x.quantile(POWER_LOW_PERCENT)),
        power_high=lambda x: float(x.quantile(POWER_HIGH_PERCENT))
    ).reset_index()
    range_dict = {}
    for _, row in stat_df.iterrows():
        bin_key = float(row['wind_bin'])
        low_val = float(row['power_low'])
        high_val = float(row['power_high'])
        range_dict[bin_key] = (low_val, high_val)
    train_max_wind = float(df_copy['Wind Speed (m/s)'].max())
    return range_dict, train_max_wind

# ===================== 测试集故障/异常样本清洗 =====================
def clean_test_abnormal(test_df, wind_range_dict, bin_width):
    df = test_df.copy()
    df['wind_bin'] = np.round(df['Wind Speed (m/s)'] / bin_width) * bin_width
    df['is_abnormal'] = False
    df['abnormal_reason'] = ""
    for idx, row in df.iterrows():
        w_bin_scalar = float(row['wind_bin'])
        real_p_scalar = float(row[POWER_COL])
        if w_bin_scalar in wind_range_dict:
            p_low, p_high = wind_range_dict[w_bin_scalar]
        else:
            p_low = 0.0
            p_high = 99999.0
        if real_p_scalar < p_low:
            df.at[idx, 'is_abnormal'] = True
            df.at[idx, 'abnormal_reason'] = "风速正常但出力过低，判定停机/故障"
        if real_p_scalar > p_high:
            df.at[idx, 'is_abnormal'] = True
            df.at[idx, 'abnormal_reason'] = "出力超出该风速正常上限"
    normal_df = df[df['is_abnormal'] == False].copy()
    abnormal_df = df[df['is_abnormal'] == True].copy()
    return normal_df, abnormal_df

# ===================== 预测功率物理上限截断 =====================
def apply_limit_equation(pred_arr, wind_arr, limit_dict, train_max_wind, global_max_p):
    pred_cut = pred_arr.copy()
    step = float(WIND_BIN_WIDTH)
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

# ===================== 主运行入口 =====================
if __name__ == "__main__":
    # 1 加载训练集
    print("【步骤1】加载训练集数据")
    X_train, y_train, df_train, max_theo_train, feat_cols, wind_train = load_and_process_data(TRAIN_DATA_PATH)
    print(f"训练集有效样本量: {len(X_train)}")

    # 2 加载原始完整测试集
    print("\n【步骤2】加载原始完整测试集")
    X_test_all, y_test_all, df_test_all, max_theo_test, _, wind_test_all = load_and_process_data(TEST_DATA_PATH)
    print(f"原始测试总样本量: {len(df_test_all)}")

    # 3 计算各风速档位正常功率区间
    wind_power_range_dict, train_max_wind = build_wind_power_range(df_train, WIND_BIN_WIDTH)

    # 4 拆分测试集：正常工况 / 故障异常样本
    df_test_normal, df_test_abnormal = clean_test_abnormal(df_test_all, wind_power_range_dict, WIND_BIN_WIDTH)
    print(f"\n【测试集异常清洗完成】")
    print(f"正常发电样本：{len(df_test_normal)} 条")
    print(f"停机/故障异常样本：{len(df_test_abnormal)} 条")

    # 导出故障样本CSV
    if len(df_test_abnormal) > 0:
        abnormal_cols = [
            'datetime','Wind Speed (m/s)','Wind Direction (°)',POWER_COL,
            'wind_speed_lag1','wind_speed_lag2','wind_speed_lag3','is_abnormal','abnormal_reason'
        ]
        df_test_abnormal[abnormal_cols].to_csv(
            f'{OUTPUT_DIR}/测试集_异常停机故障样本.csv',
            encoding='utf-8-sig', index=False
        )
        print("异常故障样本已导出")

    # 提取清洗后正常测试集（绘图、评估全部只用这套）
    X_test_clean = df_test_normal[feat_cols].copy()
    y_test_clean = df_test_normal[POWER_COL].copy()
    wind_test_clean = df_test_normal['Wind Speed (m/s)'].values.copy()

    # 5 LightGBM模型训练
    print("\n【步骤3】LightGBM模型训练")
    model = lgb.LGBMRegressor(
        n_estimators=1300,
        learning_rate=0.06,
        num_leaves=50,
        max_depth=-1,
        min_child_samples=20,
        reg_alpha=0.1,
        reg_lambda=1.0,
        subsample=0.8,
        colsample_bytree=0.8,
        random_state=42,
        verbose=-1,
        force_col_wise=True
    )
    model.fit(X_train, y_train)

    # 预测
    y_train_pred_raw = model.predict(X_train)
    y_train_pred = apply_limit_equation(y_train_pred_raw, wind_train, wind_power_range_dict, train_max_wind, max_theo_train)

    y_test_clean_pred_raw = model.predict(X_test_clean)
    y_test_clean_pred = apply_limit_equation(y_test_clean_pred_raw, wind_test_clean, wind_power_range_dict, train_max_wind, max_theo_train)

    # 三套评估指标
    train_metrics = calculate_metrics(y_train, y_train_pred, "训练集")
    test_clean_metrics = calculate_metrics(y_test_clean, y_test_clean_pred, "清洗后正常测试集")

    print("\n========== 训练集评估指标 ==========")
    print(f"R² = {train_metrics['r2']:.4f} | MAE = {train_metrics['mae']:.2f} kW")
    print(f"±{ERROR_THRESHOLD}kW准确率 = {train_metrics['acc_75kw']:.2f}%")

    print("\n========== 清洗后正常测试集 ==========")
    print(f"R² = {test_clean_metrics['r2']:.4f} | MAE = {test_clean_metrics['mae']:.2f} kW")
    print(f"±{ERROR_THRESHOLD}kW准确率 = {test_clean_metrics['acc_75kw']:.2f}%")

    # 特征重要度
    importance_df = pd.DataFrame({
        '特征': feat_cols,
        '特征贡献度': model.feature_importances_
    }).sort_values('特征贡献度', ascending=False).head(15)
    print("\n========== TOP15特征贡献 ==========")
    print(importance_df.to_string(index=False))

    # 正常样本误差表
    df_test_normal['真实功率(kW)'] = y_test_clean
    df_test_normal['预测功率(kW)'] = y_test_clean_pred
    df_test_normal['绝对误差(kW)'] = np.abs(df_test_normal['真实功率(kW)'] - df_test_normal['预测功率(kW)'])
    error_df = df_test_normal[df_test_normal['绝对误差(kW)'] > ERROR_THRESHOLD].copy()
    error_cols = [
        'datetime','Wind Speed (m/s)','Wind Direction (°)',
        'wind_speed_lag1','wind_speed_lag2','wind_speed_lag3',
        '真实功率(kW)','预测功率(kW)','绝对误差(kW)'
    ]
    error_out = error_df[error_cols].rename(columns={
        'Wind Speed (m/s)':'当前风速(m/s)',
        'Wind Direction (°)':'当前风向(°)',
        'wind_speed_lag1':'前10min风速(m/s)',
        'wind_speed_lag2':'前20min风速(m/s)',
        'wind_speed_lag3':'前30min风速(m/s)'
    }).round(2)
    error_out.to_csv(f'{OUTPUT_DIR}/测试集_误差超标正常样本.csv', encoding='utf-8-sig', index=False)

    # ===================== 绘图模块（全部测试图使用清洗后数据，补全标点） =====================
    # 图1：训练集散点
    fig1, ax1 = plt.subplots(figsize=(8, 8))
    max_train_val = max(y_train.max(), y_train_pred.max())
    x_line_train = np.linspace(0, max_train_val, 1000)
    ax1.scatter(y_train, y_train_pred, alpha=0.3, s=1, color='steelblue', label='训练集样本')
    ax1.plot(x_line_train, x_line_train, linestyle='--', color='r', linewidth=1.5, label='理想拟合 y=x')
    ax1.plot(x_line_train, x_line_train + ERROR_THRESHOLD, linestyle='-.', color='green', linewidth=1, label=f'+{ERROR_THRESHOLD}kW误差上限')
    ax1.plot(x_line_train, x_line_train - ERROR_THRESHOLD, linestyle='-.', color='orange', linewidth=1, label=f'-{ERROR_THRESHOLD}kW误差下限')
    ax1.set_xlabel('实际功率 (kW)')
    ax1.set_ylabel('仿真预测功率 (kW)')
    ax1.set_title(f'训练集风电功率全量分布\nR²={train_metrics["r2"]:.4f}  ±{ERROR_THRESHOLD}kW准确率={train_metrics["acc_75kw"]:.2f}%')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    fig1.savefig(f'{OUTPUT_DIR}/scatter_train.png', dpi=150, bbox_inches='tight')
    plt.show()

    # 图2：清洗后测试集散点（修复缺少标点，图例标题完整）
    fig2, ax2 = plt.subplots(figsize=(8, 8))
    max_test_val = max(y_test_clean.max(), y_test_clean_pred.max())
    x_line_test = np.linspace(0, max_test_val, 1000)
    ax2.scatter(y_test_clean, y_test_clean_pred, alpha=0.4, s=1, color='black', label='测试集样本')
    ax2.plot(x_line_test, x_line_test, linestyle='--', color='r', linewidth=1.5, label='理想拟合 y=x')
    ax2.plot(x_line_test, x_line_test + ERROR_THRESHOLD, linestyle='-.', color='green', linewidth=1, label=f'+{ERROR_THRESHOLD}kW误差上限')
    ax2.plot(x_line_test, x_line_test - ERROR_THRESHOLD, linestyle='-.', color='orange', linewidth=1, label=f'-{ERROR_THRESHOLD}kW误差下限')
    ax2.set_xlabel('实际功率 (kW)')
    ax2.set_ylabel('仿真预测功率 (kW)')
    ax2.set_title(f'独立测试集风电功率分布（剔除故障样本）\nR²={test_clean_metrics["r2"]:.4f}  ±{ERROR_THRESHOLD}kW准确率={test_clean_metrics["acc_75kw"]:.2f}%')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    fig2.savefig(f'{OUTPUT_DIR}/scatter_test_clean.png', dpi=150, bbox_inches='tight')
    plt.show()

    # 图3：特征贡献柱状图
    fig3, ax3 = plt.subplots(figsize=(10, 6))
    top_sort = importance_df.sort_values('特征贡献度', ascending=True)
    colors = plt.cm.Blues(np.linspace(0.4, 0.9, len(top_sort)))
    ax3.barh(range(len(top_sort)), top_sort['特征贡献度'], color=colors, edgecolor='black', linewidth=0.5)
    ax3.set_yticks(range(len(top_sort)))
    ax3.set_yticklabels(top_sort['特征'])
    ax3.set_xlabel('特征贡献度（分裂增益）')
    ax3.set_title('各物理特征对发电仿真的贡献程度TOP15')
    ax3.grid(True, alpha=0.3, axis='x')
    fig3.savefig(f'{OUTPUT_DIR}/feature_importance_top15.png', dpi=150, bbox_inches='tight')
    plt.show()

    # 图4：清洗后测试时序曲线（使用清洗后数据）
    fig4, ax4 = plt.subplots(figsize=(14, 5))
    ax4.plot(range(len(y_test_clean)), y_test_clean, label='测试集真实功率', linewidth=0.85, alpha=0.9)
    ax4.plot(range(len(y_test_clean_pred)), y_test_clean_pred, label='测试集仿真功率', linewidth=0.85, alpha=0.9)
    ax4.set_xlabel('时序样本序号')
    ax4.set_ylabel('发电功率 (kW)')
    ax4.set_title(f'独立测试集全量时序出力对比（剔除故障样本） | 测试集±{ERROR_THRESHOLD}kW准确率={test_clean_metrics["acc_75kw"]:.2f}%')
    ax4.legend()
    ax4.grid(True, alpha=0.3)
    fig4.savefig(f'{OUTPUT_DIR}/timeseries_test_clean.png', dpi=150, bbox_inches='tight')
    plt.show()
    
    
    #=================后端：保存训练模型与配置=====================================
    import joblib
    save_config = {
    "wind_power_range_dict": wind_power_range_dict,
    "train_max_wind": train_max_wind,
    "max_theo_train": max_theo_train,
    "feature_columns": feat_cols,
    "WIND_BIN_WIDTH": WIND_BIN_WIDTH,
    "ERROR_THRESHOLD": ERROR_THRESHOLD,
    "POWER_COL": POWER_COL,
    "cat_cols": ['hour', 'month', 'day_of_week', 'quarter'], 
    # 训练集均值填充滞后特征
    "mean_wind_lag1": df_train['wind_speed_lag1'].mean(),
    "mean_wind_lag2": df_train['wind_speed_lag2'].mean(),
    "mean_wind_lag3": df_train['wind_speed_lag3'].mean(),
    "mean_eff_lag1": df_train['effective_wind_lag1'].mean(),
    "mean_eff_lag2": df_train['effective_wind_lag2'].mean(),
    "mean_eff_lag3": df_train['effective_wind_lag3'].mean(),
    "mean_power_lag1": df_train['power_lag1'].mean(),
    "mean_power_lag2": df_train['power_lag2'].mean(),
    "mean_power_lag3": df_train['power_lag3'].mean(),
    "mean_theo_power": df_train['Theoretical_Power_Curve (KWh)'].mean()
    }
    joblib.dump(model, f'{OUTPUT_DIR}/model/wind_power_lgbm_model.pkl')
    joblib.dump(save_config, f'{OUTPUT_DIR}/model/model_config.pkl')
    print(f"\n模型文件已保存至 {OUTPUT_DIR} 文件夹！")
    print("生成文件：wind_power_lgbm_model.pkl、model_config.pkl")
    
    print("\n==== 全部运行完成 ====")
    print("输出文件：")
    print("1. 测试集_异常停机故障样本.csv")
    print("2. 测试集_误差超标正常样本.csv")
    print("3. 四张图表：训练集散点、清洗测试集散点、特征图、清洗测试时序图")
    
