% ============================================================
% 文件名：plot_freq_power.m
% 功能：绘制频率时序曲线 + 各机组出力堆叠面积图
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   辅助工具/主控脚本，不包含核心算法创新。
%   版权所有归属项目团队。
% ============================================================

function plot_freq_power(results)
    % 频率-出力双面板时序图
    %
    % 输入:
    %   results - 仿真结果结构体（run_mode_island输出）

    hist = results.hist;
    cfg  = results.cfg;
    t    = hist.time;
    Nv   = cfg.N_vpp;

    figure('Name', '孤岛仿真：频率与出力时序', 'Position', [100, 100, 1200, 700]);

    % ---- 上板：系统频率 ----
    subplot(2, 1, 1);
    hold on; grid on;

    colors = lines(Nv);
    for v = 1:Nv
        plot(t, hist.freq(:, v), 'Color', colors(v, :), 'LineWidth', 1.2, ...
             'DisplayName', sprintf('VPP%d', v));
    end

    % 标称频率线
    yline(cfg.f_nom, 'k--', 'LineWidth', 1.2, 'DisplayName', '标称 50Hz');
    % 安全区间
    yline(cfg.Safety.freq_max, 'r--', 'LineWidth', 1, 'DisplayName', '上限');
    yline(cfg.Safety.freq_min, 'r--', 'LineWidth', 1, 'DisplayName', '下限');
    ylim([cfg.f_nom - 1, cfg.f_nom + 1]);

    xlabel('时间 (h)');
    ylabel('频率 (Hz)');
    title('系统频率时序曲线');
    legend('Location', 'best');

    % ---- 下板：机组出力堆叠面积图 ----
    subplot(2, 1, 2);
    hold on; grid on;

    % 对每个VPP画出力堆叠
    for v = 1:Nv
        subplot(2, Nv, Nv + v);  % 底部一行Nv个子图
        hold on; grid on;

        % 堆叠面积
        P_pv   = hist.P_pv(:, v);
        P_wind = hist.P_wind(:, v);
        P_gas  = hist.P_gas(:, v);
        P_bat  = max(hist.P_bat(:, v), 0);  % 放电为正
        P_bat_ch = max(-hist.P_bat(:, v), 0); % 充电（负荷侧）
        P_load = hist.P_load(:, v);
        P_shed = hist.P_shed(:, v);

        % 出力侧堆叠
        area(t, [P_pv, P_wind, P_gas, P_bat], 'LineStyle', 'none');
        % 负荷曲线
        plot(t, P_load, 'k-', 'LineWidth', 2, 'DisplayName', '负荷');
        plot(t, P_load - P_shed, 'k--', 'LineWidth', 1.5, 'DisplayName', '实际供电');

        xlabel('时间 (h)');
        ylabel('功率 (kW)');
        title(sprintf('VPP%d 出力构成', v));
        if v == 1
            legend({'光伏', '风电', '燃气', '储能放电', '负荷', '实际供电'}, ...
                   'Location', 'best');
        end
        xlim([0, cfg.T_sim]);
    end

    sgtitle('孤岛自治仿真 — 频率与出力分析');
end
