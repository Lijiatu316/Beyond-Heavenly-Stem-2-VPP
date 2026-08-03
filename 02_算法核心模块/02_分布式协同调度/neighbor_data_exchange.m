% ============================================================
% 文件名：neighbor_data_exchange.m
% 功能：虚拟点对点通信，邻域电厂可调裕度/报价交互模拟
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
%
% 知识产权声明：
%   本文件为团队独立创新开发，属于项目核心原创算法模块。
%   版权所有，未经许可不得转载或用于商业用途。
% ============================================================

function exchange_data = neighbor_data_exchange(state, dispatch, admm_info, cfg, comm_state)
    % 邻域VPP数据交换
    %
    % 模拟VPP间点对点通信：交换当前调度方案、可调裕度、边际成本
    % 通信延迟和丢包根据comm_state注入
    %
    % 输入:
    %   state       - 当前系统状态
    %   dispatch    - 当前调度指令
    %   admm_info   - ADMM迭代信息
    %   cfg         - 全局配置
    %   comm_state  - 通信状态结构体
    %
    % 输出:
    %   exchange_data - 交换数据结构体:
    %       .marginal_cost  - 边际成本 [Nv×1]
    %       .flex_up        - 上调裕度 [Nv×1]  (kW)
    %       .flex_down      - 下调裕度 [Nv×1]  (kW)
    %       .renew_surplus  - 可再生富余 [Nv×1]  (kW)
    %       .load_deficit   - 负荷缺额 [Nv×1]  (kW)
    %       .price_bid      - 互济报价 [Nv×Nv]  (元/kWh)
    %       .link_quality   - 链路质量矩阵

    Nv = cfg.N_vpp;
    adjacency = cfg.Comm.topology.adjacency;

    % ---- 1. 各VPP计算自身边际成本和可调裕度 ----
    marginal_cost = zeros(Nv, 1);
    flex_up       = zeros(Nv, 1);
    flex_down     = zeros(Nv, 1);
    renew_surplus = zeros(Nv, 1);
    load_deficit  = zeros(Nv, 1);

    for v = 1:Nv
        % 边际成本: 燃气燃料成本(元/kWh) — 最后一度电的价格
        marginal_cost(v) = cfg.Gas.fuel_cost_a(v) * cfg.dt;

        % 上调裕度: 还能增加多少出力 (燃气+储能放电)
        flex_up(v) = max(0, cfg.Gas.P_max(v) - dispatch.P_gas(v)) ...
                   + max(0, cfg.Battery.P_dis_max(v) - max(0, dispatch.P_bat(v)));

        % 下调裕度: 还能减少多少出力 (储能充电空间)
        flex_down(v) = max(0, dispatch.P_bat(v) + cfg.Battery.P_ch_max(v));

        % 可再生富余 (光伏+风电可弃量)
        renew_surplus(v) = state.P_pv_avail(v) + state.P_wind_avail(v) ...
                         - dispatch.P_curtail_pv(v) - dispatch.P_curtail_wind(v);

        % 负荷缺额
        load_deficit(v) = max(0, state.P_load(v) ...
                         - (state.P_pv_avail(v) + state.P_wind_avail(v) ...
                         + state.P_tidal_avail(v) + dispatch.P_gas(v) ...
                         + max(0, dispatch.P_bat(v))));
    end

    % ---- 2. 构建互济报价矩阵 ----
    % price_bid(i,j): VPP i 向 VPP j 售电的报价 (元/kWh)
    % 基于卖方边际成本 + 传输损耗惩罚
    price_bid = zeros(Nv, Nv);
    for i = 1:Nv
        for j = 1:Nv
            if i ~= j && adjacency(i, j) > 0
                % 基准报价 = 买方边际成本 - 卖方边际成本
                % 卖方盈利 = 报价 - 自身边际成本 > 0 时才愿意卖
                spread = marginal_cost(j) - marginal_cost(i);
                if spread > 0
                    % 卖方报价 = 自身成本 + 50%利差
                    price_bid(i, j) = marginal_cost(i) + 0.5 * spread;
                end
            end
        end
    end

    % ---- 3. 通信延迟/丢包模拟 ----
    % 链路质量影响数据新鲜度：延迟高→数据陈旧；丢包→使用上次值
    link_quality = ones(Nv, Nv);
    if nargin >= 5 && ~isempty(comm_state) && isfield(comm_state, 'quality_matrix')
        link_quality = comm_state.quality_matrix;
    end
    link_quality(link_quality < 0) = 0;
    link_quality(link_quality > 1) = 1;

    % 质量衰减: quality<0.5 时大幅降低数据可用性
    for i = 1:Nv
        for j = 1:Nv
            if i ~= j && link_quality(i, j) < 0.5
                % 链路差 → 报价被噪声污染
                noise_factor = 1 + 0.3 * (0.5 - link_quality(i, j)) * randn();
                price_bid(i, j) = price_bid(i, j) * max(0.5, noise_factor);
            end
        end
    end

    % ---- 4. 打包输出 ----
    exchange_data = struct();
    exchange_data.marginal_cost  = marginal_cost;
    exchange_data.flex_up        = flex_up;
    exchange_data.flex_down      = flex_down;
    exchange_data.renew_surplus  = renew_surplus;
    exchange_data.load_deficit   = load_deficit;
    exchange_data.price_bid      = price_bid;
    exchange_data.link_quality   = link_quality;
end
