% ============================================================
% 文件名：tcp_rto_calculator.m
% 功能：TCP重传超时(RTO)计算器 — RFC 6298完整实现
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% RFC 6298 核心算法:
%   首次测量:  SRTT ← R,  RTTVAR ← R/2,  RTO ← SRTT + K·RTTVAR
%   后续测量:  RTTVAR ← (1-β)·RTTVAR + β·|SRTT - R|
%              SRTT   ← (1-α)·SRTT   + α·R
%              RTO    ← SRTT + max(G, K·RTTVAR)
%
%   其中: α=1/8, β=1/4, K=4, G=时钟粒度(默认100ms)
%   RTO下界: 1s (RFC 6298 sec 2.4, 已废弃，现在推荐200ms)
%   RTO上界: 至少60s
%
% 指数退避:
%   每次RTO超时后: RTO ← min(RTO × 2, RTO_max)
%   成功接收后:    RTO ← SRTT + K·RTTVAR (从退避恢复)
% ============================================================

function rto_state = tcp_rto_calculator(operation, varargin)
    % TCP RTO状态机
    %
    % 操作:
    %   init    — 初始化RTO状态
    %   measure — 记录一次RTT测量
    %   timeout — 超时事件处理 (指数退避)
    %   get_rto — 获取当前RTO值

    persistent state;
    if isempty(state)
        state = struct();
    end

    switch operation
        case 'init'
            state = rto_init(varargin{:});
            rto_state = state;
        case 'measure'
            state = rto_measure(state, varargin{:});
            rto_state = state;
        case 'timeout'
            state = rto_timeout(state, varargin{:});
            rto_state = state;
        case 'get_rto'
            rto_state = state.rto_current_ms;
        case 'get_stats'
            rto_state = state;
        otherwise
            error('未知操作: %s', operation);
    end
end


function state = rto_init(cfg)
    % 初始化RTO估算器

    if nargin < 1
        cfg = struct(...
            'initial_rto_ms', 1000, ...
            'min_rto_ms', 200, ...
            'max_rto_ms', 60000, ...
            'alpha', 0.125, ...    % SRTT平滑系数
            'beta', 0.25, ...      % RTTVAR平滑系数
            'K', 4 ...             % RTO = SRTT + K·RTTVAR
        );
    end

    state = struct(...
        'srtt_ms', 0, ...
        'rttvar_ms', 0, ...
        'rto_current_ms', cfg.initial_rto_ms, ...
        'rto_base_ms', cfg.initial_rto_ms, ...
        'backoff_multiplier', 1, ...
        'n_measurements', 0, ...
        'n_timeouts', 0, ...
        'rtt_history', [], ...
        'rto_history', [cfg.initial_rto_ms], ...
        'cfg', cfg ...
    );
end


function state = rto_measure(state, measured_rtt_ms)
    % 记录一次新的RTT测量并更新估算器
    %
    % 输入:
    %   measured_rtt_ms - 测量到的RTT值 (ms)

    cfg = state.cfg;
    state.n_measurements = state.n_measurements + 1;

    if state.srtt_ms == 0
        % 首次测量 (RFC 6298 sec 2.2)
        state.srtt_ms = measured_rtt_ms;
        state.rttvar_ms = measured_rtt_ms / 2;
    else
        % 后续测量
        state.rttvar_ms = (1 - cfg.beta) * state.rttvar_ms ...
                        + cfg.beta * abs(state.srtt_ms - measured_rtt_ms);
        state.srtt_ms = (1 - cfg.alpha) * state.srtt_ms ...
                      + cfg.alpha * measured_rtt_ms;
    end

    % 更新RTO (从退避恢复)
    state.rto_base_ms = max(cfg.min_rto_ms, ...
                             min(state.srtt_ms + cfg.K * state.rttvar_ms, ...
                                 cfg.max_rto_ms));
    state.backoff_multiplier = 1;
    state.rto_current_ms = state.rto_base_ms;

    % 记录历史
    state.rtt_history(end+1) = measured_rtt_ms;
    state.rto_history(end+1) = state.rto_current_ms;
end


function state = rto_timeout(state, t_now)
    % RTO超时事件 → 指数退避
    %
    % 输入:
    %   t_now - 当前时间 (任意单位, 仅用于记录)

    state.n_timeouts = state.n_timeouts + 1;
    state.backoff_multiplier = state.backoff_multiplier * 2;
    state.rto_current_ms = min(state.rto_base_ms * state.backoff_multiplier, ...
                                state.cfg.max_rto_ms);
    state.rto_history(end+1) = state.rto_current_ms;

    fprintf('  [RTO] 超时#%d! 退避×%.0f → RTO=%.0fms\n', ...
            state.n_timeouts, state.backoff_multiplier, state.rto_current_ms);
end


function rto_comparison_table()
    % 对比不同RTT分布下的RTO行为

    fprintf('\n========================================\n');
    fprintf('  TCP RTO 参数对比分析\n');
    fprintf('========================================\n');
    fprintf('  %-14s  %8s  %8s  %8s  %8s\n', ...
            '场景', 'RTT(ms)', 'SRTT(ms)', 'RTTVAR', 'RTO(ms)');
    fprintf('  ────────────────────────────────────────\n');

    scenarios = {
        '光纤局域网',   5,   2;
        '光纤城域网',   15,  5;
        '4G公网',       40,  15;
        '5G URLLC',     5,   1;
        '5G eMBB',      10,  3;
        '卫星LEO',      50,  15;
        '卫星GEO',      600, 50;
        'PLC窄带',      200, 80;
    };

    for s = 1:size(scenarios, 1)
        label = scenarios{s, 1};
        rtt = scenarios{s, 2};
        rttvar = scenarios{s, 3};

        % RFC 6298公式
        srtt = rtt;
        calculated_rttvar = rttvar;
        rto = srtt + 4 * calculated_rttvar;

        fprintf('  %-14s  %8.0f  %8.0f  %8.0f  %8.0f\n', label, rtt, srtt, calculated_rttvar, rto);
    end
    fprintf('========================================\n');

    % 绘制各场景RTO收敛曲线
    figure('Name', 'RTO收敛特性', 'Position', [100, 100, 900, 500]);
    hold on;
    colors = lines(size(scenarios, 1));
    for s = 1:size(scenarios, 1)
        rtt_mean = scenarios{s, 2};
        rtt_std = scenarios{s, 3};

        % 模拟测量序列
        n_meas = 50;
        rto_trace = zeros(n_meas, 1);
        st = rto_init();
        for m = 1:n_meas
            measured = max(1, rtt_mean + rtt_std * randn());
            st = rto_measure(st, measured);
            rto_trace(m) = st.rto_current_ms;
        end
        plot(1:n_meas, rto_trace, 'Color', colors(s,:), 'LineWidth', 1.2, ...
             'DisplayName', scenarios{s,1});
    end
    xlabel('测量次数'); ylabel('RTO (ms)');
    title('各通信场景RTO收敛曲线 (RFC 6298)');
    legend('Location', 'northeastoutside');
    grid on;
    saveas(gcf, 'rto_convergence.png');
    fprintf('  RTO收敛图已保存: rto_convergence.png\n');
end
