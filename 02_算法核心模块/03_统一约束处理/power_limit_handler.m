% ============================================================
% 文件名：power_limit_handler.m
% 功能：统一限幅处理，爬坡约束/储能充放电限幅/柔性负荷区间裁剪
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

function [dispatch_final, violations] = power_limit_handler(dispatch_raw, state_prev, cfg)
    % 统一约束限幅处理
    %
    % 将优化/控制输出的调度指令裁剪到物理可行域内
    %
    % 输入:
    %   dispatch_raw - 原始调度指令结构体
    %       .P_gas, .P_bat, .P_shed, .P_curtail_pv, .P_curtail_wind
    %   state_prev   - 上一时刻实际状态
    %       .P_gas_prev, .P_bat_prev, .SOC_prev
    %   cfg          - 全局配置
    %
    % 输出:
    %   dispatch_final - 限幅后的调度指令
    %   violations     - 违约记录结构体

    Nv = cfg.N_vpp;
    dispatch_final = dispatch_raw;
    violations = struct();
    violations.ramp      = zeros(1, Nv);
    violations.bat_power = zeros(1, Nv);
    violations.bat_soc   = zeros(1, Nv);

    for v = 1:Nv
        % ---- 1. 燃气轮机爬坡约束 ----
        max_ramp = cfg.Gas.ramp_rate(v) * cfg.dt;
        P_gas_upper = state_prev.P_gas_prev(v) + max_ramp;
        P_gas_lower = state_prev.P_gas_prev(v) - max_ramp;

        P_gas_raw = dispatch_raw.P_gas(v);
        P_gas_clipped = max(min(P_gas_raw, P_gas_upper), P_gas_lower);
        violations.ramp(v) = abs(P_gas_clipped - P_gas_raw);
        dispatch_final.P_gas(v) = P_gas_clipped;

        % ---- 2. 燃气出力上下限 ----
        dispatch_final.P_gas(v) = max(min(dispatch_final.P_gas(v), ...
            cfg.Gas.P_max(v)), cfg.Gas.P_min(v));

        % ---- 3. 储能充放电功率限幅 ----
        P_bat_raw = dispatch_raw.P_bat(v);
        if P_bat_raw > 0
            % 放电
            P_bat_clipped = min(P_bat_raw, cfg.Battery.P_dis_max(v));
        else
            % 充电
            P_bat_clipped = max(P_bat_raw, -cfg.Battery.P_ch_max(v));
        end
        violations.bat_power(v) = abs(P_bat_clipped - P_bat_raw);
        dispatch_final.P_bat(v) = P_bat_clipped;

        % ---- 4. 储能SOC保护（二次校验） ----
        % 放电：SOC不能低于下限
        if P_bat_clipped > 0
            SOC_drop_max = (state_prev.SOC_prev(v) - cfg.Battery.SOC_min(v)) ...
                           * cfg.Battery.E_cap(v) * cfg.Battery.eff_dis(v) / cfg.dt;
            P_bat_soc_limited = min(P_bat_clipped, max(SOC_drop_max, 0));
        else
            % 充电：SOC不能超过上限
            SOC_rise_max = (cfg.Battery.SOC_max(v) - state_prev.SOC_prev(v)) ...
                           * cfg.Battery.E_cap(v) / cfg.Battery.eff_ch(v) / cfg.dt;
            P_bat_soc_limited = max(P_bat_clipped, -max(SOC_rise_max, 0));
        end
        violations.bat_soc(v) = abs(P_bat_soc_limited - P_bat_clipped);
        dispatch_final.P_bat(v) = P_bat_soc_limited;

        % ---- 5. 切负荷限幅 ----
        dispatch_final.P_shed(v) = max(min(dispatch_raw.P_shed(v), ...
            cfg.Load.interruptible.capacity(v)), 0);

        % ---- 6. 弃风弃光弃潮汐限幅 ----
        dispatch_final.P_curtail_pv(v) = max(min(dispatch_raw.P_curtail_pv(v), ...
            state_prev.P_pv_avail(v)), 0);
        dispatch_final.P_curtail_wind(v) = max(min(dispatch_raw.P_curtail_wind(v), ...
            state_prev.P_wind_avail(v)), 0);
        if isfield(dispatch_raw, 'P_curtail_tidal') && isfield(state_prev, 'P_tidal_avail')
            dispatch_final.P_curtail_tidal(v) = max(min(dispatch_raw.P_curtail_tidal(v), ...
                state_prev.P_tidal_avail(v)), 0);
        end

        % ---- 7. 小值清零（避免数值噪声累积） ----
        for fn = {'P_gas', 'P_bat', 'P_shed', 'P_curtail_pv', 'P_curtail_wind', 'P_curtail_tidal'}
            val = dispatch_final.(fn{1})(v);
            if abs(val) < 1e-3
                dispatch_final.(fn{1})(v) = 0;
            end
        end
    end
end
