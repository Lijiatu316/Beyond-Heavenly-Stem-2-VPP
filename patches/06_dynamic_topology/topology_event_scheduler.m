% ============================================================
% 文件名：topology_event_scheduler.m
% 功能：拓扑事件调度器 — 预设和随机拓扑变化事件的管理
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 事件类型:
%   1 = LINK_DOWN       — 链路断开
%   2 = LINK_UP         — 链路恢复
%   3 = NODE_MOVE       — 节点移动
%   4 = LINK_DEGRADE    — 链路质量衰减
%   5 = RELAY_DEPLOY    — 部署临时中继
%   6 = RELAY_REMOVE    — 移除临时中继
%   7 = NODE_MOVE_ALT   — 节点移动(备用)
%   8 = TOPOLOGY_RESET  — 拓扑重置
%   9 = NODE_ADD        — 增加节点(第10个VPP)
%  10 = NODE_REMOVE     — 移除节点
%
% 场景模板:
%   1. 基站故障 (Base Station Failure): 固定链路突发中断
%   2. 应急中继部署 (Emergency Relay): 灾害后部署临时中继
%   3. 移动基站巡逻 (Mobile Patrol): 无人机/车辆定期巡检
%   4. 通信降级 (Gradual Degradation): 链路质量逐步恶化
%   5. 网络重构 (Network Reconfiguration): 计划内的拓扑调整
% ============================================================

function events = topology_event_scheduler(scenario_name, cfg)
    % 拓扑事件调度器
    %
    % 输入:
    %   scenario_name - 场景名称 或 'custom'
    %   cfg           - 全局配置
    %
    % 输出:
    %   events - 事件结构体:
    %       .schedule — [time_h, event_type, node_i, node_j, param]
    %       .labels   — 事件标签 cell array
    %       .description — 场景描述

    Nv = cfg.N_vpp;

    switch scenario_name
        case 'base_station_failure'
            events = scenario_bs_failure(Nv);
        case 'emergency_relay'
            events = scenario_emergency_relay(Nv);
        case 'mobile_patrol'
            events = scenario_mobile_patrol(Nv);
        case 'gradual_degradation'
            events = scenario_degradation(Nv);
        case 'network_reconfig'
            events = scenario_reconfig(Nv);
        case 'daily_cycle'
            events = scenario_daily_cycle(Nv);
        otherwise
            % 使用 cfg.patches.dynamic_topo.events 中的配置
            events = load_from_config(cfg);
    end
end


function events = scenario_bs_failure(Nv)
    % 场景1: 基站故障
    %   t=2h:  V3-V4链路断开 (基站硬件故障)
    %   t=4h:  V3-V4链路恢复 (维修完成)
    %   t=10h: V6-V7链路断开 (另一基站故障)
    %   t=14h: V6-V7链路恢复

    events = struct();
    events.description = '基站故障场景：模拟通信基站硬件故障及维修恢复过程';
    events.schedule = [
        2.0,  1, 3, 4, 0;     % V3-V4断开
        4.0,  2, 3, 4, 0;     % V3-V4恢复
       10.0,  1, 6, 7, 0;     % V6-V7断开
       14.0,  2, 6, 7, 0;     % V6-V7恢复
    ];
    events.labels = {'V3-V4断开', 'V3-V4恢复', 'V6-V7断开', 'V6-V7恢复'};
end


function events = scenario_emergency_relay(Nv)
    % 场景2: 应急中继部署
    %   台风/地质灾害后，部署临时移动中继恢复通信

    events = struct();
    events.description = '应急中继部署场景：灾害后V5处部署临时中继站，8h后拆除';
    events.schedule = [
        1.0,  1, 1, 2, 0;     % 故障: V1-V2断开
        1.0,  1, 4, 5, 0;     % 故障: V4-V5断开
        3.0,  5, 5, 0, 0;     % 在V5部署中继
        6.0,  2, 1, 2, 0;     % 恢复: V1-V2
       12.0,  2, 4, 5, 0;     % 恢复: V4-V5
       12.0,  6, 5, 0, 0;     % 拆除中继
    ];
    events.labels = {'V1-V2故障', 'V4-V5故障', '部署中继V5', 'V1-V2恢复', ...
                     'V4-V5恢复', '拆除中继'};
end


function events = scenario_mobile_patrol(Nv)
    % 场景3: 移动基站巡逻
    %   无人机/车辆携带移动基站定期沿环形路径巡查

    events = struct();
    events.description = '移动基站巡逻：无人机中继沿环形路径移动，8h一圈';
    events.schedule = [];
    for h = 0:2:22
        % 每2小时移动一次
        events.schedule(end+1, :) = [h, 3, mod(h/2, Nv)+1, 0, 200 + 100*rand()];
    end
    events.labels = arrayfun(@(t) sprintf('t=%.0fh节点移动', t), ...
                             events.schedule(:,1), 'UniformOutput', false);
end


function events = scenario_degradation(Nv)
    % 场景4: 通信质量逐渐下降
    %   设备老化/天气恶化导致链路质量衰减

    events = struct();
    events.description = '通信质量下降：模拟暴风雨天气导致的链路质量逐渐恶化';
    events.schedule = [
        2.0,  4, 4, 5, 0.8;   % V4-V5质量降至80%
        4.0,  4, 4, 5, 0.5;   % 进一步降至50%
        6.0,  4, 8, 9, 0.6;   % V8-V9质量降至60%
        8.0,  4, 1, 2, 0.7;   % V1-V2质量降至70%
       10.0,  4, 4, 5, 0.9;   % V4-V5恢复至90%
       14.0,  4, 8, 9, 1.0;   % V8-V9完全恢复
       16.0,  4, 1, 2, 1.0;   % V1-V2完全恢复
    ];
    events.labels = {'V4-V5×0.8', 'V4-V5×0.5', 'V8-V9×0.6', 'V1-V2×0.7', ...
                     'V4-V5修复', 'V8-V9修复', 'V1-V2修复'};
end


function events = scenario_reconfig(Nv)
    % 场景5: 计划内网络重构
    %   电网运行方式调整导致VPP重新分组

    events = struct();
    events.description = '网络重构：电网运行方式调整导致的VPP通信拓扑重组';
    events.schedule = [
        3.0,  1, 9, 1, 0;     % 环网断开 V9-V1
        3.0,  2, 9, 4, 0;     % 增加跨类连接 V9-V4
        6.0,  1, 3, 4, 0;     % 断开 V3-V4
        6.0,  2, 3, 6, 0;     % 增加 V3-V6
        9.0,  1, 7, 8, 0;     % 潮汐链断开
        9.0,  2, 7, 2, 0;     % 跨接 V7-V2
       12.0,  2, 9, 1, 0;     % 恢复环网
       12.0,  1, 9, 4, 0;     % 断开临时连接
       12.0,  2, 3, 4, 0;     % 恢复 V3-V4
       12.0,  1, 3, 6, 0;     % 断开临时连接
       12.0,  2, 7, 8, 0;     % 恢复潮汐链
       12.0,  1, 7, 2, 0;     % 断开临时连接
    ];
    events.labels = repmat({'拓扑切换'}, size(events.schedule, 1), 1);
end


function events = scenario_daily_cycle(Nv)
    % 场景6: 24h日周期综合场景
    %   包含基站故障、中继部署、移动节点等的完整日周期

    events = struct();
    events.description = '24h日周期：综合模拟基站故障、中继部署和移动节点的完整场景';
    events.schedule = [
        % 早高峰 (6-8h): 电网重载，部分通信基站温升故障
        5.5,  4, 3, 4, 0.6;   % 链路质量下降
        6.0,  1, 6, 7, 0;     % 链路断开
        % 上午 (8-12h): 维修恢复
        8.0,  5, 7, 0, 0;     % 部署移动中继
       10.0,  2, 6, 7, 0;     % 链路恢复
       10.0,  6, 7, 0, 0;     % 拆除中继
        % 午间 (12-14h): 光伏高发，通信正常
       12.0,  4, 3, 4, 1.0;   % 链路质量恢复
        % 下午 (14-18h): 移动基站车出动巡检
       14.0,  3, 3, 0, 300;   % 节点移动
       16.0,  3, 6, 0, 250;   % 节点移动
        % 晚高峰 (18-22h): 负荷重，链路压力大
       18.0,  4, 8, 9, 0.5;   % 链路质量衰减
       18.5,  1, 1, 2, 0;     % 链路断开 (过载保护)
       20.0,  5, 1, 0, 0;     % 部署中继
       22.0,  2, 1, 2, 0;     % 链路恢复
       22.0,  6, 1, 0, 0;     % 拆除中继
       23.0,  4, 8, 9, 1.0;   % 链路质量恢复
    ];
    events.labels = {
        '链路衰减V3-V4', '链路断开V6-V7', '移动中继V7', '恢复V6-V7', ...
        '拆除中继', '质量恢复V3-V4', '节点移动V3', '节点移动V6', ...
        '链路衰减V8-V9', '链路断开V1-V2', '部署中继V1', '恢复V1-V2', ...
        '拆除中继', '质量恢复V8-V9'
    };
end


function events = load_from_config(cfg)
    % 从补丁配置中加载事件
    dt = cfg.patches.dynamic_topo;
    events = dt.events;
    events.description = '从配置文件加载的自定义拓扑事件';
end


function events = random_topology_events(Nv, n_events, duration_h)
    % 生成随机拓扑变化事件 (用于敏感性分析)
    %
    % 输入:
    %   Nv         - VPP数量
    %   n_events   - 事件数量
    %   duration_h - 仿真时长
    %
    % 输出:
    %   events - 事件结构体

    if nargin < 2, n_events = 20; end
    if nargin < 3, duration_h = 24; end

    events = struct();
    events.description = sprintf('随机拓扑事件: %d事件/%dh', n_events, duration_h);

    schedule = zeros(n_events, 5);
    labels = cell(n_events, 1);

    rng(2048);

    for k = 1:n_events
        t = duration_h * rand();
        evt_type = randi([1, 7]);

        i = randi(Nv);
        j = randi(Nv);
        while j == i
            j = randi(Nv);
        end

        switch evt_type
            case {1, 2, 4}
                param = 0;
            case {3, 7}
                param = 100 + 400 * rand();  % 100-500m
            otherwise
                param = 0;
        end

        schedule(k, :) = [t, evt_type, i, j, param];
        labels{k} = sprintf('事件%d: t=%.1fh, 类型%d, V%d-V%d', k, t, evt_type, i, j);
    end

    % 按时间排序
    [~, idx] = sort(schedule(:,1));
    events.schedule = schedule(idx, :);
    events.labels = labels(idx);
end
