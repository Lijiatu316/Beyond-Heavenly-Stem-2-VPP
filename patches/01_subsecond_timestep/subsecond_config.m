% ============================================================
% 文件名：subsecond_config.m
% 功能：亚秒级仿真步长 — 参数配置模块
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 设计说明：
%   原仿真采用 dt=0.1h (360s) 粗粒度步长，适合EMS级调度但不
%   能捕捉频率调节、保护动作、通信握手等秒级/亚秒级动态。
%   本补丁采用**双时间尺度共仿真**架构：
%     - 外环 (原步长): EMS调度优化、ADMM迭代、SOC更新
%     - 内环 (亚秒级): 频率响应、电压调节、通信协议、保护动作
% ============================================================

function scfg = subsecond_config(cfg)
    % 构建亚秒级仿真配置子结构体
    %
    % 输入:
    %   cfg  - 全局配置（已含 cfg.patches.subsecond）
    %
    % 输出:
    %   scfg - 亚秒级仿真专用参数结构体

    ps = cfg.patches.subsecond;
    if ~ps.enabled
        scfg = struct('enabled', false);
        return;
    end

    scfg.enabled      = true;
    scfg.dt_fast      = ps.dt_fast;                     % 快速内环步长 (s)
    scfg.dt_outer     = cfg.dt * 3600;                  % 外环步长 (s)
    scfg.inner_steps  = round(scfg.dt_outer / scfg.dt_fast);  % 每外环步的内环步数
    scfg.T_sim_s      = cfg.T_sim * 3600;               % 总仿真时间 (s)
    scfg.N_outer      = cfg.N_steps;                    % 外环步数
    scfg.N_inner      = scfg.N_outer * scfg.inner_steps;% 内环总步数

    % 时间轴
    scfg.t_outer      = cfg.time * 3600;                % 外环时间轴 (s)
    scfg.t_fast       = (0:scfg.dt_fast:scfg.T_sim_s - scfg.dt_fast)';  % 快速时间轴

    % 插值参数
    scfg.interp_method = ps.interp_method;

    % 存储降采样
    scfg.profile_interval = ps.profile_interval;        % 每N步记录一次
    scfg.N_record = ceil(scfg.N_inner / scfg.profile_interval);

    % 快动态开关
    scfg.fast_dynamics = ps.fast_dynamics;

    % 通信协议时序参数（在秒级有意义）
    scfg.comm_update_interval = 0.1;                    % 每100ms更新通信状态
    scfg.protocol_cycle       = 0.02;                    % 协议报文循环周期20ms

    % 保护动作时序
    scfg.protection_check_interval = 0.01;              % 每10ms检查保护定值

    % 数值稳定性
    scfg.min_step_for_ode = 1e-4;                       % ODE最小步长

    fprintf('  [亚秒级配置] dt_fast=%.3fs, inner_steps=%d, N_inner=%d\n', ...
            scfg.dt_fast, scfg.inner_steps, scfg.N_inner);
    fprintf('  双时间尺度: 外环%.1fs(EMS) + 内环%.3fs(快动态)\n', ...
            scfg.dt_outer, scfg.dt_fast);
end
