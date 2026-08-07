% ============================================================
% 文件名：gas_unit_model.m
% 功能：微型燃气轮机可调出力模型（爬坡约束+燃料成本计算）
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

function [P_gas_actual, fuel_cost, ramp_violation] = gas_unit_model(P_cmd, P_prev, dt, params)
    % 燃气轮机出力执行模型（爬坡约束+成本计算）
    %
    % 输入:
    %   P_cmd   - 出力指令 (kW), [1 × N_vpp]
    %   P_prev  - 上一时刻实际出力 (kW), [1 × N_vpp]
    %   dt      - 时间步长 (h)
    %   params  - 机组参数结构体:
    %       .P_min        - 最小出力 (kW), [1 × N_vpp]
    %       .P_max        - 最大出力 (kW), [1 × N_vpp]
    %       .ramp_rate    - 爬坡率 (kW/h), [1 × N_vpp]
    %       .fuel_cost_a  - 燃料成本斜率 (元/kWh), [1 × N_vpp]
    %       .fuel_cost_b  - 燃料成本截距 (元/h), [1 × N_vpp]
    %
    % 输出:
    %   P_gas_actual    - 实际出力 (kW), [1 × N_vpp]
    %   fuel_cost       - 燃料成本 (元), [1 × N_vpp]
    %   ramp_violation  - 爬坡违约量 (kW), [1 × N_vpp]

    N_vpp = length(P_cmd);

    % 默认参数
    if nargin < 4
        params = struct();
    end
    if ~isfield(params, 'P_min'),         params.P_min = zeros(1, N_vpp); end
    if ~isfield(params, 'P_max'),         params.P_max = 200 * ones(1, N_vpp); end
    if ~isfield(params, 'ramp_rate'),     params.ramp_rate = 100 * ones(1, N_vpp); end
    if ~isfield(params, 'fuel_cost_a'),   params.fuel_cost_a = 0.35 * ones(1, N_vpp); end
    if ~isfield(params, 'fuel_cost_b'),   params.fuel_cost_b = 0.05 * ones(1, N_vpp); end

    % ---- 爬坡约束限幅 ----
    max_ramp = params.ramp_rate * dt;           % 单步最大变化量 (kW)
    P_upper_ramp = P_prev + max_ramp;
    P_lower_ramp = P_prev - max_ramp;

    P_clipped = max(min(P_cmd, P_upper_ramp), P_lower_ramp);
    ramp_violation = abs(P_clipped - P_cmd);

    % ---- 出力上下限约束 ----
    P_gas_actual = max(min(P_clipped, params.P_max), params.P_min);

    % ---- 燃料成本（线性模型）----
    fuel_cost = params.fuel_cost_a .* P_gas_actual * dt ...
                + params.fuel_cost_b .* (P_gas_actual > 0) * dt;

    % 小值归零（避免数值噪声）
    P_gas_actual(abs(P_gas_actual) < 1e-3) = 0;
    fuel_cost(abs(fuel_cost) < 1e-6) = 0;
end
