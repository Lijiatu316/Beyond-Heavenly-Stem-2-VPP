% ============================================================
% 文件名：data_interpolator.m
% 功能：将6分钟粗粒度数据插值到亚秒级分辨率
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 设计说明：
%   外环可再生数据(辐照度、风速、温度、负荷)在6分钟分辨率，
%   内环需要亚秒级数据。插值策略：
%   - 可再生资源 (辐照度/风速): 分段三次Hermite (PCHIP)，保单调性
%   - 负荷: 线性插值 (负荷变化平滑)
%   - 频率偏差: 保留粗粒度 + 内环PI动态生成高频分量
% ============================================================

function data_fast = data_interpolator(cfg, hist_data, t_step_outer, scfg)
    % 将粗粒度数据插值到亚秒级
    %
    % 输入:
    %   cfg         - 全局配置
    %   hist_data   - 历史数据结构体（来自外环当前步）
    %   t_step_outer - 当前外环步索引
    %   scfg        - 亚秒级配置
    %
    % 输出:
    %   data_fast   - 亚秒级插值数据结构体 [scfg.inner_steps × N_vpp]

    Nv = cfg.N_vpp;
    Ni = scfg.inner_steps;
    dt_s = scfg.dt_fast;

    % 构建外环时间点（当前步前后各取一个点用于插值）
    t_outer_s = scfg.t_outer;  % 外环时间轴 (s)

    data_fast = struct();
    data_fast.time_s = ((t_step_outer-1)*scfg.dt_outer : dt_s : t_step_outer*scfg.dt_outer - dt_s)';

    % ---- 辐照度插值 ----
    irrad = cfg.data.irradiance;  % [N_outer × Nv]
    data_fast.irradiance = interp_robust(t_outer_s, irrad, data_fast.time_s, scfg.interp_method);

    % ---- 温度插值 ----
    temp = cfg.data.temperature;
    data_fast.temperature = interp_robust(t_outer_s, temp, data_fast.time_s, 'linear');

    % ---- 风速插值 (PCHIP保单调性) ----
    wind = cfg.data.wind_speed;
    data_fast.wind_speed = interp_robust(t_outer_s, wind, data_fast.time_s, 'pchip');

    % ---- 负荷插值 ----
    load_data = cfg.data.load_rigid;
    data_fast.load_rigid = interp_robust(t_outer_s, load_data, data_fast.time_s, 'linear');

    % ---- 潮汐水位插值 (正弦本质，spline更好) ----
    tide = cfg.data.tide_height;
    data_fast.tide_height = interp_robust(t_outer_s, tide(:), data_fast.time_s, 'spline');

    % ---- 频率偏差 (低频分量来自数据，高频分量由PI控制器在内环生成) ----
    if isfield(cfg.data, 'freq_deviation')
        fdev = cfg.data.freq_deviation;
        data_fast.freq_dev_base = interp_robust(t_outer_s, fdev, data_fast.time_s, 'linear');
    else
        data_fast.freq_dev_base = zeros(length(data_fast.time_s), Nv);
    end

    fprintf('  [数据插值] %.2fh数据 → %.3fs分辨率 (%s), %d个内环点\n', ...
            scfg.dt_outer/3600, dt_s, scfg.interp_method, Ni);
end


function yi = interp_robust(x, y, xi, method)
    % 鲁棒插值：处理边界和NaN
    % x: 外环时间轴 [N_outer × 1]
    % y: 数据矩阵 [N_outer × N_var]
    % xi: 查询时间点 [N_inner × 1]
    % method: 插值方法字符串

    [Nx, Nv] = size(y);

    % 确保列向量
    x = x(:);
    xi = xi(:);

    % 对于每列进行插值
    yi = zeros(length(xi), Nv);
    for v = 1:Nv
        yv = y(:, v);
        % 过滤NaN
        valid = ~isnan(yv) & ~isnan(x);
        if sum(valid) < 2
            yi(:, v) = 0;
            continue;
        end
        try
            yi(:, v) = interp1(x(valid), yv(valid), xi, method, 'extrap');
            % 物理约束：辐照度非负，风速非负
            yi(:, v) = max(yi(:, v), 0);
        catch
            % 回退到线性
            yi(:, v) = interp1(x(valid), yv(valid), xi, 'linear', 'extrap');
            yi(:, v) = max(yi(:, v), 0);
        end
    end
end
