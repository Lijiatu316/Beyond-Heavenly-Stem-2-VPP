% ============================================================
% 文件名：freq_volt_pi_control.m
% 功能：孤岛一次+二次调频调压闭环PI控制
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

function [dispatch_corrected, freq_new, volt_new, pi_state] = freq_volt_pi_control(dispatch, state, dt, cfg, pi_state_prev)
    % 孤岛调频调压PI闭环控制（闭环：PI修正→更新ΔP→反馈到频率）
    %
    % 频率动态模型（下垂+一阶惯性）：
    %   Δf_steady = -(R / P_base) × ΔP       (下垂稳态偏差)
    %   Δf_new = α×Δf_prev + (1-α)×Δf_steady  (一阶惯性滞后)
    %   α = exp(-dt×3600 / T_f), T_f ≈ 5s
    %
    % PI控制器（二次调频，消除稳态偏差）：
    %   ΔP_PI = Kp × Δf + Ki × ∫Δf dt
    %
    % 流程: ①PI计算修正量 → ②修正dispatch → ③用修正后ΔP更新频率
    %
    % 输入:
    %   dispatch     - EMS调度指令结构体
    %   state        - 当前系统状态
    %   dt           - 控制步长 (h)
    %   cfg          - 全局配置
    %   pi_state_prev- 上一时刻PI状态
    %
    % 输出:
    %   dispatch_corrected - 修正后的调度指令
    %   freq_new           - 更新后的频率 (Hz)
    %   pi_state           - PI控制器状态

    Nv = cfg.N_vpp;
    f_nom = cfg.f_nom;

    % PI参数和频率动态参数
    % 采用"纯下垂一次调频 + PI积分二次调频"模型（模拟真实电网调频机制）
    if ~isfield(cfg, 'PI')
        cfg.PI.Kp = 200;         % 比例增益 (kW/Hz)
        cfg.PI.Ki = 100;         % 积分增益 (kW/Hz·h)
        cfg.PI.droop_R = 0.02;   % 下垂系数 (2% — 微网逆变器典型值)
        cfg.PI.P_base = 1500;    % 基准功率 (kVA) — 匹配更大负荷
        cfg.PI.alpha_f = 0.80;   % 强平滑: 80%历史+20%当前 → 抑制跳变
    end

    Kp = cfg.PI.Kp;
    Ki = cfg.PI.Ki;
    R  = cfg.PI.droop_R;
    P_base = cfg.PI.P_base;
    alpha_f = cfg.PI.alpha_f;

    % 初始化PI状态
    if nargin < 5 || isempty(pi_state_prev)
        pi_state.integral = zeros(1, Nv);
        pi_state.freq_dev_prev = zeros(1, Nv);
    else
        pi_state = pi_state_prev;
    end

    % ===== ① PI计算调频修正量 =====
    freq_dev_prev = pi_state.freq_dev_prev;

    % 更新积分项（用上一时刻的频偏）
    pi_state.integral = pi_state.integral + freq_dev_prev * cfg.dt;

    % PI输出：频率偏低(Δf<0)→需要增发(ΔP>0)，故取负号
    delta_P_PI = -(Kp * freq_dev_prev + Ki * pi_state.integral);

    % 积分抗饱和（限制积分项不超过可调资源范围）
    for v = 1:Nv
        max_integral = (cfg.Gas.P_max(v) + cfg.Battery.P_dis_max(v)) / max(Ki, 1e-6);
        pi_state.integral(v) = max(min(pi_state.integral(v), max_integral), -max_integral);
    end

    % ===== ② 修正dispatch =====
    dispatch_corrected = dispatch;

    for v = 1:Nv
        if abs(delta_P_PI(v)) < 0.1
            continue;
        end

        if delta_P_PI(v) > 0
            % 频率偏低→需要增发
            gas_available = cfg.Gas.P_max(v) - dispatch.P_gas(v);
            gas_add = min(delta_P_PI(v), gas_available);
            dispatch_corrected.P_gas(v) = dispatch.P_gas(v) + gas_add;
            remaining = delta_P_PI(v) - gas_add;

            if remaining > 0.1 && dispatch.P_bat(v) >= 0
                bat_available = cfg.Battery.P_dis_max(v) - dispatch.P_bat(v);
                bat_add = min(remaining, bat_available);
                dispatch_corrected.P_bat(v) = dispatch.P_bat(v) + bat_add;
            end
        else
            % 频率偏高→需要减发/多充
            delta_reduce = abs(delta_P_PI(v));

            gas_reduce = min(delta_reduce, dispatch.P_gas(v) - cfg.Gas.P_min(v));
            dispatch_corrected.P_gas(v) = dispatch.P_gas(v) - gas_reduce;
            remaining = delta_reduce - gas_reduce;

            if remaining > 0.1
                ch_available = cfg.Battery.P_ch_max(v) + dispatch.P_bat(v);
                bat_reduce = min(remaining, ch_available);
                dispatch_corrected.P_bat(v) = dispatch.P_bat(v) - bat_reduce;
            end
        end
    end

    % 约束裁剪
    dispatch_corrected = unify_limits(dispatch_corrected, cfg, state);

    % ===== ③ 用修正后的功率平衡更新频率 =====
    P_tidal_out = 0;
    if isfield(state, 'P_tidal_avail')
        P_tidal_out = state.P_tidal_avail;
    end
    P_tidal_curt = 0;
    if isfield(dispatch_corrected, 'P_curtail_tidal')
        P_tidal_curt = dispatch_corrected.P_curtail_tidal;
    end
    P_gen  = state.P_pv_avail + state.P_wind_avail + max(P_tidal_out - P_tidal_curt, 0) ...
             + dispatch_corrected.P_gas + max(dispatch_corrected.P_bat, 0);
    P_load = state.P_load - dispatch_corrected.P_shed ...
             - dispatch_corrected.P_curtail_pv - dispatch_corrected.P_curtail_wind ...
             + max(-dispatch_corrected.P_bat, 0);  % 储能充电算负荷

    delta_P = P_gen - P_load;  % 修正后的功率不平衡 (kW)

    % 纯下垂频偏 (一次调频): Δf = -R × f_nom × ΔP / P_base
    freq_dev_raw = -R * f_nom * (delta_P / P_base);

    % 指数平滑 (模拟转子惯性): 避免频率跳变
    freq_dev = alpha_f * pi_state.freq_dev_prev + (1 - alpha_f) * freq_dev_raw;

    % 记录状态
    pi_state.freq_dev_prev = freq_dev;
    freq_new = f_nom + freq_dev;

    % ===== ④ Q-V下垂电压控制（IEEE 1547 Category B） =====
    if ~isfield(cfg, 'Volt')
        cfg.Volt.V_nom = 1.0;       % 标称电压 (p.u.)
        cfg.Volt.R_q = 0.05;        % Q-V下垂斜率 (p.u./Mvar)
        cfg.Volt.pf_typical = 0.95; % 典型功率因数 → Q ≈ P * tan(acos(0.95))
    end
    V_nom = cfg.Volt.V_nom;
    R_q = cfg.Volt.R_q;
    tan_phi = tan(acos(cfg.Volt.pf_typical));  % Q/P 比值

    % 估算无功不平衡 (以有功不平衡为参考，Q≈P*0.33)
    Q_imbalance = delta_P * tan_phi / 1000;  % Mvar
    volt_dev = -R_q * Q_imbalance;           % p.u. 偏差
    volt_new = V_nom + volt_dev;

    % 初始化电压状态
    if ~isfield(pi_state, 'volt_prev')
        pi_state.volt_prev = V_nom;
    end
    pi_state.volt_prev = volt_new;

    % ===== ⑤ 频率越限保护动作（IEEE 1547-2018） =====
    if ~isfield(cfg, 'Safety'), cfg.Safety = struct(); end
    if ~isfield(cfg.Safety, 'freq_protect_steps'), cfg.Safety.freq_protect_steps = 10; end
    if ~isfield(pi_state, 'freq_under_steps'), pi_state.freq_under_steps = zeros(1, Nv); end
    if ~isfield(pi_state, 'freq_over_steps'),  pi_state.freq_over_steps  = zeros(1, Nv); end

    protect_steps = cfg.Safety.freq_protect_steps;
    for v = 1:Nv
        % 低频保护：累计连续越限步数
        if freq_new(v) < cfg.Safety.freq_min
            pi_state.freq_under_steps(v) = pi_state.freq_under_steps(v) + 1;
        else
            pi_state.freq_under_steps(v) = 0;
        end
        % 过频保护
        if freq_new(v) > cfg.Safety.freq_max
            pi_state.freq_over_steps(v) = pi_state.freq_over_steps(v) + 1;
        else
            pi_state.freq_over_steps(v) = 0;
        end

        % 低频超时→强制切负荷10%
        if pi_state.freq_under_steps(v) >= protect_steps
            extra_shed = cfg.Load.interruptible.capacity(v) * 0.2;
            dispatch_corrected.P_shed(v) = min(dispatch_corrected.P_shed(v) + extra_shed, ...
                                               cfg.Load.interruptible.capacity(v));
            pi_state.freq_under_steps(v) = 0;  % 重置计数器（动作后）
            % 记录保护动作
            if ~isfield(pi_state, 'protect_actions')
                pi_state.protect_actions = cell(1, Nv);
            end
            pi_state.protect_actions{v} = [pi_state.protect_actions{v}, ...
                sprintf('UFLS@t=%.1fh: +%.0fkW shed', 0, extra_shed)];
        end

        % 过频超时→增加弃可再生能源
        if pi_state.freq_over_steps(v) >= protect_steps
            % 优先弃潮汐，其次风电，最后光伏
            tidal_curt = min(dispatch_corrected.P_curtail_tidal(v) + 50, ...
                state.P_tidal_avail(v));
            dispatch_corrected.P_curtail_tidal(v) = tidal_curt;
            pi_state.freq_over_steps(v) = 0;
        end
    end
end


function d = unify_limits(d, cfg, state)
    % 快速限幅，确保修正后的指令不越界
    for v = 1:cfg.N_vpp
        d.P_gas(v) = max(min(d.P_gas(v), cfg.Gas.P_max(v)), cfg.Gas.P_min(v));
        d.P_bat(v) = max(min(d.P_bat(v), cfg.Battery.P_dis_max(v)), -cfg.Battery.P_ch_max(v));
        d.P_shed(v) = max(min(d.P_shed(v), cfg.Load.interruptible.capacity(v)), 0);
        d.P_curtail_pv(v) = max(min(d.P_curtail_pv(v), state.P_pv_avail(v)), 0);
        d.P_curtail_wind(v) = max(min(d.P_curtail_wind(v), state.P_wind_avail(v)), 0);
        if isfield(d, 'P_curtail_tidal') && isfield(state, 'P_tidal_avail')
            d.P_curtail_tidal(v) = max(min(d.P_curtail_tidal(v), state.P_tidal_avail(v)), 0);
        end
    end
end
