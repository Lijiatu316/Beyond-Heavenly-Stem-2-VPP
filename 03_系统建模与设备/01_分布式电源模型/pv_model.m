% ============================================================
% 文件名：pv_model.m
% 功能：光伏实时出力模型（基于预测汇总/pv_model_engine.py 的物理公式+真实参数）
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   物理公式适配自预测汇总/光伏/pv_model_engine.py（团队原创模型）。
%   版权所有归属项目团队。
% ============================================================

function P_pv = pv_model(irradiance, temperature, params, incidence_angle, wind_speed)
    % 光伏实时出力计算（物理模型，与 pv_model_engine.py 的 PVPhysicalModel.predict 一致）
    %
    % 输入:
    %   irradiance      - 太阳直射辐照度 (W/m^2), [1 × N_vpp]
    %   temperature     - 环境温度 (℃), [1 × N_vpp]
    %   params          - 光伏参数结构体（从 pv_params.csv 加载的真实参数）:
    %       .capacity(N_vpp) - 各VPP装机容量 (kWp)
    %       .G_std          - 参考辐照度 (W/m^2), 默认 1000
    %       .alpha_temp     - 温度系数 (/℃), 默认 0.0038
    %       .T_cell_std     - 参考电池温度 (℃), 默认 25
    %       .eta_system     - 系统效率, 默认 0.8
    %       .k_board_temp   - 板温系数, 默认 0.016
    %       .k_wind_cool    - 风冷系数, 默认 0.1
    %       .low_light_threshold - 弱光阈值 (W/m^2), 默认 200
    %       .low_light_base     - 弱光基数, 默认 0.6
    %       .low_light_divisor  - 弱光除数 (W/m^2), 默认 500
    %       .max_power_ratio    - 最大功率比, 默认 1.1
    %   incidence_angle - 太阳入射角 (度), [1 × N_vpp], 默认 30
    %   wind_speed      - 风速 (m/s), [1 × N_vpp], 默认 0
    %
    % 输出:
    %   P_pv - 光伏实际出力 (kW), [1 × N_vpp]
    %
    % 物理公式 (与 pv_model_engine.py 一致):
    %   angle_factor = max(cos(θ), 0)
    %   G_eff = G × angle_factor
    %   T_cell = T_air + k_board_temp × G_eff - k_wind_cool × wind
    %   f_temp = 1 - alpha_temp × (T_cell - T_cell_std)
    %   P_base = G_eff / G_std × Pn × eta_system × f_temp
    %   弱光修正 + 功率限幅

    Nv = length(irradiance);

    % 默认参数
    if nargin < 3 || ~isfield(params, 'G_std')
        params.G_std = 1000;
    end
    if ~isfield(params, 'alpha_temp'),  params.alpha_temp = 0.0038; end
    if ~isfield(params, 'T_cell_std'),  params.T_cell_std = 25; end
    if ~isfield(params, 'eta_system'),  params.eta_system = 0.8; end
    if ~isfield(params, 'k_board_temp'),params.k_board_temp = 0.016; end
    if ~isfield(params, 'k_wind_cool'), params.k_wind_cool = 0.1; end
    if ~isfield(params, 'low_light_threshold'), params.low_light_threshold = 200; end
    if ~isfield(params, 'low_light_base'),      params.low_light_base = 0.6; end
    if ~isfield(params, 'low_light_divisor'),   params.low_light_divisor = 500; end
    if ~isfield(params, 'max_power_ratio'),     params.max_power_ratio = 1.1; end
    if nargin < 4, incidence_angle = 30 * ones(1, Nv); end
    if nargin < 5, wind_speed = zeros(1, Nv); end

    % 截断辐照度范围 [0, 1200]
    G = min(max(irradiance, 0), 1200);

    % 入射角因子：cos(θ)，最小为0
    angle_factor = max(cosd(incidence_angle), 0);
    G_eff = G .* angle_factor;

    % 电池温度模型
    T_cell = temperature + params.k_board_temp * G_eff - params.k_wind_cool * wind_speed;
    T_cell = min(max(T_cell, temperature - 5), 80);

    % 温度修正因子
    f_temp = 1 - params.alpha_temp * (T_cell - params.T_cell_std);
    f_temp = min(max(f_temp, 0.2), 1.1);

    % 基础功率 (Pn=1 per-unit, 乘以实际装机构成容量)
    P_base = G_eff / params.G_std .* params.capacity * params.eta_system .* f_temp;

    % 弱光逆变器效率修正
    for v = 1:Nv
        if G_eff(v) < params.low_light_threshold && G_eff(v) > 0
            f_g = params.low_light_base + G_eff(v) / params.low_light_divisor;
            P_base(v) = P_base(v) * f_g;
        end
    end

    % 功率限幅
    P_max = params.capacity * params.max_power_ratio;
    P_pv = min(max(P_base, 0), P_max);
end
