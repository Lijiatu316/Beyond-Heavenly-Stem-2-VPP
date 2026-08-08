% ============================================================
% 文件名：correlated_comm_model.m
% 功能：真实通信损伤模型 — Gilbert-Elliott信道 + 延迟-丢包相关性
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 设计背景：
%   原 comm_delay_sim.m 采用独立同分布高斯噪声，无法反映真实通信网络的：
%   1. 时间相关性 — 好的链路倾向于保持好，坏的链路倾向于保持坏
%   2. 突发丢包 — 丢包成簇出现而非随机均匀分布
%   3. 延迟-丢包相关性 — 高延迟链路丢包率也更高（共享拥塞根因）
%
% 理论基础：
%   - Gilbert-Elliott 两状态马尔可夫信道模型 (1960, 1963)
%   - 3GPP TR 38.901 信道模型 (5G NR)
%   - ITU-T G.1050 网络损伤模型
%   - 实测数据: 4G/5G公网和电力专网延迟丢包测量
%
% 与原函数的接口兼容：
%   comm_state = correlated_comm_model(cfg, t_step, fault_active, channel_state)
%   输入/输出格式与 comm_delay_sim() 完全一致，可直接替换
% ============================================================

function [comm_state, channel_state] = correlated_comm_model(cfg, t_step, fault_active, channel_state)
    % 相关信道模型 — VPP间邻域链路通信质量模拟
    %
    % 输入:
    %   cfg           - 全局配置 (需含 cfg.patches.real_comm)
    %   t_step        - 当前时间步索引
    %   fault_active  - 故障激活矩阵 [Nv × Nv]
    %   channel_state - (可选) 上一时间步的信道状态，保持马尔可夫连续性
    %
    % 输出:
    %   comm_state    - 通信状态 (与原函数相同的结构体)
    %   channel_state - 更新后的信道状态，用于下一时间步

    Nv = cfg.N_vpp;
    topo = cfg.Comm.topology;
    rc = cfg.patches.real_comm;

    if ~rc.enabled
        % 回退到原始模型
        comm_state = comm_delay_sim(cfg, t_step, fault_active);
        channel_state = [];
        return;
    end

    % ---- 初始化信道状态 (如果首次调用) ----
    if nargin < 4 || isempty(channel_state)
        channel_state = init_channel_state(Nv, topo, rc);
    end

    % ---- 马尔可夫状态转移 ----
    rng(t_step * 300 + 128);
    ge = rc.gilbert_elliott;

    for i = 1:Nv
        for j = 1:Nv
            if i == j || topo(i, j) == 0
                continue;
            end

            % 状态转移概率矩阵
            P_GG = ge.P_GG;
            P_GB = ge.P_GB;
            P_BG = ge.P_BG;
            P_BB = ge.P_BB;

            % 考虑故障对转移概率的影响 (故障使链路更倾向坏状态)
            if fault_active(i, j) || fault_active(j, i)
                P_GG = max(0.1, P_GG - 0.5);
                P_GB = min(0.9, P_GB + 0.5);
                P_BG = max(0.1, P_BG - 0.1);
                P_BB = min(0.95, P_BB + 0.1);
            end

            % 状态转移
            if channel_state.state(i, j) == 1  % GOOD
                if rand() < P_GB
                    channel_state.state(i, j) = 0;  % → BAD
                    channel_state.burst_start(i, j) = t_step;
                end
            else  % BAD
                if rand() < P_BG
                    channel_state.state(i, j) = 1;  % → GOOD
                    channel_state.burst_duration(i, j) = t_step - channel_state.burst_start(i, j);
                end
            end

            % 记录状态持续时间
            if channel_state.state(i, j) == 1
                channel_state.good_duration(i, j) = channel_state.good_duration(i, j) + 1;
            else
                channel_state.bad_duration(i, j) = channel_state.bad_duration(i, j) + 1;
            end
        end
    end

    % ---- 生成延迟和丢包 (基于信道状态) ----
    rng(t_step * 400 + 256);

    % 基础噪声 (空间相关性: 相邻VPP的通信环境相似)
    for i = 1:Nv
        for j = 1:Nv
            if i == j
                channel_state.delay(i, j) = 0;
                channel_state.loss(i, j) = 0;
                continue;
            end

            if topo(i, j) == 0
                channel_state.delay(i, j) = Inf;
                channel_state.loss(i, j) = 1;
                continue;
            end

            if channel_state.state(i, j) == 1  % GOOD state
                % 低延迟、低丢包
                delay_mean = ge.delay_good_mean;
                delay_std  = ge.delay_good_std;
                loss_mean  = ge.loss_good_mean;

                % 伽马分布 (延迟非负，且右偏更真实)
                if delay_std > 0
                    k_good = (delay_mean / delay_std)^2;
                    theta_good = delay_std^2 / delay_mean;
                    channel_state.delay(i, j) = gamrnd(k_good, theta_good);
                else
                    channel_state.delay(i, j) = delay_mean;
                end

                % Beta分布 (丢包率在0-1之间)
                if loss_mean > 0 && loss_mean < 1
                    alpha = loss_mean * 20;
                    beta_param = (1 - loss_mean) * 20;
                    channel_state.loss(i, j) = betarnd(alpha, beta_param);
                else
                    channel_state.loss(i, j) = loss_mean;
                end

            else  % BAD state
                % 高延迟、高丢包
                delay_mean = ge.delay_bad_mean;
                delay_std  = ge.delay_bad_std;
                loss_mean  = ge.loss_bad_mean;

                if delay_std > 0
                    k_bad = (delay_mean / delay_std)^2;
                    theta_bad = delay_std^2 / delay_mean;
                    channel_state.delay(i, j) = gamrnd(k_bad, theta_bad);
                else
                    channel_state.delay(i, j) = delay_mean;
                end

                if loss_mean > 0 && loss_mean < 1
                    alpha = loss_mean * 10;
                    beta_param = (1 - loss_mean) * 10;
                    channel_state.loss(i, j) = betarnd(alpha, beta_param);
                else
                    channel_state.loss(i, j) = loss_mean;
                end
            end

            % ---- 延迟-丢包相关性 (Copula方法) ----
            % 利用已有的 corr 参数使延迟和丢包共享随机源
            rho = ge.delay_loss_corr;
            if abs(rho) > 0
                % 对延迟和丢包施加相关性
                z1 = norminv(max(0.001, min(0.999, channel_state.loss(i, j))));
                z2_corr = rho * z1 + sqrt(1 - rho^2) * randn();
                channel_state.delay(i, j) = max(0.001, ...
                    channel_state.delay(i, j) * (1 + 0.5 * z2_corr));
            end
        end
    end

    % ---- 考虑突发丢包 (突发期内丢包率显著升高) ----
    if rc.burst_loss_enabled
        for i = 1:Nv
            for j = 1:Nv
                if topo(i, j) == 0 || i == j
                    continue;
                end
                if channel_state.state(i, j) == 0  % BAD状态
                    % 在坏状态初期，丢包率额外加倍 (突发效应)
                    if channel_state.bad_duration(i, j) < 3
                        channel_state.loss(i, j) = min(1, channel_state.loss(i, j) * 2);
                    end
                end
            end
        end
    end

    % ---- 链路间弱相关性 (空间一致性) ----
    % 相邻链路的通信质量有少量共同趋势
    for i = 1:Nv
        neighbors = find(topo(i, :) > 0);
        if length(neighbors) >= 2
            % 计算邻居链路当前平均质量
            avg_loss = mean(channel_state.loss(i, neighbors));
            % 每条链路向均值微调 (空间平滑因子 0.1)
            for j = neighbors
                channel_state.loss(i, j) = (1 - 0.1) * channel_state.loss(i, j) ...
                                         + 0.1 * avg_loss;
            end
        end
    end

    % ---- 对称化 ----
    delay = (channel_state.delay + channel_state.delay') / 2;
    loss  = (channel_state.loss + channel_state.loss') / 2;

    % ---- 质量评分 ----
    quality = max(1 - (delay / cfg.Comm.delay_threshold + loss / cfg.Comm.loss_threshold) / 2, 0);
    quality = min(quality, 1);
    quality = (quality + quality') / 2;

    % ---- 组装输出 ----
    comm_state.delay     = delay;
    comm_state.loss_rate = loss;
    comm_state.quality   = quality;

    % 附加信道状态信息 (用于分析和调试)
    comm_state.channel_state_info = struct(...
        'gilbert_elliott_state', channel_state.state, ...
        'good_duration', channel_state.good_duration, ...
        'bad_duration', channel_state.bad_duration, ...
        'model', 'Gilbert-Elliott + Copula correlation' ...
    );
end


function cs = init_channel_state(Nv, topo, rc)
    % 初始化信道状态

    cs = struct();
    cs.state = ones(Nv, Nv);          % 1=GOOD, 0=BAD (初始全部GOOD)
    cs.delay = zeros(Nv, Nv);
    cs.loss = zeros(Nv, Nv);
    cs.good_duration = zeros(Nv, Nv);
    cs.bad_duration = zeros(Nv, Nv);
    cs.burst_start = zeros(Nv, Nv);
    cs.burst_duration = zeros(Nv, Nv);

    % 非连接链路标记为GOOD (实际不会使用)
    for i = 1:Nv
        for j = 1:Nv
            if i ~= j && topo(i, j) == 0
                cs.state(i, j) = 0;  % 无连接 → 视为BAD
            end
        end
    end

    % 以概率初始化坏状态 (约5%)
    rng(42);
    for i = 1:Nv
        for j = (i+1):Nv
            if topo(i, j) > 0
                if rand() < 0.05
                    cs.state(i, j) = 0;
                    cs.state(j, i) = 0;
                    cs.burst_start(i, j) = 1;
                    cs.burst_start(j, i) = 1;
                end
            end
        end
    end
end
