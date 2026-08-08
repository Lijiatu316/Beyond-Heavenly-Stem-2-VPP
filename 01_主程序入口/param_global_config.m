% ============================================================
% 文件名：param_global_config.m
% 功能：全局静态参数配置，机组限值/储能SOC/电价/通信阈值/保护定值/拓扑
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   辅助工具/主控脚本，不包含核心算法创新。
%   版权所有归属项目团队。
% ============================================================

function cfg = param_global_config()
    % 全局参数统一配置（返回结构体，避免全局变量污染）— V2.0 9-VPP扩展版
    %
    % 输出:
    %   cfg - 全局配置结构体，包含所有仿真参数

    % ==================== 仿真基础设置 ====================
    cfg.N_vpp    = 9;          % VPP数量 (V2.0: 3→9)
    cfg.T_sim    = 24;         % 仿真时长 (h)
    cfg.dt       = 0.1;        % 时间步长 (h)，6分钟级
    cfg.N_steps  = cfg.T_sim / cfg.dt;  % 总步数 = 240
    cfg.f_nom    = 50;         % 标称频率 (Hz)
    cfg.time     = (0:cfg.dt:cfg.T_sim-cfg.dt)';  % 时间轴 (h)

    % VPP类型标签: 1-3=光伏侧重, 4-6=风电侧重, 7-9=潮汐侧重
    cfg.vpp_types = {'光伏侧重','光伏侧重','光伏侧重', ...
                     '风电侧重','风电侧重','风电侧重', ...
                     '潮汐侧重','潮汐侧重','潮汐侧重'};

    % ==================== 光伏参数（对接预测汇总/pv_params.csv）====================
    % V1-3光伏侧重, V4-9少量光伏
    cfg.PV.capacity       = [600, 500, 550, 200, 150, 180, 250, 200, 220];  % 装机容量 (kWp)
    cfg.PV.G_std          = 1000;               % 参考辐照度 (W/m2)
    cfg.PV.alpha_temp     = 0.0038;             % 温度系数 (/C)
    cfg.PV.T_cell_std     = 25;                 % 参考电池温度 (C)
    cfg.PV.eta_system     = 0.8;                % 系统效率
    cfg.PV.k_board_temp   = 0.016;              % 板温系数
    cfg.PV.k_wind_cool    = 0.1;                % 风冷系数
    cfg.PV.low_light_threshold = 200;           % 弱光阈值 (W/m2)
    cfg.PV.low_light_base      = 0.6;           % 弱光基数
    cfg.PV.low_light_divisor   = 500;           % 弱光除数
    cfg.PV.max_power_ratio     = 1.1;           % 最大功率比

    % ==================== 风电参数（对接预测汇总/wind_model_config.csv）====================
    % V4-6风电侧重, V1-3,V7-9少量风电
    cfg.Wind.capacity     = [200, 250, 180, 700, 600, 650, 300, 250, 280];  % 装机容量 (kW)
    cfg.Wind.v_cutin      = 3;                  % 切入风速 (m/s)
    cfg.Wind.v_rated      = 12;                 % 额定风速 (m/s)
    cfg.Wind.v_cutout     = 25;                 % 切出风速 (m/s)
    cfg.Wind.air_density  = 1.225;              % 空气密度 (kg/m3)
    cfg.Wind.Cp_max       = 0.45;               % 最大风能利用系数
    cfg.Wind.mech_eff     = 0.95;               % 机械效率
    cfg.Wind.train_max_wind = 20.5;             % 训练集最大风速 (m/s)
    cfg.Wind.mean_power_kW  = 1424;             % 训练集平均功率 (kW)
    cfg.Wind.ref_capacity   = 3600;             % 训练风机额定容量 (kW)

    % ==================== 潮汐发电参数（对接预测汇总/tidal_params.csv）====================
    cfg.Tidal.enabled      = true;              % 启用潮汐发电
    % V7-9潮汐侧重, V1-6少量潮汐, 总计仍为江厦3200kW
    cfg.Tidal.capacity     = [300, 200, 250, 350, 250, 300, 500, 550, 500];  % 各VPP潮汐容量 (kW)
    cfg.Tidal.rho          = 1025;              % 海水密度 (kg/m3)
    cfg.Tidal.g            = 9.81;              % 重力加速度 (m/s2)
    cfg.Tidal.S            = 5300000;           % 库区面积 (m2) — 江厦潮汐电站
    cfg.Tidal.eta          = 0.78;              % 综合效率
    cfg.Tidal.loss_factor  = 0.95;              % 损耗系数
    cfg.Tidal.unit_number  = 5;                 % 机组台数
    cfg.Tidal.unit_power   = 640;               % 单机功率 (kW)
    cfg.Tidal.H_min        = 1.0;               % 最小水头 (m)
    cfg.Tidal.Q_max        = 120;               % 最大流量 (m3/s)

    % ==================== 燃气轮机参数 ====================
    cfg.Gas.P_min         = [40, 45, 50, 55, 50, 45, 60, 55, 50];    % 最小出力 (kW)
    cfg.Gas.P_max         = [600, 550, 500, 800, 750, 700, 650, 600, 550];  % 最大出力 (kW)
    cfg.Gas.ramp_rate     = [300, 280, 250, 400, 380, 350, 320, 300, 280];  % 爬坡率 (kW/h)
    cfg.Gas.fuel_cost_a   = [0.35, 0.35, 0.35, 0.38, 0.38, 0.38, 0.33, 0.33, 0.33];  % 燃料成本斜率
    cfg.Gas.fuel_cost_b   = repmat(0.05, 1, 9);  % 燃料成本截距 (元/h)
    cfg.Gas.fuel_cost_c   = zeros(1, 9);          % 二次成本系数 (元/kW²h), 0=线性模型向后兼容
    cfg.Gas.ramp_enabled_in_opt = false;          % 孤岛模式是否在优化中启用爬坡约束 (默认关闭)

    % ==================== 储能参数 ====================
    cfg.Battery.E_cap     = [400, 350, 380, 500, 450, 480, 420, 400, 430];  % 额定容量 (kWh)
    cfg.Battery.SOC0      = [0.50, 0.55, 0.52, 0.60, 0.58, 0.55, 0.53, 0.57, 0.55];  % 初始SOC
    cfg.Battery.SOC_min   = repmat(0.10, 1, 9);  % SOC下限
    cfg.Battery.SOC_max   = repmat(0.90, 1, 9);  % SOC上限
    cfg.Battery.P_ch_max  = [80, 75, 78, 100, 95, 90, 85, 82, 88];   % 最大充电功率 (kW)
    cfg.Battery.P_dis_max = [80, 75, 78, 100, 95, 90, 85, 82, 88];   % 最大放电功率 (kW)
    cfg.Battery.eff_ch    = repmat(0.92, 1, 9);  % 充电效率
    cfg.Battery.eff_dis   = repmat(0.92, 1, 9);  % 放电效率

    % ==================== 负荷参数 ====================
    cfg.Load.rigid_peak   = [1600, 1400, 1500, 1800, 1600, 1700, 1500, 1400, 1300];  % 各VPP峰值负荷 (kW)
    cfg.Load.load_scale   = 4.0;                 % CSV场景负荷缩放系数
    cfg.Load.interruptible.capacity      = [120, 100, 110, 140, 120, 130, 110, 100, 90];  % 可中断容量 (kW)
    cfg.Load.interruptible.comp_price    = repmat(0.80, 1, 9);  % 补偿价格
    cfg.Load.interruptible.min_interrupt = repmat(5, 1, 9);     % 最小中断量 (kW)
    cfg.Load.shiftable.capacity    = [60, 50, 55, 70, 65, 60, 55, 50, 45];  % 可平移容量 (kW)
    cfg.Load.shiftable.window_start = 6;               % 时间窗起始 (h)
    cfg.Load.shiftable.window_end   = 22;              % 时间窗结束 (h)
    cfg.Load.shiftable.shift_cost_a = repmat(0.05, 1, 9);  % 平移成本

    % ==================== 通信网络参数 ====================
    % 9-VPP环网+跨类互联拓扑: 同类VPP链式连接, 跨类边界互联
    topo = zeros(9);
    % 光伏链: V1-V2, V2-V3
    topo(1,2)=1; topo(2,3)=1;
    % 风电链: V4-V5, V5-V6
    topo(4,5)=1; topo(5,6)=1;
    % 潮汐链: V7-V8, V8-V9
    topo(7,8)=1; topo(8,9)=1;
    % 跨类互联: V3-V4, V6-V7, V9-V1 (形成环网)
    topo(3,4)=1; topo(6,7)=1; topo(9,1)=1;
    cfg.Comm.topology  = topo + topo';           % 对称邻接矩阵
    cfg.Comm.delay_threshold = 0.1;              % 时延阈值 (s)
    cfg.Comm.loss_threshold  = 0.3;              % 丢包率阈值
    cfg.Comm.base_delay  = 0.01;                 % 基线时延 (s)
    cfg.Comm.base_loss   = 0.01;                 % 基线丢包率
    % 联络线传输容量 (kW), 非邻域=Inf(无限制), 自连接=0
    cfg.Comm.P_line_max  = 500 * ones(9);        % 默认500kW联络线容量
    cfg.Comm.P_line_max(1:10:end) = 0;           % 对角线=0 (自连接)

    % ==================== 电价参数 ====================
    cfg.Price.grid_import  = repmat(0.5, 1, 9);   % 从主网购电 (元/kWh)
    cfg.Price.grid_export  = repmat(0.35, 1, 9);  % 向主网售电 (元/kWh)
    cfg.Price.curtail_pv   = 0.1;                  % 弃光惩罚 (元/kWh)
    cfg.Price.curtail_wind = 0.1;                  % 弃风惩罚 (元/kWh)
    cfg.Price.curtail_tidal = 0.3;                 % 弃潮汐惩罚 (元/kWh)
    cfg.Price.load_shedding = 5.0;                 % 切负荷惩罚 (元/kWh)

    % ==================== 安全保护定值 ====================
    cfg.Safety.freq_min   = 49.5;    % 低频减载阈值 (Hz)
    cfg.Safety.freq_max   = 50.5;    % 过频保护阈值 (Hz)
    cfg.Safety.volt_min   = 0.90;    % 低压保护 (p.u.)
    cfg.Safety.volt_max   = 1.10;    % 过压保护 (p.u.)

    % ==================== 网络损耗参数 ====================
    cfg.Network.loss_coeff   = 0.02;              % 网损系数 (2% of inter-VPP exchange)
    cfg.Network.loss_enabled = true;              % 启用网损建模

    % ==================== 支撑层模块配置 ====================
    cfg.Support.clock_sync_enabled      = true;   % 时钟同步模块
    cfg.Support.condition_aware_enabled = true;   % 工况感知模块
    cfg.Support.data_cache_enabled      = true;   % 数据缓存与断点续传
    cfg.Support.clock_sync.max_drift_s  = 0.5;    % 最大允许时钟漂移 (s)
    cfg.Support.data_cache.max_age_h    = 1.0;    % 缓存数据最大保留时间 (h)
    cfg.Support.data_cache.max_size     = 1000;   % 缓存buffer最大条数

    % ==================== 仿真场景设置 ====================
    cfg.scenario.force_island   = true;     % true=全程孤岛, false=按通信质量自动切换
    cfg.scenario.fault_schedule = [];       % 故障时间表 [start_h, end_h; ...] 空=全程故障

    % ==================== 预测参数 ====================
    cfg.forecast.horizon = 6;               % 预测步数
    cfg.forecast.window  = 12;              % 滑动窗口
    cfg.forecast.method  = 'persistence';   % 'persistence' | 'moving_avg' | 'trend'

    % ==================== 生成模拟输入数据 ====================
    cfg = generate_scenario_data(cfg);
end


function cfg = generate_scenario_data(cfg)
    % 加载场景数据：优先从预测汇总/导出的CSV读取，失败则合成
    N  = cfg.N_steps;
    Nv = cfg.N_vpp;
    t  = cfg.time;

    % CSV文件路径（相对于项目根目录）
    data_dir = fullfile(fileparts(mfilename('fullpath')), '..', '预测汇总', 'matlab_input');
    scenario_file = fullfile(data_dir, 'scenario_24h.csv');
    pv_params_file = fullfile(data_dir, 'pv_params.csv');
    tidal_params_file = fullfile(data_dir, 'tidal_params.csv');

    % ========= 尝试从CSV加载场景数据 =========
    csv_loaded = false;
    if exist(scenario_file, 'file')
        try
            T = readtable(scenario_file);
            fprintf('  [数据对接] 从预测汇总加载场景数据: %s\n', scenario_file);

            N_csv = height(T);
            if N_csv >= N
                % 截断或补齐到仿真步数
                idx = 1:N;

                % 辐照度：每个VPP使用相同的辐照度（微调以增加差异性）
                G_base = T.irradiance_Wm2(idx);
                cfg.data.irradiance = repmat(G_base, 1, Nv);
                % 叠加微小VPP间差异
                rng(42);
                cfg.data.irradiance = cfg.data.irradiance .* (1 + 0.02 * randn(N, Nv));
                cfg.data.irradiance = max(cfg.data.irradiance, 0);

                % 温度
                T_base = T.temperature_C(idx);
                cfg.data.temperature = repmat(T_base, 1, Nv);

                % 风速：各VPP间有差异
                v_base = T.wind_speed_ms(idx);
                cfg.data.wind_speed = zeros(N, Nv);
                rng(43);
                for v = 1:Nv
                    cfg.data.wind_speed(:, v) = v_base .* (0.85 + 0.3 * rand(1));
                end
                cfg.data.wind_speed = max(cfg.data.wind_speed, 0);

                % 负荷：从CSV总负荷×缩放系数，按峰值比例分配到各VPP
                load_total = T.load_kW(idx) * cfg.Load.load_scale;
                peak_ratio = cfg.Load.rigid_peak / sum(cfg.Load.rigid_peak);
                cfg.data.load_rigid = load_total .* peak_ratio;

                % 潮汐水位
                cfg.data.tide_height = T.tide_height_m(idx);

                % 预测参考值（可选——用于对比验证）
                pv_ref_file = fullfile(data_dir, 'pv_power_24h.csv');
                wind_ref_file = fullfile(data_dir, 'wind_power_24h.csv');
                if exist(pv_ref_file, 'file')
                    T_pv = readtable(pv_ref_file);
                    cfg.data.pv_power_ref = T_pv.pv_power_kW(idx);
                end
                if exist(wind_ref_file, 'file')
                    T_wind = readtable(wind_ref_file);
                    cfg.data.wind_power_ref = T_wind.wind_power_kW(idx);
                end

                csv_loaded = true;
            end
        catch ME
            fprintf('  [警告] CSV加载失败: %s, 回退到合成数据\n', ME.message);
        end
    end

    % ========= 加载PV模型参数 =========
    if exist(pv_params_file, 'file')
        try
            T_pv = readtable(pv_params_file);
            for r = 1:height(T_pv)
                pname = strrep(T_pv{r, 1}{1}, ' ', '');
                pval = T_pv{r, 2};
                % 映射到cfg.PV
                switch pname
                    case 'G_std',                cfg.PV.G_std = pval;
                    case 'Pn',                   % Pn是基准容量, 不覆盖capacity
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
            fprintf('  [数据对接] 光伏物理参数已从 pv_params.csv 加载\n');
        catch ME
            fprintf('  [警告] PV参数加载失败: %s\n', ME.message);
        end
    end

    % ========= 加载潮汐参数 =========
    if exist(tidal_params_file, 'file')
        try
            T_tidal = readtable(tidal_params_file);
            for r = 1:height(T_tidal)
                pname = strrep(T_tidal{r, 1}{1}, ' ', '');
                try
                    pval = T_tidal{r, 2};
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
            fprintf('  [数据对接] 潮汐电站参数已从 tidal_params.csv 加载\n');
        catch ME
            fprintf('  [警告] 潮汐参数加载失败: %s\n', ME.message);
        end
    end

    % ========= 回退：未加载CSV时使用合成数据 =========
    if ~csv_loaded
        fprintf('  [回退] 未找到CSV数据，使用合成场景数据\n');
        cfg = generate_synthetic_data(cfg);
    end

    % 可平移负荷基准（始终合成，CSV中没有）
    P_shift_base = zeros(N, Nv);
    for v = 1:Nv
        P_shift_base(:, v) = cfg.Load.shiftable.capacity(v) * 0.8 ...
            * exp(-((t-20)/2).^2);
    end
    cfg.data.shiftable_baseline = P_shift_base;

    % 频率初始偏差（始终小幅噪声）
    rng(400);
    cfg.data.freq_deviation = 0.002 * randn(N, Nv);

    fprintf('全局参数配置完成: %d VPPs, %d 时间步 (dt=%.2f h)\n', ...
            cfg.N_vpp, cfg.N_steps, cfg.dt);
    if csv_loaded
        fprintf('  数据来源: 预测汇总/matlab_input/ (真实模型参数 + 场景数据)\n');
    end
end


function cfg = generate_synthetic_data(cfg)
    % 合成数据回退方案（原 generate_scenario_data 的逻辑）
    N  = cfg.N_steps;
    Nv = cfg.N_vpp;
    t  = cfg.time;

    % 辐照度
    G_peak = [900, 850, 880];
    G = zeros(N, Nv);
    for v = 1:Nv
        G(:, v) = G_peak(v) * max(sin(pi * (t - 6) / 12), 0).^1.5;
        rng(42 + v);
        G(:, v) = G(:, v) .* (1 + 0.1 * randn(N, 1));
        G(:, v) = max(G(:, v), 0);
    end
    cfg.data.irradiance = G;

    % 温度
    T_amb = 23.5 + 8.5 * sin(pi * (t - 8) / 12);
    rng(100);
    T_amb = T_amb + 2 * randn(N, 1);
    cfg.data.temperature = repmat(T_amb, 1, Nv);

    % 风速
    v_mean = [6.5, 7.2, 5.8];
    v_wind = zeros(N, Nv);
    for v = 1:Nv
        rng(200 + v);
        v_lf = v_mean(v) + 2 * sin(pi * (t - 10) / 14);
        v_hf = 1.5 * randn(N, 1);
        alpha = 0.3;
        v_filt = zeros(N, 1);
        v_filt(1) = v_mean(v);
        for k = 2:N
            v_filt(k) = alpha * (v_lf(k) + v_hf(k)) + (1-alpha) * v_filt(k-1);
        end
        v_wind(:, v) = max(v_filt, 0);
    end
    cfg.data.wind_speed = v_wind;

    % 负荷
    P_load = zeros(N, Nv);
    for v = 1:Nv
        P_base = cfg.Load.rigid_peak(v) * 0.5;
        P_morning = cfg.Load.rigid_peak(v) * 0.85 * exp(-((t-10)/3).^2);
        P_evening = cfg.Load.rigid_peak(v) * 1.00 * exp(-((t-18)/3).^2);
        P_midday  = cfg.Load.rigid_peak(v) * 0.60 * exp(-((t-13)/2).^2);
        rng(300 + v);
        P_load(:, v) = P_base + P_morning + P_evening + 0.5 * P_midday + 10 * randn(N, 1);
        P_load(:, v) = max(P_load(:, v), 50);
    end
    cfg.data.load_rigid = P_load;

    % 潮汐（合成）
    cfg.data.tide_height = 3.5 + 2.5 * sin(2*pi*t/12.42) + 1.0 * sin(2*pi*t/24 + 1.5);
end
