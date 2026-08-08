% ============================================================
% 文件名：patch_config.m
% 功能：统一补丁配置入口，所有6项增强的激活开关与参数
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 使用方式：
%   cfg = param_global_config();    % 先加载原始配置
%   cfg = patch_config(cfg);        % 再叠加补丁配置
%   cfg.patches.xxx.enabled = true; % 按需激活各补丁
% ============================================================

function cfg = patch_config(cfg)
    % 统一补丁配置函数
    %
    % 输入:
    %   cfg - 由 param_global_config() 返回的原始配置结构体
    %
    % 输出:
    %   cfg - 附带 patches 字段的增强配置

    % ==================== 补丁总开关 ====================
    cfg.patches.master_switch = true;  % 总开关，false时全部禁用回退到原始代码

    % ==================== 补丁01: 亚秒级仿真步长 ====================
    cfg.patches.subsecond = struct();
    cfg.patches.subsecond.enabled      = true;
    cfg.patches.subsecond.dt_fast      = 0.5;        % 快速内环步长 (s)
    cfg.patches.subsecond.dt_outer     = cfg.dt * 3600;  % 外环步长 (s) = 360
    cfg.patches.subsecond.inner_steps  = cfg.patches.subsecond.dt_outer / cfg.patches.subsecond.dt_fast;
    cfg.patches.subsecond.interp_method = 'pchip';    % 插值方法: 'linear'|'pchip'|'spline'
    cfg.patches.subsecond.fast_dynamics = true;       % 是否在内环仿真快速动态(频率/电压)
    cfg.patches.subsecond.profile_interval = 100;     % 每N个内环步记录一次(降采样存储)

    % ==================== 补丁02: 真实电站数据接入 ====================
    cfg.patches.real_data = struct();
    cfg.patches.real_data.enabled        = true;
    cfg.patches.real_data.sources        = {'jiangxia_tidal', 'onshore_wind_cluster', 'pv_station_cluster'};
    cfg.patches.real_data.data_dir       = fullfile(fileparts(mfilename('fullpath')), '02_real_data_fetcher', 'real_data_cache');
    cfg.patches.real_data.fallback_to_synthetic = true;  % 数据不可用时回退到合成数据
    cfg.patches.real_data.resample_method = 'interp1';    % 重采样方法
    cfg.patches.real_data.time_zone      = 'Asia/Shanghai';
    % 数据源详细配置
    cfg.patches.real_data.jiangxia = struct(...
        'station_name', '江厦潮汐试验电站', ...
        'latitude', 28.34, ...
        'longitude', 121.35, ...
        'capacity_kW', 3200, ...
        'data_url', 'https://example.org/jiangxia/tidal_level' ...  % 待替换为实际数据源
    );
    cfg.patches.real_data.wind_cluster = struct(...
        'station_name', '沿海风电集群', ...
        'region', '浙江/福建沿海', ...
        'total_capacity_MW', 50, ...
        'num_turbines', 25, ...
        'data_url', 'https://example.org/wind/cluster_data' ...
    );
    cfg.patches.real_data.pv_cluster = struct(...
        'station_name', '分布式光伏集群', ...
        'region', '浙江', ...
        'total_capacity_MWp', 30, ...
        'data_url', 'https://example.org/pv/cluster_data' ...
    );

    % ==================== 补丁03: 真实通信损伤模型 ====================
    cfg.patches.real_comm = struct();
    cfg.patches.real_comm.enabled            = true;
    cfg.patches.real_comm.model_type         = 'gilbert_elliott';  % 'gilbert_elliott'|'markov_modulated'
    cfg.patches.real_comm.correlation_length = 10;       % 时间相关性长度 (步)
    cfg.patches.real_comm.burst_loss_enabled = true;     % 启用突发丢包
    % Gilbert-Elliott 两状态马尔可夫模型参数
    cfg.patches.real_comm.gilbert_elliott = struct(...
        'P_GG', 0.95, ...     % 好状态→好状态转移概率
        'P_GB', 0.05, ...     % 好状态→坏状态转移概率
        'P_BG', 0.20, ...     % 坏状态→好状态转移概率
        'P_BB', 0.80, ...     % 坏状态→坏状态转移概率
        'delay_good_mean', 0.010, ...   % 好状态平均延迟 (s)
        'delay_good_std',  0.003, ...   % 好状态延迟标准差 (s)
        'delay_bad_mean',  0.350, ...   % 坏状态平均延迟 (s)
        'delay_bad_std',   0.150, ...   % 坏状态延迟标准差 (s)
        'loss_good_mean',  0.002, ...   % 好状态平均丢包率
        'loss_bad_mean',   0.450, ...   % 坏状态平均丢包率
        'delay_loss_corr', 0.65 ...     % 延迟-丢包相关系数
    );
    % 基于实测数据的经验参数（参考3G/4G/5G公网和专网测量）
    cfg.patches.real_comm.empirical = struct(...
        'fiber_mean_delay_ms', 5, ...
        'fiber_jitter_ms', 0.5, ...
        'fourg_mean_delay_ms', 40, ...
        'fourg_jitter_ms', 15, ...
        'fiveg_mean_delay_ms', 10, ...
        'fiveg_jitter_ms', 3, ...
        'lora_mean_delay_ms', 200, ...
        'lora_packet_loss', 0.05 ...
    );

    % ==================== 补丁04: VPP通信协议栈 ====================
    cfg.patches.protocol = struct();
    cfg.patches.protocol.enabled          = true;
    cfg.patches.protocol.protocols        = {'IEC61850_MMS', 'IEC61850_GOOSE', 'Modbus_TCP', 'DNP3'};
    cfg.patches.protocol.default_protocol = 'IEC61850_MMS';  % 默认VPP间通信协议
    % IEC 61850-8-1 MMS (Manufacturing Message Specification)
    cfg.patches.protocol.iec61850_mms = struct(...
        'message_overhead_bytes', 128, ...  % 协议头部开销
        'max_pdu_size_bytes', 1500, ...     % 最大PDU
        'report_interval_ms', 100, ...      % 报告间隔
        'priority', 3 ...                   % 优先级 (1-7, 7最高)
    );
    % IEC 61850-8-1 GOOSE (Generic Object Oriented Substation Event)
    cfg.patches.protocol.iec61850_goose = struct(...
        'message_overhead_bytes', 64, ...
        'max_message_size_bytes', 1526, ...
        'retransmission_ms', [0, 2, 4, 8, 16, 32, 64, 128, 256, 512], ...  % GOOSE重传序列
        'max_latency_ms', 4, ...        % 最大允许时延
        'priority', 7 ...               % 最高优先级
    );
    % Modbus TCP
    cfg.patches.protocol.modbus_tcp = struct(...
        'message_overhead_bytes', 7, ...   % MBAP header
        'max_read_registers', 125, ...     % 单次最大读取寄存器数
        'default_timeout_ms', 1000, ...    % 默认超时
        'poll_interval_ms', 500, ...       % 轮询间隔
        'priority', 2 ...
    );
    % DNP3 (IEEE 1815)
    cfg.patches.protocol.dnp3 = struct(...
        'message_overhead_bytes', 10, ...  % DNP3 header
        'max_fragment_size_bytes', 2048, ...
        'event_reporting_enabled', true, ...
        'unsolicited_response_enabled', true, ...
        'priority', 4 ...
    );

    % ==================== 补丁05: TCP三次握手恢复 ====================
    cfg.patches.tcp_handshake = struct();
    cfg.patches.tcp_handshake.enabled         = true;
    cfg.patches.tcp_handshake.initial_rto_ms  = 1000;    % 初始重传超时 (RFC 6298建议)
    cfg.patches.tcp_handshake.min_rto_ms      = 200;     % 最小RTO
    cfg.patches.tcp_handshake.max_rto_ms      = 60000;   % 最大RTO (60s)
    cfg.patches.tcp_handshake.max_syn_retries = 6;       % SYN最大重试次数 (RFC 1122)
    cfg.patches.tcp_handshake.syn_timeout_ms  = 3000;    % SYN超时
    cfg.patches.tcp_handshake.rtt_alpha       = 0.125;   % SRTT平滑系数 (RFC 6298)
    cfg.patches.tcp_handshake.rtt_beta        = 0.25;    % RTTVAR平滑系数
    cfg.patches.tcp_handshake.rtt_k           = 4;       % RTO = SRTT + K*RTTVAR
    % 不同通信介质下的典型RTT
    cfg.patches.tcp_handshake.rtt_profiles = struct(...
        'fiber',        struct('mean_ms', 5,   'std_ms', 1), ...
        'four_g',       struct('mean_ms', 40,  'std_ms', 15), ...
        'five_g',       struct('mean_ms', 10,  'std_ms', 3), ...
        'satellite',    struct('mean_ms', 600, 'std_ms', 50), ...
        'powerline',    struct('mean_ms', 100, 'std_ms', 30) ...
    );

    % ==================== 补丁06: 动态拓扑路由 ====================
    cfg.patches.dynamic_topo = struct();
    cfg.patches.dynamic_topo.enabled        = true;
    cfg.patches.dynamic_topo.routing_algo   = 'dijkstra';  % 'dijkstra'|'aodv'|'olsr'
    cfg.patches.dynamic_topo.mobile_nodes   = [3, 6, 9];   % 可移动的VPP节点编号
    % 拓扑事件配置
    cfg.patches.dynamic_topo.events = struct(...
        'schedule', [ ...  % [time_h, event_type, node_i, node_j, param]
            2.0,  1, 3, 4, 0;   % t=2h: V3-V4链路断开 (基站故障)
            4.0,  2, 3, 4, 0;   % t=4h: V3-V4链路恢复
            6.0,  3, 7, 0, 250; % t=6h: 节点V7移动，速度250m
            8.0,  4, 8, 9, 0.5; % t=8h: V8-V9链路质量下降50%
           10.0,  5, 5, 0, 0;   % t=10h: 在V5部署临时中继站
           14.0,  6, 5, 0, 0;   % t=14h: 移除V5临时中继
           18.0,  7, 2, 0, 300; % t=18h: 节点V2移动
        ], ...
        'event_labels', {{'链路故障', '链路恢复', '节点移动', '链路衰减', '中继部署', '中继移除', '节点移动'}} ...
    );
    cfg.patches.dynamic_topo.mobility_model = 'random_waypoint';  % 'random_waypoint'|'gauss_markov'|'custom'
    cfg.patches.dynamic_topo.route_convergence_time_ms = 500;  % 路由收敛时间
    cfg.patches.dynamic_topo.max_hops = 5;  % 最大跳数
end
