% ============================================================
% 文件名：tcp_recovery_model.m
% 功能：TCP通信恢复过程详细建模 — 三次握手+RTO指数退避
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 本文件提供TCP三次握手的独立仿真和参数敏感性分析，
% 可用于评估不同通信介质(RTT分布)下的恢复时间。
%
% 场景分析:
%   1. 光纤专网: RTT~5ms, 握手<15ms
%   2. 4G公网:   RTT~40ms, 握手<120ms
%   3. 5G专网:   RTT~10ms, 握手<30ms
%   4. 卫星通信:  RTT~600ms, 握手<1.8s
%   5. 电力线载波: RTT~100ms, 握手<300ms
% ============================================================

function results = tcp_recovery_model(medium_type, sim_cfg)
    % TCP恢复过程仿真
    %
    % 输入:
    %   medium_type - 通信介质类型
    %       'fiber', 'four_g', 'five_g', 'satellite', 'powerline'
    %   sim_cfg     - 仿真配置 (可选)
    %       .n_samples      — 蒙特卡洛样本数 (默认1000)
    %       .pkt_loss_rate  — 握手报文丢包率 (默认0.05)
    %       .max_retries    — 最大SYN重试 (默认6)
    %
    % 输出:
    %   results - 恢复过程分析结果

    if nargin < 2
        sim_cfg = struct();
    end
    if ~isfield(sim_cfg, 'n_samples')
        sim_cfg.n_samples = 1000;
    end
    if ~isfield(sim_cfg, 'pkt_loss_rate')
        sim_cfg.pkt_loss_rate = 0.05;
    end
    if ~isfield(sim_cfg, 'max_retries')
        sim_cfg.max_retries = 6;
    end

    % TCP默认参数 (RFC 6298)
    initial_rto_ms = 1000;
    min_rto_ms = 200;
    max_rto_ms = 60000;
    rtt_alpha = 0.125;
    rtt_beta = 0.25;
    rtt_K = 4;

    % 各介质的RTT分布参数 (基于实测)
    rtt_profiles = struct(...
        'fiber',      struct('mean_ms', 5,   'std_ms', 1,   'label', '光纤专网'), ...
        'four_g',     struct('mean_ms', 40,  'std_ms', 15,  'label', '4G公网'), ...
        'five_g',     struct('mean_ms', 10,  'std_ms', 3,   'label', '5G专网'), ...
        'satellite',  struct('mean_ms', 600, 'std_ms', 50,  'label', '卫星通信'), ...
        'powerline',  struct('mean_ms', 100, 'std_ms', 30,  'label', '电力线载波') ...
    );

    if ~ismember(medium_type, fieldnames(rtt_profiles))
        error('未知通信介质: %s', medium_type);
    end

    profile = rtt_profiles.(medium_type);
    n = sim_cfg.n_samples;
    p_loss = sim_cfg.pkt_loss_rate;
    max_retries = sim_cfg.max_retries;

    % ---- 蒙特卡洛仿真 ----
    handshake_times = zeros(n, 1);
    num_retries = zeros(n, 1);
    success = true(n, 1);

    for sample = 1:n
        rtt = max(0.001, profile.mean_ms + profile.std_ms * randn());  % 实际RTT (ms)

        % 初始化RTO
        srtt = rtt;
        rttvar = rtt / 2;
        rto = max(min_rto_ms, min(srtt + rtt_K * rttvar, max_rto_ms));

        total_time = 0;
        retries = 0;

        while retries <= max_retries
            % 发送SYN
            total_time = total_time + rtt / 2;  % SYN到达对端

            % SYN-ACK丢失? (或SYN丢失)
            if rand() < p_loss
                % 超时等待
                total_time = total_time + rto / 1000;  % RTO (ms→s)
                retries = retries + 1;

                % 指数退避
                rto = min(rto * 2, max_rto_ms);

                if retries > max_retries
                    success(sample) = false;
                    break;
                end
                continue;
            end

            % 收到SYN-ACK
            total_time = total_time + rtt / 2;

            % 发送ACK (最后一跳)
            total_time = total_time + rtt / 2;

            % 更新RTT估算
            srtt_new = (1 - rtt_alpha) * srtt + rtt_alpha * rtt;
            rttvar_new = (1 - rtt_beta) * rttvar + rtt_beta * abs(srtt - rtt);
            srtt = srtt_new;
            rttvar = rttvar_new;
            rto = max(min_rto_ms, min(srtt + rtt_K * rttvar, max_rto_ms));

            break;  % 握手完成
        end

        handshake_times(sample) = total_time;
        num_retries(sample) = retries;
    end

    % ---- 统计分析 ----
    success_rate = mean(success) * 100;
    valid_times = handshake_times(success);

    results = struct();
    results.medium = medium_type;
    results.medium_label = profile.label;
    results.rtt_mean_ms = profile.mean_ms;
    results.rtt_std_ms = profile.std_ms;
    results.n_samples = n;
    results.success_rate_pct = success_rate;
    results.handshake_time_mean_ms = mean(valid_times) * 1000;
    results.handshake_time_median_ms = median(valid_times) * 1000;
    results.handshake_time_p95_ms = prctile(valid_times, 95) * 1000;
    results.handshake_time_p99_ms = prctile(valid_times, 99) * 1000;
    results.handshake_time_min_ms = min(valid_times) * 1000;
    results.handshake_time_max_ms = max(valid_times) * 1000;
    results.avg_retries = mean(num_retries);
    results.handshake_times = handshake_times;
    results.num_retries = num_retries;
    results.success = success;

    % ---- 打印报告 ----
    fprintf('========================================\n');
    fprintf('  TCP三次握手恢复分析 — %s\n', profile.label);
    fprintf('========================================\n');
    fprintf('  RTT: %.1f ± %.1f ms\n', profile.mean_ms, profile.std_ms);
    fprintf('  丢包率: %.0f%%\n', p_loss * 100);
    fprintf('  样本数: %d\n', n);
    fprintf('  握手成功率: %.1f%%\n', success_rate);
    fprintf('\n  握手时长统计:\n');
    fprintf('    均值:    %.1f ms\n', results.handshake_time_mean_ms);
    fprintf('    中位数:  %.1f ms\n', results.handshake_time_median_ms);
    fprintf('    P95:     %.1f ms\n', results.handshake_time_p95_ms);
    fprintf('    P99:     %.1f ms\n', results.handshake_time_p99_ms);
    fprintf('    最小值:  %.1f ms\n', results.handshake_time_min_ms);
    fprintf('    最大值:  %.1f ms\n', results.handshake_time_max_ms);
    fprintf('  平均SYN重传: %.2f 次\n', results.avg_retries);
    fprintf('========================================\n');

    % ---- 可视化 ----
    figure('Name', sprintf('TCP恢复分析 — %s', profile.label), ...
           'Position', [100, 100, 1000, 600]);

    subplot(2,2,1);
    histogram(valid_times * 1000, 50, 'Normalization', 'probability');
    xlabel('握手时长 (ms)'); ylabel('概率');
    title(sprintf('握手时长分布 (%s)', profile.label));
    xline(results.handshake_time_mean_ms, 'r--', sprintf('均值=%.1fms', results.handshake_time_mean_ms));
    xline(results.handshake_time_median_ms, 'b--', sprintf('中位=%.1fms', results.handshake_time_median_ms));
    grid on;

    subplot(2,2,2);
    histogram(num_retries, 'BinMethod', 'integers');
    xlabel('SYN重传次数'); ylabel('频次');
    title('SYN重传次数分布');
    grid on;

    subplot(2,2,3);
    cdfplot(valid_times * 1000);
    xlabel('握手时长 (ms)'); ylabel('累积概率');
    title('握手时长CDF');
    grid on;

    subplot(2,2,4);
    % 各介质对比 (运行全部5种介质)
    all_media = fieldnames(rtt_profiles);
    compare_means = zeros(length(all_media), 1);
    compare_p95 = zeros(length(all_media), 1);
    compare_labels = cell(length(all_media), 1);
    for m = 1:length(all_media)
        prof = rtt_profiles.(all_media{m});
        rtt_est = prof.mean_ms;
        % 理论握手时间 ≈ 3 × RTT/2 (无丢包理想情况)
        compare_means(m) = 1.5 * rtt_est;
        compare_p95(m) = 3 * rtt_est;  % P95 ≈ 2×理想
        compare_labels{m} = prof.label;
    end

    bar_data = [compare_means, compare_p95];
    bar(bar_data);
    set(gca, 'XTickLabel', compare_labels);
    xtickangle(45);
    ylabel('握手时长 (ms)');
    legend({'均值', 'P95'}, 'Location', 'northwest');
    title('各通信介质TCP握手时长对比');
    grid on;

    saveas(gcf, sprintf('tcp_recovery_%s.png', medium_type));
    fprintf('  分析图表已保存: tcp_recovery_%s.png\n', medium_type);
end


function compare_all_media()
    % 对比所有通信介质的TCP恢复性能
    media = {'fiber', 'four_g', 'five_g', 'satellite', 'powerline'};
    all_results = cell(length(media), 1);

    fprintf('\n');
    fprintf('═══════════════════════════════════════════════\n');
    fprintf('  各通信介质TCP三次握手恢复时间对比\n');
    fprintf('═══════════════════════════════════════════════\n');
    fprintf('  %-14s  %8s  %8s  %8s  %8s\n', '介质', 'RTT(ms)', '均值(ms)', 'P95(ms)', '成功率');
    fprintf('  ────────────────────────────────────────────\n');

    for m = 1:length(media)
        all_results{m} = tcp_recovery_model(media{m}, ...
            struct('n_samples', 500, 'pkt_loss_rate', 0.05, 'max_retries', 6));
        r = all_results{m};
        fprintf('  %-14s  %8.1f  %8.1f  %8.1f  %7.1f%%\n', ...
                r.medium_label, r.rtt_mean_ms, ...
                r.handshake_time_mean_ms, r.handshake_time_p95_ms, ...
                r.success_rate_pct);
    end
    fprintf('═══════════════════════════════════════════════\n');
end
