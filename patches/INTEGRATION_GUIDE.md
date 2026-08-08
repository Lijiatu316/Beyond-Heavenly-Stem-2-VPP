# VPP仿真系统补丁集成指南

## 概览

本文档说明如何将6个补丁模块集成到现有的"去中心化虚拟电厂协同自治调控仿真系统"中，以最小的代码改动实现仿真能力升级。

## 核心设计原则

1. **非侵入式**: 所有补丁为独立文件，不修改任何原始代码
2. **开关控制**: 通过 `cfg.patches.xxx.enabled` 按需激活
3. **向后兼容**: 禁用所有补丁时，系统回退到原始行为
4. **渐进增强**: 可单独启用任意补丁组合

## 快速集成 (3步)

### Step 1: 添加路径

在你的仿真入口脚本 (`main_VPP_simulation.m`) 开头添加:

```matlab
% 添加补丁路径
addpath(genpath('patches/'));
```

### Step 2: 加载补丁配置

```matlab
cfg = param_global_config();   % 原始配置
cfg = patch_config(cfg);       % 叠加补丁配置

% 按需激活补丁
cfg.patches.subsecond.enabled   = true;   % 亚秒级仿真
cfg.patches.real_data.enabled   = false;  % 真实数据 (需Python环境)
cfg.patches.real_comm.enabled   = true;   % 真实通信模型
cfg.patches.protocol.enabled    = true;   % 协议栈
cfg.patches.tcp_handshake.enabled = true; % TCP握手
cfg.patches.dynamic_topo.enabled  = true; % 动态拓扑
```

### Step 3: 在仿真循环中调用

```matlab
% --- 替代原始通信检测 ---
if cfg.patches.real_comm.enabled
    [comm_state, channel_state] = correlated_comm_model(cfg, t, fault_active, channel_state);
else
    comm_state = comm_delay_sim(cfg, t, fault_active);
end

% --- 替代原始故障检测 ---
if cfg.patches.dynamic_topo.enabled
    [routing, fault_active] = dynamic_routing('process_events', routing, t_now_h);
    topo = routing.current_topo;
end

% --- 协议栈集成 ---
if cfg.patches.protocol.enabled
    % 构造VPP间通信报文
    msg = protocol_message_builder('IEC61850_MMS', src, dst, payload, cfg);
    % msg.latency_ms 包含协议处理延迟
end

% --- TCP握手集成 ---
if cfg.patches.tcp_handshake.enabled
    tcp = tcp_connection_manager('step', tcp, fault_active, t_now_s, dt_s);
    % tcp.conn(i,j) 指示TCP连接状态
end
```

## 各补丁单独集成详解

### 补丁01: 亚秒级仿真步长

**适用场景**: 需要仿真秒级/亚秒级动态（频率调节、保护动作、通信时序）

**集成方案A — 完全替换** (推荐用于全新仿真):
```matlab
results = subsecond_main(@run_mode_island);   % 孤岛模式
results = subsecond_main(@run_mode_cooperate); % 协同模式
```

**集成方案B — 局部集成** (仅在内环需要快动态):
```matlab
scfg = subsecond_config(cfg);
data_fast = data_interpolator(cfg, hist_data, t_outer, scfg);
% data_fast 包含亚秒级插值数据，供快动态模块使用
```

**关键参数**:
- `cfg.patches.subsecond.dt_fast`: 内环步长 (默认0.5s)
- `cfg.patches.subsecond.fast_dynamics`: 是否在内环计算频率/电压

### 补丁02: 真实电站数据

**适用场景**: 用真实气象/电站数据替换数学合成数据

**首次使用**:
```bash
cd patches/02_real_data_fetcher/
python fetch_renewable_data.py --station all --date 2024-06-15
```

**MATLAB集成**:
```matlab
cfg = integrate_real_data(cfg);  % 在 generate_scenario_data 之前调用
% 如果数据不可用，自动回退到原始合成数据
```

**数据源**:
- NASA POWER (免费全球气象数据API)
- 国家海洋预报中心潮汐数据
- 江厦潮汐电站调和常数

### 补丁03: 真实通信损伤模型

**适用场景**: 需要延迟-丢包相关性、突发丢包等真实通信损伤特性

**直接替换原函数**:
```matlab
% 原代码:
comm_state = comm_delay_sim(cfg, t, fault_active);

% 替换为:
[comm_state, channel_state] = correlated_comm_model(cfg, t, fault_active, channel_state);
```

**独立分析**:
```matlab
% 运行 Gilbert-Elliott 信道参数分析
channel = gilbert_elliott_channel();  % 使用默认参数
% channel = gilbert_elliott_channel(struct('P_GG',0.98, 'P_BB',0.85, ...));
```

**关键参数**:
- `cfg.patches.real_comm.gilbert_elliott.P_GG`: 好→好转移概率 (默认0.95)
- `cfg.patches.real_comm.gilbert_elliott.P_BB`: 坏→坏转移概率 (默认0.80)
- 稳态坏状态概率 = P_GB/(P_GB+P_BG)

### 补丁04: VPP通信协议栈

**适用场景**: 需要在仿真中区分不同通信协议的性能差异

**协议延迟查询**:
```matlab
% 构造GOOSE保护报文
goose_msg = protocol_message_builder('IEC61850_GOOSE', 1, 2, ...
    struct('trip_signal', true, 'breaker_id', 'BRK_01'), cfg);
% goose_msg.latency_ms < 4ms (GOOSE硬实时约束)

% 构造MMS遥测报文
mms_msg = protocol_message_builder('IEC61850_MMS', 1, 2, ...
    struct('vpp_state', state_P_pv), cfg);
% mms_msg.latency_ms ~ 10-20ms (典型MMS延迟)

% 带宽分析
protocol_bandwidth_analysis(cfg);
```

**协议选择建议**:
| 应用场景 | 推荐协议 | 延迟要求 |
|---------|---------|---------|
| 保护跳闸 | GOOSE | < 4ms |
| 遥测遥信 | MMS | < 100ms |
| 传统设备 | Modbus TCP | < 1s |
| SCADA远动 | DNP3 | < 1s |

### 补丁05: TCP三次握手恢复

**适用场景**: 需要精确建模通信故障恢复过程

**独立分析** (各介质恢复时间对比):
```matlab
% 分析所有通信介质
compare_all_media();

% 单独分析5G专网
tcp_recovery_model('five_g');

% 自定义丢包率分析
tcp_recovery_model('fiber', struct('pkt_loss_rate', 0.10));
```

**仿真集成**:
```matlab
% 初始化
tcp = tcp_connection_manager('init', cfg);

% 每步更新 (在亚秒级内环中调用)
tcp = tcp_connection_manager('step', tcp, fault_active, t_now_s, dt_s);

% 获取链路延迟
latency = tcp_connection_manager('get_latency', tcp, src, dst);
% 连接未建立时返回 Inf

% 统计报告
tcp_connection_manager('report', tcp);
```

**典型恢复时间 (参考)**:
| 通信介质 | RTT | 理想握手 | P95握手 (5%丢包) |
|---------|-----|---------|-----------------|
| 光纤专网 | 5ms | 7.5ms | 15ms |
| 5G专网 | 10ms | 15ms | 30ms |
| 4G公网 | 40ms | 60ms | 180ms |
| 电力线载波 | 100ms | 150ms | 450ms |
| 卫星通信 | 600ms | 900ms | 2700ms |

### 补丁06: 动态拓扑路由

**适用场景**: 仿真移动基站、临时中继、拓扑重构等场景

**初始化**:
```matlab
routing = dynamic_routing('init', cfg);

% 选择预设场景
events = topology_event_scheduler('daily_cycle', cfg);  % 完整日周期
```

**仿真循环集成**:
```matlab
% 处理拓扑事件
[routing, topo_current] = dynamic_routing('process_events', routing, t_now_h);

% 使用更新后的拓扑
cfg.Comm.topology = topo_current;

% 获取VPP间路由
[paths, costs, hops] = dynamic_routing('compute_routes', routing, topo_current, delay_matrix);
% paths(i,j) = 从i到j的下一跳
```

**可视化**:
```matlab
% 拓扑快照
topology_visualizer('snapshot', topo_current, t_now_h, positions, labels);

% 路由路径展示
topology_visualizer('route_path', topo_current, routing_table, 1, 5, positions);

% 统计仪表板
topology_visualizer('dashboard', routing.topo_history, routing.topo_history_time);

% 生成动画
topology_visualizer('animation', routing.topo_history, routing.topo_history_time, positions);
```

## 全补丁协同集成示例

以下是一个完整的仿真脚本，展示所有6个补丁的协同使用:

```matlab
% ============================================================
% VPP仿真主程序 (补丁增强版)
% ============================================================
addpath(genpath('patches/'));

% --- 配置 ---
cfg = param_global_config();
cfg = patch_config(cfg);

% 激活所有补丁
cfg.patches.subsecond.enabled   = true;
cfg.patches.real_data.enabled   = true;
cfg.patches.real_comm.enabled   = true;
cfg.patches.protocol.enabled    = true;
cfg.patches.tcp_handshake.enabled = true;
cfg.patches.dynamic_topo.enabled  = true;

% 加载真实数据
cfg = integrate_real_data(cfg);

% --- 亚秒级配置 ---
scfg = subsecond_config(cfg);

% --- 初始化 ---
Nv = cfg.N_vpp;
state = init_state(cfg);
channel_state = [];
routing = dynamic_routing('init', cfg);
tcp = tcp_connection_manager('init', cfg);

% --- 主仿真循环 ---
for t = 1:cfg.N_steps
    t_now_h = cfg.time(t);

    % 动态拓扑更新
    if cfg.patches.dynamic_topo.enabled
        [routing, topo] = dynamic_routing('process_events', routing, t_now_h);
        cfg.Comm.topology = topo;
        fault_active = (topo < 0.3);  % 低质量视为故障
    end

    % 通信质量 (增强模型)
    if cfg.patches.real_comm.enabled
        [comm_state, channel_state] = correlated_comm_model(cfg, t, fault_active, channel_state);
    else
        comm_state = comm_delay_sim(cfg, t, fault_active);
    end

    % TCP连接管理 (内环中使用)
    if cfg.patches.tcp_handshake.enabled
        tcp = tcp_connection_manager('step', tcp, fault_active, t_now_h*3600, scfg.dt_fast);
    end

    % 模式判断 + EMS调度 (原始逻辑)
    [mode, mode_detail] = mode_judge_comm(comm_state, cfg, cfg.scenario.force_island);
    % ... (原有的调度逻辑) ...

    % 协议栈集成
    if cfg.patches.protocol.enabled
        msg = protocol_message_builder('IEC61850_MMS', src, dst, payload, cfg);
        additional_latency = msg.latency_ms / 1000;  % ms→s
    end

    % 数据记录
    % ...
end

% --- 结果后处理 ---
tcp_connection_manager('report', tcp);
dynamic_routing('report', routing);
topology_visualizer('dashboard', routing.topo_history, routing.topo_history_time);
```

## 验证清单

部署补丁后，建议运行以下验证:

- [ ] 补丁01: `scfg = subsecond_config(cfg)` 输出正确的 inner_steps
- [ ] 补丁02: 运行 `fetch_renewable_data.py`，检查 `real_data_cache/matlab_input/scenario_24h.csv`
- [ ] 补丁03: 运行 `gilbert_elliott_channel()`，检查稳态分布收敛到理论值
- [ ] 补丁04: 运行 `protocol_bandwidth_analysis(cfg)`，确认带宽利用率 < 100%
- [ ] 补丁05: 运行 `compare_all_media()`，确认各介质恢复时间合理
- [ ] 补丁06: 运行 `topology_event_scheduler('daily_cycle', cfg)`，检查事件时间排序正确

## 常见问题

**Q: 补丁02需要Python，MATLAB中如何调用？**
A: `integrate_real_data.m` 通过 `system('python fetch_renewable_data.py')` 调用。确保Python在系统PATH中。

**Q: 补丁01的亚秒级仿真导致运行时间过长？**
A: 增大 `cfg.patches.subsecond.profile_interval` 减少记录频率，或仅对关键时段启用亚秒级。

**Q: 如何将补丁成果写入论文？**
A: 建议在论文第8章(系统实现与验证)中增加各补丁的仿真对比分析，展示改进前后的差异。
