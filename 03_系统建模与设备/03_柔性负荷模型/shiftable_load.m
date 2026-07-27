% ============================================================
% 文件名：shiftable_load.m
% 功能：可平移负荷模型（充电桩/空调，时间窗约束+能量守恒）
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

function [P_shifted, shift_cost, shift_result] = shiftable_load(P_baseline, P_shift_cmd, t, dt, params)
    % 可平移负荷调度模型
    %
    % 输入:
    %   P_baseline   - 原始负荷曲线值 (kW), [1 × N_vpp]
    %   P_shift_cmd  - 平移功率指令 (kW), [1 × N_vpp]
    %                  正值 = 从当前时段移出（减少当前负荷）
    %                  负值 = 从其他时段移入（增加当前负荷）
    %   t            - 当前时间 (h)
    %   dt           - 时间步长 (h)
    %   params       - 可平移负荷参数:
    %       .capacity     - 可平移容量 (kW), [1 × N_vpp]
    %       .window_start - 可平移时间窗起始 (h), 默认 6
    %       .window_end   - 可平移时间窗结束 (h), 默认 22
    %       .shift_cost_a - 平移成本系数 (元/kWh), 默认 0.05
    %
    % 输出:
    %   P_shifted    - 平移后负荷功率 (kW), [1 × N_vpp]
    %   shift_cost   - 平移成本 (元), [1 × N_vpp]
    %   shift_result - 平移结果结构体

    N_vpp = length(P_baseline);

    % 默认参数
    if nargin < 5
        params = struct();
    end
    if ~isfield(params, 'window_start'), params.window_start = 6; end
    if ~isfield(params, 'window_end'),   params.window_end = 22; end
    if ~isfield(params, 'shift_cost_a'), params.shift_cost_a = 0.05 * ones(1, N_vpp); end

    % ---- 时间窗口检查 ----
    % 仅在可平移时间窗内允许平移操作
    in_window = (t >= params.window_start && t <= params.window_end);

    if ~in_window
        % 不在时间窗内：不做平移
        P_shifted = P_baseline;
        shift_cost = zeros(1, N_vpp);
        shift_result = struct('shift_amount', zeros(1, N_vpp), 'in_window', false);
        return;
    end

    % ---- 平移量约束 ----
    % 移出量 ≤ 当前负荷（不能把负荷移成负的）
    max_shift_out = min(P_baseline, params.capacity);
    % 移入量 ≤ 容量上限
    max_shift_in  = params.capacity;

    % 限制平移指令
    P_shift_cmd_clipped = zeros(1, N_vpp);
    for i = 1:N_vpp
        if P_shift_cmd(i) > 0
            % 移出负荷：减少当前负荷
            P_shift_cmd_clipped(i) = min(P_shift_cmd(i), max_shift_out(i));
        elseif P_shift_cmd(i) < 0
            % 移入负荷：增加当前负荷
            P_shift_cmd_clipped(i) = max(P_shift_cmd(i), -max_shift_in(i));
        end
    end

    % ---- 执行平移 ----
    P_shifted = P_baseline - P_shift_cmd_clipped;  % 移出时减去，移入时加上

    % 负荷非负
    P_shifted = max(P_shifted, 0);

    % ---- 平移成本 ----
    % 成本与平移量的绝对值成正比
    shift_cost = params.shift_cost_a .* abs(P_shift_cmd_clipped) * dt;

    % ---- 输出结构体 ----
    shift_result = struct();
    shift_result.shift_amount = P_shift_cmd_clipped;
    shift_result.shifted_energy = P_shift_cmd_clipped * dt;  % 平移电量 (kWh)
    shift_result.in_window = in_window;
end
