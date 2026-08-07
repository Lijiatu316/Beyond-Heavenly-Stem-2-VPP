% ============================================================
% 文件名：plot_index_bar.m
% 功能：输出经济指标柱状图，发电成本/消纳率等多维度对比
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   辅助工具/主控脚本，不包含核心算法创新。
%   版权所有归属项目团队。
% ============================================================

function plot_index_bar(results)
    % 经济指标柱状图面板
    %
    % 输入:
    %   results - 仿真结果结构体

    eco = results.eco_index;
    cfg = results.cfg;
    Nv  = cfg.N_vpp;

    figure('Name', '孤岛仿真：经济指标评价', 'Position', [200, 200, 1000, 600]);

    % ---- 子图1: 各VPP消纳率 ----
    subplot(2, 3, 1);
    bar(1:Nv, eco.renewable_rate_vpp * 100);
    xlabel('VPP编号');
    ylabel('消纳率 (%)');
    title('各VPP新能源消纳率');
    ylim([0, 105]);
    grid on;
    for v = 1:Nv
        text(v, eco.renewable_rate_vpp(v)*100 + 2, ...
             sprintf('%.1f%%', eco.renewable_rate_vpp(v)*100), ...
             'HorizontalAlignment', 'center', 'FontSize', 9);
    end

    % ---- 子图2: 各VPP调度成本 ----
    subplot(2, 3, 2);
    bar(1:Nv, eco.cost_vpp);
    xlabel('VPP编号');
    ylabel('成本 (元)');
    title('各VPP调度总成本');
    grid on;

    % ---- 子图3: 成本构成饼图 ----
    subplot(2, 3, 3);
    cost_labels = {'燃料成本', '切负荷惩罚', '弃风光惩罚'};
    cost_vals = [eco.fuel_cost_total, eco.shedding_cost_total, eco.curtailment_cost_total];
    cost_vals = max(cost_vals, 0);
    if sum(cost_vals) > 0
        pie(cost_vals, cost_labels);
        title('成本构成');
    else
        text(0.5, 0.5, '成本为零', 'HorizontalAlignment', 'center');
        title('成本构成');
    end

    % ---- 子图4: 频率合格率 ----
    subplot(2, 3, 4);
    bar(1:Nv, eco.freq_qualified_vpp * 100);
    xlabel('VPP编号');
    ylabel('合格率 (%)');
    title('频率合格率');
    ylim([90, 105]);
    grid on;

    % ---- 子图5: 供电可靠性 ----
    subplot(2, 3, 5);
    bar(1:Nv, eco.reliability_vpp * 100);
    xlabel('VPP编号');
    ylabel('可靠性 (%)');
    title('供电可靠性');
    ylim([90, 105]);
    grid on;

    % ---- 子图6: 综合评分雷达 ----
    subplot(2, 3, 6);
    categories = {'消纳率', '经济性', '频率质量', '可靠性'};
    scores = [eco.renewable_rate, ...
              1 - eco.total_cost / max(eco.total_cost, 100), ...
              eco.freq_qualified_rate, ...
              eco.reliability];
    scores = max(min(scores, 1), 0);  % clip to [0,1]

    % 简易雷达图（用极坐标bar模拟）
    theta = linspace(0, 2*pi, length(categories) + 1);
    rho   = [scores, scores(1)];  % 闭合
    polarplot(theta, rho, 'b-o', 'LineWidth', 1.5, 'MarkerSize', 6, ...
              'MarkerFaceColor', 'b');
    thetaticks(rad2deg(theta(1:end-1)));
    thetaticklabels(categories);
    rlim([0, 1]);
    title('综合评分');

    sgtitle(sprintf('孤岛自治仿真 — 经济指标评价 (总成本: %.1f元)', eco.total_cost));
end
