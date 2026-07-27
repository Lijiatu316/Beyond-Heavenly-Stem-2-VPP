% ============================================================
% 文件名：tidal_model.m
% 功能：潮汐发电出力模型（基于江厦潮汐电站真实物理参数）
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   物理参数来源于预测汇总/潮汐/电站参数.xlsx（江厦潮汐电站）。
%   模型公式为团队原创实现。
%   版权所有归属项目团队。
% ============================================================

function [P_tidal, tidal_state] = tidal_model(tide_height, prev_basin_level, dt, params)
    % 潮汐发电出力计算（单库单向落潮发电模型）
    %
    % 输入:
    %   tide_height      - 当前海侧潮位 (m), [1 × N_vpp]
    %   prev_basin_level - 上一时刻库区水位 (m), [1 × N_vpp]
    %   dt               - 时间步长 (h)
    %   params           - 潮汐电站参数结构体:
    %       .rho            - 海水密度 (kg/m³), 默认 1025
    %       .g              - 重力加速度 (m/s²), 默认 9.81
    %       .S              - 库区面积 (m²), 默认 5,300,000
    %       .eta            - 综合效率, 默认 0.78
    %       .loss_factor    - 综合损耗系数, 默认 0.95
    %       .unit_number    - 机组台数, 默认 5
    %       .unit_power     - 单机额定功率 (kW), 默认 640
    %       .H_min          - 最小启动水头 (m), 默认 1.0
    %       .Q_max          - 最大过流流量 (m³/s), 默认 120
    %       .capacity(N_vpp)- 各VPP分摊容量 (kW) — 潮汐电站总容量按比例分配
    %
    % 输出:
    %   P_tidal     - 潮汐发电出力 (kW), [1 × N_vpp]
    %   tidal_state - 潮汐状态结构体

    Nv = length(tide_height);

    % 默认参数（江厦潮汐电站）
    if nargin < 4
        params = struct();
    end
    if ~isfield(params, 'rho'),          params.rho = 1025; end
    if ~isfield(params, 'g'),            params.g = 9.81; end
    if ~isfield(params, 'S'),            params.S = 5300000; end
    if ~isfield(params, 'eta'),          params.eta = 0.78; end
    if ~isfield(params, 'loss_factor'),  params.loss_factor = 0.95; end
    if ~isfield(params, 'unit_number'),  params.unit_number = 5; end
    if ~isfield(params, 'unit_power'),   params.unit_power = 640; end
    if ~isfield(params, 'H_min'),        params.H_min = 1.0; end
    if ~isfield(params, 'Q_max'),        params.Q_max = 120; end

    total_capacity = params.unit_number * params.unit_power;  % 3200 kW

    if nargin < 2 || isempty(prev_basin_level)
        prev_basin_level = tide_height;  % 初始时库区水位=海侧潮位
    end

    % 初始化输出
    P_tidal = zeros(1, Nv);
    basin_level_new = zeros(1, Nv);

    for v = 1:Nv
        H_sea = tide_height(v);
        H_basin = prev_basin_level(v);

        % 工作水头 (海侧 - 库区)
        H_work = H_basin - H_sea;

        % 判断是否满足发电条件
        can_generate = (H_work >= params.H_min);  % 落潮发电

        if can_generate
            % 流量计算：Q = S × dH/dt (库区水位下降速率)
            % 简化：取可用流量的合理范围
            Q_available = min(params.Q_max, params.S * H_work / (dt * 3600) * 0.01);

            % 水力功率公式
            P_hydro = params.rho * params.g * Q_available * H_work ...
                      * params.eta * params.loss_factor / 1000;  % kW

            % 限幅至装机容量
            P_per_unit = min(P_hydro, total_capacity);

            % 库区水位更新（发电导致水位下降）
            V_used = Q_available * dt * 3600;  % 本次发电用水量 (m³)
            dH = V_used / params.S;
            basin_level_new(v) = H_basin - dH;
        else
            % 不发电：仅涨潮时库区自然充水
            P_per_unit = 0;
            if H_sea > H_basin
                % 涨潮充水：库区水位趋近海侧
                basin_level_new(v) = H_basin + 0.3 * (H_sea - H_basin);
            else
                basin_level_new(v) = H_basin;
            end
        end

        % 分摊到各VPP（按容量比例）
        if isfield(params, 'capacity') && total_capacity > 0
            P_tidal(v) = P_per_unit * params.capacity(v) / total_capacity;
        else
            P_tidal(v) = 0;
        end
    end

    % 输出状态
    tidal_state = struct();
    tidal_state.basin_level = basin_level_new;
    tidal_state.H_work = tide_height - basin_level_new;
    tidal_state.is_generating = (P_tidal > 0);
end
