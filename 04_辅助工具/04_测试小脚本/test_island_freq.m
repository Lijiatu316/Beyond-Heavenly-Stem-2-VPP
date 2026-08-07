% ============================================================
% 文件名：test_island_freq.m
% 功能：单独测试孤岛调频效果（阶跃扰动+PI响应验证）
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   辅助工具/主控脚本，不包含核心算法创新。
%   版权所有归属项目团队。
% ============================================================

function test_island_freq()
    % 孤岛调频效果专项测试
    %
    % 测试内容:
    %   1. 阶跃负荷扰动下的频率响应
    %   2. PI控制器收敛性
    %   3. 频率恢复时间

    fprintf('============================================\n');
    fprintf('  孤岛调频效果专项测试\n');
    fprintf('============================================\n\n');

    % 加载配置
    cfg = param_global_config();
    cfg.scenario.force_island = true;

    % 简化测试：单VPP、短时仿真
    Nv = 1;
    dt = cfg.dt;
    N = 200;  % 20小时（足够观察调频响应）

    % ---- 构建测试场景 ----
    % 恒风光、恒负荷 + 阶跃扰动
    P_pv_const   = 200;   % kW
    P_wind_const = 100;   % kW
    P_load_base  = 250;   % kW
    P_load_step  = 80;    % kW 阶跃扰动量

    t = (0:dt:(N-1)*dt)';

    % 负荷：50步后加入阶跃
    P_load = P_load_base * ones(N, Nv);
    P_load(60:end, :) = P_load_base + P_load_step;

    % 频率偏差初始
    rng(42);
    freq_dev = 0.05 * randn(N, Nv);  % 小幅噪声

    % ---- 初始化状态 ----
    state.SOC       = [0.6];
    state.P_gas_prev = [100];
    state.P_bat_prev = [0];
    state.freq      = cfg.f_nom;
    state.P_pv_avail   = [P_pv_const];
    state.P_wind_avail = [P_wind_const];
    state.P_load       = [P_load_base];
    state.freq_dev     = [0];

    pi_state = [];

    % ---- 记录变量 ----
    rec = struct();
    rec.t      = t;
    rec.freq   = zeros(N, 1);
    rec.P_gas  = zeros(N, 1);
    rec.P_bat  = zeros(N, 1);
    rec.P_load = P_load;
    rec.delta_P_PI = zeros(N, 1);

    for k = 1:N
        state.P_load = P_load(k, :);

        % 简单约束
        constraints = struct();
        constraints.P_gas_min = 0;
        constraints.P_gas_max = cfg.Gas.P_max(1);
        constraints.P_bat_ch_max = cfg.Battery.P_ch_max(1);
        constraints.P_bat_dis_max = cfg.Battery.P_dis_max(1);
        constraints.P_shed_max = cfg.Load.interruptible.capacity(1);
        constraints.P_curtail_pv_max = P_pv_const;
        constraints.P_curtail_wind_max = P_wind_const;
        constraints.P_net_load = P_load(k) - P_pv_const - P_wind_const;
        constraints.needs_shedding = false;
        constraints.min_shedding = 0;

        % 启发式调度（不用fmincon，简化测试）
        dispatch.P_gas = 100;
        dispatch.P_bat = 0;
        dispatch.P_shed = 0;
        dispatch.P_curtail_pv = 0;
        dispatch.P_curtail_wind = 0;

        % 频率偏差（叠加噪声+不平衡引起）
        P_imbalance = P_pv_const + P_wind_const + dispatch.P_gas + dispatch.P_bat ...
                      - P_load(k) + dispatch.P_shed + dispatch.P_curtail_pv + dispatch.P_curtail_wind;
        state.freq_dev = -0.01 * P_imbalance / 100 + freq_dev(k);  % 简化频率响应模型
        state.freq = cfg.f_nom + state.freq_dev;

        % PI调频
        [dispatch_corrected, freq_new, pi_state] = freq_volt_pi_control(...
            dispatch, state, dt, cfg, pi_state);

        % 记录
        rec.freq(k)   = freq_new;
        rec.P_gas(k)  = dispatch_corrected.P_gas;
        rec.P_bat(k)  = dispatch_corrected.P_bat;
        if k == 1
            rec.delta_P_PI(k) = 0;
        else
            rec.delta_P_PI(k) = dispatch_corrected.P_gas - dispatch.P_gas + ...
                                dispatch_corrected.P_bat - dispatch.P_bat;
        end

        % 更新状态
        state.freq = freq_new;
        state.P_gas_prev = dispatch_corrected.P_gas;
        state.P_bat_prev = dispatch_corrected.P_bat;
    end

    % ---- 结果分析 ----
    % 阶跃后恢复时间（频率回到 50±0.05Hz）
    step_idx = 60;
    post_step_freq = rec.freq(step_idx:end);
    settled = abs(post_step_freq - cfg.f_nom) < 0.05;
    recovery_steps = find(settled, 1, 'first');
    if ~isempty(recovery_steps)
        recovery_time = recovery_steps * dt * 60;  % 分钟
    else
        recovery_time = NaN;
    end

    % ---- 可视化 ----
    figure('Name', '调频测试', 'Position', [150, 150, 1100, 500]);

    subplot(2, 2, 1);
    hold on; grid on;
    plot(t, rec.freq, 'b-', 'LineWidth', 1.5);
    yline(cfg.f_nom, 'k--');
    yline(cfg.Safety.freq_max, 'r--');
    yline(cfg.Safety.freq_min, 'r--');
    xline(t(step_idx), 'g--', 'LineWidth', 1.5, 'Label', '阶跃时刻');
    xlabel('时间 (h)'); ylabel('频率 (Hz)');
    title('频率响应');
    legend('系统频率', '标称50Hz', 'Location', 'best');

    subplot(2, 2, 2);
    hold on; grid on;
    plot(t, rec.P_gas, 'r-', 'LineWidth', 1.2, 'DisplayName', '燃气');
    plot(t, rec.P_bat, 'b-', 'LineWidth', 1.2, 'DisplayName', '储能');
    plot(t, rec.P_load, 'k-', 'LineWidth', 1.5, 'DisplayName', '负荷');
    xline(t(step_idx), 'g--');
    xlabel('时间 (h)'); ylabel('功率 (kW)');
    title('出力响应');
    legend('Location', 'best');

    subplot(2, 2, 3);
    hold on; grid on;
    plot(t, rec.delta_P_PI, 'm-', 'LineWidth', 1.2);
    xline(t(step_idx), 'g--');
    xlabel('时间 (h)'); ylabel('\Delta P_{PI} (kW)');
    title('PI调频出力修正量');

    subplot(2, 2, 4);
    bar(categorical({'阶跃量(kW)','恢复时间(min)','最大频偏(Hz)','稳态频偏(Hz)'}), ...
        [P_load_step, recovery_time, ...
         max(abs(rec.freq(step_idx:end)-cfg.f_nom)), ...
         abs(mean(rec.freq(end-20:end))-cfg.f_nom)]);
    title('测试指标');
    grid on;

    sgtitle('孤岛调频PI控制 — 阶跃扰动测试');

    % ---- 测试报告 ----
    fprintf('\n============================================\n');
    fprintf('  调频测试结果\n');
    fprintf('============================================\n');
    fprintf('  阶跃扰动量:    %d kW\n', P_load_step);
    fprintf('  最大频偏:      %.3f Hz\n', max(abs(rec.freq(step_idx:end) - cfg.f_nom)));
    fprintf('  稳态频偏:      %.3f Hz\n', abs(mean(rec.freq(end-20:end)) - cfg.f_nom));
    if ~isnan(recovery_time)
        fprintf('  恢复时间:      %.1f 分钟\n', recovery_time);
    else
        fprintf('  恢复时间:      未恢复到稳态\n');
    end
    fprintf('  PI积分终值:    %.3f\n', pi_state.integral(end));
    fprintf('============================================\n');

    % 合格判定
    max_dev = max(abs(rec.freq(step_idx:end) - cfg.f_nom));
    if max_dev < 0.5 && ~isnan(recovery_time) && recovery_time < 30
        fprintf('\n✓ 调频测试通过\n');
    else
        fprintf('\n✗ 调频测试未达标（需调整PI参数）\n');
    end
end
