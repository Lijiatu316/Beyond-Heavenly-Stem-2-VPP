% ============================================================
% 文件名：run_mode_cooperate.m
% 功能：网络良好-去中心化协同调度工况完整仿真
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
%
% 知识产权声明：
%   辅助工具/主控脚本，不包含核心算法创新。
%   版权所有归属项目团队。
% ============================================================

function results = run_mode_cooperate()
    % 协同调度模式完整仿真入口
    %
    % 与孤岛模式的核心区别:
    %   - VPP间通过ADMM迭代交换信息，实现全局协同优化
    %   - 功率可以在VPP间流动（互济），降低成本
    %   - 频率由全局PI控制协调，稳定性更好
    %
    % 输出:
    %   results - 仿真结果结构体

    fprintf('============================================\n');
    fprintf('  去中心化虚拟电厂 — 协同调度仿真\n');
    fprintf('============================================\n\n');

    % ============ Step 0: 参数初始化 ============
    fprintf('[Step 0] 加载全局参数...\n');
    cfg = param_global_config();
    cfg.scenario.force_island = false;  % 允许协同模式
    cfg.scenario.mode = 'cooperate';

    % ADMM参数 (如果param_global_config中没有，使用默认值)
    if ~isfield(cfg, 'ADMM')
        cfg.ADMM = struct();
    end
    if ~isfield(cfg.ADMM, 'rho'),       cfg.ADMM.rho       = 0.5;    end
    if ~isfield(cfg.ADMM, 'max_iter'),  cfg.ADMM.max_iter  = 50;     end
    if ~isfield(cfg.ADMM, 'tolerance'), cfg.ADMM.tolerance = 0.005;  end

    Nv = cfg.N_vpp;
    N  = cfg.N_steps;
    dt = cfg.dt;

    % ============ Step 1: 状态变量初始化 ============
    fprintf('[Step 1] 初始化状态变量...\n');

    % 历史记录
    hist.time       = cfg.time;
    hist.P_pv       = zeros(N, Nv);
    hist.P_wind     = zeros(N, Nv);
    hist.P_tidal    = zeros(N, Nv);
    hist.P_gas      = zeros(N, Nv);
    hist.P_bat      = zeros(N, Nv);
    hist.P_load     = zeros(N, Nv);
    hist.P_shed     = zeros(N, Nv);
    hist.P_curtail  = zeros(N, Nv);
    hist.SOC        = zeros(N, Nv);
    hist.freq       = zeros(N, Nv);
    hist.volt       = zeros(N, Nv);
    hist.mode       = zeros(N, 1);
    hist.cost       = zeros(N, Nv);
    % 协同特有记录 — 动态链路
    hist.admm_iter      = zeros(N, 1);
    hist.admm_residual  = zeros(N, 1);
    % 动态扩展交换功率记录：根据拓扑上三角链路创建
    topo = cfg.Comm.topology;
    exchange_links = [];  % [from, to] pairs
    for i = 1:Nv
        for j = i+1:Nv
            if topo(i,j) > 0
                exchange_links(end+1, :) = [i, j];
                field_name = sprintf('exchange_VPP%d%d', i, j);
                hist.(field_name) = zeros(N, 1);
            end
        end
    end
    hist.exchange_links = exchange_links;
    % Per-link delay storage — one column per connected link
    hist.comm_delay_links = zeros(N, size(exchange_links,1));

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
    state.freq_dev     = zeros(1, Nv);

    % PI控制状态
    pi_state = [];

    % 潮汐状态
    tidal_state = [];

    % 频率偏差历史 (从cfg.data获取)
    if isfield(cfg.data, 'freq_deviation')
        freq_dev_history = cfg.data.freq_deviation;
    else
        freq_dev_history = zeros(N, Nv);
    end

    % 通信 — 协同模式通信正常 (无故障)
    fault_active = false(Nv);

    % ============ Step 2: 时间步循环 ============
    fprintf('[Step 2] 开始时序仿真 (%d步, dt=%.2fh)...\n', N, dt);
    tic;

    for t = 1:N
        t_now = cfg.time(t);

        % ---- 2.1 设备出力计算 ----
        incidence_angle = 65 * abs(cos(pi * (t_now - 12) / 14));
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
                cfg.data.tide_height(t) * ones(1, Nv), prev_basin, dt, cfg.Tidal);
        else
            state.P_tidal_avail = zeros(1, Nv);
        end

        % ---- 2.2 负荷 ----
        state.P_load = cfg.data.load_rigid(t, :);

        % ---- 2.3 预测 ----
        if t > 1
            hist_pv   = hist.P_pv(1:t, :);
            hist_wind = hist.P_wind(1:t, :);
            hist_load = hist.P_load(1:t, :);
        else
            hist_pv   = state.P_pv_avail;
            hist_wind = state.P_wind_avail;
            hist_load = state.P_load;
        end
        fc.P_pv = hist_pv; fc.P_wind = hist_wind; fc.P_load = hist_load;
        forecast = power_forecast(fc, t, cfg);

        % ---- 2.4 通信检测 ----
        comm_state = comm_delay_sim(cfg, t, fault_active);
        [mode, mode_detail] = mode_judge_comm(comm_state, cfg, false);

        % ---- 2.5 安全约束 ----
        constraints = island_constraint_calc(state, cfg);

        % ---- 2.6 协同ADMM优化 (核心差异) ----
        if mode == 1  % COOPERATE模式
            [dispatch, admm_info] = admm_distributed_opt(state, constraints, cfg, comm_state);
            % 邻域数据交换
            exchange_data = neighbor_data_exchange(state, dispatch, admm_info, cfg, comm_state);
            % 备用容量分配
            reserve = coop_constraint_allocate(state, exchange_data, dispatch, cfg);
        else
            % 通信异常 → 降级为孤岛模式
            dispatch = vpp_island_ems(state, forecast, constraints, cfg);
            admm_info = struct('iterations', 0, 'primal_residual', 0, ...
                               'dual_residual', 0, 'converged', false, ...
                               'exchange_power', zeros(Nv, Nv));
        end

        % ---- 2.7 PI调频修正 (协同模式下频率更稳定) ----
        state.freq_dev = freq_dev_history(t, :);
        state.freq = cfg.f_nom + state.freq_dev;
        [dispatch, freq_new, volt_new, pi_state] = freq_volt_pi_control(...
            dispatch, state, dt, cfg, pi_state);

        % ---- 2.8 约束限幅 ----
        s_prev.P_pv_avail    = state.P_pv_avail;
        s_prev.P_wind_avail  = state.P_wind_avail;
        s_prev.P_tidal_avail = state.P_tidal_avail;
        s_prev.P_gas_prev    = state.P_gas_prev;
        s_prev.P_bat_prev    = state.P_bat_prev;
        s_prev.SOC_prev      = state.SOC;
        [dispatch, violations] = power_limit_handler(dispatch, s_prev, cfg);

        % ---- 2.9 更新状态 ----
        [state.P_gas_prev, ~, ~] = gas_unit_model(...
            dispatch.P_gas, state.P_gas_prev, dt, cfg.Gas);
        [state.SOC, state.P_bat_prev, ~] = battery_bms_model(...
            dispatch.P_bat, state.SOC, dt, cfg.Battery);
        state.P_bat_prev = dispatch.P_bat;
        [~, ~, ~] = interrupt_load(dispatch.P_shed, cfg.Load.interruptible);
        state.freq = freq_new;
        state.volt = volt_new;

        % ---- 2.10 记录历史 ----
        hist.P_pv(t, :)    = state.P_pv_avail;
        hist.P_wind(t, :)  = state.P_wind_avail;
        hist.P_tidal(t, :) = state.P_tidal_avail;
        hist.P_gas(t, :)   = state.P_gas_prev;
        hist.P_bat(t, :)   = state.P_bat_prev;
        hist.P_load(t, :)  = state.P_load;
        hist.P_shed(t, :)  = dispatch.P_shed;
        hist.P_curtail(t, :)= dispatch.P_curtail_pv + dispatch.P_curtail_wind + dispatch.P_curtail_tidal;
        hist.SOC(t, :)     = state.SOC;
        hist.freq(t, :)    = state.freq;
        hist.volt(t, :)    = state.volt;
        hist.mode(t)       = mode;
        hist.cost(t, :)    = dispatch.total_cost;

        % 协同特有记录
        hist.admm_iter(t)      = admm_info.iterations;
        hist.admm_residual(t)  = admm_info.primal_residual;
        % Store per-link delay (not just mean)
        for k = 1:size(exchange_links,1)
            i = exchange_links(k,1); j = exchange_links(k,2);
            hist.comm_delay_links(t, k) = comm_state.delay(i, j);
        end
        % 动态记录所有链路的交换功率
        for k = 1:size(exchange_links, 1)
            i = exchange_links(k, 1); j = exchange_links(k, 2);
            fname = sprintf('exchange_VPP%d%d', i, j);
            if size(admm_info.exchange_power, 1) >= max(i, j)
                hist.(fname)(t) = admm_info.exchange_power(i, j);
            end
        end

        % ---- 进度 ----
        if mod(t, ceil(N/10)) == 0
            fprintf('  进度: %d/%d (%.1f%%), ADMM iter=%d, 耗时: %.1fs\n', ...
                    t, N, 100*t/N, admm_info.iterations, toc);
        end
    end

    elapsed = toc;
    fprintf('\n[Step 2] 仿真完成! 总耗时: %.1fs\n\n', elapsed);

    % ============ Step 3: 结果后处理 ============
    fprintf('[Step 3] 计算评价指标...\n');
    results = struct();
    results.cfg  = cfg;
    results.hist = hist;
    results.eco_index = calculate_eco_index(hist, cfg);
    results.alarms = safety_alarm_check(hist, cfg);

    % ============ Step 4: 可视化 ============
    fprintf('[Step 4] 生成可视化图表...\n');
    plot_freq_power(results);
    plot_soc_trade(results);
    plot_index_bar(results);

    % ============ Step 5: 导出 ============
    fprintf('[Step 5] 导出数据...\n');
    save_result_mat(results);
    export_csv_data(results);

    % 导出协同专用CSV
    export_cooperate_csv(results, cfg);

    % ============ 结果摘要 ============
    fprintf('\n============================================\n');
    fprintf('  协同模式仿真结果摘要\n');
    fprintf('============================================\n');
    fprintf('  新能源消纳率:  %.1f%%\n', results.eco_index.renewable_rate * 100);
    fprintf('  调度总成本:    %.2f 元\n', results.eco_index.total_cost);
    fprintf('  频率合格率:    %.1f%%\n', results.eco_index.freq_qualified_rate * 100);
    fprintf('  供电可靠性:    %.1f%%\n', results.eco_index.reliability * 100);
    fprintf('  切负荷总量:    %.1f kWh\n', sum(hist.P_shed(:)) * dt);
    fprintf('  平均ADMM迭代:  %.1f 次\n', mean(hist.admm_iter));
    fprintf('  告警次数:      %d 次\n', results.alarms.total_alarms);
    fprintf('============================================\n');
    fprintf('\n仿真结束。\n');
end


function export_cooperate_csv(results, cfg)
    % 导出协同模式专用CSV (含VPP间交换功率、ADMM残差、通信延迟)
    %
    % 生成 cooperate_timeseries.csv
    % 格式与孤岛模式 island_timeseries.csv 一致，额外增加:
    %   VPP12_Exchange_kW, VPP23_Exchange_kW, VPP31_Exchange_kW
    %   ADMM_Residual, Comm_Delay_ms

    h = results.hist;
    N = size(h.P_pv, 1);
    dt_h = cfg.dt;

    % 构建表头
    header = 'Time_h';
    for v = 1:cfg.N_vpp
        header = sprintf('%s,VPP%d_PV_kW', header, v);
    end
    for v = 1:cfg.N_vpp
        header = sprintf('%s,VPP%d_Wind_kW', header, v);
    end
    for v = 1:cfg.N_vpp
        header = sprintf('%s,VPP%d_Gas_kW', header, v);
    end
    for v = 1:cfg.N_vpp
        header = sprintf('%s,VPP%d_Bat_kW', header, v);
    end
    for v = 1:cfg.N_vpp
        header = sprintf('%s,VPP%d_Load_kW', header, v);
    end
    for v = 1:cfg.N_vpp
        header = sprintf('%s,VPP%d_Shed_kW', header, v);
    end
    for v = 1:cfg.N_vpp
        header = sprintf('%s,VPP%d_Curtail_kW', header, v);
    end
    for v = 1:cfg.N_vpp
        header = sprintf('%s,VPP%d_SOC', header, v);
    end
    for v = 1:cfg.N_vpp
        header = sprintf('%s,VPP%d_Freq_Hz', header, v);
    end
    % 动态添加交换功率列
    links = results.hist.exchange_links;
    for k = 1:size(links, 1)
        header = sprintf('%s,VPP%d%d_Exchange_kW', header, links(k,1), links(k,2));
    end
    % Per-link delay columns
    for k = 1:size(links,1)
        header = sprintf('%s,VPP%d%d_Delay_ms', header, links(k,1), links(k,2));
    end
    header = sprintf('%s,ADMM_Residual', header);

    % 写入数据
    fid = fopen('cooperate_timeseries.csv', 'w');
    fprintf(fid, '%s\n', header);

    for t = 1:N
        fprintf(fid, '%.6f', cfg.time(t));
        for v = 1:cfg.N_vpp, fprintf(fid, ',%.4f', h.P_pv(t, v)); end
        for v = 1:cfg.N_vpp, fprintf(fid, ',%.4f', h.P_wind(t, v)); end
        for v = 1:cfg.N_vpp, fprintf(fid, ',%.4f', h.P_gas(t, v)); end
        for v = 1:cfg.N_vpp, fprintf(fid, ',%.4f', h.P_bat(t, v)); end
        for v = 1:cfg.N_vpp, fprintf(fid, ',%.4f', h.P_load(t, v)); end
        for v = 1:cfg.N_vpp, fprintf(fid, ',%.4f', h.P_shed(t, v)); end
        for v = 1:cfg.N_vpp, fprintf(fid, ',%.4f', h.P_curtail(t, v)); end
        for v = 1:cfg.N_vpp, fprintf(fid, ',%.6f', h.SOC(t, v)); end
        for v = 1:cfg.N_vpp, fprintf(fid, ',%.6f', h.freq(t, v)); end
        % 动态写出交换功率
        for k = 1:size(links, 1)
            fname = sprintf('exchange_VPP%d%d', links(k,1), links(k,2));
            fprintf(fid, ',%.4f', h.(fname)(t));
        end
        % Per-link delay
        for k = 1:size(links, 1)
            fprintf(fid, ',%.3f', h.comm_delay_links(t, k) * 1000);
        end
        fprintf(fid, ',%.6f', h.admm_residual(t));
        fprintf(fid, '\n');
    end

    fclose(fid);
    fprintf('  协同CSV导出: cooperate_timeseries.csv (%d行 x %d列)\n', N, 1+9*cfg.N_vpp+size(links,1)+2);
end
