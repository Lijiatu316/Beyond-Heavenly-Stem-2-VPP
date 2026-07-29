% ============================================================
% 文件名：island_constraint_calc.m
% 功能：孤岛安全约束计算，SOC/机组出力/切负荷边界
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

function constraints = island_constraint_calc(state, cfg)
    % 孤岛安全约束边界计算
    %
    % 输入:
    %   state - 当前系统状态结构体:
    %       .P_pv_avail    - 光伏可用出力 (kW), [1 × N_vpp]
    %       .P_wind_avail  - 风电可用出力 (kW), [1 × N_vpp]
    %       .P_load        - 当前负荷 (kW), [1 × N_vpp]
    %       .SOC           - 当前储能SOC, [1 × N_vpp]
    %       .P_gas_prev    - 上一时刻燃气出力 (kW), [1 × N_vpp]
    %   cfg   - 全局配置
    %
    % 输出:
    %   constraints - 约束结构体:
    %       .P_gas_min        - 燃气最小出力
    %       .P_gas_max        - 燃气最大出力
    %       .P_bat_ch_max     - 储能充电最大功率
    %       .P_bat_dis_max    - 储能放电最大功率
    %       .P_shed_max       - 最大可切负荷
    %       .P_curtail_pv_max  - 最大可弃光伏
    %       .P_curtail_wind_max- 最大可弃风电
    %       .P_net_load       - 净负荷 (负荷-风光可用出力)
    %       .needs_shedding   - 是否需要切负荷
    %       .min_shedding     - 最小切负荷量

    Nv = cfg.N_vpp;

    % ---- 燃气轮机约束 ----
    P_gas_min_raw = cfg.Gas.P_min;
    P_gas_max_raw = cfg.Gas.P_max;

    % 孤岛模式：去掉爬坡约束（紧急状态，燃气需快速响应）
    % 爬坡限制在并网模式下有用，但在孤岛自治中会锁死燃气出力
    P_gas_min = P_gas_min_raw;
    P_gas_max = P_gas_max_raw;

    % ---- 储能功率约束（含SOC保护） ----
    P_bat_ch_max  = cfg.Battery.P_ch_max;
    P_bat_dis_max = cfg.Battery.P_dis_max;

    % SOC保护约束：
    % 放电：SOC不能低于下限 → P_dis ≤ (SOC - SOC_min) × E × eff_dis / dt
    SOC_discharge_margin = max(state.SOC - cfg.Battery.SOC_min, 0) ...
                           .* cfg.Battery.E_cap .* cfg.Battery.eff_dis / cfg.dt;
    P_bat_dis_max = min(P_bat_dis_max, SOC_discharge_margin);

    % 充电：SOC不能高于上限 → P_ch ≤ (SOC_max - SOC) × E / (eff_ch × dt)
    SOC_charge_margin = max(cfg.Battery.SOC_max - state.SOC, 0) ...
                        .* cfg.Battery.E_cap ./ cfg.Battery.eff_ch / cfg.dt;
    P_bat_ch_max = min(P_bat_ch_max, SOC_charge_margin);

    % ---- 柔性负荷约束 ----
    P_shed_max = cfg.Load.interruptible.capacity;

    % ---- 弃风弃光弃潮汐约束 ----
    P_curtail_pv_max = state.P_pv_avail;
    P_curtail_wind_max = state.P_wind_avail;
    P_curtail_tidal_max = state.P_tidal_avail;

    % ---- 净负荷与切负荷评估 ----
    P_renewable = state.P_pv_avail + state.P_wind_avail + state.P_tidal_avail;
    P_net_load = state.P_load - P_renewable;  % 正值=缺电, 负值=富余

    % 最大可调资源
    P_max_adjust = P_gas_max + P_bat_dis_max + P_shed_max;

    % 最小必须出力
    P_min_must = P_gas_min - P_bat_ch_max; % 燃气至少出这么多，储能最多充这么多

    % 切负荷判定
    needs_shedding = false(1, Nv);
    min_shedding = zeros(1, Nv);

    for v = 1:Nv
        if P_net_load(v) > 0
            % 缺电：检查所有可调资源能否填补缺口
            if P_net_load(v) > P_max_adjust(v)
                needs_shedding(v) = true;
                min_shedding(v) = P_net_load(v) - P_max_adjust(v) + P_shed_max(v);
                min_shedding(v) = max(0, min_shedding(v));
            end
        end
    end

    % ---- 组装输出 ----
    constraints = struct();
    constraints.P_gas_min       = P_gas_min;
    constraints.P_gas_max       = P_gas_max;
    constraints.P_bat_ch_max    = P_bat_ch_max;
    constraints.P_bat_dis_max   = P_bat_dis_max;
    constraints.P_shed_max      = P_shed_max;
    constraints.P_curtail_pv_max    = P_curtail_pv_max;
    constraints.P_curtail_wind_max  = P_curtail_wind_max;
    constraints.P_curtail_tidal_max = P_curtail_tidal_max;
    constraints.P_net_load      = P_net_load;
    constraints.needs_shedding  = needs_shedding;
    constraints.min_shedding    = min_shedding;
end
