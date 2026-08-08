% ============================================================
% 文件名：topology_visualizer.m
% 功能：动态拓扑可视化 — 拓扑演变动画 + 路由路径展示
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 功能:
%   1. 拓扑快照 — 绘制指定时刻的网络拓扑图
%   2. 拓扑动画 — 生成24h拓扑演变GIF/视频
%   3. 路由路径展示 — 高亮指定VPP对的当前路由路径
%   4. 拓扑统计仪表板 — 连接数/平均跳数/节点度的时间序列
% ============================================================

function topology_visualizer(action, varargin)
    % 拓扑可视化主函数
    %
    % 使用方式:
    %   topology_visualizer('snapshot', topo, time, positions, labels);
    %   topology_visualizer('animation', topo_history, times, positions);
    %   topology_visualizer('route_path', topo, routing_table, src, dst);
    %   topology_visualizer('dashboard', topo_history, times, stats);

    switch action
        case 'snapshot'
            plot_snapshot(varargin{:});
        case 'animation'
            plot_animation(varargin{:});
        case 'route_path'
            plot_route_path(varargin{:});
        case 'dashboard'
            plot_dashboard(varargin{:});
        otherwise
            error('未知可视化操作: %s', action);
    end
end


function plot_snapshot(topo, t_now_h, positions, labels)
    % 绘制拓扑快照
    %
    % 输入:
    %   topo      - 邻接矩阵 [Nv × Nv]
    %   t_now_h   - 当前时间 (h)
    %   positions - 节点坐标 [Nv × 2] (可选, 默认环形布局)
    %   labels    - 节点标签 cell array (可选)

    Nv = size(topo, 1);

    if nargin < 3 || isempty(positions)
        positions = compute_ring_positions(Nv);
    end
    if nargin < 4
        labels = arrayfun(@(v) sprintf('V%d', v), 1:Nv, 'UniformOutput', false);
    end

    figure('Name', sprintf('拓扑快照 t=%.1fh', t_now_h), ...
           'Position', [100, 100, 700, 600]);
    hold on;

    % 链路类型: 同类型VPP (光伏1-3, 风电4-6, 潮汐7-9) vs 跨类连接
    type_colors = {[0.3, 0.6, 1.0], [0.3, 0.8, 0.3], [1.0, 0.6, 0.2]};  % 蓝/绿/橙
    cross_color = [0.7, 0.3, 0.3];  % 红色跨类连接

    % 绘制链路
    for i = 1:Nv
        for j = i+1:Nv
            if topo(i, j) > 0
                % 判断链路类型
                type_i = ceil(i / 3);
                type_j = ceil(j / 3);
                if type_i == type_j
                    color = type_colors{min(type_i, 3)};
                    lw = 2;
                else
                    color = cross_color;
                    lw = 1.5;
                end

                % 链路质量 → 透明度
                alpha = min(1, topo(i, j));

                plot([positions(i,1), positions(j,1)], ...
                     [positions(i,2), positions(j,2)], ...
                     '-', 'Color', [color, alpha], 'LineWidth', ...
                     lw * (0.5 + 0.5 * alpha));
            end
        end
    end

    % 节点类型标记
    node_markers = {'o', 's', 'd'};  % 光伏=圆, 风电=方, 潮汐=菱
    node_colors = {[0.2, 0.5, 1.0], [0.2, 0.8, 0.2], [1.0, 0.5, 0.2]};

    for v = 1:Nv
        type_v = ceil(v / 3);
        mk = node_markers{min(type_v, 3)};
        nc = node_colors{min(type_v, 3)};
        plot(positions(v, 1), positions(v, 2), mk, ...
             'MarkerSize', 15, 'MarkerFaceColor', nc, ...
             'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
        text(positions(v, 1) + 0.3, positions(v, 2) + 0.3, labels{v}, ...
             'FontSize', 10, 'FontWeight', 'bold');
    end

    xlabel('X (km)'); ylabel('Y (km)');
    title(sprintf('VPP通信拓扑 (t=%.1f h)', t_now_h));
    axis equal;
    xlim([min(positions(:,1))-2, max(positions(:,1))+2]);
    ylim([min(positions(:,2))-2, max(positions(:,2))+2]);
    grid on;

    % 图例
    legend_entries = {'光伏链(蓝)', '风电链(绿)', '潮汐链(橙)', '跨类连接(红)'};
    legend(legend_entries, 'Location', 'northeastoutside');

    hold off;
end


function plot_animation(topo_history, times, positions)
    % 生成拓扑演变动画
    %
    % 输入:
    %   topo_history — 拓扑矩阵cell array {1×T}
    %   times        — 时间轴 [T × 1] (h)
    %   positions    — 节点坐标 (可选)

    Nv = size(topo_history{1}, 1);

    if nargin < 3 || isempty(positions)
        positions = compute_ring_positions(Nv);
    end

    fig = figure('Name', '拓扑演变动画', 'Position', [50, 50, 900, 700]);

    for t = 1:length(times)
        clf;
        subplot(1, 2, 1);
        plot_snapshot_in_axes(topo_history{t}, times(t), positions);
        title(sprintf('VPP通信拓扑 (t=%.1fh)', times(t)));

        subplot(1, 2, 2);
        plot_topology_stats(topo_history, times, t);

        drawnow;

        % 保存帧 (用于GIF生成)
        frame = getframe(fig);
        im = frame2im(frame);
        [A, map] = rgb2ind(im, 256);

        if t == 1
            imwrite(A, map, 'topology_evolution.gif', 'gif', ...
                    'LoopCount', Inf, 'DelayTime', 0.5);
        else
            imwrite(A, map, 'topology_evolution.gif', 'gif', ...
                    'WriteMode', 'append', 'DelayTime', 0.5);
        end
    end

    fprintf('  拓扑动画已保存: topology_evolution.gif\n');
end


function plot_snapshot_in_axes(topo, t_now_h, positions)
    % 在已有axes中绘制拓扑快照 (用于动画子图)
    Nv = size(topo, 1);
    hold on;

    type_colors = {[0.3, 0.6, 1.0], [0.3, 0.8, 0.3], [1.0, 0.6, 0.2]};
    cross_color = [0.7, 0.3, 0.3];

    for i = 1:Nv
        for j = i+1:Nv
            if topo(i, j) > 0
                type_i = ceil(i / 3);
                type_j = ceil(j / 3);
                color = type_colors{min(type_i, 3)};
                if type_i ~= type_j
                    color = cross_color;
                end
                alpha = min(1, topo(i, j));
                plot([positions(i,1), positions(j,1)], ...
                     [positions(i,2), positions(j,2)], ...
                     '-', 'Color', [color, alpha], ...
                     'LineWidth', 1.5 * (0.5 + 0.5 * alpha));
            end
        end
    end

    node_markers = {'o', 's', 'd'};
    font_colors = {[0.2, 0.5, 1.0], [0.2, 0.7, 0.2], [1.0, 0.5, 0.2]};
    for v = 1:Nv
        type_v = ceil(v / 3);
        fc = font_colors{min(type_v, 3)};
        plot(positions(v, 1), positions(v, 2), node_markers{min(type_v, 3)}, ...
             'MarkerSize', 12, 'MarkerFaceColor', fc, 'MarkerEdgeColor', 'k');
        text(positions(v, 1) + 0.25, positions(v, 2) + 0.25, ...
             sprintf('V%d', v), 'FontSize', 8);
    end

    axis equal; grid on;
    xlim([min(positions(:,1))-1.5, max(positions(:,1))+1.5]);
    ylim([min(positions(:,2))-1.5, max(positions(:,2))+1.5]);
    hold off;
end


function plot_topology_stats(topo_history, times, current_idx)
    % 绘制拓扑统计指标时间序列

    T = length(times);
    n_links = zeros(T, 1);
    avg_degree = zeros(T, 1);
    n_components = zeros(T, 1);

    for t = 1:T
        topo = topo_history{t};
        Nv = size(topo, 1);
        n_links(t) = sum(topo(:) > 0) / 2;
        avg_degree(t) = mean(sum(topo > 0, 2));
        n_components(t) = count_connected_components(topo);
    end

    subplot(3,1,1);
    plot(times(1:current_idx), n_links(1:current_idx), 'b-', 'LineWidth', 1.5);
    xlabel('时间 (h)'); ylabel('链路数');
    title('活跃链路数'); grid on;

    subplot(3,1,2);
    plot(times(1:current_idx), avg_degree(1:current_idx), 'g-', 'LineWidth', 1.5);
    xlabel('时间 (h)'); ylabel('平均度');
    title('节点平均度'); grid on;

    subplot(3,1,3);
    plot(times(1:current_idx), n_components(1:current_idx), 'r-', 'LineWidth', 1.5);
    xlabel('时间 (h)'); ylabel('连通分量数');
    title('连通分量数'); grid on;
    ylim([0, max(2, max(n_components))]);
end


function nc = count_connected_components(topo)
    % 统计连通分量数 (基于DFS)
    Nv = size(topo, 1);
    visited = false(1, Nv);
    nc = 0;

    for v = 1:Nv
        if ~visited(v)
            nc = nc + 1;
            % DFS
            stack = v;
            while ~isempty(stack)
                u = stack(end);
                stack(end) = [];
                if ~visited(u)
                    visited(u) = true;
                    neighbors = find(topo(u, :) > 0);
                    for n = neighbors
                        if ~visited(n)
                            stack(end+1) = n;
                        end
                    end
                end
            end
        end
    end
end


function plot_route_path(topo, routing_table, src, dst, positions)
    % 高亮显示从src到dst的路由路径
    %
    % 输入:
    %   topo           — 拓扑邻接矩阵
    %   routing_table  — 下一跳路由表
    %   src, dst       — 源/目标节点
    %   positions      — 节点坐标

    Nv = size(topo, 1);

    if nargin < 5 || isempty(positions)
        positions = compute_ring_positions(Nv);
    end

    % 追踪路径
    path = trace_path(routing_table, src, dst);

    figure('Name', sprintf('路由路径 V%d → V%d', src, dst), ...
           'Position', [150, 150, 700, 600]);
    hold on;

    % 绘制所有链路 (灰色细线)
    for i = 1:Nv
        for j = i+1:Nv
            if topo(i, j) > 0
                plot([positions(i,1), positions(j,1)], ...
                     [positions(i,2), positions(j,2)], ...
                     '-', 'Color', [0.8, 0.8, 0.8], 'LineWidth', 0.5);
            end
        end
    end

    % 绘制路径 (彩色粗线)
    if ~isempty(path) && length(path) >= 2
        for k = 1:length(path)-1
            i = path(k);
            j = path(k+1);
            plot([positions(i,1), positions(j,1)], ...
                 [positions(i,2), positions(j,2)], ...
                 '-', 'Color', [1.0, 0.2, 0.2], 'LineWidth', 3);

            % 路径箭头 (简化: 在中点画三角)
            mid = (positions(i,:) + positions(j,:)) / 2;
            plot(mid(1), mid(2), 'r>', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
        end
    end

    % 绘制节点
    for v = 1:Nv
        if v == src
            plot(positions(v,1), positions(v,2), 'o', 'MarkerSize', 18, ...
                 'MarkerFaceColor', 'g', 'MarkerEdgeColor', 'k', 'LineWidth', 2);
        elseif v == dst
            plot(positions(v,1), positions(v,2), 'o', 'MarkerSize', 18, ...
                 'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'k', 'LineWidth', 2);
        elseif ismember(v, path)
            plot(positions(v,1), positions(v,2), 'o', 'MarkerSize', 14, ...
                 'MarkerFaceColor', [1.0, 0.8, 0.3], 'MarkerEdgeColor', 'k');
        else
            plot(positions(v,1), positions(v,2), 'o', 'MarkerSize', 10, ...
                 'MarkerFaceColor', [0.7, 0.7, 0.7], 'MarkerEdgeColor', 'k');
        end
        text(positions(v,1) + 0.3, positions(v,2) + 0.3, sprintf('V%d', v), ...
             'FontSize', 9);
    end

    xlabel('X (km)'); ylabel('Y (km)');
    title(sprintf('路由路径: V%d → V%d (跳数: %d)', src, dst, length(path)-1));
    axis equal; grid on;
    hold off;

    fprintf('  路由路径 V%d → V%d: %s (跳数: %d)\n', ...
            src, dst, mat2str(path), length(path)-1);
end


function path = trace_path(routing_table, src, dst)
    % 从路由表追踪完整路径
    Nv = size(routing_table, 1);
    path = src;
    current = src;
    max_hops = Nv + 1;

    while current ~= dst && length(path) < max_hops
        next = routing_table(current, dst);
        if next == 0 || next == current
            path = [];
            return;  % 不可达或路由循环
        end
        current = next;
        path(end+1) = current;
    end
end


function plot_dashboard(topo_history, times, stats)
    % 拓扑统计仪表板 — 综合显示拓扑健康指标

    T = length(times);
    Nv = size(topo_history{1}, 1);

    n_links = zeros(T, 1);
    n_active = zeros(T, 1);
    n_changes = zeros(T, 1);

    for t = 1:T
        topo = topo_history{t};
        n_links(t) = sum(topo(:) > 0) / 2;
        n_active(t) = sum(sum(topo > 0, 2) > 0);  % 有连接的节点数

        if t > 1
            delta = topo_history{t} - topo_history{t-1};
            n_changes(t) = sum(abs(delta(:))) / 2;
        end
    end

    fig = figure('Name', '拓扑健康仪表板', 'Position', [50, 50, 1200, 700]);

    % (1) 链路数时间序列
    subplot(2,3,1);
    plot(times, n_links, 'b-', 'LineWidth', 1.5);
    xlabel('时间 (h)'); ylabel('活跃链路数');
    title('活跃链路数'); grid on;

    % (2) 拓扑变化计数
    subplot(2,3,2);
    bar(times, n_changes, 'FaceColor', [1.0, 0.4, 0.4]);
    xlabel('时间 (h)'); ylabel('链路变化数');
    title('拓扑变化事件'); grid on;

    % (3) 最终时刻拓扑
    subplot(2,3,3);
    positions = compute_ring_positions(Nv);
    plot_snapshot_in_axes(topo_history{end}, times(end), positions);
    title(sprintf('最终拓扑 (t=%.1fh)', times(end)));

    % (4) 链路稳定性 (各链路的活跃时间占比)
    subplot(2,3,4);
    stability = zeros(Nv, Nv);
    for t = 1:T
        stability = stability + (topo_history{t} > 0);
    end
    stability = stability / T;
    imagesc(stability);
    colorbar; colormap('parula');
    clim([0, 1]);
    xlabel('VPP节点'); ylabel('VPP节点');
    title('链路稳定性 (活跃时间占比)');
    axis equal tight;

    % (5) 节点度分布 (最后时刻)
    subplot(2,3,5);
    degrees = sum(topo_history{end} > 0, 2);
    bar(1:Nv, degrees, 'FaceColor', [0.3, 0.6, 1.0]);
    xlabel('VPP编号'); ylabel('节点度');
    title('节点度 (当前拓扑)'); grid on;
    xticks(1:Nv);

    % (6) 统计摘要
    subplot(2,3,6);
    axis off;
    text(0.1, 0.95, '拓扑统计摘要', 'FontSize', 14, 'FontWeight', 'bold');
    text(0.1, 0.85, sprintf('最大链路数: %d', sum(topo_history{1}(:)>0)/2));
    text(0.1, 0.78, sprintf('最小链路数: %d', min(n_links)));
    text(0.1, 0.71, sprintf('平均链路数: %.1f', mean(n_links)));
    text(0.1, 0.64, sprintf('拓扑变化总次数: %d', sum(n_changes)));
    text(0.1, 0.57, sprintf('链路可用率: %.1f%%', 100 * mean(n_links) / (sum(topo_history{1}(:)>0)/2)));
    text(0.1, 0.50, sprintf('仿真时长: %.1fh', times(end)));
    text(0.1, 0.40, '— 链路类型 —', 'FontWeight', 'bold');
    text(0.1, 0.33, '光伏链: V1-V2-V3');
    text(0.1, 0.28, '风电链: V4-V5-V6');
    text(0.1, 0.23, '潮汐链: V7-V8-V9');
    text(0.1, 0.18, '跨类互联: V3-V4, V6-V7, V9-V1');

    saveas(fig, 'topology_dashboard.png');
    fprintf('  拓扑仪表板已保存: topology_dashboard.png\n');
end


function positions = compute_ring_positions(Nv)
    % 计算环形布局坐标
    positions = zeros(Nv, 2);
    for v = 1:Nv
        angle = 2 * pi * (v - 1) / Nv - pi/2;
        positions(v, :) = [cos(angle), sin(angle)] * 8;
    end
end
