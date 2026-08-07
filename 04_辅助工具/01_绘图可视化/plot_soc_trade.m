% ============================================================
% 文件名：plot_soc_trade.m
% 功能：绘制储能SOC轨迹 + VPP间交互功率
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   辅助工具/主控脚本，不包含核心算法创新。
%   版权所有归属项目团队。
% ============================================================

function plot_soc_trade(results)
    % SOC轨迹 + 交互功率双面板图
    %
    % 输入:
    %   results - 仿真结果结构体

    hist = results.hist;
    cfg  = results.cfg;
    t    = hist.time;
    Nv   = cfg.N_vpp;

    figure('Name', '孤岛仿真：储能SOC与交互功率', 'Position', [150, 150, 1100, 600]);

    % ---- 上板：SOC轨迹 ----
    subplot(2, 1, 1);
    hold on; grid on;

    colors = lines(Nv);
    for v = 1:Nv
        plot(t, hist.SOC(:, v) * 100, 'Color', colors(v, :), 'LineWidth', 1.8, ...
             'DisplayName', sprintf('VPP%d', v));
    end

    % SOC安全区间
    yline(cfg.Battery.SOC_min(1) * 100, 'r--', 'LineWidth', 1);
    yline(cfg.Battery.SOC_max(1) * 100, 'r--', 'LineWidth', 1);
    ylim([0, 100]);

    xlabel('时间 (h)');
    ylabel('SOC (%)');
    title('储能SOC轨迹');
    legend('Location', 'best');

    % ---- 下板：储能充放电功率 ----
    subplot(2, 1, 2);
    hold on; grid on;

    for v = 1:Nv
        stairs(t, hist.P_bat(:, v), 'Color', colors(v, :), 'LineWidth', 1.2, ...
              'DisplayName', sprintf('VPP%d 储能', v));
    end

    yline(0, 'k-', 'LineWidth', 0.5);
    xlabel('时间 (h)');
    ylabel('充放电功率 (kW)');
    title('储能充放电功率 (+放电/-充电)');
    legend('Location', 'best');
    xlim([0, cfg.T_sim]);

    sgtitle('孤岛自治仿真 — 储能状态分析');
end
