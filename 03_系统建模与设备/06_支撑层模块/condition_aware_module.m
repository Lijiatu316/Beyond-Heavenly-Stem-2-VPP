% ============================================================
% 文件名：condition_aware_module.m
% 功能：多源信息融合态势感知模块，综合通信质量/频率/电压
%       评估系统当前运行工况并输出严重等级
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   本文件为团队独立创新开发，属于项目原创模块。
%   版权所有，未经许可不得转载或用于商业用途。
% ============================================================

function [condition, severity, detail] = condition_aware_module(comm_state, mode, freq, volt, cfg)
    % 工况感知模块 — 综合评估系统运行工况
    %
    % 工况分类 (按严重程度递增):
    %   'NORMAL'          — 正常运行（通信良好+频率电压正常）
    %   'COMM_DEGRADED'   — 通信劣化（延迟/丢包偏高，仍可协同）
    %   'FREQ_ABNORMAL'   — 频率异常（越限但未触发保护）
    %   'VOLT_ABNORMAL'   — 电压异常
    %   'EMERGENCY'       — 紧急工况（已进入孤岛+频率越限）
    %
    % 输入:
    %   comm_state - 通信状态结构体（可为空[]）
    %   mode       - 当前运行模式: 1=COOPERATE, 2=ISLAND
    %   freq       - 各VPP当前频率 (Hz), [1×Nv] 向量
    %   volt       - 各VPP当前电压 (p.u.), [1×Nv] 向量
    %   cfg        - 全局配置结构体
    %
    % 输出:
    %   condition - 工况标签 (字符串)
    %   severity  - 严重等级 (0=正常, 1=注意, 2=警告, 3=紧急)
    %   detail    - 结构体，包含各维度详细评估:
    %       .freq_max_dev   - 最大频率偏差 (Hz)
    %       .volt_max_dev   - 最大电压偏差 (p.u.)
    %       .comm_avg_quality - 平均通信质量 (0-1)
    %       .triggered_by   - 触发分类的原因描述

    % 默认输出
    severity = 0;
    condition = 'NORMAL';
    detail = struct('freq_max_dev', 0, 'volt_max_dev', 0, ...
                    'comm_avg_quality', 1.0, 'triggered_by', '');

    % 快速通道：支撑层关闭
    if ~cfg.Support.condition_aware_enabled
        return;
    end

    triggered_by = {};

    % ---- 1. 通信质量评估 ----
    if ~isempty(comm_state) && isfield(comm_state, 'quality_matrix')
        qmat = comm_state.quality_matrix;
        detail.comm_avg_quality = mean(qmat(qmat > 0));
        if isempty(detail.comm_avg_quality) || isnan(detail.comm_avg_quality)
            detail.comm_avg_quality = 1.0;
        end
    else
        detail.comm_avg_quality = 1.0;
    end

    % 通信劣化判定
    if detail.comm_avg_quality < 0.3
        severity = 3;
        condition = 'EMERGENCY';
        triggered_by{end+1} = '通信严重劣化(quality<0.3)';
    elseif detail.comm_avg_quality < 0.6
        severity = max(severity, 2);
        condition = 'COMM_DEGRADED';
        triggered_by{end+1} = '通信中度劣化(quality<0.6)';
    end

    % 孤岛模式隐含通信不可用
    if mode == 2  % ISLAND
        severity = max(severity, 2);
        if ~strcmp(condition, 'EMERGENCY')
            condition = 'COMM_DEGRADED';
        end
        triggered_by{end+1} = '已进入孤岛模式(通信中断)';
    end

    % ---- 2. 频率评估 ----
    f_nom = cfg.f_nom;
    if isempty(freq)
        freq_dev = 0;
    else
        freq_dev = abs(freq(:) - f_nom);
    end
    detail.freq_max_dev = max(freq_dev);

    if any(freq_dev > 0.5)
        severity = 3;
        condition = 'EMERGENCY';
        triggered_by{end+1} = sprintf('频率严重越限(Δf=%.2fHz)', detail.freq_max_dev);
    elseif any(freq_dev > 0.2)
        severity = max(severity, 2);
        if ~ismember(condition, {'EMERGENCY', 'COMM_DEGRADED'})
            condition = 'FREQ_ABNORMAL';
        end
        triggered_by{end+1} = sprintf('频率轻度越限(Δf=%.2fHz)', detail.freq_max_dev);
    end

    % ---- 3. 电压评估 ----
    if isempty(volt)
        volt_dev = 0;
    else
        volt_dev = abs(volt(:) - 1.0);
    end
    detail.volt_max_dev = max(volt_dev);

    if any(volt_dev > 0.1)
        severity = max(severity, 2);
        if ~ismember(condition, {'EMERGENCY', 'FREQ_ABNORMAL', 'COMM_DEGRADED'})
            condition = 'VOLT_ABNORMAL';
        end
        triggered_by{end+1} = sprintf('电压越限(ΔV=%.3f p.u.)', detail.volt_max_dev);
    end

    % ---- 汇编触发原因 ----
    if ~isempty(triggered_by)
        detail.triggered_by = strjoin(triggered_by, '; ');
    end
end
