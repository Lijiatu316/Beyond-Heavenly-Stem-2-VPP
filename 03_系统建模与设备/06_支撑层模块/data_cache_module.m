% ============================================================
% 文件名：data_cache_module.m
% 功能：通信中断期间本地数据缓存与断点续传模块
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   本文件为团队独立创新开发，属于项目原创模块。
%   版权所有，未经许可不得转载或用于商业用途。
% ============================================================

function [cache, recovered_data] = data_cache_module(action, cache, data, cfg)
    % 数据缓存模块 — 通信中断期间本地数据缓存与断点续传
    %
    % 支持动作:
    %   'init'     — 初始化缓存结构体
    %   'store'    — 通信中断时缓存待发送数据
    %   'retrieve' — 通信恢复时检索并回传未发送的缓存数据
    %   'flush'    — 清理超过 max_age_h 的过期缓存条目
    %
    % 输入:
    %   action - 操作指令: 'init' | 'store' | 'retrieve' | 'flush'
    %   cache  - 缓存结构体（首次调用传 []，后续传入返回值）
    %   data   - 待缓存/检索的数据结构体
    %            store操作: data必须包含 .t_now (当前时间h) 和 .payload (任意数据)
    %            retrieve操作: data可传 []（返回所有未发送条目）
    %   cfg    - 全局配置结构体
    %
    % 输出:
    %   cache          - 更新后的缓存结构体（下次调用需传入）
    %   recovered_data - 恢复的数据元胞数组（仅retrieve操作有内容）

    recovered_data = [];

    % 快速通道：支撑层关闭
    if ~cfg.Support.data_cache_enabled
        if strcmp(action, 'init')
            cache = struct('buffer', {{}}, 'timestamps', [], 'count', 0, ...
                          'total_stored', 0, 'total_retrieved', 0);
        end
        return;
    end

    switch action
        case 'init'
            % ---- 初始化空缓存 ----
            max_size = cfg.Support.data_cache.max_size;
            cache = struct();
            cache.buffer  = cell(max_size, 1);
            cache.timestamps = zeros(max_size, 1);
            cache.count = 0;
            cache.total_stored = 0;
            cache.total_retrieved = 0;

        case 'store'
            % ---- 缓存待发送数据 ----
            if ~isfield(data, 't_now') || ~isfield(data, 'payload')
                warning('data_cache_module:store — data缺少t_now或payload字段，跳过');
                return;
            end

            max_size = cfg.Support.data_cache.max_size;

            % 先清理过期条目腾出空间
            if cache.count >= max_size
                cache = flush_expired(cache, data.t_now, cfg);
            end

            % 缓存满 → 丢弃最旧条目 (FIFO)
            if cache.count >= max_size
                cache.buffer(1:end-1) = cache.buffer(2:end);
                cache.timestamps(1:end-1) = cache.timestamps(2:end);
                cache.count = cache.count - 1;
            end

            % 追加新条目
            cache.count = cache.count + 1;
            cache.buffer{cache.count} = data.payload;
            cache.timestamps(cache.count) = data.t_now;
            cache.total_stored = cache.total_stored + 1;

        case 'retrieve'
            % ---- 通信恢复，返回所有缓存数据 ----
            if cache.count > 0
                recovered_data = cache.buffer(1:cache.count);
                cache.buffer(1:cache.count) = cell(cache.count, 1);
                cache.total_retrieved = cache.total_retrieved + cache.count;
                cache.count = 0;
                cache.timestamps(:) = 0;
            end

        case 'flush'
            % ---- 清理过期条目 ----
            if nargin >= 3 && ~isempty(data) && isfield(data, 't_now')
                cache = flush_expired(cache, data.t_now, cfg);
            end

        otherwise
            warning('data_cache_module: 未知操作 "%s"，忽略', action);
    end
end


function cache = flush_expired(cache, t_now, cfg)
    % 内部函数：清理过期缓存条目
    if cache.count == 0
        return;
    end

    max_age_h = cfg.Support.data_cache.max_age_h;
    valid_mask = (t_now - cache.timestamps(1:cache.count)) <= max_age_h;

    if all(valid_mask)
        return;
    end

    n_valid = sum(valid_mask);
    n_expired = cache.count - n_valid;

    % 保留有效条目，其余置空
    cache.buffer(1:n_valid) = cache.buffer(valid_mask);
    cache.buffer(n_valid+1:cache.count) = cell(n_expired, 1);
    cache.timestamps(1:n_valid) = cache.timestamps(valid_mask);
    cache.timestamps(n_valid+1:cache.count) = 0;
    cache.count = n_valid;
end
