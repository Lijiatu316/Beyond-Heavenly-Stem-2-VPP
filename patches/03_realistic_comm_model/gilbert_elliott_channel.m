% ============================================================
% 文件名：gilbert_elliott_channel.m
% 功能：Gilbert-Elliott两状态马尔可夫信道模型 — 独立信道分析工具
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 理论基础：
%   E. N. Gilbert (1960): "Capacity of a burst-noise channel"
%   E. O. Elliott (1963): "Estimates of error rates for codes on burst-noise channels"
%
% 模型:
%   P = [P_GG  P_GB]  稳态分布: π_G = P_BG/(P_GB+P_BG)
%       [P_BG  P_BB]            π_B = P_GB/(P_GB+P_BG)
%
% 该模型已被广泛用于:
%   - 电力线载波通信 (PLC) 信道建模
%   - 无线传感器网络 (WSN) 链路质量评估
%   - 配电网通信网络可靠性分析
%
% 本文件可作为独立工具进行信道稳态分析，
% 验证参数设置是否合理 (如稳态坏状态概率、平均突发长度等)
% ============================================================

function channel = gilbert_elliott_channel(params)
    % Gilbert-Elliott信道分析器
    %
    % 输入:
    %   params - 参数结构体:
    %       .P_GG, .P_GB, .P_BG, .P_BB — 状态转移概率
    %       .n_steps — 仿真步数 (可选，默认1000)
    %
    % 输出:
    %   channel - 分析结果结构体:
    %       .state_sequence   — 状态序列
    %       .steady_state     — 稳态分布
    %       .mean_burst_len   — 平均突发长度 (步)
    %       .mean_good_len    — 平均好状态持续长度 (步)
    %       .transition_matrix — 转移概率矩阵

    if nargin < 1
        params = struct('P_GG', 0.95, 'P_GB', 0.05, 'P_BG', 0.20, 'P_BB', 0.80, 'n_steps', 10000);
    end
    if ~isfield(params, 'n_steps')
        params.n_steps = 10000;
    end

    P_GG = params.P_GG; P_GB = params.P_GB;
    P_BG = params.P_BG; P_BB = params.P_BB;
    n = params.n_steps;

    % ---- 转移概率矩阵 ----
    P = [P_GG, P_GB;
         P_BG, P_BB];

    % ---- 稳态分布 ----
    pi_G = P_BG / (P_GB + P_BG);
    pi_B = P_GB / (P_GB + P_BG);
    pi_steady = [pi_G, pi_B];

    % ---- 平均持续长度 ----
    mean_good_len = 1 / P_GB;    % GOOD状态期望持续步数
    mean_burst_len = 1 / P_BG;   % BAD状态期望持续步数 (平均突发长度)

    % ---- 蒙特卡洛仿真 ----
    state = ones(1, n);  % 1=GOOD, 0=BAD
    state(1) = rand() < pi_G;

    for k = 2:n
        if state(k-1) == 1  % GOOD
            state(k) = rand() < P_GG;
        else  % BAD
            state(k) = rand() < P_BG;
        end
    end

    % ---- 统计分析 ----
    % 统计突发
    burst_lengths = [];
    good_lengths = [];
    current_run = 1;
    for k = 2:n
        if state(k) == state(k-1)
            current_run = current_run + 1;
        else
            if state(k-1) == 1  % GOOD run ended
                good_lengths(end+1) = current_run;
            else  % BAD run ended
                burst_lengths(end+1) = current_run;
            end
            current_run = 1;
        end
    end

    % ---- 输出 ----
    channel = struct();
    channel.params = params;
    channel.transition_matrix = P;
    channel.steady_state = struct('pi_G', pi_G, 'pi_B', pi_B);
    channel.mean_burst_len = mean_burst_len;
    channel.mean_good_len = mean_good_len;
    channel.theoretical_avg_loss = pi_B;  % 稳态丢包率 ≈ 坏状态概率
    channel.state_sequence = state;
    channel.empirical_pi_G = mean(state);
    channel.empirical_pi_B = 1 - mean(state);
    channel.empirical_mean_burst = mean(burst_lengths);
    channel.empirical_mean_good = mean(good_lengths);
    channel.burst_lengths = burst_lengths;
    channel.good_lengths = good_lengths;

    % ---- 打印分析报告 ----
    fprintf('========================================\n');
    fprintf('  Gilbert-Elliott 信道模型分析\n');
    fprintf('========================================\n');
    fprintf('  转移矩阵:\n');
    fprintf('    P(G→G)=%.3f  P(G→B)=%.3f\n', P_GG, P_GB);
    fprintf('    P(B→G)=%.3f  P(B→B)=%.3f\n', P_BG, P_BB);
    fprintf('\n');
    fprintf('  稳态分布: π_G=%.3f, π_B=%.3f\n', pi_G, pi_B);
    fprintf('  平均好状态长度: %.1f 步\n', mean_good_len);
    fprintf('  平均突发长度:   %.1f 步\n', mean_burst_len);
    fprintf('  稳态丢包率:     %.1f%%\n', pi_B * 100);
    fprintf('\n');
    fprintf('  仿真验证 (%d步):\n', n);
    fprintf('    经验 π_B:       %.3f\n', channel.empirical_pi_B);
    fprintf('    经验平均突发:   %.1f 步\n', channel.empirical_mean_burst);
    fprintf('    经验平均好状态: %.1f 步\n', channel.empirical_mean_good);
    fprintf('========================================\n');

    % ---- 可视化 ----
    figure('Name', 'Gilbert-Elliott信道分析', 'Position', [100, 100, 1000, 600]);

    subplot(2,2,1);
    plot(state(1:min(n, 500)), 'LineWidth', 0.5);
    xlabel('步数'); ylabel('状态');
    ylim([-0.1, 1.1]); yticks([0, 1]); yticklabels({'BAD', 'GOOD'});
    title(sprintf('信道状态序列 (前%d步)', min(n, 500)));
    grid on;

    subplot(2,2,2);
    histogram(burst_lengths, 'Normalization', 'probability', 'BinMethod', 'integers');
    hold on;
    x = 1:max(burst_lengths);
    y_geo = geopdf(x-1, 1/mean_burst_len);
    plot(x, y_geo, 'r-', 'LineWidth', 1.5);
    xlabel('突发长度 (步)'); ylabel('概率');
    title(sprintf('突发长度分布 (μ=%.1f步)', mean_burst_len));
    legend('仿真', '几何分布(理论)', 'Location', 'northeast');
    grid on;

    subplot(2,2,3);
    acf = autocorr(double(state), min(n-1, 200));
    plot(0:min(n-1, 200), acf, 'LineWidth', 1);
    xlabel('滞后 (步)'); ylabel('自相关');
    title('信道状态自相关函数');
    grid on;

    subplot(2,2,4);
    bar([pi_G, pi_B]);
    set(gca, 'XTickLabel', {'GOOD', 'BAD'});
    ylabel('概率'); title('稳态分布');
    ylim([0, 1]);
    grid on;

    saveas(gcf, 'gilbert_elliott_analysis.png');
    fprintf('  分析图表已保存: gilbert_elliott_analysis.png\n');
end
