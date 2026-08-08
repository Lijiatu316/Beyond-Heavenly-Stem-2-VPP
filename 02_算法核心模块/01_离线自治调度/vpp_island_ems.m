% ============================================================
% 文件名：vpp_island_ems.m
% 功能：孤岛本地能量管理，本地源荷储能功率平衡优化（fmincon求解）
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

function dispatch = vpp_island_ems(state, forecast, constraints, cfg)
    % 孤岛本地能量管理优化
    %
    % 为每个VPP独立求解功率分配优化问题（不依赖邻域通信）
    %
    % 决策变量 (per VPP):
    %   x = [P_gas, P_bat, P_shed, P_curtail_pv, P_curtail_wind, P_curtail_tidal]
    %      P_bat > 0 = 放电, P_bat < 0 = 充电
    %
    % 目标: min (燃料成本 + 切负荷惩罚 + 弃风光潮惩罚)
    %
    % 约束:
    %   功率平衡: P_renew + P_gas + P_bat = P_load - P_shed - P_curtail_total
    %   设备限幅: P_min ≤ x ≤ P_max
    %
    % 输入:
    %   state       - 当前系统状态
    %   forecast    - 功率预测结构体
    %   constraints - 约束边界（island_constraint_calc输出）
    %   cfg         - 全局配置
    %
    % 输出:
    %   dispatch - 调度指令结构体:
    %       .P_gas, .P_bat, .P_shed, .P_curtail_pv, .P_curtail_wind
    %       .total_cost, .cost_breakdown

    Nv = cfg.N_vpp;

    % 初始化输出
    dispatch = struct();
    dispatch.P_gas           = zeros(1, Nv);
    dispatch.P_bat           = zeros(1, Nv);
    dispatch.P_shed          = zeros(1, Nv);
    dispatch.P_curtail_pv    = zeros(1, Nv);
    dispatch.P_curtail_wind  = zeros(1, Nv);
    dispatch.P_curtail_tidal = zeros(1, Nv);
    dispatch.total_cost      = zeros(1, Nv);
    dispatch.cost_breakdown  = cell(1, Nv);
    dispatch.success         = true(1, Nv);

    % 对每个VPP独立优化
    for v = 1:Nv
        [x_opt, fval, exitflag] = solve_single_vpp(v, state, constraints, cfg);

        if exitflag > 0
            dispatch.P_gas(v)           = x_opt(1);
            dispatch.P_bat(v)           = x_opt(2);
            dispatch.P_shed(v)          = x_opt(3);
            dispatch.P_curtail_pv(v)    = x_opt(4);
            dispatch.P_curtail_wind(v)  = x_opt(5);
            dispatch.P_curtail_tidal(v) = x_opt(6);
            dispatch.total_cost(v)      = fval;
        else
            % fmincon失败→降级为启发式调度
            dispatch.success(v) = false;
            [dispatch, fval] = fallback_dispatch(v, state, constraints, cfg, dispatch);
            dispatch.total_cost(v) = fval;
        end

        dispatch.cost_breakdown{v} = struct(...
            'fuel',     dispatch.P_gas(v) * cfg.Gas.fuel_cost_a(v) * cfg.dt, ...
            'shedding', dispatch.P_shed(v) * cfg.Price.load_shedding * cfg.dt, ...
            'curtail',  (dispatch.P_curtail_pv(v) + dispatch.P_curtail_wind(v) + dispatch.P_curtail_tidal(v)) ...
                         * cfg.Price.curtail_pv * cfg.dt);
    end
end


function [x_opt, fval, exitflag] = solve_single_vpp(v, state, constraints, cfg)
    % 单个VPP的EMS优化子问题

    % ---- 决策变量边界 ----
    % x = [P_gas, P_bat, P_shed, P_curtail_pv, P_curtail_wind, P_curtail_tidal]
    tidal_max = 0;
    if isfield(constraints, 'P_curtail_tidal_max')
        tidal_max = constraints.P_curtail_tidal_max(v);
    end
    lb = [constraints.P_gas_min(v), ...
          -constraints.P_bat_ch_max(v), ...
          0, 0, 0, 0];

    ub = [constraints.P_gas_max(v), ...
           constraints.P_bat_dis_max(v), ...
           constraints.P_shed_max(v), ...
           constraints.P_curtail_pv_max(v), ...
           constraints.P_curtail_wind_max(v), ...
           tidal_max];

    % ---- 初始点 ----
    x0 = zeros(6, 1);
    x0(1) = max(0, min(constraints.P_net_load(v), constraints.P_gas_max(v)));
    residual = constraints.P_net_load(v) - x0(1);
    if residual > 0
        x0(2) = min(residual, ub(2));
    elseif residual < 0
        x0(2) = max(residual, lb(2));
    end

    % ---- 目标函数 ----
    % f(x) = fuel_cost + shed_penalty + curtail_penalty (含潮汐)
    function cost = objective(x)
        P_gas  = x(1);
        P_shed = x(3);
        P_curtail_pv_wind = x(4) + x(5);
        P_curtail_tidal   = x(6);

        cost = cfg.Gas.fuel_cost_a(v) * P_gas * cfg.dt ...
             + cfg.Gas.fuel_cost_b(v) * (P_gas > 0) * cfg.dt ...
             + cfg.Gas.fuel_cost_c(v) * P_gas^2 * cfg.dt ...
             + cfg.Price.load_shedding * P_shed * cfg.dt ...
             + cfg.Price.curtail_pv * P_curtail_pv_wind * cfg.dt ...
             + cfg.Price.curtail_tidal * P_curtail_tidal * cfg.dt;
        % 网损惩罚（孤岛模式无VPP间交换，P_loss=0）
        if isfield(cfg, 'Network') && cfg.Network.loss_enabled
            P_loss = 0;  % 孤岛模式无跨VPP功率流
            cost = cost + cfg.Price.grid_import(v) * P_loss * cfg.dt;
        end
    end

    % ---- 约束函数 ----
    function [c, ceq] = constraints_fun(x)
        P_gas       = x(1);
        P_bat       = x(2);
        P_shed      = x(3);
        P_curt_pv   = x(4);
        P_curt_wind = x(5);
        P_curt_tide = x(6);

        P_tidal = 0;
        if isfield(state, 'P_tidal_avail')
            P_tidal = max(state.P_tidal_avail(v) - P_curt_tide, 0);
        end
        P_available = state.P_pv_avail(v) + state.P_wind_avail(v) ...
                      + P_tidal + P_gas + P_bat;
        P_demand    = state.P_load(v) - P_shed - P_curt_pv - P_curt_wind;
        ceq = P_available - P_demand;

        % 爬坡约束（仅在启用时将不等式约束加入c向量）
        if isfield(cfg.Gas, 'ramp_enabled_in_opt') && cfg.Gas.ramp_enabled_in_opt
            max_ramp = cfg.Gas.ramp_rate(v) * cfg.dt;
            c = [P_gas - state.P_gas_prev(v) - max_ramp;      % 上爬坡
                 state.P_gas_prev(v) - P_gas - max_ramp];     % 下爬坡
        else
            c = [];
        end
    end

    % ---- fmincon求解 ----
    opts = optimoptions('fmincon', ...
        'Display', 'off', ...
        'Algorithm', 'sqp', ...
        'MaxIterations', 200, ...
        'ConstraintTolerance', 1e-4, ...
        'OptimalityTolerance', 1e-4, ...
        'FiniteDifferenceType', 'central', ...
        'FiniteDifferenceStepSize', 1e-3);

    [x_opt, fval, exitflag] = fmincon(@objective, x0, [], [], [], [], lb, ub, ...
                                       @constraints_fun, opts);

    % 清理小数值噪声
    x_opt(abs(x_opt) < 1e-4) = 0;
end


function [dispatch, fval] = fallback_dispatch(v, state, constraints, cfg, dispatch)
    % 降级启发式调度（fmincon失败时的安全兜底）
    % 优先级：风光消纳 > 储能调节 > 燃气补充 > 切负荷

    % 净负荷已包含潮汐（island_constraint_calc中P_renewable含tidal）
    P_net = constraints.P_net_load(v);

    if P_net <= 0
        % ---- 富余场景：优先充电储能 ----
        surplus = abs(P_net);
        % 1. 储能充电
        dispatch.P_bat(v) = -min(surplus, constraints.P_bat_ch_max(v));
        surplus = surplus + dispatch.P_bat(v);  % P_bat为负，实际是减surplus

        % 2. 若还有富余→弃风光
        if surplus > 1e-4
            curt = min(surplus, constraints.P_curtail_pv_max(v) + constraints.P_curtail_wind_max(v));
            dispatch.P_curtail_pv(v)   = min(curt, constraints.P_curtail_pv_max(v));
            dispatch.P_curtail_wind(v) = curt - dispatch.P_curtail_pv(v);
        end
    else
        % ---- 缺电场景：储能放电 → 燃气 → 切负荷 ----
        deficit = P_net;

        % 1. 储能放电
        dispatch.P_bat(v) = min(deficit, constraints.P_bat_dis_max(v));
        deficit = deficit - dispatch.P_bat(v);

        % 2. 燃气轮机
        if deficit > 1e-4
            dispatch.P_gas(v) = min(deficit, constraints.P_gas_max(v));
            deficit = deficit - dispatch.P_gas(v);
        end

        % 3. 切负荷（最后手段）
        if deficit > 1e-4
            dispatch.P_shed(v) = min(deficit, constraints.P_shed_max(v));
        end
    end

    % 计算成本
    fval = cfg.Gas.fuel_cost_a(v) * dispatch.P_gas(v) * cfg.dt ...
         + cfg.Gas.fuel_cost_b(v) * (dispatch.P_gas(v) > 0) * cfg.dt ...
         + cfg.Gas.fuel_cost_c(v) * dispatch.P_gas(v)^2 * cfg.dt ...
         + cfg.Price.load_shedding * dispatch.P_shed(v) * cfg.dt ...
         + cfg.Price.curtail_pv * (dispatch.P_curtail_pv(v) + dispatch.P_curtail_wind(v)) * cfg.dt;
end
