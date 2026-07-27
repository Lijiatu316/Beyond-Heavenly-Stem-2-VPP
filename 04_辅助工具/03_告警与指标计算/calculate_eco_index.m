% ============================================================
% 文件名：calculate_eco_index.m
% 功能：计算消纳率/调度成本/备用容量/供电可靠性/频率合格率等评价指标
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   辅助工具/主控脚本，不包含核心算法创新。
%   版权所有归属项目团队。
% ============================================================

function eco = calculate_eco_index(hist, cfg)
    % 经济性与可靠性评价指标计算
    %
    % 输入:
    %   hist - 仿真历史数据结构体
    %   cfg  - 全局配置
    %
    % 输出:
    %   eco - 评价指标结构体

    Nv  = cfg.N_vpp;
    dt  = cfg.dt;
    t   = hist.time;
    f_nom = cfg.f_nom;

    % ========== 1. 新能源消纳率 ==========
    % 消纳率 = 实际利用量 / 理论可发量（含潮汐）
    P_pv_total    = sum(hist.P_pv, 2);
    P_wind_total  = sum(hist.P_wind, 2);
    P_tidal_total = sum(hist.P_tidal, 2);
    P_curtail_total = sum(hist.P_curtail, 2);

    total_available = sum(P_pv_total + P_wind_total + P_tidal_total) * dt;  % kWh
    total_curtailed = sum(P_curtail_total) * dt;                   % kWh

    if total_available > 0
        eco.renewable_rate = 1 - total_curtailed / total_available;
    else
        eco.renewable_rate = 1;
    end

    % 逐VPP消纳率
    eco.renewable_rate_vpp = zeros(1, Nv);
    for v = 1:Nv
        avail_v = sum(hist.P_pv(:, v) + hist.P_wind(:, v)) * dt;
        curt_v  = sum(hist.P_curtail(:, v)) * dt;
        if avail_v > 0
            eco.renewable_rate_vpp(v) = 1 - curt_v / avail_v;
        else
            eco.renewable_rate_vpp(v) = 1;
        end
    end

    % ========== 2. 调度成本 ==========
    eco.cost_vpp     = sum(hist.cost, 1);          % 各VPP总成本
    eco.total_cost   = sum(eco.cost_vpp);

    % 成本明细
    eco.fuel_cost_total       = sum(sum(hist.P_gas, 1) .* cfg.Gas.fuel_cost_a * dt);
    eco.shedding_cost_total   = sum(sum(hist.P_shed, 1) * cfg.Price.load_shedding * dt);
    eco.curtailment_cost_total = sum(sum(hist.P_curtail, 1) * cfg.Price.curtail_pv * dt);

    % ========== 3. 频率合格率 ==========
    freq_ok = (hist.freq >= cfg.Safety.freq_min) & (hist.freq <= cfg.Safety.freq_max);
    eco.freq_qualified_rate = sum(freq_ok(:)) / numel(freq_ok);

    eco.freq_qualified_vpp = zeros(1, Nv);
    for v = 1:Nv
        eco.freq_qualified_vpp(v) = sum(freq_ok(:, v)) / size(freq_ok, 1);
    end

    % 频率统计
    eco.freq_mean  = mean(hist.freq, 1);
    eco.freq_std   = std(hist.freq, 0, 1);
    eco.freq_max_dev = max(abs(hist.freq - f_nom), [], 1);

    % ========== 4. 供电可靠性 ==========
    % 可靠性 = 1 - (缺供电量 / 总需电量)
    total_load   = sum(sum(hist.P_load)) * dt;          % 总需电量
    total_shed   = sum(sum(hist.P_shed)) * dt;           % 总切负荷量
    if total_load > 0
        eco.reliability = 1 - total_shed / total_load;
    else
        eco.reliability = 1;
    end

    eco.reliability_vpp = zeros(1, Nv);
    for v = 1:Nv
        load_v = sum(hist.P_load(:, v)) * dt;
        shed_v = sum(hist.P_shed(:, v)) * dt;
        if load_v > 0
            eco.reliability_vpp(v) = 1 - shed_v / load_v;
        else
            eco.reliability_vpp(v) = 1;
        end
    end

    % ========== 5. 备用容量充裕度 ==========
    % 最大可用容量 / 峰值负荷
    P_max_avail = cfg.Gas.P_max + cfg.Battery.P_dis_max + cfg.PV.capacity + cfg.Wind.capacity;
    P_peak_load = max(hist.P_load, [], 1);
    eco.reserve_margin = P_max_avail ./ P_peak_load;

    % ========== 6. 碳排放估算（简化） ==========
    % 燃气轮机碳排放按 0.5 kg CO2/kWh 估算
    total_gas_kWh = sum(sum(hist.P_gas)) * dt;
    eco.co2_emission_est = total_gas_kWh * 0.5;  % kg CO2
end
