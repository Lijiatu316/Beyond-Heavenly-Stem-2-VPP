# 超越乙号新能源虚拟电站 — 项目整体架构

> 去中心化虚拟电厂协同自治调控仿真平台
>
> 版本：v1.0 | 更新：2026-08-04

---

## 目录

1. [项目概述](#1-项目概述)
2. [目录结构](#2-目录结构)
3. [三层架构总览](#3-三层架构总览)
4. [MATLAB 仿真层](#4-matlab-仿真层)
5. [Python 预测层](#5-python-预测层)
6. [Web 可视化层](#6-web-可视化层)
7. [数据流](#7-数据流)
8. [双模式运行逻辑](#8-双模式运行逻辑)
9. [设计系统](#9-设计系统)
10. [部署与运行](#10-部署与运行)

---

## 1. 项目概述

**超越乙号新能源虚拟电站**是一个完整的去中心化虚拟电厂（VPP）协同自治调控仿真平台。项目覆盖从能源预测、时序仿真、分布式优化到 Web 可视化的全链路。

### 核心能力

| 能力 | 实现 |
|------|------|
| 多能源建模 | 光伏（物理模型）、风电（LightGBM）、潮汐（江厦电站参数）、燃气轮机、储能 |
| 孤岛自治仿真 | fmincon 六维优化 + PI 调频 + Q-V 调压，240 步 × 0.1h 时序 |
| 分布式协同仿真 | ADMM 去中心化多 VPP 优化 + 邻域功率互济 |
| 智能预测 | LightGBM 风电预测 + 光伏物理模型，分钟级精度 |
| Web 控制舱 | Chart.js 五图联动 + 玻璃面板 + 事件时间线 + 模式切换 |
| 设计系统 | CSS 变量驱动的明暗双主题 + Outfit/JetBrains Mono 字体 + 玻璃材质面板 |

### 技术栈

```
┌─────────────────────────────────────────────────────┐
│  MATLAB R2023b+  │  Python 3.x    │  HTML/CSS/JS    │
│  Optimization    │  LightGBM      │  Chart.js 4.4   │
│  Toolbox         │  NumPy         │  PapaParse 5.4  │
│  fmincon (SQP)   │  tkinter       │  Tailwind CSS   │
└─────────────────────────────────────────────────────┘
```

---

## 2. 目录结构

```
超越乙号新能源虚拟电站/
│
├── ARCHITECTURE.md                    ← 本文件：项目架构文档
├── DESIGN.md                          ← 设计系统规范
├── README.md                          ← 项目说明
│
├── 01_主程序入口/                     ← ★ 主控层
│   ├── main_VPP_simulation.m          │  总仿真入口（当前调用孤岛模式）
│   ├── run_mode_island.m              │  孤岛自治模式完整仿真（240步循环）
│   ├── run_mode_cooperate.m           │  协同调度模式完整仿真（ADMM+互济）
│   └── param_global_config.m          │  全局参数配置 + CSV自动加载
│
├── 02_算法核心模块/                   ← ★ 决策层
│   ├── mode_judge_comm.m              │  通信质量→模式判別（孤岛/协同）
│   ├── 01_离线自治调度/               │
│   │   ├── vpp_island_ems.m           │  fmincon 六维优化（每VPP独立求解）
│   │   ├── freq_volt_pi_control.m     │  PI调频 + Q-V调压 + UFLS保护
│   │   └── island_constraint_calc.m   │  安全约束边界计算
│   ├── 02_分布式协同调度/             │
│   │   ├── admm_distributed_opt.m     │  ADMM多VPP协同优化（150行）
│   │   ├── neighbor_data_exchange.m   │  邻域P2P数据交换（边际成本/报价）
│   │   └── coop_constraint_allocate.m │  分布式备用容量分配
│   └── 03_统一约束处理/               │
│       └── power_limit_handler.m      │  统一约束限幅（7道检查）
│
├── 03_系统建模与设备/                 ← ★ 物理层
│   ├── 01_分布式电源模型/
│   │   ├── pv_model.m                 │  光伏物理模型（辐照度→功率）
│   │   ├── wind_model.m               │  风电三段式功率曲线
│   │   ├── tidal_model.m              │  潮汐单库单向发电（江厦电站）
│   │   └── gas_unit_model.m           │  燃气轮机+爬坡约束
│   ├── 02_储能系统模型/
│   │   └── battery_bms_model.m        │  储能SOC递推+充放电保护
│   ├── 03_柔性负荷模型/
│   │   ├── interrupt_load.m           │  可中断负荷+补偿成本
│   │   └── shiftable_load.m           │  可平移负荷+时间窗
│   ├── 04_通信网络仿真/
│   │   ├── comm_delay_sim.m           │  延迟/丢包仿真
│   │   └── comm_fault_trigger.m       │  故障注入（按时间表）
│   └── 05_功率预测模块/
│       └── power_forecast.m           │  持续性/移动平均/趋势预测
│
├── 04_辅助工具/                       ← ★ 支撑层
│   ├── 01_绘图可视化/
│   │   ├── plot_freq_power.m          │  频率/功率时序图
│   │   ├── plot_soc_trade.m           │  SOC轨迹+互济交互图
│   │   └── plot_index_bar.m           │  经济指标柱状图
│   ├── 02_数据存储导出/
│   │   ├── export_csv_data.m          │  导出CSV（island_timeseries等）
│   │   └── save_result_mat.m          │  保存.mat结果
│   ├── 03_告警与指标计算/
│   │   ├── calculate_eco_index.m      │  六维经济指标计算
│   │   └── safety_alarm_check.m       │  安全告警统计
│   └── 04_测试小脚本/
│       ├── test_island_freq.m         │  孤岛频率阶跃响应测试
│       └── test_admm_iter.m           │  ADMM收敛测试（桩）
│
├── 预测汇总/                          ← ★ Python预测层
│   ├── export_for_matlab.py           │  Python→MATLAB数据桥梁
│   ├── matlab_input/                  │  导出的CSV输入文件（6个）
│   │   ├── scenario_24h.csv           │  240行：辐照度/温度/风速/负荷/潮高
│   │   ├── pv_params.csv              │  光伏物理参数
│   │   ├── tidal_params.csv           │  潮汐电站参数
│   │   ├── wind_model_config.csv      │  风电模型配置
│   │   ├── pv_power_24h.csv           │  参考光伏预测
│   │   └── wind_power_24h.csv         │  参考风电预测（LightGBM）
│   ├── 光伏/
│   │   ├── pv_model_engine.py         │  光伏物理模型引擎
│   │   ├── pv_power_model.bin         │  序列化模型参数
│   │   └── 容量可调的光伏实时预测APP.py │  光伏预测交互应用
│   ├── 风电/
│   │   ├── 最终模型.py                │  风电LightGBM模型
│   │   ├── 风电实时预测APP.py         │  风电预测交互应用
│   │   └── model/                     │  LightGBM模型文件(.pkl)
│   └── 潮汐/
│       ├── 潮汐发电弹窗.py             │  潮汐参数交互应用
│       └── 电站参数.xlsx               │  江厦潮汐电站真实参数
│
├── 仿真结果/                          ← MATLAB输出
│   ├── island_timeseries.csv          │  孤岛仿真时序（240行×28列）
│   ├── island_indices.csv             │  全局经济指标
│   └── island_vpp_indices.csv         │  逐VPP指标对比
│
├── Web 前端（根目录）
│   ├── index.html                     ← 落地页（Immersion Design）
│   ├── dashboard.html                 ← 孤岛自治控制舱
│   ├── dashboard_cooperate.html       ← 协同调度控制舱
│   ├── island_timeseries.csv          → 孤岛控制舱数据源
│   └── cooperate_timeseries.csv       → 协同控制舱数据源
│
└── 文档/
    ├── 项目说明文档.md
    ├── 断网仿真说明文档.md
    └── 榜题原文_CP-202613.md
```

---

## 3. 三层架构总览

```
┌──────────────────────────────────────────────────────────────┐
│                      WEB 可视化层                             │
│  index.html  →  dashboard.html  ⇄  dashboard_cooperate.html  │
│  Outfit + JetBrains Mono | Chart.js | PapaParse | CSS Tokens │
├──────────────────────────────────────────────────────────────┤
│                           ▲                                  │
│                      CSV  数据流                               │
│                           ▼                                  │
├──────────────────────────────────────────────────────────────┤
│                    MATLAB 仿真引擎层                           │
│  ┌──────────────┐   ┌──────────────────────────────────┐    │
│  │  孤岛自治模式  │   │        分布式协同模式              │    │
│  │  fmincon SQP  │   │  ADMM迭代 + 邻域互济 + 功率交换   │    │
│  │  PI调频+Q-V   │   │  Lagrange乘子 + 全局收敛          │    │
│  │  独立优化      │   │  通信质量→自动模式切换            │    │
│  └──────────────┘   └──────────────────────────────────┘    │
├──────────────────────────────────────────────────────────────┤
│                           ▲                                  │
│                    参数注入 (CSV)                              │
│                           ▼                                  │
├──────────────────────────────────────────────────────────────┤
│                    Python 智能预测层                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │ 光伏物理  │  │ 风电LGBM │  │ 潮汐参数  │  │ 预测APP     │  │
│  │ 模型      │  │ 预测     │  │ 模型     │  │ (tkinter)  │  │
│  └──────────┘  └──────────┘  └──────────┘  └────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### 层间接口

```
Python预测 → export_for_matlab.py → matlab_input/*.csv
                                           ↓
                                    param_global_config.m (自动加载)
                                           ↓
                                    MATLAB仿真 (240步循环)
                                           ↓
                              export_csv_data.m → island_timeseries.csv
                              run_mode_cooperate → cooperate_timeseries.csv
                                           ↓
                              fetch() → PapaParse → Chart.js
```

---

## 4. MATLAB 仿真层

### 4.1 主仿真循环 (240 步)

```
for t = 1:240 (dt = 0.1h, 总计24h)
  │
  ├─ [2.1] 设备出力计算
  │   pv_model()  → P_pv_avail
  │   wind_model() → P_wind_avail
  │   tidal_model() → P_tidal_avail
  │
  ├─ [2.2] 负荷计算
  │   cfg.data.load_rigid(t, :)
  │
  ├─ [2.3] 功率预测
  │   power_forecast() → 持续性/移动平均/趋势
  │
  ├─ [2.4] 通信检测 + 模式判断
  │   comm_delay_sim() → delay/loss/quality矩阵
  │   mode_judge_comm() → ISLAND | COOPERATE
  │
  ├─ [2.5] 安全约束
  │   island_constraint_calc() → P_min/max边界
  │
  ├─ [2.6] 调度优化 ★核心差异★
  │   ┌─ ISLAND:  vpp_island_ems() → fmincon 6维独立优化
  │   └─ COOPERATE: admm_distributed_opt() → ADMM迭代
  │                  neighbor_data_exchange() → 边际成本/报价
  │                  coop_constraint_allocate() → 备用分配
  │
  ├─ [2.7] PI调频修正
  │   freq_volt_pi_control() → 频率修正 + Q-V调压
  │
  ├─ [2.8] 约束限幅
  │   power_limit_handler() → 7道安全检查
  │
  ├─ [2.9] 状态更新
  │   gas_unit_model() / battery_bms_model() → 更新P_gas_prev, SOC
  │
  └─ [2.10] 记录历史
       hist.P_pv/P_wind/P_gas/P_bat/SOC/freq/cost...
```

### 4.2 孤岛模式优化 (vpp_island_ems.m)

```matlab
决策变量 (6维): x = [P_gas, P_bat, P_shed, P_curtail_pv, P_curtail_wind, P_curtail_tidal]

目标函数: min (燃料成本 + 切负荷惩罚 + 弃风光潮惩罚)

约束:
  - 功率平衡: P_renew + P_gas + P_bat = P_load - P_shed - P_curtail
  - 设备限幅: lb ≤ x ≤ ub
  - SOC保护: 通过island_constraint_calc限制充放电max

求解器: fmincon (SQP, 200迭代, 中心差分)
```

### 4.3 协同模式优化 (admm_distributed_opt.m)

```matlab
ADMM迭代:
  for iter = 1:max_iter
    1. 各VPP独立求解: min f_v(x) + (ρ/2)||x - consensus + u||²
    2. 全局共识更新: z = 邻域加权平均（考虑通信质量衰减）
    3. 对偶变量: u^k+1 = u^k + x^k+1 - z^k+1
    4. 收敛检查: primal_res < tol && dual_res < tol
  end

通信拓扑:  VPP1 ↔ VPP2, VPP1 ↔ VPP3  (邻接矩阵)
           VPP2 与 VPP3 无直连

衰减因子:  链路质量 < 0.5 → 报价被噪声污染
```

### 4.4 设备模型参数

| 设备 | 模型类型 | 关键参数 |
|------|---------|---------|
| 光伏 | 物理模型 | 辐照度、温度、入射角 → P_pv |
| 风电 | 三段式功率曲线 | 切入2.5m/s、额定12m/s、切出25m/s |
| 潮汐 | 单库单向（江厦） | 库容10^6m³、水头3-5m、5×640kW |
| 燃气 | 爬坡约束 | P_min=30% P_max, Ramp=40% P_max/h |
| 储能 | SOC递推 | SOC₀=0.5, η_ch=η_dis=0.92, SOC∈[0.1,0.9] |

---

## 5. Python 预测层

### 5.1 光伏预测

```
pv_model_engine.py
  ├── 物理模型：辐照度 × 面板面积 × 效率系数 × 温度修正
  ├── 参数来源：pv_power_model.bin (序列化)
  └── 输出：pv_power_24h.csv, pv_params.csv
```

### 5.2 风电预测

```
最终模型.py
  ├── LightGBM 回归模型
  ├── 输入特征：风速、风向、温度、气压、历史出力
  ├── 模型文件：model/wind_power_lgbm_model.pkl
  └── 输出：wind_power_24h.csv, wind_model_config.csv
```

### 5.3 数据桥梁

```
export_for_matlab.py
  ├── 读取各模型输出
  ├── 整合为 matlab_input/scenario_24h.csv
  │   列：时间 | 辐照度 | 温度 | 风速 | 负荷 | 潮高
  └── 输出到 预测汇总/matlab_input/
```

---

## 6. Web 可视化层

### 6.1 页面体系

```
index.html (落地页)
  │
  ├── [进入控制舱] → dashboard.html (孤岛自治控制舱)
  │                      │
  │                      ├─ Header 模式切换 ←→ dashboard_cooperate.html
  │                      ├─ 实时运行态势 + 能源拓扑 SVG
  │                      ├─ VPP 节点健康面板
  │                      ├─ 6 项 KPI 指标卡
  │                      ├─ 5 张 Chart.js 图表
  │                      └─ 事件时间线
  │
  └── [协同调度] → dashboard_cooperate.html (协同调度控制舱)
                       ├─ ADMM 优化态势
                       ├─ VPP 间功率交换图
                       ├─ ADMM 收敛曲线
                       ├─ 模式性能对比面板
                       └─ 孤岛/协同模式切换
```

### 6.2 技术栈

| 层 | 技术 | 用途 |
|----|------|------|
| 样式 | Tailwind CSS (CDN) | 工具类布局 |
| 字体 | Outfit + JetBrains Mono | 正文 + 数据 |
| 图表 | Chart.js 4.4 | 5张交互图表 |
| 数据 | PapaParse 5.4 | CSV客户端解析 |
| 动效 | CSS Animations + requestAnimationFrame | 入场/视差/loading |
| 主题 | CSS自定义属性 | 明暗双模式 |

### 6.3 数据加载流程

```
浏览器 fetch('island_timeseries.csv')
  → Papa.parse(text, {header:true, dynamicTyping:true})
  → 动态匹配列名 (Object.keys → find by pattern)
  → 聚合计算 (PV/Wind/Gas/Load/Shed/Curtail → 6项KPI)
  → textContent直接赋值
  → Chart.js初始化 5 张图表
  → 隐藏loading spinner
```

### 6.4 设计系统 (DESIGN.md)

```
色彩:
  canvas: #060912  表面: #0a101b  面板: rgba(15,23,36,.74)
  主色(蓝): #4f8cff  青色: #22d3ee  绿色: #34d399
  琥珀: #fbbf24  红色: #fb5a67  紫色: #8b8fff

字体层级:
  Display: Outfit 800 clamp(2.8rem,6vw,5.2rem)
  Heading: Outfit 600-720
  Body: Outfit 400
  Data: JetBrains Mono 650-750

圆角: 6/8/10/12/16px (仪表盘) / 落地页混合
间距: 4px基准 → 8/12/16/20/24/32/48/64px
动画: cubic-bezier(0.16,1,0.3,1) · 150-400ms
```

---

## 7. 数据流

### 7.1 完整数据流

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Python预测    │────→│ MATLAB仿真    │────→│ Web控制舱     │
│              │     │              │     │              │
│ 光伏物理模型  │     │ fmincon/ADMM │     │ Chart.js     │
│ 风电LGBM     │ CSV │ 240步循环     │ CSV │ PapaParse    │
│ 潮汐参数     │     │ PI调频       │     │ 事件时间线    │
└──────────────┘     └──────────────┘     └──────────────┘
       │                    │                     │
       ▼                    ▼                     ▼
  matlab_input/      island_timeseries.csv    浏览器渲染
  scenario_24h.csv   cooperate_timeseries.csv  五图联动
```

### 7.2 CSV 数据格式

**island_timeseries.csv** (240行 × 28列):
```
Time_h | VPP1_PV_kW ... VPP3_PV_kW | VPP1_Wind_kW ... |
VPP1_Gas_kW ... | VPP1_Bat_kW ... | VPP1_Load_kW ... |
VPP1_Shed_kW ... | VPP1_Curtail_kW ... |
VPP1_SOC ... | VPP1_Freq_Hz ...
```

**cooperate_timeseries.csv** (240行 × 33列):
```
[同 island_timeseries.csv 的前 28 列]
+ VPP12_Exchange_kW | VPP23_Exchange_kW | VPP31_Exchange_kW
+ ADMM_Residual | Comm_Delay_ms
```

---

## 8. 双模式运行逻辑

### 8.1 模式判定

```
mode_judge_comm(comm_state)
  │
  ├─ 任一链路 delay > 0.1s → ISLAND
  ├─ 任一链路 loss > 0.3   → ISLAND
  ├─ 平均质量 < 0.5        → ISLAND
  └─ 以上皆不满足          → COOPERATE
```

### 8.2 孤岛 vs 协同

| 维度 | 孤岛自治 | 分布式协同 |
|------|---------|-----------|
| 优化方式 | fmincon 独立求解 | ADMM 迭代收敛 |
| VPP间通信 | 无 | 邻接矩阵拓扑 |
| 功率流动 | 无互济 | 低成本→高成本售电 |
| 频率控制 | PI 本地调频 | PI + 邻域辅助 |
| 触发条件 | 通信故障 | 通信正常 |
| 备用容量 | 本地自备 | 分布式分配 |
| 状态色 | 红橙 (#fb5a67) | 绿 (#34d399) |

---

## 9. 设计系统

详见 [DESIGN.md](DESIGN.md) — 9 节完整规范，包含：

- 色彩令牌（语义命名）
- 字体层级（Outfit + JetBrains Mono）
- 组件样式（按钮、面板、KPI卡、图表）
- 布局原则（12列网格、间距尺度）
- 深度与高度（z-index层级）
- 暗色模式协议（CSS变量双主题）
- 动效系统（四层级：页面/卡片/数据/状态）
- 响应式断点（1280/980/640px）
- Agent Prompt Guide

---

## 10. 部署与运行

### 10.1 MATLAB 仿真

```matlab
% 在 MATLAB 中将项目根目录添加到路径
addpath(genpath('C:\Users\Lenovo\Desktop\超越乙号新能源虚拟电站'))

% 运行孤岛模式
run_mode_island()

% 运行协同模式（需先生成 island_timeseries.csv）
run_mode_cooperate()

% 输出文件：
%   island_timeseries.csv    → 孤岛控制舱数据源
%   cooperate_timeseries.csv → 协同控制舱数据源
```

### 10.2 Web 前端

```bash
cd "C:\Users\Lenovo\Desktop\超越乙号新能源虚拟电站"
python -m http.server 8080
```

访问:
- `http://localhost:8080/index.html` — 落地页
- `http://localhost:8080/dashboard.html` — 孤岛控制舱
- `http://localhost:8080/dashboard_cooperate.html` — 协同控制舱

### 10.3 项目仓库

```
GitHub: https://github.com/Lijiatu316/Beyond-Heavenly-Stem-2-VPP
```

---

## 附录 A: 文件统计

| 类别 | 文件数 | 总行数（约） |
|------|--------|------------|
| MATLAB (.m) | 30 | 3,500+ |
| Python (.py) | 6 | 800+ |
| HTML/CSS/JS | 3 | 2,500+ |
| CSV 数据 | 15+ | 240行×多个 |
| 文档 (.md/.docx) | 8 | — |
| 设计系统 | 1 | 200+ |

## 附录 B: 关键算法索引

| 算法 | 文件 | 核心函数 |
|------|------|---------|
| fmincon SQP | vpp_island_ems.m | `fmincon(@objective, x0, ...)` |
| ADMM | admm_distributed_opt.m | `solve_local_admm()` × Nv |
| PI调频 | freq_volt_pi_control.m | Droop + PI积分 |
| LightGBM | 最终模型.py | `lgb.predict(features)` |
| 光伏物理 | pv_model_engine.py | 辐照度→电流→功率 |
| 潮汐单库 | tidal_model.m | Q = f(水头, 库容) |
| 模式判断 | mode_judge_comm.m | 通信矩阵→模式标签 |
| 经济指标 | calculate_eco_index.m | 消纳率/成本/频率/可靠性 |
