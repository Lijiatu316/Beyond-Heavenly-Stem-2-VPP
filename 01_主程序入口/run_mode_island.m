% ============================================================
% 文件名：run_mode_island.m
% 功能：单独运行网络故障-离线自治孤岛工况（全程断网仿真）
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   辅助工具/主控脚本，不包含核心算法创新。
%   版权所有归属项目团队。
% ============================================================

function results = run_mode_island()
    % 孤岛自治模式完整仿真入口
    %
    % 输出:
    %   results - 仿真结果结构体，包含全部时序数据和指标

    fprintf('============================================\n');
    fprintf('  去中心化虚拟电厂 — 孤岛自治仿真\n');
    fprintf('============================================\n\n');

    % ============ Step 0: 参数初始化 ============
    fprintf('[Step 0] 加载全局参数...\n');
    cfg = param_global_config();
    cfg.scenario.force_island = true;  % 全程孤岛

    Nv = cfg.N_vpp;
    N  = cfg.N_steps;
    dt = cfg.dt;

    % ============ Step 1: 状态变量初始化 ============
    fprintf('[Step 1] 初始化状态变量...\n');

    % 历史记录缓冲区
    hist.time       = cfg.time;
    hist.P_pv       = zeros(N, Nv);
    hist.P_wind     = zeros(N, Nv);
    hist.P_tidal    = zeros(N, Nv);
    hist.P_gas      = zeros(N, Nv);
    hist.P_bat      = zeros(N, Nv);  % 正值放电，负值充电
    hist.P_load     = zeros(N, Nv);
    hist.P_shed     = zeros(N, Nv);
    hist.P_curtail  = zeros(N, Nv);  % 弃风弃光总量
    hist.SOC        = zeros(N, Nv);
    hist.freq       = zeros(N, Nv);
    hist.volt       = zeros(N, Nv);
    hist.mode       = zeros(N, 1);   % 1=ISLAND, 0=COOPERATE
    hist.cost       = zeros(N, Nv);

    % 初始状态
    state.SOC        = cfg.Battery.SOC0;
    state.P_gas_prev = zeros(1, Nv);
    state.P_bat_prev = zeros(1, Nv);
    state.freq       = cfg.f_nom * ones(1, Nv);  % 初始频率 = 标称值
    state.volt       = ones(1, Nv);              % 初始电压 = 1.0 p.u.
    state.P_pv_avail   = zeros(1, Nv);
    state.P_wind_avail = zeros(1, Nv);
    state.P_tidal_avail = zeros(1, Nv);
    state.P_load       = zeros(1, Nv);

    % PI控制器状态
    pi_state = [];

    % 潮汐状态
    tidal_state = [];  % 库区水位

    % 频率——由PI控制器内生计算，不再从外部CSV读
    % 初始频率 = 标称值，后续由freq_volt_pi_control动态计算

    % 通信故障（全程激活）
    fault_active = comm_fault_trigger(0, [], cfg.Comm.topology, true);

    % ============ Step 2: 时间步循环 ============
    fprintf('[Step 2] 开始时序仿真 (%d步, dt=%.2fh)...\n', N, dt);
    tic;

    for t = 1:N
        t_now = cfg.time(t);

        % ---- 2.1 设备出力计算 ----
        % 太阳入射角（日变化: 正午≈0°→日升/日落≈70°）
        incidence_angle = 65 * abs(cos(pi * (t_now - 12) / 14));
        % 光伏（对接预测汇总/pv_model_engine.py的真实物理公式）
        state.P_pv_avail   = pv_model(cfg.data.irradiance(t, :), ...
                                      cfg.data.temperature(t, :), cfg.PV, ...
                                      incidence_angle * ones(1, Nv), ...
                                      cfg.data.wind_speed(t, :));
        % 风电
        state.P_wind_avail = wind_model(cfg.data.wind_speed(t, :), cfg.Wind);

        % 潮汐发电（对接预测汇总/潮汐/电站参数.xlsx — 江厦潮汐电站）
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

        % ---- 2.2 负荷计算 ----
        state.P_load = cfg.data.load_rigid(t, :);

        % ---- 2.3 功率预测 ----
        % 构建历史结构体
        if t > 1
            hist_pv   = hist.P_pv(1:t, :);
            hist_wind = hist.P_wind(1:t, :);
            hist_load = hist.P_load(1:t, :);
        else
            hist_pv   = state.P_pv_avail;
            hist_wind = state.P_wind_avail;
            hist_load = state.P_load;
        end
        forecast_input.P_pv   = hist_pv;
        forecast_input.P_wind = hist_wind;
        forecast_input.P_load = hist_load;
        forecast = power_forecast(forecast_input, t, cfg);

        % ---- 2.4 通信检测 + 模式判定 ----
        comm_state = comm_delay_sim(cfg, t, fault_active);
        [mode, mode_detail] = mode_judge_comm(comm_state, cfg, true);
        % mode=2 表示ISLAND

        % ---- 2.5 孤岛安全约束 ----
        constraints = island_constraint_calc(state, cfg);

        % ---- 2.6 孤岛EMS优化 ----
        dispatch = vpp_island_ems(state, forecast, constraints, cfg);

        % ---- 2.7 PI调频修正 ----
        % 频率动态内生计算：从真实功率缺口通过下垂+惯性模型算出
        % 不再使用外部CSV的虚假频率数据
        [dispatch, freq_new, volt_new, pi_state] = freq_volt_pi_control(...
            dispatch, state, dt, cfg, pi_state);

        % ---- 2.8 统一约束限幅 ----
        state_prev.P_pv_avail    = state.P_pv_avail;
        state_prev.P_wind_avail  = state.P_wind_avail;
        state_prev.P_tidal_avail = state.P_tidal_avail;
        state_prev.P_gas_prev    = state.P_gas_prev;
        state_prev.P_bat_prev    = state.P_bat_prev;
        state_prev.SOC_prev      = state.SOC;

        [dispatch, violations] = power_limit_handler(dispatch, state_prev, cfg);

        % ---- 2.9 执行调度，更新状态 ----
        % 燃气轮机
        [state.P_gas_prev, ~, ~] = gas_unit_model(...
            dispatch.P_gas, state.P_gas_prev, dt, cfg.Gas);

        % 储能
        [state.SOC, state.P_bat_prev, ~] = battery_bms_model(...
            dispatch.P_bat, state.SOC, dt, cfg.Battery);
        state.P_bat_prev = dispatch.P_bat;

        % 切负荷
        [~, ~, ~] = interrupt_load(dispatch.P_shed, cfg.Load.interruptible);

        % 更新频率和电压
        state.freq = freq_new;
        state.volt = volt_new;

        % ---- 2.10 记录历史 ----
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

        % ---- 进度输出 ----
        if mod(t, ceil(N/10)) == 0
            fprintf('  进度: %d/%d (%.1f%%), 耗时: %.1fs\n', ...
                    t, N, 100*t/N, toc);
        end
    end

    elapsed = toc;
    fprintf('\n[Step 2] 仿真完成! 总耗时: %.1fs\n\n', elapsed);

    % ============ Step 3: 结果后处理 ============
    fprintf('[Step 3] 计算评价指标...\n');

    results = struct();
    results.cfg  = cfg;
    results.hist = hist;

    % 经济指标
    results.eco_index = calculate_eco_index(hist, cfg);

    % 安全告警
    results.alarms = safety_alarm_check(hist, cfg);

    % ============ Step 4: 可视化 ============
    fprintf('[Step 4] 生成可视化图表...\n');

    plot_freq_power(results);
    plot_soc_trade(results);
    plot_index_bar(results);

    % ============ Step 5: 数据导出 ============
    fprintf('[Step 5] 导出数据...\n');

    save_result_mat(results);
    export_csv_data(results);

    % ============ 结果摘要 ============
    fprintf('\n============================================\n');
    fprintf('  仿真结果摘要\n');
    fprintf('============================================\n');
    fprintf('  新能源消纳率:  %.1f%%\n', results.eco_index.renewable_rate * 100);
    fprintf('  调度总成本:    %.2f 元\n', results.eco_index.total_cost);
    fprintf('  频率合格率:    %.1f%%\n', results.eco_index.freq_qualified_rate * 100);
    fprintf('  供电可靠性:    %.1f%%\n', results.eco_index.reliability * 100);
    fprintf('  切负荷总量:    %.1f kWh\n', sum(hist.P_shed(:)) * dt);
    fprintf('  告警次数:      %d 次\n', results.alarms.total_alarms);
    fprintf('============================================\n');

    fprintf('\n仿真结束。\n');
end
