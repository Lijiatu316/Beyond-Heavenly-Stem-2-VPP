% ============================================================
% 文件名：coop_constraint_allocate.m
% 功能：多机组备用容量分布式分配
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
%
% 知识产权声明：
%   本文件为团队独立创新开发，属于项目核心原创算法模块。
%   版权所有，未经许可不得转载或用于商业用途。
% ============================================================

function reserve = coop_constraint_allocate(state, exchange_data, dispatch, cfg)
    % 协同约束分配 — 多机组备用容量分布式分配
    %
    % 基于邻域交换信息，分布式计算各VPP应承担的:
    %   - 上调备用 (应对负荷突增/可再生骤降)
    %   - 下调备用 (应对可再生突增/负荷骤降)
    %   - 互济功率建议 (VPP间最优功率流转)
    %
    % 分配原则:
    %   1. 可调裕度大的VPP承担更多备用
    %   2. 边际成本低的VPP优先提供上调备用
    %   3. 可再生富余的VPP优先提供下调备用
    %
    % 输入:
    %   state         - 当前系统状态
    %   exchange_data - 邻域交换数据 (neighbor_data_exchange输出)
    %   dispatch      - 当前调度指令
    %   cfg           - 全局配置
    %
    % 输出:
    %   reserve - 备用分配结构体

    Nv = cfg.N_vpp;
    reserve = struct();

    % ---- 1. 计算系统总备用需求 ----
    % 上调备用需求 = 最大单机故障容量 + 负荷预测误差 (取10%负荷)
    total_load = sum(state.P_load);
    reserve_up_total   = max(cfg.Gas.P_max) + 0.10 * total_load;
    reserve_down_total = 0.15 * total_load;  % 总可再生出力的不确定性

    % ---- 2. 按可调裕度比例分配上调备用 ----
    total_flex_up = sum(exchange_data.flex_up);
    if total_flex_up > 0
        reserve.up_ratio = exchange_data.flex_up / total_flex_up;
    else
        reserve.up_ratio = ones(Nv, 1) / Nv;
    end
    reserve.up_amount = reserve.up_ratio * reserve_up_total;

    % ---- 3. 按可再生富余比例分配下调备用 ----
    total_surplus = sum(exchange_data.renew_surplus);
    if total_surplus > 0
        reserve.down_ratio = exchange_data.renew_surplus / total_surplus;
    else
        reserve.down_ratio = ones(Nv, 1) / Nv;
    end
    reserve.down_amount = reserve.down_ratio * reserve_down_total;

    % ---- 4. 互济功率建议 ----
    % 基于边际成本差异: 成本低的VPP多发电，卖给成本高的VPP
    mc = exchange_data.marginal_cost;
    mc_avg = mean(mc);
    reserve.transfer_advice = zeros(Nv, 1);

    for v = 1:Nv
        if mc(v) < mc_avg
            % 低成本VPP: 建议多发电 (增加出力)
            reserve.transfer_advice(v) = +exchange_data.flex_up(v) * 0.3;
        elseif mc(v) > mc_avg
            % 高成本VPP: 建议少发电 (从邻居购电)
            reserve.transfer_advice(v) = -exchange_data.flex_down(v) * 0.3;
        end
    end

    % ---- 5. 裕度校验 ----
    reserve.up_amount   = max(0, min(reserve.up_amount, exchange_data.flex_up));
    reserve.down_amount = max(0, min(reserve.down_amount, exchange_data.flex_down));

    % ---- 6. 汇总 ----
    reserve.total_up_reserve   = sum(reserve.up_amount);
    reserve.total_down_reserve = sum(reserve.down_amount);
    reserve.up_coverage        = sum(exchange_data.flex_up) / max(reserve_up_total, 1);
    reserve.down_coverage      = sum(exchange_data.renew_surplus) / max(reserve_down_total, 1);
end
