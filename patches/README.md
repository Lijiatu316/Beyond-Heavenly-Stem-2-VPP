# VPP仿真系统补丁代码包 v1.0

## 概述

本补丁包针对"去中心化虚拟电厂协同自治调控仿真系统"的六项关键仿真能力短板，提供**即插即用**的增强模块。所有补丁均为**非侵入式**设计——无需修改原始代码，通过回调函数和配置开关集成。

## 补丁清单

| 编号 | 补丁名称 | 解决的核心问题 | 关键文件 |
|------|---------|---------------|---------|
| 01 | 亚秒级仿真步长 | 将仿真步长从6分钟提升至秒级/亚秒级 | `subsecond_main.m` |
| 02 | 真实电站数据接入 | 替换数学合成数据，接入国内电站实测数据 | `fetch_renewable_data.py` |
| 03 | 真实通信损伤模型 | 延迟-丢包相关性建模（Gilbert-Elliott信道） | `correlated_comm_model.m` |
| 04 | VPP通信协议栈 | 实现IEC 61850/Modbus/DNP3协议报文模拟 | `protocol_message_builder.m` |
| 05 | TCP三次握手恢复 | 通信恢复过程建模（SYN/SYN-ACK/ACK+RTO） | `tcp_connection_manager.m` |
| 06 | 动态拓扑路由 | 移动基站/临时中继/故障路由切换 | `dynamic_routing.m` |

## 快速开始

### 1. 配置所有补丁

```matlab
% 在你的仿真入口脚本中，于 param_global_config() 之后添加:
addpath(genpath('patches/'));
cfg = param_global_config();
cfg = patch_config(cfg);  % 统一补丁配置（可选择性激活各补丁）
```

### 2. 选择性激活

```matlab
% 仅激活特定补丁:
cfg.patches.subsecond.enabled   = true;   % 亚秒级仿真
cfg.patches.real_data.enabled   = true;   % 真实数据
cfg.patches.real_comm.enabled   = true;   % 真实通信模型
cfg.patches.protocol.enabled    = true;   % 协议栈
cfg.patches.tcp_handshake.enabled = true; % TCP握手
cfg.patches.dynamic_topo.enabled  = true; % 动态拓扑
```

### 3. 在仿真循环中使用

```matlab
% 替代原 comm_delay_sim() 调用:
if cfg.patches.real_comm.enabled
    comm_state = correlated_comm_model(cfg, t, fault_active, channel_state);
else
    comm_state = comm_delay_sim(cfg, t, fault_active);
end
```

## 兼容性

- MATLAB R2023b+
- Python 3.8+ (仅补丁02需要)
- 所有补丁与原仿真系统完全兼容
- 可在同一仿真中按需组合使用

## 目录结构

```
patches/
├── README.md
├── patch_config.m              # 统一配置入口
├── 01_subsecond_timestep/      # 亚秒级仿真
├── 02_real_data_fetcher/       # 真实数据抓取
├── 03_realistic_comm_model/    # 真实通信建模
├── 04_vpp_protocol_stack/      # 通信协议栈
├── 05_tcp_handshake_recovery/  # TCP握手恢复
└── 06_dynamic_topology/        # 动态拓扑路由
```

## 学术引用

本补丁包为"超越乙号"冯如杯竞赛论文的配套代码。如需在学术论文中引用，请注明：

> [项目团队]. 去中心化虚拟电厂协同自治调控仿真系统 — 通信与拓扑增强补丁包 v1.0. 2026.

---

**版权归属项目团队，仅供学术研究使用。**
