% ============================================================
% 文件名：wind_model.m
% 功能：风机出力模型，风速→风电功率（切入/额定/切出三段功率曲线）
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

function P_wind = wind_model(wind_speed, params)
    % 风机出力计算（标准三段式功率曲线）
    %
    % 输入:
    %   wind_speed - 风速 (m/s), 标量或向量 [1 × N_vpp]
    %   params     - 风机参数结构体:
    %       .capacity    - 装机容量 (kW), [1 × N_vpp]
    %       .v_cutin     - 切入风速 (m/s), 默认 3
    %       .v_rated     - 额定风速 (m/s), 默认 12
    %       .v_cutout    - 切出风速 (m/s), 默认 25
    %       .air_density - 空气密度 (kg/m^3), 默认 1.225
    %       .rotor_area  - 叶轮扫风面积 (m^2), [1 × N_vpp]
    %       .Cp_max      - 最大风能利用系数, 默认 0.45
    %       .mech_eff    - 机械效率, 默认 0.95
    %
    % 输出:
    %   P_wind - 风电实际出力 (kW), [1 × N_vpp]

    % 默认参数
    if nargin < 2
        params = struct();
    end
    if ~isfield(params, 'v_cutin'),      params.v_cutin = 3; end
    if ~isfield(params, 'v_rated'),      params.v_rated = 12; end
    if ~isfield(params, 'v_cutout'),     params.v_cutout = 25; end
    if ~isfield(params, 'air_density'),  params.air_density = 1.225; end
    if ~isfield(params, 'Cp_max'),       params.Cp_max = 0.45; end
    if ~isfield(params, 'mech_eff'),     params.mech_eff = 0.95; end

    v = max(wind_speed, 0);
    P_wind = zeros(size(v));
    N_vpp = length(v);

    % 确保向量参数
    if ~isfield(params, 'rotor_area')
        % 从容量反推：P_rated ≈ 0.5*ρ*A*Cp*η*v_rated³ → A = P_rated/(0.5*ρ*Cp*η*v_rated³)
        params.rotor_area = params.capacity * 1000 ./ ...
            (0.5 * params.air_density * params.Cp_max * params.v_rated^3 * params.mech_eff);
    end

    % 三段功率曲线
    for i = 1:N_vpp
        if v(i) < params.v_cutin || v(i) >= params.v_cutout
            P_wind(i) = 0;                          % 无风或强风切出
        elseif v(i) < params.v_rated
            % 最优功率跟踪区：P ∝ v³
            P_wind(i) = 0.5 * params.air_density * params.rotor_area(i) ...
                        * params.Cp_max * v(i)^3 * params.mech_eff / 1000; % kW
        else
            % 额定功率区
            P_wind(i) = params.capacity(i);
        end
    end

    % 不超过装机容量
    P_wind = min(P_wind, params.capacity);
    P_wind = max(P_wind, 0);
end
