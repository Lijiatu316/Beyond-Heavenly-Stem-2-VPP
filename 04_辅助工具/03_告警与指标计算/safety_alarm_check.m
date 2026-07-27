% ============================================================
% 文件名：safety_alarm_check.m
% 功能：越限告警统计，低频/过频/储能SOC越限/切负荷事件
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   辅助工具/主控脚本，不包含核心算法创新。
%   版权所有归属项目团队。
% ============================================================

function alarms = safety_alarm_check(hist, cfg)
    % 安全越限告警统计分析
    %
    % 输入:
    %   hist - 仿真历史数据
    %   cfg  - 全局配置
    %
    % 输出:
    %   alarms - 告警统计结构体

    Nv   = cfg.N_vpp;
    N    = cfg.N_steps;
    freq_min = cfg.Safety.freq_min;
    freq_max = cfg.Safety.freq_max;

    alarms = struct();
    alarms.total_alarms = 0;

    % ========== 1. 频率越限告警 ==========
    freq_under  = hist.freq < freq_min;   % 低频告警
    freq_over   = hist.freq > freq_max;   % 过频告警

    alarms.freq_under_count  = sum(freq_under(:));
    alarms.freq_over_count   = sum(freq_over(:));
    alarms.freq_under_vpp    = sum(freq_under, 1);   % 各VPP低频次数
    alarms.freq_over_vpp     = sum(freq_over, 1);

    % 低频持续时间统计（连续步数×dt）
    alarms.freq_under_duration = zeros(1, Nv);
    for v = 1:Nv
        under_mask = freq_under(:, v);
        if any(under_mask)
            % 找最长连续段
            d = diff([0; under_mask; 0]);
            starts = find(d == 1);
            ends   = find(d == -1) - 1;
            durations = (ends - starts + 1) * cfg.dt * 60;  % 分钟
            if ~isempty(durations)
                alarms.freq_under_duration(v) = max(durations);
            end
        end
    end

    % ========== 2. SOC越限告警 ==========
    soc_under  = hist.SOC < cfg.Battery.SOC_min;   % SOC过低
    soc_over   = hist.SOC > cfg.Battery.SOC_max;   % SOC过高

    alarms.soc_under_count = sum(soc_under(:));
    alarms.soc_over_count  = sum(soc_over(:));
    alarms.soc_under_vpp   = sum(soc_under, 1);
    alarms.soc_over_vpp    = sum(soc_over, 1);

    % ========== 3. 切负荷事件统计 ==========
    shed_active = hist.P_shed > 0.01;  % >10W视为切负荷事件

    alarms.shed_count     = sum(shed_active(:));       % 总切负荷步数
    alarms.shed_count_vpp = sum(shed_active, 1);
    alarms.shed_total_kWh = sum(sum(hist.P_shed)) * cfg.dt;
    alarms.shed_max_kW    = max(hist.P_shed, [], 1);

    % 切负荷事件段
    alarms.shed_events = 0;
    for v = 1:Nv
        d = diff([0; shed_active(:, v); 0]);
        alarms.shed_events = alarms.shed_events + sum(d == 1);
    end

    % ========== 4. 告警汇总 ==========
    alarms.total_alarms = alarms.freq_under_count + alarms.freq_over_count ...
                        + alarms.soc_under_count + alarms.soc_over_count;

    alarms.summary = sprintf(...
        '告警总计: %d | 低频:%d 过频:%d SOC低:%d SOC高:%d 切负荷事件:%d', ...
        alarms.total_alarms, alarms.freq_under_count, alarms.freq_over_count, ...
        alarms.soc_under_count, alarms.soc_over_count, alarms.shed_events);
end
