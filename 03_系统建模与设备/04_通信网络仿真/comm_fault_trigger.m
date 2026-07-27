% ============================================================
% 文件名：comm_fault_trigger.m
% 功能：通信故障注入（按时间表触发/解除断网故障）
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

function fault_active = comm_fault_trigger(t_now, fault_schedule, topology, force_all)
    % 通信故障触发/解除判断
    %
    % 输入:
    %   t_now          - 当前时刻 (h)
    %   fault_schedule - 故障时间表 [M × 2] 或 [M × 4]
    %                    [start_h, end_h] — 全拓扑故障
    %                    [start_h, end_h, vpp_i, vpp_j] — 指定链路故障
    %   topology       - 通信拓扑邻接矩阵 [N_vpp × N_vpp]
    %   force_all      - 强制全部链路故障 (logical), 默认 false
    %
    % 输出:
    %   fault_active - 故障激活矩阵 [N_vpp × N_vpp], logical

    Nv = size(topology, 1);

    if nargin < 4
        force_all = false;
    end

    % 强制全部故障模式（全程孤岛仿真用）
    if force_all
        fault_active = (topology > 0);  % 所有连接链路故障
        return;
    end

    % ---- 初始化：无故障 ----
    fault_active = false(Nv, Nv);

    % ---- 检查故障时间表 ----
    if isempty(fault_schedule)
        return;
    end

    for k = 1:size(fault_schedule, 1)
        t_start = fault_schedule(k, 1);
        t_end   = fault_schedule(k, 2);

        % 判断当前时刻是否在故障窗口内
        if t_now >= t_start && t_now < t_end
            if size(fault_schedule, 2) >= 4
                % 指定链路故障
                vpp_i = fault_schedule(k, 3);
                vpp_j = fault_schedule(k, 4);
                if vpp_i <= Nv && vpp_j <= Nv && topology(vpp_i, vpp_j) > 0
                    fault_active(vpp_i, vpp_j) = true;
                    fault_active(vpp_j, vpp_i) = true;  % 对称
                end
            else
                % 全拓扑故障：激活所有连接链路
                fault_active = (topology > 0);
            end
            break;  % 找到匹配的故障窗口即退出
        end
    end
end
