% ============================================================
% 文件名：integrate_real_data.m
% 功能：将Python抓取的真实数据集成到MATLAB仿真中
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统 — 补丁包
% 开发环境：MATLAB R2023b
%
% 集成方式：
%   1. 调用Python脚本抓取数据 → 2. 读取CSV → 3. 替换cfg.data
%   本文件设计为 param_global_config.m 的无侵入替代：
%     cfg = integrate_real_data(cfg);  % 在 generate_scenario_data 之前调用
% ============================================================

function cfg = integrate_real_data(cfg)
    % 真实数据集成函数
    %
    % 输入:
    %   cfg - 原始配置结构体
    %
    % 输出:
    %   cfg - data字段已被替换为真实数据的配置

    ps = cfg.patches.real_data;
    if ~ps.enabled
        fprintf('  [真实数据] 未启用，使用原始合成数据\n');
        return;
    end

    fprintf('========================================\n');
    fprintf('  [真实数据集成] 替换合成数据为真实电站数据\n');
    fprintf('========================================\n');

    data_dir = fullfile(fileparts(mfilename('fullpath')), 'real_data_cache', 'matlab_input');
    scenario_file = fullfile(data_dir, 'scenario_24h.csv');
    pv_params_file = fullfile(data_dir, 'pv_params.csv');
    tidal_params_file = fullfile(data_dir, 'tidal_params.csv');

    % ---- Step 1: 尝试调用Python抓取最新数据 ----
    if ~exist(scenario_file, 'file') || needs_refresh(data_dir, 86400)
        fprintf('  [Step 1] 调用Python抓取最新数据...\n');
        fetch_success = call_python_fetcher(data_dir);
        if ~fetch_success
            fprintf('  [警告] Python抓取失败，尝试使用缓存数据\n');
        end
    else
        fprintf('  [Step 1] 缓存数据有效 (<24h)，跳过抓取\n');
    end

    % ---- Step 2: 加载CSV数据 ----
    if ~exist(scenario_file, 'file')
        fprintf('  [回退] 未找到真实数据文件，使用原始合成数据\n');
        return;
    end

    fprintf('  [Step 2] 加载真实场景数据...\n');
    try
        T = readtable(scenario_file);
        fprintf('  场景数据: %d行 × %d列\n', height(T), width(T));

        N = cfg.N_steps;
        Nv = cfg.N_vpp;

        % 将24小时数据插值到仿真时间步
        t_csv = T.time_h;
        t_sim = cfg.time;

        % 辐照度
        if ismember('irradiance_Wm2', T.Properties.VariableNames)
            G_csv = T.irradiance_Wm2;
            G_interp = interp1(t_csv, G_csv, t_sim, 'pchip', 'extrap');
            G_interp = max(G_interp, 0);
            cfg.data.irradiance = repmat(G_interp, 1, Nv);
            % VPP间差异 (微小)
            rng(42);
            cfg.data.irradiance = cfg.data.irradiance .* (1 + 0.02 * randn(N, Nv));
            cfg.data.irradiance = max(cfg.data.irradiance, 0);
            fprintf('  辐照度: 真实数据 (NASA POWER/Jiangxia)\n');
        end

        % 温度
        if ismember('temperature_C', T.Properties.VariableNames)
            T_csv = T.temperature_C;
            cfg.data.temperature = repmat(interp1(t_csv, T_csv, t_sim, 'linear', 'extrap')', 1, Nv);
            fprintf('  温度: 真实数据\n');
        end

        % 风速
        if ismember('wind_speed_ms', T.Properties.VariableNames)
            v_csv = T.wind_speed_ms;
            for v = 1:Nv
                rng(43 + v);
                cfg.data.wind_speed(:, v) = interp1(t_csv, v_csv, t_sim, 'linear', 'extrap')' ...
                    .* (0.85 + 0.3 * rand(1));
            end
            cfg.data.wind_speed = max(cfg.data.wind_speed, 0);
            fprintf('  风速: 真实数据 + VPP间差异\n');
        end

        % 负荷
        if ismember('load_kW', T.Properties.VariableNames)
            load_csv = T.load_kW;
            load_interp = interp1(t_csv, load_csv, t_sim, 'linear', 'extrap');
            peak_ratio = cfg.Load.rigid_peak / sum(cfg.Load.rigid_peak);
            cfg.data.load_rigid = load_interp' .* peak_ratio;
            fprintf('  负荷: 真实日负荷曲线\n');
        end

        % 潮汐水位
        if ismember('tide_height_m', T.Properties.VariableNames)
            cfg.data.tide_height = interp1(t_csv, T.tide_height_m, t_sim, 'spline', 'extrap')';
            fprintf('  潮汐水位: 调和分析预报 (江厦潮汐电站)\n');
        end

    catch ME
        fprintf('  [错误] 数据加载失败: %s\n', ME.message);
        fprintf('  [回退] 使用合成数据\n');
    end

    % ---- Step 3: 加载VPP参数 ----
    if exist(pv_params_file, 'file')
        try
            T_pv = readtable(pv_params_file);
            for r = 1:height(T_pv)
                pname = strrep(T_pv{r,1}{1}, ' ', '');
                pval = T_pv{r,2};
                switch pname
                    case 'G_std',                cfg.PV.G_std = pval;
                    case 'T_cell_std',           cfg.PV.T_cell_std = pval;
                    case 'alpha_temp',           cfg.PV.alpha_temp = pval;
                    case 'eta_system',           cfg.PV.eta_system = pval;
                    case 'k_board_temp',         cfg.PV.k_board_temp = pval;
                    case 'k_wind_cool',          cfg.PV.k_wind_cool = pval;
                    case 'low_light_threshold',  cfg.PV.low_light_threshold = pval;
                    case 'low_light_base',       cfg.PV.low_light_base = pval;
                    case 'low_light_divisor',    cfg.PV.low_light_divisor = pval;
                    case 'max_power_ratio',      cfg.PV.max_power_ratio = pval;
                end
            end
            fprintf('  [Step 3] 光伏参数已从真实数据更新\n');
        catch
        end
    end

    if exist(tidal_params_file, 'file')
        try
            T_tidal = readtable(tidal_params_file);
            for r = 1:height(T_tidal)
                try
                    pname = strrep(T_tidal{r,1}{1}, ' ', '');
                    pval = T_tidal{r,2};
                    if ~isnan(pval)
                        switch pname
                            case 'rho',           cfg.Tidal.rho = pval;
                            case 'g',             cfg.Tidal.g = pval;
                            case 'S',             cfg.Tidal.S = pval;
                            case 'eta',           cfg.Tidal.eta = pval;
                            case 'loss_factor',   cfg.Tidal.loss_factor = pval;
                            case 'unit_number',   cfg.Tidal.unit_number = pval;
                            case 'unit_power',    cfg.Tidal.unit_power = pval;
                            case 'H_min',         cfg.Tidal.H_min = pval;
                            case 'Q_max',         cfg.Tidal.Q_max = pval;
                        end
                    end
                catch
                end
            end
            fprintf('  潮汐电站参数已从真实数据更新\n');
        catch
        end
    end

    fprintf('========================================\n');
    fprintf('  [真实数据集成] 完成\n');
    fprintf('  数据来源: NASA POWER + 江厦潮汐站 + CMA气象\n');
    fprintf('========================================\n');
end


function need = needs_refresh(data_dir, ttl_seconds)
    % 检查缓存是否需要刷新
    scenario_file = fullfile(data_dir, 'scenario_24h.csv');
    if ~exist(scenario_file, 'file')
        need = true;
        return;
    end
    finfo = dir(scenario_file);
    age = now - datenum(finfo.date);
    need = (age * 86400) > ttl_seconds;
end


function success = call_python_fetcher(data_dir)
    % 调用Python数据抓取脚本
    try
        py_script = fullfile(fileparts(mfilename('fullpath')), 'fetch_renewable_data.py');

        % 检查Python可用性
        [status, ~] = system('python --version');
        if status ~= 0
            [status, ~] = system('python3 --version');
            if status ~= 0
                fprintf('  [错误] Python不可用\n');
                success = false;
                return;
            end
            py_cmd = 'python3';
        else
            py_cmd = 'python';
        end

        % 执行抓取脚本
        cmd = sprintf('%s "%s" --output "%s"', py_cmd, py_script, data_dir);
        fprintf('  执行: %s\n', cmd);
        [status, output] = system(cmd);

        if status == 0
            fprintf('%s\n', output);
            success = true;
        else
            fprintf('  [Python错误] status=%d\n%s\n', status, output);
            success = false;
        end
    catch ME
        fprintf('  [异常] %s\n', ME.message);
        success = false;
    end
end
