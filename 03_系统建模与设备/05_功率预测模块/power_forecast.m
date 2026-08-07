% ============================================================
% 文件名：power_forecast.m
% 功能：风光负荷短期功率预测，持久性模型+滑动平均（本地边缘预测，无需云端）
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   底层建模思路参考：
%     1) 中国大学MOOC《智能微电网技术》教学案例
%     2) 开源库PyPSA（MIT协议）风光储模型架构
%   本文件为参考开源模型适配实现，非核心创新模块。
%   版权所有归属项目团队，引用需注明出处。
% ============================================================

function forecast = power_forecast(history, t, cfg)
    % 短期功率预测（持久性+趋势外推）
    %
    % 输入:
    %   history - 历史数据结构体:
    %       .P_pv   - 光伏历史出力 (kW), [N_history × N_vpp]
    %       .P_wind - 风电历史出力 (kW), [N_history × N_vpp]
    %       .P_load - 负荷历史数据 (kW), [N_history × N_vpp]
    %       .G      - 历史辐照度 (W/m^2)
    %       .v_wind - 历史风速 (m/s)
    %   t      - 当前时间步索引
    %   cfg    - 全局配置
    %       .forecast.horizon  - 预测步数, 默认 6 (即提前1h @ dt=0.1h)
    %       .forecast.window   - 滑动窗口长度, 默认 12
    %       .forecast.method   - 预测方法: 'persistence' | 'moving_avg' | 'trend'
    %
    % 输出:
    %   forecast - 预测结果结构体:
    %       .P_pv   - 光伏预测值 (kW), [horizon × N_vpp]
    %       .P_wind - 风电预测值 (kW), [horizon × N_vpp]
    %       .P_load - 负荷预测值 (kW), [horizon × N_vpp]

    % 默认参数
    if nargin < 3
        cfg = struct();
    end
    if ~isfield(cfg, 'forecast'), cfg.forecast = struct(); end
    if ~isfield(cfg.forecast, 'horizon'), cfg.forecast.horizon = 6; end
    if ~isfield(cfg.forecast, 'window'),  cfg.forecast.window = 12; end
    if ~isfield(cfg.forecast, 'method'),  cfg.forecast.method = 'persistence'; end

    H = cfg.forecast.horizon;
    W = cfg.forecast.window;
    method = cfg.forecast.method;

    % 初始化输出
    forecast = struct();
    forecast.P_pv   = zeros(H, cfg.N_vpp);
    forecast.P_wind = zeros(H, cfg.N_vpp);
    forecast.P_load = zeros(H, cfg.N_vpp);

    switch lower(method)
        case 'persistence'
            % 持久性模型：未来 = 最近一拍的观测值
            % 适用于超短期预测（<1h），风光短时波动用最新值近似
            for h = 1:H
                idx = max(t - h + 1, 1);
                forecast.P_pv(h, :)   = history.P_pv(idx, :);
                forecast.P_wind(h, :) = history.P_wind(idx, :);
                forecast.P_load(h, :) = history.P_load(idx, :);
            end

        case 'moving_avg'
            % 滑动平均：未来 = 最近W步的均值
            idx_start = max(t - W + 1, 1);
            idx_end   = t;
            avg_P_pv   = mean(history.P_pv(idx_start:idx_end, :), 1);
            avg_P_wind = mean(history.P_wind(idx_start:idx_end, :), 1);
            avg_P_load = mean(history.P_load(idx_start:idx_end, :), 1);

            for h = 1:H
                forecast.P_pv(h, :)   = avg_P_pv;
                forecast.P_wind(h, :) = avg_P_wind;
                forecast.P_load(h, :) = avg_P_load;
            end

        case 'trend'
            % 线性趋势外推：用最近W步拟合线性趋势，外推未来
            if t >= 3
                idx_start = max(t - W + 1, 1);
                idx_end   = t;
                x = (idx_start:idx_end)';
                N_hist = length(x);

                % 对每个VPP分别拟合
                for v = 1:cfg.N_vpp
                    % 光伏
                    y_pv = history.P_pv(idx_start:idx_end, v);
                    p_pv = polyfit(x, y_pv, min(1, N_hist-1));
                    forecast.P_pv(:, v) = polyval(p_pv, (t+1:t+H)');

                    % 风电
                    y_wind = history.P_wind(idx_start:idx_end, v);
                    p_wind = polyfit(x, y_wind, min(1, N_hist-1));
                    forecast.P_wind(:, v) = polyval(p_wind, (t+1:t+H)');

                    % 负荷
                    y_load = history.P_load(idx_start:idx_end, v);
                    p_load = polyfit(x, y_load, min(1, N_hist-1));
                    forecast.P_load(:, v) = polyval(p_load, (t+1:t+H)');
                end
            else
                % 历史不足3步，退化为持久性模型
                for h = 1:H
                    forecast.P_pv(h, :)   = history.P_pv(t, :);
                    forecast.P_wind(h, :) = history.P_wind(t, :);
                    forecast.P_load(h, :) = history.P_load(t, :);
                end
            end

        otherwise
            error('未知预测方法: %s', method);
    end

    % 出力非负约束
    forecast.P_pv   = max(forecast.P_pv, 0);
    forecast.P_wind = max(forecast.P_wind, 0);
    forecast.P_load = max(forecast.P_load, 0);
end
