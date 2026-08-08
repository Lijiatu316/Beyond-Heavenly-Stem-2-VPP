% ============================================================
% 文件名：mobile_node_model.m
% 功能：移动节点运动模型 — Random Waypoint, Gauss-Markov, 定制轨迹
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 应用场景:
%   1. 移动基站车 — 应急场景下灵活部署的临时通信节点
%   2. 无人机中继 — 低空无人机携带的通信中继设备
%   3. 移动VPP — 车载储能/光伏系统的通信模块
%   4. 船舶VPP — 海上风电运维船的自组网节点
%
% 运动模型:
%   - Random Waypoint: 随机选择目标点，匀速移动，到达后随机停留
%   - Gauss-Markov: 带记忆的速度模型，v(t+1) = α·v(t) + (1-α)·μ + σ·√(1-α²)·w
%   - Custom Trajectory: 预设轨迹点插值
%
% 参考文献:
%   - Camp, T. et al. "A survey of mobility models for ad hoc network research"
%     Wireless Communications and Mobile Computing, 2002
%   - 3GPP TR 38.901 v16.1.0 "Study on channel model for frequencies from 0.5 to 100 GHz"
% ============================================================

function node = mobile_node_model(model_type, params)
    % 移动节点运动模型
    %
    % 输入:
    %   model_type - 'random_waypoint' | 'gauss_markov' | 'custom'
    %   params     - 模型参数结构体
    %
    % 输出:
    %   node - 节点结构体，含位置/速度更新函数句柄

    switch model_type
        case 'random_waypoint'
            node = init_random_waypoint(params);
        case 'gauss_markov'
            node = init_gauss_markov(params);
        case 'custom'
            node = init_custom_trajectory(params);
        otherwise
            error('未知移动模型: %s', model_type);
    end
end


function node = init_random_waypoint(params)
    % Random Waypoint 移动模型
    %
    % 参数:
    %   .area_size   — 运动区域 [xmin, xmax; ymin, ymax] (km)
    %   .speed_range — 速度范围 [vmin, vmax] (km/h)
    %   .pause_range — 停留时间范围 [pmin, pmax] (min)
    %   .start_pos   — 初始位置 [x, y] (km)

    if nargin < 1
        params = struct();
    end
    if ~isfield(params, 'area_size')
        params.area_size = [0, 20; 0, 20];  % 20km × 20km区域
    end
    if ~isfield(params, 'speed_range')
        params.speed_range = [10, 60];  % 10-60 km/h (移动基站车)
    end
    if ~isfield(params, 'pause_range')
        params.pause_range = [0, 30];  % 0-30 min停留
    end
    if ~isfield(params, 'start_pos')
        params.start_pos = [10, 10];
    end

    node = struct();
    node.model = 'Random Waypoint';
    node.params = params;

    % 状态变量
    node.pos = params.start_pos;         % 当前位置 [x, y]
    node.dest = params.start_pos;        % 目标位置
    node.velocity = [0, 0];             % 速度向量 [vx, vy]
    node.state = 'paused';              % 'moving' | 'paused'
    node.pause_remaining = 0;           % 剩余停留时间
    node.speed = 0;

    % 更新函数
    node.update = @(dt_h) update_random_waypoint(node, dt_h);
    node.reset = @(new_pos) reset_waypoint(node, new_pos);
end


function node = update_random_waypoint(node, dt_h)
    % Random Waypoint 单步更新
    %
    % 输入:
    %   dt_h - 时间步长 (h)
    %
    % 输出:
    %   node - 更新后的节点

    if strcmp(node.state, 'paused')
        node.pause_remaining = node.pause_remaining - dt_h;
        if node.pause_remaining <= 0
            % 选择新目标
            area = node.params.area_size;
            node.dest = [area(1,1) + rand() * (area(1,2) - area(1,1)), ...
                         area(2,1) + rand() * (area(2,2) - area(2,1))];
            v_range = node.params.speed_range;
            node.speed = v_range(1) + rand() * (v_range(2) - v_range(1));

            % 计算速度方向
            dir_vec = node.dest - node.pos;
            dist = norm(dir_vec);
            if dist > 0
                node.velocity = node.speed * dir_vec / dist;
            else
                node.velocity = [0, 0];
            end
            node.state = 'moving';
        end
    else  % moving
        % 向目标移动
        node.pos = node.pos + node.velocity * dt_h;

        % 检查是否到达目标 (距离 < 速度×步长)
        dist_to_dest = norm(node.dest - node.pos);
        if dist_to_dest < norm(node.velocity) * dt_h * 2
            node.pos = node.dest;
            node.velocity = [0, 0];
            node.state = 'paused';
            p_range = node.params.pause_range;
            node.pause_remaining = (p_range(1) + rand() * (p_range(2) - p_range(1))) / 60;  % min→h
        end
    end
end


function node = reset_waypoint(node, new_pos)
    % 重置节点到新位置
    node.pos = new_pos;
    node.state = 'paused';
    node.pause_remaining = 0;
end


function node = init_gauss_markov(params)
    % Gauss-Markov 移动模型
    %
    % 速度更新: v(k+1) = α·v(k) + (1-α)·μ + σ·√(1-α²)·w(k)
    %
    % 参数:
    %   .alpha      — 记忆因子 (0=无记忆随机游走, 1=完全确定性)
    %   .mean_speed — 平均速度 [vx_mean, vy_mean] (km/h)
    %   .std_speed  — 速度标准差 [σx, σy]
    %   .start_pos  — 初始位置

    if nargin < 1
        params = struct();
    end
    if ~isfield(params, 'alpha'),      params.alpha = 0.75; end
    if ~isfield(params, 'mean_speed'), params.mean_speed = [0, 0]; end
    if ~isfield(params, 'std_speed'),  params.std_speed = [30, 30]; end
    if ~isfield(params, 'boundary'),   params.boundary = [0, 20; 0, 20]; end
    if ~isfield(params, 'start_pos'),  params.start_pos = [10, 10]; end

    node = struct();
    node.model = 'Gauss-Markov';
    node.params = params;
    node.pos = params.start_pos;
    node.velocity = [0, 0];  % 初始静止

    node.update = @(dt_h) update_gauss_markov(node, dt_h);
end


function node = update_gauss_markov(node, dt_h)
    % Gauss-Markov 单步更新
    p = node.params;
    alpha = p.alpha;
    w = randn(1, 2);  % 标准正态噪声

    for dim = 1:2
        node.velocity(dim) = alpha * node.velocity(dim) + ...
                             (1 - alpha) * p.mean_speed(dim) + ...
                             p.std_speed(dim) * sqrt(1 - alpha^2) * w(dim);
    end

    % 更新位置
    node.pos = node.pos + node.velocity * dt_h;

    % 边界反射
    for dim = 1:2
        if node.pos(dim) < p.boundary(dim, 1)
            node.pos(dim) = p.boundary(dim, 1);
            node.velocity(dim) = abs(node.velocity(dim));
        elseif node.pos(dim) > p.boundary(dim, 2)
            node.pos(dim) = p.boundary(dim, 2);
            node.velocity(dim) = -abs(node.velocity(dim));
        end
    end
end


function node = init_custom_trajectory(params)
    % 定制轨迹模型
    %
    % 参数:
    %   .waypoints  — 路径点 [N × 3]  [time_h, x_km, y_km]
    %   .loop       — 是否循环

    if nargin < 1
        params = struct();
    end
    if ~isfield(params, 'waypoints')
        % 默认: 环形轨迹 (模拟巡检无人机)
        theta = linspace(0, 2*pi, 25)';
        t_h = linspace(0, 8, 25)';  % 8小时一圈
        r = 5;  % 5km半径
        params.waypoints = [t_h, 10 + r*cos(theta), 10 + r*sin(theta)];
    end
    if ~isfield(params, 'loop'), params.loop = true; end

    node = struct();
    node.model = 'Custom Trajectory';
    node.params = params;
    node.pos = params.waypoints(1, 2:3);
    node.velocity = [0, 0];
    node.t_total = 0;  % 累计仿真时间

    node.update = @(dt_h) update_custom_trajectory(node, dt_h);
end


function node = update_custom_trajectory(node, dt_h)
    % 定制轨迹单步更新 (基于时间插值)
    p = node.params;
    wp = p.waypoints;
    node.t_total = node.t_total + dt_h;

    % 循环处理
    total_duration = wp(end, 1);
    if p.loop && node.t_total > total_duration
        node.t_total = mod(node.t_total, total_duration);
    end

    t_now = min(node.t_total, total_duration);

    % 分段线性插值
    for i = 1:size(wp, 1) - 1
        if t_now >= wp(i, 1) && t_now <= wp(i+1, 1)
            alpha = (t_now - wp(i, 1)) / (wp(i+1, 1) - wp(i, 1));
            node.pos = (1 - alpha) * wp(i, 2:3) + alpha * wp(i+1, 2:3);
            % 速度估计
            node.velocity = (wp(i+1, 2:3) - wp(i, 2:3)) / (wp(i+1, 1) - wp(i, 1));
            break;
        end
    end
end


function demo_all_models()
    % 演示三种移动模型，生成轨迹对比图

    models = {'random_waypoint', 'gauss_markov', 'custom'};
    colors = {'b', 'r', 'g'};

    figure('Name', '移动节点模型对比', 'Position', [100, 100, 800, 600]);

    for m = 1:length(models)
        node = mobile_node_model(models{m});
        dt = 0.1;  % 6min步长
        n_steps = 240;  % 24h
        positions = zeros(n_steps, 2);

        for t = 1:n_steps
            node = node.update(dt);
            positions(t, :) = node.pos;
        end

        subplot(2, 2, m);
        plot(positions(:,1), positions(:,2), [colors{m}, '-'], 'LineWidth', 1);
        hold on;
        plot(positions(1,1), positions(1,2), 'ko', 'MarkerSize', 8, 'MarkerFaceColor', 'k');  % 起点
        plot(positions(end,1), positions(end,2), 'ks', 'MarkerSize', 8, 'MarkerFaceColor', 'w');  % 终点
        xlabel('X (km)'); ylabel('Y (km)');
        title(sprintf('移动模型: %s', node.model));
        legend({'轨迹', '起点', '终点'}, 'Location', 'best');
        axis equal; grid on;
    end

    % 速度对比
    subplot(2, 2, 4);
    for m = 1:length(models)
        node = mobile_node_model(models{m});
        speeds = zeros(n_steps, 1);
        for t = 1:n_steps
            node = node.update(dt);
            speeds(t) = norm(node.velocity);
        end
        plot((1:n_steps) * dt, speeds, colors{m}, 'LineWidth', 1);
        hold on;
    end
    xlabel('时间 (h)'); ylabel('速度 (km/h)');
    title('速度变化对比');
    legend(models, 'Location', 'best');
    grid on;

    saveas(gcf, 'mobility_models_comparison.png');
    fprintf('  移动模型对比图已保存: mobility_models_comparison.png\n');
end
