% ============================================================
% 文件名：subsecond_main.m
% 功能：亚秒级双时间尺度共仿真主控制器
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 架构：
%   for t_outer = 1:N_outer  (EMS调度, 6分钟步长)
%       ├── EMS优化 (ADMM / 孤岛EMS)
%       ├── 设备出力计算 (保持原步长)
%       └── for k_inner = 1:inner_steps  (快动态, 亚秒级)
%               ├── 频率响应 (下垂+惯性)
%               ├── 电压调节
%               ├── 通信协议时序
%               ├── 保护检测
%               └── 数据记录
%
% 与原始代码的关系：
%   本模块是 run_mode_island/run_mode_cooperate 的增强替代，
%   将原仿真循环中的EMS调度保持在外环，新增内环快动态。
%   不修改原始文件，通过 cfg.patches.subsecond.enabled 切换。
% ============================================================

function results = subsecond_main(run_mode_func, cfg_override)
    % 亚秒级双尺度仿真入口
    %
    % 输入:
    %   run_mode_func - 函数句柄 @run_mode_island 或 @run_mode_cooperate
    %                   (传入原始模式函数，内部回退时调用)
    %   cfg_override  - 可选的配置覆盖 (struct)
    %
    % 输出:
    %   results - 仿真结果结构体 (含 fast 子字段存储快动态数据)

    % ---- 加载配置 ----
    cfg = param_global_config();
    cfg = patch_config(cfg);

    if nargin >= 2 && ~isempty(cfg_override)
        % 合并覆盖配置
        fns = fieldnames(cfg_override);
        for i = 1:length(fns)
            cfg.(fns{i}) = cfg_override.(fns{i});
        end
    end

    if ~cfg.patches.subsecond.enabled
        fprintf('[亚秒级补丁] 未启用，回退到原始仿真\n');
        results = run_mode_func();
        return;
    end

    scfg = subsecond_config(cfg);

    fprintf('============================================\n');
    fprintf('  亚秒级双尺度共仿真\n');
    fprintf('  外环步长: %.1fs (EMS) | 内环步长: %.3fs (快动态)\n', ...
            scfg.dt_outer, scfg.dt_fast);
    fprintf('  总仿真: %.1fh, %d外环步 × %d内环步\n', ...
            cfg.T_sim, scfg.N_outer, scfg.inner_steps);
    fprintf('============================================\n\n');

    Nv = cfg.N_vpp;
    N_outer = scfg.N_outer;
    N_inner = scfg.inner_steps;
    dt_fast = scfg.dt_fast;
    dt_outer_h = cfg.dt;

    % ============ 外环状态初始化 ============
    fprintf('[初始化] 启动外环状态...\n');

    % 历史记录（外环）
    hist.time       = cfg.time;
    hist.P_pv       = zeros(N_outer, Nv);
    hist.P_wind     = zeros(N_outer, Nv);
    hist.P_tidal    = zeros(N_outer, Nv);
    hist.P_gas      = zeros(N_outer, Nv);
    hist.P_bat      = zeros(N_outer, Nv);
    hist.P_load     = zeros(N_outer, Nv);
    hist.P_shed     = zeros(N_outer, Nv);
    hist.P_curtail  = zeros(N_outer, Nv);
    hist.SOC        = zeros(N_outer, Nv);
    hist.freq       = zeros(N_outer, Nv);
    hist.volt       = zeros(N_outer, Nv);
    hist.mode       = zeros(N_outer, 1);
    hist.cost       = zeros(N_outer, Nv);

    % 快动态记录（降采样）
    N_record = scfg.N_record;
    fast.time_s    = zeros(N_record, 1);
    fast.freq      = zeros(N_record, Nv);
    fast.volt      = zeros(N_record, Nv);
    fast.df_dt     = zeros(N_record, Nv);   % RoCoF (频率变化率)
    fast.P_fast    = zeros(N_record, Nv);   % 快速功率调节量
    fast.protect_triggered = zeros(N_record, 1);

    % 初始状态
    state.SOC        = cfg.Battery.SOC0;
    state.P_gas_prev = zeros(1, Nv);
    state.P_bat_prev = zeros(1, Nv);
    state.freq       = cfg.f_nom * ones(1, Nv);
    state.volt       = ones(1, Nv);
    state.P_pv_avail   = zeros(1, Nv);
    state.P_wind_avail = zeros(1, Nv);
    state.P_tidal_avail = zeros(1, Nv);
    state.P_load       = zeros(1, Nv);

    pi_state = [];
    tidal_state = [];
    fault_active = comm_fault_trigger(0, [], cfg.Comm.topology, cfg.scenario.force_island);

    % 通信协议状态初始化（如果启用补丁04）
    if cfg.patches.protocol.enabled
        proto_state = protocol_state_init(cfg, Nv);
    end

    % TCP连接状态初始化（如果启用补丁05）
    if cfg.patches.tcp_handshake.enabled
        tcp_state = tcp_state_init(cfg, Nv);
    end

    % ============ 双尺度主循环 ============
    fprintf('[仿真] 开始双尺度循环...\n');
    tic;
    record_idx = 0;

    for t = 1:N_outer
        t_now_h = cfg.time(t);

        % ======== 外环: EMS调度 (保持原逻辑) ========

        % 太阳入射角
        incidence_angle = 65 * abs(cos(pi * (t_now_h - 12) / 14));

        % 设备出力 (使用外环粗粒度数据)
        state.P_pv_avail = pv_model(cfg.data.irradiance(t, :), ...
                                     cfg.data.temperature(t, :), cfg.PV, ...
                                     incidence_angle * ones(1, Nv), ...
                                     cfg.data.wind_speed(t, :));
        state.P_wind_avail = wind_model(cfg.data.wind_speed(t, :), cfg.Wind);

        if cfg.Tidal.enabled
            prev_basin = [];
            if ~isempty(tidal_state)
                prev_basin = tidal_state.basin_level;
            end
            [state.P_tidal_avail, tidal_state] = tidal_model(...
                cfg.data.tide_height(t) * ones(1, Nv), prev_basin, dt_outer_h, cfg.Tidal);
        else
            state.P_tidal_avail = zeros(1, Nv);
        end

        state.P_load = cfg.data.load_rigid(t, :);

        % 预测
        if t > 1
            hist_pv = hist.P_pv(1:t, :);
            hist_wind = hist.P_wind(1:t, :);
            hist_load = hist.P_load(1:t, :);
        else
            hist_pv = state.P_pv_avail;
            hist_wind = state.P_wind_avail;
            hist_load = state.P_load;
        end
        fc.P_pv = hist_pv; fc.P_wind = hist_wind; fc.P_load = hist_load;
        forecast = power_forecast(fc, t, cfg);

        % 通信检测 (使用增强通信模型如果启用)
        if cfg.patches.real_comm.enabled
            comm_state = correlated_comm_model(cfg, t, fault_active);
        else
            comm_state = comm_delay_sim(cfg, t, fault_active);
        end

        [mode, mode_detail] = mode_judge_comm(comm_state, cfg, cfg.scenario.force_island);

        % EMS调度
        constraints = island_constraint_calc(state, cfg);
        if mode == 1  % COOPERATE
            [dispatch, admm_info] = admm_distributed_opt(state, constraints, cfg, comm_state);
            reserve = coop_constraint_allocate(state, ...
                neighbor_data_exchange(state, dispatch, admm_info, cfg, comm_state), dispatch, cfg);
        else
            dispatch = vpp_island_ems(state, forecast, constraints, cfg);
            admm_info = struct('iterations', 0, 'primal_residual', 0, ...
                               'dual_residual', 0, 'converged', false, ...
                               'exchange_power', zeros(Nv, Nv));
        end

        % PI调频 (外环)
        freq_dev = zeros(1, Nv);
        if isfield(cfg.data, 'freq_deviation')
            freq_dev = cfg.data.freq_deviation(t, :);
        end
        state.freq = cfg.f_nom + freq_dev;
        [dispatch, freq_new, volt_new, pi_state] = freq_volt_pi_control(...
            dispatch, state, dt_outer_h, cfg, pi_state);

        % ======== 内环: 亚秒级快动态 ========
        if scfg.fast_dynamics
            [state, fast, record_idx, pi_state, proto_state, tcp_state] = ...
                run_inner_loop(state, dispatch, cfg, scfg, t, ...
                               fast, record_idx, pi_state, fault_active, ...
                               proto_state, tcp_state);
        end

        % 约束限幅
        s_prev.P_pv_avail    = state.P_pv_avail;
        s_prev.P_wind_avail  = state.P_wind_avail;
        s_prev.P_tidal_avail = state.P_tidal_avail;
        s_prev.P_gas_prev    = state.P_gas_prev;
        s_prev.P_bat_prev    = state.P_bat_prev;
        s_prev.SOC_prev      = state.SOC;
        [dispatch, violations] = power_limit_handler(dispatch, s_prev, cfg);

        % 状态更新
        [state.P_gas_prev, ~, ~] = gas_unit_model(dispatch.P_gas, state.P_gas_prev, dt_outer_h, cfg.Gas);
        [state.SOC, state.P_bat_prev, ~] = battery_bms_model(dispatch.P_bat, state.SOC, dt_outer_h, cfg.Battery);
        state.P_bat_prev = dispatch.P_bat;
        [~, ~, ~] = interrupt_load(dispatch.P_shed, cfg.Load.interruptible);
        if scfg.fast_dynamics
            % 频率和电压已在内环更新
        else
            state.freq = freq_new;
            state.volt = volt_new;
        end

        % 记录外环历史
        hist.P_pv(t, :)      = state.P_pv_avail;
        hist.P_wind(t, :)    = state.P_wind_avail;
        hist.P_tidal(t, :)   = state.P_tidal_avail;
        hist.P_gas(t, :)     = state.P_gas_prev;
        hist.P_bat(t, :)     = state.P_bat_prev;
        hist.P_load(t, :)    = state.P_load;
        hist.P_shed(t, :)    = dispatch.P_shed;
        hist.P_curtail(t, :) = dispatch.P_curtail_pv + dispatch.P_curtail_wind + dispatch.P_curtail_tidal;
        hist.SOC(t, :)       = state.SOC;
        hist.freq(t, :)      = state.freq;
        hist.volt(t, :)      = state.volt;
        hist.mode(t)         = mode;
        hist.cost(t, :)      = dispatch.total_cost;

        if mod(t, ceil(N_outer/10)) == 0
            fprintf('  外环: %d/%d (%.1f%%), 内环记录: %d点, 耗时: %.1fs\n', ...
                    t, N_outer, 100*t/N_outer, record_idx, toc);
        end
    end

    elapsed = toc;
    fprintf('\n[仿真完成] 总耗时: %.1fs (含%d个外环步 + %d个内环步)\n', ...
            elapsed, N_outer, record_idx);

    % 后处理
    results = struct();
    results.cfg  = cfg;
    results.hist = hist;
    results.fast = fast;
    results.scfg = scfg;
    results.eco_index = calculate_eco_index(hist, cfg);
    results.alarms = safety_alarm_check(hist, cfg);

    % 可视化（含快动态）
    plot_freq_power(results);
    if scfg.fast_dynamics
        plot_fast_dynamics(results);
    end
    plot_soc_trade(results);
    plot_index_bar(results);

    % 导出
    save_result_mat(results);
    export_csv_data(results);
    export_fast_csv(results, scfg);

    % 摘要
    fprintf('\n============================================\n');
    fprintf('  亚秒级仿真结果摘要\n');
    fprintf('============================================\n');
    fprintf('  仿真步长: 外环%.1fs + 内环%.3fs\n', scfg.dt_outer, scfg.dt_fast);
    fprintf('  快动态采样点: %d\n', record_idx);
    fprintf('  新能源消纳率: %.1f%%\n', results.eco_index.renewable_rate * 100);
    fprintf('  调度总成本:   %.2f 元\n', results.eco_index.total_cost);
    fprintf('  频率合格率:   %.1f%%\n', results.eco_index.freq_qualified_rate * 100);
    fprintf('============================================\n');
end


function [state, fast, record_idx, pi_state, proto_state, tcp_state] = ...
        run_inner_loop(state, dispatch, cfg, scfg, t_outer, ...
                       fast, record_idx, pi_state, fault_active, ...
                       proto_state, tcp_state)
    % 内环亚秒级仿真循环
    %
    % 仿真对象:
    %   1. 频率动态 (摆动方程 + 下垂控制)
    %   2. 电压动态 (励磁调节)
    %   3. 通信协议时序 (报文发送/接收/延迟)
    %   4. 保护动作检测
    %   5. TCP连接状态机推进

    Nv = cfg.N_vpp;
    Ni = scfg.inner_steps;
    dt = scfg.dt_fast;
    profile_int = scfg.profile_interval;

    % 简化的发电机摆动方程参数
    H = 3.0;       % 惯性常数 (s) — 典型VPP等效惯量
    D = 1.0;       % 阻尼系数 (p.u.)
    R_droop = 0.05; % 下垂系数 (5%)

    for k = 1:Ni
        t_inner_s = (t_outer - 1) * scfg.dt_outer + k * dt;

        % ---- 1. 频率动态 (摆动方程离散化) ----
        % ΔP = P_gen - P_load → df/dt = (ΔP - D*Δf) / (2*H)
        P_gen_total = dispatch.P_gas + dispatch.P_bat + dispatch.P_curtail_pv ...
                    + dispatch.P_curtail_wind + dispatch.P_curtail_tidal;
        P_load_total = state.P_load - dispatch.P_shed;

        delta_P = P_gen_total - P_load_total;  % 功率不平衡 (kW)
        delta_P_pu = delta_P / 1000;           % 粗略标幺化
        delta_f = state.freq - cfg.f_nom;

        % 欧拉积分
        df_dt = (delta_P_pu - D .* delta_f) ./ (2 * H);
        state.freq = state.freq + df_dt * dt;

        % 下垂控制修正
        delta_f_droop = -R_droop * delta_P_pu;
        state.freq = state.freq + 0.1 * (delta_f_droop - delta_f);  % 缓慢修正

        % ---- 2. 电压动态 (简化一阶滞后) ----
        tau_v = 0.5;  % 电压调节时间常数
        V_ref = 1.0;  % 参考电压 p.u.
        dV_dt = (V_ref - state.volt) / tau_v;
        state.volt = state.volt + dV_dt * dt;
        state.volt = max(0.85, min(1.15, state.volt));

        % ---- 3. 通信协议时序 (如果启用补丁04) ----
        if cfg.patches.protocol.enabled && mod(k, round(scfg.protocol_cycle / dt)) == 0
            proto_state = protocol_cycle_step(proto_state, cfg, state, t_inner_s);
        end

        % ---- 4. TCP连接状态机 (如果启用补丁05) ----
        if cfg.patches.tcp_handshake.enabled && mod(k, max(1, round(0.01 / dt))) == 0
            tcp_state = tcp_state_machine_step(tcp_state, cfg, fault_active, t_inner_s, dt);
        end

        % ---- 5. 保护检测 ----
        if mod(k, max(1, round(scfg.protection_check_interval / dt))) == 0
            for v = 1:Nv
                if state.freq(v) < cfg.Safety.freq_min || state.freq(v) > cfg.Safety.freq_max
                    % 触发保护动作：频率越限告警
                end
                if state.volt(v) < cfg.Safety.volt_min || state.volt(v) > cfg.Safety.volt_max
                    % 触发保护动作：电压越限告警
                end
            end
        end

        % ---- 6. 降采样记录 ----
        if mod(k, profile_int) == 0
            record_idx = record_idx + 1;
            if record_idx <= length(fast.time_s)
                fast.time_s(record_idx)    = t_inner_s;
                fast.freq(record_idx, :)   = state.freq;
                fast.volt(record_idx, :)   = state.volt;
                fast.df_dt(record_idx, :)  = df_dt;
                fast.P_fast(record_idx, :) = delta_P;
            end
        end
    end
end


function plot_fast_dynamics(results)
    % 绘制快动态结果
    fast = results.fast;
    scfg = results.scfg;

    figure('Name', '亚秒级快动态', 'Position', [100, 100, 1200, 600]);

    subplot(2,2,1);
    plot(fast.time_s / 3600, fast.freq);
    xlabel('时间 (h)'); ylabel('频率 (Hz)');
    title('频率快动态 (亚秒级)');
    grid on;

    subplot(2,2,2);
    plot(fast.time_s / 3600, fast.volt);
    xlabel('时间 (h)'); ylabel('电压 (p.u.)');
    title('电压快动态');
    grid on;

    subplot(2,2,3);
    plot(fast.time_s / 3600, fast.df_dt);
    xlabel('时间 (h)'); ylabel('df/dt (Hz/s)');
    title('RoCoF (频率变化率)');
    grid on;

    subplot(2,2,4);
    plot(fast.time_s / 3600, fast.P_fast);
    xlabel('时间 (h)'); ylabel('ΔP (kW)');
    title('功率不平衡');
    grid on;

    saveas(gcf, 'fast_dynamics.png');
    fprintf('  快动态图表已保存: fast_dynamics.png\n');
end


function export_fast_csv(results, scfg)
    % 导出快动态数据
    fast = results.fast;
    Nv = size(fast.freq, 2);

    fid = fopen('fast_dynamics.csv', 'w');
    header = 'Time_s';
    for v = 1:Nv
        header = sprintf('%s,VPP%d_Freq_Hz,VPP%d_Volt_pu,VPP%d_RoCoF_Hzs,VPP%d_dP_kW', ...
                         header, v, v, v, v);
    end
    fprintf(fid, '%s\n', header);

    for i = 1:length(fast.time_s)
        if fast.time_s(i) == 0 && i > 1
            break;
        end
        fprintf(fid, '%.6f', fast.time_s(i));
        for v = 1:Nv
            fprintf(fid, ',%.6f,%.6f,%.6f,%.4f', ...
                    fast.freq(i,v), fast.volt(i,v), fast.df_dt(i,v), fast.P_fast(i,v));
        end
        fprintf(fid, '\n');
    end
    fclose(fid);
    fprintf('  快动态CSV导出: fast_dynamics.csv\n');
end


function state = protocol_state_init(cfg, Nv)
    % 初始化通信协议状态
    state = struct();
    state.last_send_time = zeros(Nv, Nv);   % 最后发送时间
    state.msg_queue = cell(Nv, Nv);          % 消息队列
    state.msg_seq = zeros(Nv, Nv);          % 消息序列号
    state.stats = struct('sent', 0, 'received', 0, 'dropped', 0, 'latency_sum', 0);
end


function state = protocol_cycle_step(state, cfg, sys_state, t_now)
    % 通信协议循环步进（补丁04集成）
    % 在亚秒级内环中周期性调用，模拟协议报文收发
    % 详细实现在 04_vpp_protocol_stack/ 中

    % 轻量级集成桩：在每个协议周期更新通信统计
    Nv = size(state.last_send_time, 1);
    topo = cfg.Comm.topology;

    for i = 1:Nv
        for j = 1:Nv
            if topo(i, j) > 0 && i ~= j
                % 检查是否需要发送新报文
                interval = cfg.patches.protocol.iec61850_mms.report_interval_ms / 1000;
                if t_now - state.last_send_time(i, j) >= interval
                    state.last_send_time(i, j) = t_now;
                    state.msg_seq(i, j) = state.msg_seq(i, j) + 1;
                    state.stats.sent = state.stats.sent + 1;
                end
            end
        end
    end
end


function state = tcp_state_init(cfg, Nv)
    % 初始化TCP连接状态（补丁05集成）
    % 详细实现在 05_tcp_handshake_recovery/ 中
    state = struct();
    state.conn_status = ones(Nv, Nv);       % 0=CLOSED, 1=ESTABLISHED, 2=SYN_SENT, 3=SYN_RCVD
    state.conn_status(logical(eye(Nv))) = 1; % 自连接保持ESTABLISHED
    state.syn_retries = zeros(Nv, Nv);
    state.rto_ms = cfg.patches.tcp_handshake.initial_rto_ms * ones(Nv, Nv);
    state.srtt_ms = zeros(Nv, Nv);
    state.rttvar_ms = zeros(Nv, Nv);
    state.handshake_start_time = -ones(Nv, Nv);
    state.recovery_time_ms = zeros(Nv, Nv);
end


function state = tcp_state_machine_step(state, cfg, fault_active, t_now, dt)
    % TCP连接状态机步进（补丁05集成）
    % 详细实现在 05_tcp_handshake_recovery/ 中

    Nv = size(state.conn_status, 1);
    topo = cfg.Comm.topology;
    tcp_cfg = cfg.patches.tcp_handshake;

    for i = 1:Nv
        for j = 1:Nv
            if i == j || topo(i, j) == 0
                continue;
            end

            link_fault = fault_active(i, j) || fault_active(j, i);

            if link_fault && state.conn_status(i, j) == 1  % ESTABLISHED
                % 链路故障 → 连接断开
                state.conn_status(i, j) = 0;  % CLOSED
                state.handshake_start_time(i, j) = -1;

            elseif ~link_fault && state.conn_status(i, j) == 0  % CLOSED
                % 链路恢复 → 发起TCP三次握手
                state.conn_status(i, j) = 2;  % SYN_SENT
                state.syn_retries(i, j) = 0;
                state.handshake_start_time(i, j) = t_now;

            elseif state.conn_status(i, j) == 2  % SYN_SENT
                % 等待SYN-ACK (模拟RTT后收到)
                rtt = state.srtt_ms(i, j);
                if rtt == 0
                    rtt = tcp_cfg.initial_rto_ms;
                end
                elapsed = (t_now - state.handshake_start_time(i, j)) * 1000;

                if elapsed >= rtt * 0.5  % SYN-ACK到达 (RTT/2)
                    state.conn_status(i, j) = 3;  % SYN_RCVD
                elseif elapsed >= tcp_cfg.syn_timeout_ms
                    % SYN超时 → 重传
                    state.syn_retries(i, j) = state.syn_retries(i, j) + 1;
                    if state.syn_retries(i, j) >= tcp_cfg.max_syn_retries
                        state.conn_status(i, j) = 0;  % 放弃，回到CLOSED
                        state.syn_retries(i, j) = 0;
                    else
                        state.rto_ms(i, j) = min(state.rto_ms(i, j) * 2, tcp_cfg.max_rto_ms);
                        state.handshake_start_time(i, j) = t_now;  % 重新开始
                    end
                end

            elseif state.conn_status(i, j) == 3  % SYN_RCVD
                % 发送ACK (最后一跳)
                elapsed = (t_now - state.handshake_start_time(i, j)) * 1000;
                if elapsed >= state.rto_ms(i, j) * 0.75
                    % 握手完成
                    state.conn_status(i, j) = 1;  % ESTABLISHED
                    state.recovery_time_ms(i, j) = elapsed;
                    % RTO回退到初始值
                    state.rto_ms(i, j) = tcp_cfg.initial_rto_ms;
                end
            end
        end
    end
end
