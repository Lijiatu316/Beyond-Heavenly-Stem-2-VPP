% ============================================================
% 文件名：interrupt_load.m
% 功能：可中断负荷模型（中断量约束+补偿成本）
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

function [P_interrupt_actual, compensation_cost, interrupt_result] = interrupt_load(P_interrupt_cmd, params)
    % 可中断负荷执行模型
    %
    % 输入:
    %   P_interrupt_cmd - 中断功率指令 (kW), [1 × N_vpp]
    %                    正值为中断量（减少的负荷）
    %   params          - 可中断负荷参数:
    %       .capacity       - 可中断容量上限 (kW), [1 × N_vpp]
    %       .comp_price     - 中断补偿价格 (元/kWh), [1 × N_vpp]
    %       .min_interrupt  - 最小中断量 (kW), 默认 0
    %       .max_duration   - 最大连续中断时间 (h), 默认 Inf
    %
    % 输出:
    %   P_interrupt_actual - 实际中断功率 (kW), [1 × N_vpp]
    %   compensation_cost   - 补偿成本 (元), [1 × N_vpp]
    %   interrupt_result    - 中断结果结构体

    N_vpp = length(P_interrupt_cmd);

    % 默认参数
    if nargin < 2
        params = struct();
    end
    if ~isfield(params, 'min_interrupt'), params.min_interrupt = zeros(1, N_vpp); end

    % ---- 中断量约束 ----
    % 中断量 ∈ [0, capacity]
    P_interrupt_actual = max(min(P_interrupt_cmd, params.capacity), 0);

    % 小于最小中断量的归零（避免微小中断）
    zero_mask = P_interrupt_actual < params.min_interrupt;
    P_interrupt_actual(zero_mask) = 0;

    % ---- 补偿成本 ----
    compensation_cost = P_interrupt_actual .* params.comp_price;  % 元/h → 实际成本还需乘dt

    % ---- 输出结构体 ----
    interrupt_result = struct();
    interrupt_result.capacity_used = P_interrupt_actual ./ params.capacity;
    interrupt_result.capacity_used(isnan(interrupt_result.capacity_used)) = 0;
    interrupt_result.is_interrupted = P_interrupt_actual > 0;
end
