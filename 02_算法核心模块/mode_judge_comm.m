% ============================================================
% 文件名：mode_judge_comm.m
% 功能：网络状态判别算法，时延丢包率判定输出运行模式标识
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   本文件为团队独立创新开发，属于项目核心原创算法模块。
%   理论基础参考：
%     1) ADMM分布式优化理论：edX Optimization for Energy Systems
%     2) 微网调频控制：IEEE Std 1547-2018
%   算法实现、模式切换逻辑、多源协同策略为原创。
%   版权所有，未经许可不得转载或用于商业用途。
% ============================================================

function [mode, mode_detail] = mode_judge_comm(comm_state, cfg, force_island)
    % 通信质量→运行模式判别
    %
    % 输入:
    %   comm_state   - 通信状态结构体（comm_delay_sim输出）
    %       .delay     - 时延矩阵 (s)
    %       .loss_rate - 丢包率矩阵
    %   cfg          - 全局配置
    %   force_island - 强制孤岛模式 (logical), 默认 false
    %
    % 输出:
    %   mode        - 运行模式: 'COOPERATE' | 'ISLAND'
    %   mode_detail - 判别详情结构体

    % 常量定义
    COOPERATE = 1;
    ISLAND    = 2;

    if nargin < 3
        force_island = false;
    end

    Nv = cfg.N_vpp;

    % ---- 强制孤岛 ----
    if force_island
        mode = ISLAND;
        mode_detail = struct(...
            'mode_str', 'ISLAND', ...
            'reason', '强制孤岛模式', ...
            'max_delay', Inf, ...
            'max_loss', 1, ...
            'avg_quality', 0, ...
            'failed_links', cfg.Comm.topology > 0, ...
            'num_failed', sum(cfg.Comm.topology(:) > 0));
        return;
    end

    % ---- 通信质量评估 ----
    delay = comm_state.delay;
    loss  = comm_state.loss_rate;
    topo  = cfg.Comm.topology;

    delay_th = cfg.Comm.delay_threshold;
    loss_th  = cfg.Comm.loss_threshold;

    % 逐链路判定（仅检查拓扑中有连接的链路）
    delay_fail = (delay > delay_th) & (topo > 0);
    loss_fail  = (loss  > loss_th)  & (topo > 0);

    % 链路故障 = 时延超标 或 丢包超标
    link_failed = delay_fail | loss_fail;

    % 取上三角（避免重复计数）
    link_failed_upper = triu(link_failed, 1);
    num_failed = sum(link_failed_upper(:));
    num_links  = sum(triu(topo, 1), 'all');

    % ---- 模式判定逻辑 ----
    % 条件1：任何一条链路故障 → ISLAND（保守策略：单链路中断即孤岛）
    % 条件2：平均通信质量 < 0.5 → ISLAND
    quality_active = comm_state.quality(topo > 0);
    if ~isempty(quality_active)
        avg_quality = mean(quality_active(:));
    else
        avg_quality = 1;
    end

    if num_failed > 0 || avg_quality < 0.5
        mode = ISLAND;
        if num_failed > 0
            reason = sprintf('通信链路故障: %d/%d 条链路中断', num_failed, num_links);
        else
            reason = sprintf('通信质量过低: 平均质量=%.2f', avg_quality);
        end
    else
        mode = COOPERATE;
        reason = sprintf('通信正常: %d条链路质量良好', num_links);
    end

    % ---- 详细输出 ----
    mode_detail = struct(...
        'mode_str',    get_mode_str(mode), ...
        'reason',      reason, ...
        'max_delay',   max(delay(topo > 0)), ...
        'max_loss',    max(loss(topo > 0)), ...
        'avg_quality', avg_quality, ...
        'failed_links', link_failed, ...
        'num_failed',  num_failed, ...
        'num_links',   num_links);
end


function s = get_mode_str(mode)
    if mode == 1
        s = 'COOPERATE';
    else
        s = 'ISLAND';
    end
end
