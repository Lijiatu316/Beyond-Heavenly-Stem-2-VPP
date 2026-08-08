% ============================================================
% 文件名：clock_sync_module.m
% 功能：多VPP时钟同步检查模块，检测各VPP仿真时钟对齐状态
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   本文件为团队独立创新开发，属于项目原创模块。
%   版权所有，未经许可不得转载或用于商业用途。
% ============================================================

function [sync_status, time_offset, detail] = clock_sync_module(vpp_times, cfg)
    % 时钟同步模块 — 检查各VPP仿真时钟对齐状态
    %
    % 输入:
    %   vpp_times - 各VPP当前仿真时间 (h), [1×Nv] 或 [Nv×1]
    %   cfg       - 全局配置结构体，需包含 cfg.Support 字段
    %
    % 输出:
    %   sync_status - 字符串: 'ok' / 'warning' / 'error'
    %   time_offset - 最大时钟偏差 (s)
    %   detail      - 结构体，包含详细诊断信息:
    %       .max_drift_s   - 最大漂移量 (s)
    %       .mean_drift_s  - 平均漂移量 (s)
    %       .num_drifted   - 超差VPP对数量
    %       .all_offsets   - Nv×Nv 成对偏差矩阵 (s)

    % 默认输出
    sync_status = 'ok';
    time_offset = 0;
    detail = struct('max_drift_s', 0, 'mean_drift_s', 0, ...
                    'num_drifted', 0, 'all_offsets', []);

    % 快速通道：支撑层关闭
    if ~cfg.Support.clock_sync_enabled
        return;
    end

    % 单VPP无需同步检查
    Nv = length(vpp_times);
    if Nv <= 1
        return;
    end

    % 转为秒单位
    vpp_times_s = vpp_times(:) * 3600;

    % 计算成对偏差矩阵
    detail.all_offsets = abs(vpp_times_s - vpp_times_s');

    % 统计
    detail.max_drift_s = max(detail.all_offsets(:));
    detail.mean_drift_s = mean(detail.all_offsets(detail.all_offsets > 0));
    if isnan(detail.mean_drift_s)
        detail.mean_drift_s = 0;
    end

    time_offset = detail.max_drift_s;

    % 判定同步状态
    max_allowed = cfg.Support.clock_sync.max_drift_s;
    if detail.max_drift_s <= max_allowed * 0.5
        sync_status = 'ok';
    elseif detail.max_drift_s <= max_allowed
        sync_status = 'warning';
    else
        sync_status = 'error';
    end

    % 统计超差对数量
    upper_tri = triu(detail.all_offsets, 1);
    detail.num_drifted = sum(upper_tri(:) > max_allowed);
end
