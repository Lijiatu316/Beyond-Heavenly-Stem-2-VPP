% ============================================================
% 文件名：export_csv_data.m
% 功能：导出CSV表格数据供Python/Excel后处理分析
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   辅助工具/主控脚本，不包含核心算法创新。
%   版权所有归属项目团队。
% ============================================================

function export_csv_data(results, prefix)
    % 导出CSV数据文件
    %
    % 输入:
    %   results - 仿真结果结构体
    %   prefix  - 文件名前缀 (可选), 默认 'island'

    if nargin < 2
        prefix = 'island';
    end

    hist = results.hist;
    cfg  = results.cfg;
    Nv   = cfg.N_vpp;
    N    = cfg.N_steps;
    t    = hist.time;

    % ---- 1. 时序数据 ----
    % 构建大表：时间 | VPP1_Ppv | VPP1_Pwind | ... | VPP1_SOC | ...
    var_names = {'Time_h'};
    data_cols = t;

    fields = {'P_pv', 'P_wind', 'P_gas', 'P_bat', 'P_load', 'P_shed', 'P_curtail', 'SOC', 'freq'};
    field_labels = {'PV_kW', 'Wind_kW', 'Gas_kW', 'Bat_kW', 'Load_kW', 'Shed_kW', 'Curtail_kW', 'SOC', 'Freq_Hz'};

    for f = 1:length(fields)
        for v = 1:Nv
            var_names{end+1} = sprintf('VPP%d_%s', v, field_labels{f});
            data_cols = [data_cols, hist.(fields{f})(:, v)];
        end
    end

    T = array2table(data_cols, 'VariableNames', var_names);
    csv_filename = sprintf('%s_timeseries.csv', prefix);
    try
        writetable(T, csv_filename);
        fprintf('  时序数据已导出: %s (%d行 × %d列)\n', csv_filename, N, length(var_names));
    catch ME
        fprintf('  [警告] 无法写入 %s: %s\n', csv_filename, ME.message);
    end

    % ---- 2. 指标汇总 ----
    eco = results.eco_index;
    alarms = results.alarms;

    idx_names  = {'指标', '数值', '单位'};
    idx_data   = {
        '新能源消纳率',     eco.renewable_rate * 100,     '%';
        '调度总成本',       eco.total_cost,               '元';
        '燃料成本',         eco.fuel_cost_total,          '元';
        '切负荷惩罚成本',   eco.shedding_cost_total,      '元';
        '弃风光惩罚成本',   eco.curtailment_cost_total,   '元';
        '频率合格率',       eco.freq_qualified_rate * 100,'%';
        '供电可靠性',       eco.reliability * 100,        '%';
        'CO2排放估算',      eco.co2_emission_est,         'kg';
        '总告警次数',       alarms.total_alarms,          '次';
        '低频告警次数',     alarms.freq_under_count,      '次';
        '过频告警次数',     alarms.freq_over_count,       '次';
        '切负荷事件数',     alarms.shed_events,           '次';
        '切负荷总量',       alarms.shed_total_kWh,        'kWh';
    };

    T_idx = cell2table(idx_data, 'VariableNames', idx_names);
    idx_filename = sprintf('%s_indices.csv', prefix);
    try
        writetable(T_idx, idx_filename);
        fprintf('  指标汇总已导出: %s\n', idx_filename);
    catch ME
        % 文件被锁时用时间戳后缀重试
        alt_name = sprintf('%s_indices_%s.csv', prefix, datestr(now, 'HHMMSS'));
        try
            writetable(T_idx, alt_name);
            fprintf('  指标汇总已导出: %s (原文件被占用)\n', alt_name);
        catch
            fprintf('  [警告] 无法写入指标文件: %s\n', ME.message);
        end
    end

    % ---- 3. 逐VPP指标 ----
    vpp_names = {'指标'};
    for v = 1:Nv
        vpp_names{end+1} = sprintf('VPP%d', v);
    end

    vpp_data = {
        '消纳率(%)',          eco.renewable_rate_vpp * 100;
        '频率合格率(%)',      eco.freq_qualified_vpp * 100;
        '供电可靠性(%)',      eco.reliability_vpp * 100;
        '调度成本(元)',       eco.cost_vpp;
        '备用裕度',           eco.reserve_margin;
        '平均频率(Hz)',       eco.freq_mean;
        '最大频偏(Hz)',       eco.freq_max_dev;
        '低频告警(次)',       alarms.freq_under_vpp;
        'SOC越限(次)',        alarms.soc_under_vpp;
        '切负荷(次)',         alarms.shed_count_vpp;
        '最大切负荷(kW)',     alarms.shed_max_kW;
    };

    for r = 1:size(vpp_data, 1)
        vpp_table_data{r, 1} = vpp_data{r, 1};
        for v = 1:Nv
            vpp_table_data{r, v+1} = vpp_data{r, 2}(v);
        end
    end

    T_vpp = cell2table(vpp_table_data, 'VariableNames', vpp_names);
    vpp_filename = sprintf('%s_vpp_indices.csv', prefix);
    try
        writetable(T_vpp, vpp_filename);
        fprintf('  逐VPP指标已导出: %s\n', vpp_filename);
    catch ME
        fprintf('  [警告] 无法写入 %s: %s\n', vpp_filename, ME.message);
    end
end
