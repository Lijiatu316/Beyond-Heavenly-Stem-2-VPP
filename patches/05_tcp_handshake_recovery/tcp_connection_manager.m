% ============================================================
% 文件名：tcp_connection_manager.m
% 功能：TCP连接管理器 — 三次握手、RTO计算、指数退避
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 设计背景：
%   原系统中的通信恢复是瞬时完成的（fault_active=false → 立即恢复通信）。
%   实际通信恢复需要TCP三次握手，经历以下阶段：
%     1. SYN_SENT   — 发送SYN报文
%     2. SYN_RCVD   — 收到SYN-ACK，发送ACK
%     3. ESTABLISHED — 连接建立完成
%   若SYN丢失，需要RTO超时重传，RTO随重传次数指数增长。
%
% 参考标准:
%   - RFC 6298  (TCP Retransmission Timeout)
%   - RFC 1122  (TCP requirements — 3-way handshake)
%   - RFC 5681  (TCP Congestion Control)
%
% 状态机:
%   CLOSED ──(链路恢复)──→ SYN_SENT ──(收到SYN-ACK)──→ SYN_RCVD ──(发送ACK)──→ ESTABLISHED
%     ↑                       │                                │
%     └──(超过max_retries)────┘                                │
%     ↑                        │                               │
%     └──(SYN超时<max)─重传────┘                               │
%                                                              │
%   ESTABLISHED ──(链路故障)──→ CLOSED
% ============================================================

function tcp = tcp_connection_manager(action, varargin)
    % TCP连接管理器 — 通用接口
    %
    % 使用方式:
    %   tcp = tcp_connection_manager('init', cfg);
    %   tcp = tcp_connection_manager('step', tcp, fault_active, t_now, dt);
    %   report = tcp_connection_manager('report', tcp);
    %
    % 输入:
    %   action - 操作: 'init' | 'step' | 'report' | 'get_latency'
    %   varargin - 取决于 action

    switch action
        case 'init'
            tcp = tcp_init(varargin{1});
        case 'step'
            tcp = tcp_step(varargin{1}, varargin{2}, varargin{3}, varargin{4});
        case 'report'
            tcp = tcp_report(varargin{1});
        case 'get_latency'
            tcp = tcp_get_latency(varargin{1}, varargin{2}, varargin{3});
        otherwise
            error('未知操作: %s', action);
    end
end


function tcp = tcp_init(cfg)
    % 初始化TCP连接管理器
    %
    % 输入:
    %   cfg - 全局配置 (需含 cfg.patches.tcp_handshake)
    %
    % 输出:
    %   tcp - TCP状态结构体

    Nv = cfg.N_vpp;
    topo = cfg.Comm.topology;
    ta = cfg.patches.tcp_handshake;

    tcp = struct();
    tcp.Nv = Nv;
    tcp.topo = topo;

    % 连接状态: 0=CLOSED, 1=ESTABLISHED, 2=SYN_SENT, 3=SYN_RCVD
    tcp.conn = ones(Nv, Nv);
    tcp.conn(logical(eye(Nv))) = 1;  % 自连接始终ESTABLISHED

    % RTO管理
    tcp.srtt_ms     = zeros(Nv, Nv);     % 平滑RTT (RFC 6298)
    tcp.rttvar_ms   = zeros(Nv, Nv);     % RTT方差
    tcp.rto_ms      = ta.initial_rto_ms * ones(Nv, Nv);  % 重传超时
    tcp.rto_backoff = zeros(Nv, Nv);     % 退避乘数

    % 握手状态
    tcp.handshake_start_s = -ones(Nv, Nv);  % 握手开始时间
    tcp.syn_retries       = zeros(Nv, Nv);  % SYN重试次数
    tcp.syn_sent_time_s   = zeros(Nv, Nv);  % 上次SYN发送时间

    % 统计
    tcp.stats = struct(...
        'total_handshakes', 0, ...
        'successful_handshakes', 0, ...
        'failed_handshakes', 0, ...
        'total_syn_retransmissions', 0, ...
        'avg_handshake_duration_ms', 0, ...
        'total_disconnections', 0 ...
    );

    % 历史记录
    tcp.history = struct(...
        'time_s', [], ...
        'event', {{}}, ...  % 事件类型: 'SYN','SYN_ACK','ACK','TIMEOUT','ESTABLISHED','CLOSED'
        'link', [], ...
        'detail', {{}} ...
    );

    % 参数缓存
    tcp.cfg = ta;

    fprintf('  [TCP管理器] 初始化 %dVPP, 最大RTO=%dms\n', Nv, ta.max_rto_ms);
end


function tcp = tcp_step(tcp, fault_active, t_now_s, dt_s)
    % TCP状态机 — 单步推进
    %
    % 输入:
    %   tcp          - TCP状态结构体
    %   fault_active - 故障矩阵 [Nv × Nv]
    %   t_now_s      - 当前仿真时间 (s)
    %   dt_s         - 仿真步长 (s)

    Nv = tcp.Nv;
    ta = tcp.cfg;

    for i = 1:Nv
        for j = 1:Nv
            if i == j || tcp.topo(i, j) == 0
                continue;
            end

            link_fault = fault_active(i, j) || fault_active(j, i);

            % ---- 故障处理: ESTABLISHED → CLOSED ----
            if link_fault && tcp.conn(i, j) == 1
                tcp.conn(i, j) = 0;
                tcp.stats.total_disconnections = tcp.stats.total_disconnections + 1;
                log_event(tcp, t_now_s, 'CLOSED', [i, j], '链路故障');
                continue;
            end

            % ---- 恢复处理: 启动三次握手 ----
            if ~link_fault && tcp.conn(i, j) == 0  % CLOSED → 发起握手
                tcp.conn(i, j) = 2;  % SYN_SENT
                tcp.syn_retries(i, j) = 0;
                tcp.rto_backoff(i, j) = 0;
                tcp.handshake_start_s(i, j) = t_now_s;
                tcp.syn_sent_time_s(i, j) = t_now_s;
                tcp.stats.total_handshakes = tcp.stats.total_handshakes + 1;
                log_event(tcp, t_now_s, 'SYN', [i, j], '链路恢复，发送SYN');
                continue;
            end

            % ---- 握手阶段: SYN_SENT ----
            if tcp.conn(i, j) == 2
                elapsed_ms = (t_now_s - tcp.syn_sent_time_s(i, j)) * 1000;
                current_rto = tcp.rto_ms(i, j);

                % 模拟RTT/2后收到SYN-ACK
                rtt_half = tcp.srtt_ms(i, j) / 2;
                if rtt_half == 0
                    rtt_half = ta.initial_rto_ms / 4;  % 首次RTT估计
                end

                if elapsed_ms >= rtt_half
                    % 模拟丢包：SYN或SYN-ACK丢失概率
                    pkt_loss = 0.05;  % 握手报文丢包率5%
                    if rand() < pkt_loss
                        % 包丢失 → 等待RTO超时重传
                    end

                    if rand() >= pkt_loss  % 包到达
                        tcp.conn(i, j) = 3;  % SYN_RCVD
                        % 更新SRTT (测量到的RTT)
                        measured_rtt = elapsed_ms * 2;  % RTT = 2 × one-way
                        update_rtt_estimate(tcp, i, j, measured_rtt, ta);
                        log_event(tcp, t_now_s, 'SYN_ACK', [i, j], sprintf('RTT=%.1fms', measured_rtt));
                    end
                end

                % 检查SYN超时
                if elapsed_ms >= current_rto
                    tcp.syn_retries(i, j) = tcp.syn_retries(i, j) + 1;
                    tcp.stats.total_syn_retransmissions = tcp.stats.total_syn_retransmissions + 1;

                    if tcp.syn_retries(i, j) >= ta.max_syn_retries
                        % 握手失败
                        tcp.conn(i, j) = 0;  % 回到CLOSED
                        tcp.syn_retries(i, j) = 0;
                        tcp.stats.failed_handshakes = tcp.stats.failed_handshakes + 1;
                        log_event(tcp, t_now_s, 'TIMEOUT', [i, j], ...
                                  sprintf('SYN重试%d次后放弃', ta.max_syn_retries));
                    else
                        % 指数退避重传
                        tcp.rto_backoff(i, j) = tcp.rto_backoff(i, j) + 1;
                        tcp.rto_ms(i, j) = min(tcp.rto_ms(i, j) * 2, ta.max_rto_ms);
                        tcp.syn_sent_time_s(i, j) = t_now_s;
                        log_event(tcp, t_now_s, 'SYN', [i, j], ...
                                  sprintf('SYN重传#%d, RTO=%.0fms', ...
                                          tcp.syn_retries(i, j), tcp.rto_ms(i, j)));
                    end
                end

                continue;
            end

            % ---- 握手阶段: SYN_RCVD → 发送ACK (最后一跳) ----
            if tcp.conn(i, j) == 3
                elapsed_ms = (t_now_s - tcp.handshake_start_s(i, j)) * 1000;
                rtt_half = tcp.srtt_ms(i, j) / 2;
                if rtt_half == 0
                    rtt_half = ta.initial_rto_ms / 4;
                end

                if elapsed_ms >= rtt_half * 1.5  % SYN-RCVD持续~1.5×半RTT
                    tcp.conn(i, j) = 1;  % ESTABLISHED
                    tcp.rto_backoff(i, j) = 0;
                    tcp.stats.successful_handshakes = tcp.stats.successful_handshakes + 1;

                    % 更新平均握手时长
                    n = tcp.stats.successful_handshakes;
                    avg_old = tcp.stats.avg_handshake_duration_ms;
                    tcp.stats.avg_handshake_duration_ms = ...
                        (avg_old * (n - 1) + elapsed_ms) / max(n, 1);

                    log_event(tcp, t_now_s, 'ESTABLISHED', [i, j], ...
                              sprintf('握手完成, 耗时%.1fms', elapsed_ms));
                end
            end
        end
    end
end


function update_rtt_estimate(tcp, i, j, measured_rtt, ta)
    % RFC 6298 RTT估算器
    %
    % SRTT    = (1-α)·SRTT + α·RTT_measured
    % RTTVAR  = (1-β)·RTTVAR + β·|SRTT - RTT_measured|
    % RTO     = SRTT + K·RTTVAR

    alpha = ta.rtt_alpha;
    beta  = ta.rtt_beta;
    K     = ta.rtt_k;

    srtt_old = tcp.srtt_ms(i, j);
    rttvar_old = tcp.rttvar_ms(i, j);

    if srtt_old == 0
        % 首次测量
        tcp.srtt_ms(i, j) = measured_rtt;
        tcp.rttvar_ms(i, j) = measured_rtt / 2;
    else
        tcp.srtt_ms(i, j) = (1 - alpha) * srtt_old + alpha * measured_rtt;
        tcp.rttvar_ms(i, j) = (1 - beta) * rttvar_old + beta * abs(srtt_old - measured_rtt);
    end

    tcp.rto_ms(i, j) = max(ta.min_rto_ms, ...
                            min(tcp.srtt_ms(i, j) + K * tcp.rttvar_ms(i, j), ...
                                ta.max_rto_ms));
end


function latency = tcp_get_latency(tcp, src, dst)
    % 获取TCP连接当前延迟
    % 返回:
    %   latency - TCP连接附加延迟 (s), 含SRTT和当前RTO影响
    %             如果连接未建立，返回 Inf

    if tcp.conn(src, dst) == 1
        latency = tcp.srtt_ms(src, dst) / 1000;
        if latency == 0
            latency = tcp.cfg.initial_rto_ms / 4000;  % 默认RTT/4 one-way
        end
    else
        latency = Inf;  % 未建立连接
    end
end


function tcp_report(tcp)
    % 打印TCP连接统计报告

    s = tcp.stats;
    fprintf('\n========================================\n');
    fprintf('  TCP连接管理统计报告\n');
    fprintf('========================================\n');
    fprintf('  总握手次数:      %d\n', s.total_handshakes);
    fprintf('  成功握手:        %d\n', s.successful_handshakes);
    fprintf('  失败握手:        %d\n', s.failed_handshakes);
    fprintf('  SYN重传总数:     %d\n', s.total_syn_retransmissions);
    fprintf('  平均握手时长:    %.1f ms\n', s.avg_handshake_duration_ms);
    fprintf('  总断连次数:      %d\n', s.total_disconnections);
    fprintf('  握手成功率:      %.1f%%\n', ...
            100 * s.successful_handshakes / max(s.total_handshakes, 1));

    % 当前连接状态
    Nv = tcp.Nv;
    n_links = sum(tcp.topo(:) > 0) / 2;
    n_established = sum(tcp.conn(:) == 1) / 2 - Nv/2;  % 剔除自连接
    n_syn_sent = sum(tcp.conn(:) == 2) / 2;
    n_syn_rcvd = sum(tcp.conn(:) == 3) / 2;
    n_closed = sum(tcp.conn(:) == 0) / 2;

    fprintf('\n  当前连接状态:\n');
    fprintf('    ESTABLISHED: %d/%d 链路\n', n_established, n_links);
    fprintf('    SYN_SENT:    %d\n', n_syn_sent);
    fprintf('    SYN_RCVD:    %d\n', n_syn_rcvd);
    fprintf('    CLOSED:      %d\n', n_closed);
    fprintf('========================================\n');
end


function log_event(tcp, t, event, link, detail)
    % 内部事件日志记录
    idx = length(tcp.history.time_s) + 1;
    tcp.history.time_s(idx) = t;
    tcp.history.event{idx} = event;
    tcp.history.link(idx, :) = link;
    tcp.history.detail{idx} = detail;
end
