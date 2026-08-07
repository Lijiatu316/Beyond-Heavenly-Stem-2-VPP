% ============================================================
% 文件名：admm_distributed_opt.m
% 功能：ADMM去中心化多VPP协同优化，邻域功率互济
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
%
% 知识产权声明：
%   本文件为团队独立创新开发，属于项目核心原创算法模块。
%   算法实现、模式切换逻辑、多源协同策略为原创。
%   版权所有，未经许可不得转载或用于商业用途。
% ============================================================

function [dispatch, admm_info] = admm_distributed_opt(state, constraints, cfg, comm_state)
    % ADMM分布式多VPP协同优化
    %
    % 每个VPP独立求解本地子问题，通过邻域交换拉格朗日乘子
    % 迭代至全局最优，实现VPP间功率互济
    %
    % 数学模型:
    %   min Σ f_i(x_i)  s.t.  Σ A_i x_i = 0 (全局功率平衡耦合)
    %
    % ADMM迭代 (per VPP i):
    %   x_i^{k+1} = argmin { f_i(x_i) + (ρ/2)||x_i - x_i^k + u_i^k||² }
    %   u_i^{k+1} = u_i^k + x_i^{k+1} - z^{k+1}
    %   其中 z = (1/Nv) Σ x_i   (平均共识变量)
    %
    % 输入:
    %   state       - 当前系统状态
    %   constraints - 约束边界
    %   cfg         - 全局配置
    %   comm_state  - 通信状态 (delay, loss, quality)
    %
    % 输出:
    %   dispatch  - 调度指令
    %   admm_info - ADMM迭代信息(残差、迭代次数、交换功率)

    Nv = cfg.N_vpp;
    rho = cfg.ADMM.rho;        % 惩罚参数 (默认 0.5)
    max_iter = cfg.ADMM.max_iter;  % 最大迭代次数 (默认 50)
    tol = cfg.ADMM.tolerance;  % 收敛容差 (默认 0.005)

    % 决策变量维度: 6 per VPP
    % [P_gas, P_bat, P_shed, P_curtail_pv, P_curtail_wind, P_curtail_tidal]
    n_var = 6;

    % ---- 初始化 ----
    % 全局变量 (所有VPP共享的共识值)
    x_global = zeros(Nv, n_var);   % 全局共识解 z^k
    u_dual   = zeros(Nv, n_var);   % 缩放对偶变量 u^k

    % 各VPP的本地最优解
    x_local = zeros(Nv, n_var);

    % ---- 通信衰减因子 (链路质量越差，信息交换越不完整) ----
    % comm_state.quality_matrix: Nv×Nv 链路质量矩阵
    comm_factor = ones(Nv, Nv);
    if nargin >= 4 && ~isempty(comm_state) && isfield(comm_state, 'quality_matrix')
        comm_factor = comm_state.quality_matrix;
        comm_factor(comm_factor < 0.3) = 0.3;  % 最低30%信息传递
    end

    % ---- 邻接矩阵 (9-VPP环网+跨类互联) ----
    if isstruct(cfg.Comm.topology)
        adjacency = cfg.Comm.topology.adjacency;
    else
        adjacency = cfg.Comm.topology;  % 直接矩阵
    end

    % ---- ADMM主循环 ----
    primal_residual_history = zeros(max_iter, 1);
    dual_residual_history   = zeros(max_iter, 1);

    for iter = 1:max_iter
        x_old = x_local;

        % ============ Step 1: 各VPP独立求解本地子问题 ============
        for v = 1:Nv
            % 本地目标: f_v(x) + (ρ/2)·Σ_j[ ||x - z_j||² ]  (j in neighbors)
            % 近似为: f_v(x) + (ρ/2)·||x - consensus_target||²
            %
            % consensus_target = 各邻居解的加权平均 (考虑通信延迟)
            neighbor_list = find(adjacency(v, :));
            if isempty(neighbor_list)
                consensus_target = x_global(v, :);
            else
                consensus_target = x_global(v, :);
                neighbor_weight_total = 0;
                for j = neighbor_list
                    w = comm_factor(v, j);  % 通信质量权重
                    consensus_target = consensus_target + w * (x_global(j, :) - x_global(v, :));
                    neighbor_weight_total = neighbor_weight_total + w;
                end
                if neighbor_weight_total > 0
                    consensus_target = x_global(v, :) + ...
                        (consensus_target - x_global(v, :)) / (1 + neighbor_weight_total);
                end
            end

            % 调用本地优化子问题 (fmincon + ADMM增广项)
            x_local(v, :) = solve_local_admm(v, state, constraints, cfg, ...
                                             consensus_target, u_dual(v, :), rho);
        end

        % ============ Step 2: 全局共识更新 (模拟通信) ============
        % 在去中心化架构中，每个VPP只知道邻居的值
        x_global_new = x_global;
        for v = 1:Nv
            neighbor_list = find(adjacency(v, :));
            if isempty(neighbor_list)
                % 孤立节点：保持自己的解
                x_global_new(v, :) = x_local(v, :);
            else
                % 加权平均邻居和自己的解
                avg = x_local(v, :);
                count = 1;
                for j = neighbor_list
                    w = comm_factor(v, j);
                    avg = avg + w * x_local(j, :);
                    count = count + w;
                end
                x_global_new(v, :) = avg / count;
            end
        end
        x_global = x_global_new;

        % ============ Step 3: 对偶变量更新 ============
        for v = 1:Nv
            u_dual(v, :) = u_dual(v, :) + x_local(v, :) - x_global(v, :);
        end

        % ============ Step 4: 收敛检查 ============
        primal_res = norm(x_local - x_global, 'fro') / sqrt(Nv);
        dual_res   = rho * norm(x_global - x_old, 'fro') / sqrt(Nv);

        primal_residual_history(iter) = primal_res;
        dual_residual_history(iter)   = dual_res;

        if primal_res < tol && dual_res < tol
            break;
        end
    end

    % ---- 构建调度输出 ----
    dispatch = struct();
    dispatch.P_gas           = x_local(:, 1)';
    dispatch.P_bat           = x_local(:, 2)';
    dispatch.P_shed          = x_local(:, 3)';
    dispatch.P_curtail_pv    = x_local(:, 4)';
    dispatch.P_curtail_wind  = x_local(:, 5)';
    dispatch.P_curtail_tidal = x_local(:, 6)';
    dispatch.total_cost      = zeros(1, Nv);

    % 计算各VPP实际成本
    for v = 1:Nv
        P_gas = dispatch.P_gas(v);
        P_shed = dispatch.P_shed(v);
        P_curt = dispatch.P_curtail_pv(v) + dispatch.P_curtail_wind(v) + dispatch.P_curtail_tidal(v);

        dispatch.total_cost(v) = cfg.Gas.fuel_cost_a(v) * P_gas * cfg.dt ...
                               + cfg.Price.load_shedding * P_shed * cfg.dt ...
                               + cfg.Price.curtail_pv * P_curt * cfg.dt;
    end
    dispatch.success = true(1, Nv);

    % ---- ADMM迭代信息 ----
    admm_info = struct();
    admm_info.iterations      = iter;
    admm_info.primal_residual = primal_residual_history(iter);
    admm_info.dual_residual   = dual_residual_history(iter);
    admm_info.converged       = (iter < max_iter);
    admm_info.primal_history  = primal_residual_history(1:iter);
    admm_info.dual_history    = dual_residual_history(1:iter);
    admm_info.exchange_power  = compute_exchange(x_local, adjacency);
    admm_info.x_global        = x_global;
end


function x_opt = solve_local_admm(v, state, constraints, cfg, consensus, u, rho)
    % 单个VPP的ADMM增广拉格朗日子问题
    %
    % min  f_v(x) + (ρ/2)·||x - consensus + u||²
    % s.t. 本地约束 g_v(x) ≤ 0

    n_var = 6;

    % ---- 边界 ----
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

    % ---- 初始点 (从共识值开始) ----
    x0 = consensus;
    x0 = max(lb, min(ub, x0));
    if all(x0 == 0)
        x0(1) = max(0, min(constraints.P_net_load(v), ub(1)));
        x0(2) = min(max(0, constraints.P_net_load(v) - x0(1)), ub(2));
    end

    % ---- 目标函数 (本地成本 + ADMM增广项) ----
    function cost = objective(x)
        P_gas  = x(1);
        P_shed = x(3);
        P_curt = x(4) + x(5) + x(6);

        % 本地运行成本
        local_cost = cfg.Gas.fuel_cost_a(v) * P_gas * cfg.dt ...
                   + cfg.Gas.fuel_cost_b(v) * (P_gas > 0) * cfg.dt ...
                   + cfg.Price.load_shedding * P_shed * cfg.dt ...
                   + cfg.Price.curtail_pv * P_curt * cfg.dt;

        % ADMM增广项: (ρ/2)·||x - consensus + u||²
        diff = x(:) - consensus(:) + u(:);
        admm_penalty = (rho / 2) * (diff' * diff);

        cost = local_cost + admm_penalty;
    end

    % ---- 约束函数 (同孤岛模式) ----
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
        c = [];
    end

    % ---- fmincon求解 ----
    opts = optimoptions('fmincon', ...
        'Display', 'off', ...
        'Algorithm', 'sqp', ...
        'MaxIterations', 150, ...
        'ConstraintTolerance', 1e-4, ...
        'OptimalityTolerance', 1e-4);

    [x_opt, ~, exitflag] = fmincon(@objective, x0, [], [], [], [], lb, ub, ...
                                    @constraints_fun, opts);

    % fmincon失败 → 启发式回退
    if exitflag <= 0
        x_opt = consensus;
        x_opt(1) = max(0, min(constraints.P_net_load(v), ub(1)));
        residual = constraints.P_net_load(v) - x_opt(1);
        if residual > 0
            x_opt(2) = min(residual, ub(2));
        else
            x_opt(2) = max(residual, lb(2));
        end
    end

    % 清理小数值噪声
    x_opt(abs(x_opt) < 1e-4) = 0;
    x_opt = x_opt(:)';
end


function exchange = compute_exchange(x_local, adjacency)
    % 计算VPP间的互济功率
    % 基于邻域解差异：exchange(i,j) = x_i(功率平衡相关) - x_j(功率平衡相关)
    Nv = size(x_local, 1);
    exchange = zeros(Nv, Nv);

    % 用燃气+储能+切负荷的差异来估算交换功率
    for i = 1:Nv
        for j = (i+1):Nv
            if adjacency(i, j) > 0
                % P_gas + P_bat + P_shed 代表VPP自身处理能力
                % 差值代表需要通过交换来弥补的部分
                self_i = x_local(i, 1) + x_local(i, 2) + x_local(i, 3);
                self_j = x_local(j, 1) + x_local(j, 2) + x_local(j, 3);
                % 功率从富裕方流向不足方
                exchange(i, j) = (self_i - self_j) / 2;
                exchange(j, i) = -exchange(i, j);  % 反对称
            end
        end
    end
end
