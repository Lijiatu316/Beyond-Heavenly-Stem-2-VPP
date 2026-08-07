% ============================================================
% 文件名：comm_delay_sim.m
% 功能：模拟通信时延、数据丢包（VPP间邻域链路的通信质量模拟）
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

function comm_state = comm_delay_sim(cfg, t_step, fault_active)
    % 通信网络质量模拟
    %
    % 输入:
    %   cfg          - 全局配置
    %   t_step       - 当前时间步索引
    %   fault_active - 故障是否激活 (logical), [N_vpp × N_vpp]
    %
    % 输出:
    %   comm_state - 通信状态结构体:
    %       .delay       - 时延矩阵 (s), [N_vpp × N_vpp]
    %       .loss_rate   - 丢包率矩阵, [N_vpp × N_vpp]
    %       .quality     - 通信质量评分 [0,1], [N_vpp × N_vpp]

    Nv = cfg.N_vpp;
    topo = cfg.Comm.topology;

    % 故障矩阵（若未提供则默认无故障）
    if nargin < 3
        fault_active = false(Nv, Nv);
    end

    % ---- 基线通信质量 ----
    base_delay = cfg.Comm.base_delay;
    base_loss  = cfg.Comm.base_loss;

    % ---- 正常工况：小幅度随机波动 ----
    rng(t_step * 100 + 42);  % 确定性随机种子（可复现）
    delay_normal = base_delay + 0.005 * randn(Nv, Nv);   % ±5ms抖动
    loss_normal  = base_loss  + 0.01  * rand(Nv, Nv);     % 0~2%丢包

    rng(t_step * 200 + 84);  % 独立随机种子用于故障叠加
    % ---- 故障工况：时延×100，丢包率→0.5~1.0 ----
    delay_fault = 0.2 + 0.3 * rand(Nv, Nv);     % 200~500ms时延
    loss_fault  = 0.5 + 0.5 * rand(Nv, Nv);      % 50%~100%丢包

    % ---- 合成通信状态 ----
    % 仅拓扑中有连接的链路受故障影响，无连接链路保持0
    delay    = zeros(Nv, Nv);
    loss     = zeros(Nv, Nv);

    for i = 1:Nv
        for j = 1:Nv
            if i == j
                % 自通信：零时延零丢包
                delay(i, j) = 0;
                loss(i, j)  = 0;
            elseif topo(i, j) == 1
                % 邻域链路：根据故障状态切换
                if fault_active(i, j) || fault_active(j, i)
                    delay(i, j) = delay_fault(i, j);
                    loss(i, j)  = loss_fault(i, j);
                else
                    delay(i, j) = max(delay_normal(i, j), 0);
                    loss(i, j)  = max(min(loss_normal(i, j), 1), 0);
                end
            else
                % 无连接链路
                delay(i, j) = Inf;
                loss(i, j)  = 1;
            end
        end
    end

    % ---- 通信质量评分 ----
    quality = max(1 - (delay / cfg.Comm.delay_threshold + loss / cfg.Comm.loss_threshold) / 2, 0);
    quality = min(quality, 1);

    % ---- 组装输出 ----
    comm_state.delay     = (delay + delay') / 2;  % 对称化
    comm_state.loss_rate = (loss  + loss')  / 2;
    comm_state.quality   = (quality + quality') / 2;
end
