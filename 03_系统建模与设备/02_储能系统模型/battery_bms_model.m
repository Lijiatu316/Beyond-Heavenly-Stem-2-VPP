% ============================================================
% 文件名：battery_bms_model.m
% 功能：储能SOC递推模型（充放电损耗+保护阈值限幅）
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

function [SOC_new, P_bat_actual, SOC_violation] = battery_bms_model(P_cmd, SOC_prev, dt, params)
    % 储能SOC递推与充放电限幅
    %
    % 输入:
    %   P_cmd       - 充放电功率指令 (kW), [1 × N_vpp]
    %                P>0 放电, P<0 充电
    %   SOC_prev    - 上一时刻SOC, [1 × N_vpp]
    %   dt          - 时间步长 (h)
    %   params      - 储能参数结构体:
    %       .E_cap      - 额定容量 (kWh), [1 × N_vpp]
    %       .SOC_min    - SOC下限, 默认 0.2
    %       .SOC_max    - SOC上限, 默认 0.9
    %       .P_ch_max   - 最大充电功率 (kW), [1 × N_vpp]
    %       .P_dis_max  - 最大放电功率 (kW), [1 × N_vpp]
    %       .eff_ch     - 充电效率, 默认 0.92
    %       .eff_dis    - 放电效率, 默认 0.92
    %
    % 输出:
    %   SOC_new       - 更新后SOC, [1 × N_vpp]
    %   P_bat_actual  - 实际充放电功率 (kW), [1 × N_vpp]
    %   SOC_violation - SOC越限量, [1 × N_vpp]

    N_vpp = length(P_cmd);

    % 默认参数
    if nargin < 4
        params = struct();
    end
    if ~isfield(params, 'SOC_min'),   params.SOC_min = 0.2 * ones(1, N_vpp); end
    if ~isfield(params, 'SOC_max'),   params.SOC_max = 0.9 * ones(1, N_vpp); end
    if ~isfield(params, 'eff_ch'),    params.eff_ch = 0.92 * ones(1, N_vpp); end
    if ~isfield(params, 'eff_dis'),   params.eff_dis = 0.92 * ones(1, N_vpp); end

    % ---- 最大充放电功率约束 ----
    P_ch_max  = params.P_ch_max;   % 充电功率上限（正值）
    P_dis_max = params.P_dis_max;  % 放电功率上限（正值）

    % 功率指令限幅
    P_bat_actual = zeros(1, N_vpp);
    for i = 1:N_vpp
        if P_cmd(i) > 0
            % 放电：功率为正
            P_bat_actual(i) = min(P_cmd(i), P_dis_max(i));
        elseif P_cmd(i) < 0
            % 充电：功率为负
            P_bat_actual(i) = max(P_cmd(i), -P_ch_max(i));
        end
    end

    % ---- SOC递推 ----
    % SOC = SOC_prev - (P * dt) / (eff * E_cap)
    %   放电(P>0): 从电池取能量, P/eff_dis 是实际取出的, SOC下降, 故减号
    %   充电(P<0): 存入电池, P*eff_ch 是实际存入的(负), SOC上升
    SOC_new = zeros(1, N_vpp);
    for i = 1:N_vpp
        if P_bat_actual(i) > 0
            % 放电
            delta_SOC = P_bat_actual(i) * dt / (params.eff_dis(i) * params.E_cap(i));
            SOC_new(i) = SOC_prev(i) - delta_SOC;
        else
            % 充电 (P_bat_actual < 0)
            delta_SOC = abs(P_bat_actual(i)) * dt * params.eff_ch(i) / params.E_cap(i);
            SOC_new(i) = SOC_prev(i) + delta_SOC;
        end
    end

    % ---- SOC上下限保护 ----
    SOC_unclamped = SOC_new;
    SOC_new = max(min(SOC_new, params.SOC_max), params.SOC_min);
    SOC_violation = abs(SOC_new - SOC_unclamped);

    % 若SOC越限被裁剪，修正实际功率
    % 仅对越限VPP进行回退修正
    for i = 1:N_vpp
        if SOC_violation(i) > 1e-6
            % 从SOC裁剪量反推功率修正量
            if SOC_unclamped(i) > params.SOC_max(i)
                % 充电超上限：减少充电功率
                delta_P = SOC_violation(i) * params.E_cap(i) / (dt * params.eff_ch(i));
                P_bat_actual(i) = P_bat_actual(i) + delta_P;  % 充电功率(负)增加(减少绝对值)
            elseif SOC_unclamped(i) < params.SOC_min(i)
                % 放电超下限：减少放电功率
                delta_P = SOC_violation(i) * params.E_cap(i) * params.eff_dis(i) / dt;
                P_bat_actual(i) = P_bat_actual(i) - delta_P;  % 放电功率(正)减少
            end
        end
    end
end
