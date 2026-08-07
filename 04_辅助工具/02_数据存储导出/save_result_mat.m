% ============================================================
% 文件名：save_result_mat.m
% 功能：保存全部时序数据和指标为MAT文件
% 所属项目：去中心化虚拟电厂协同自治调控仿真系统
% 开发环境：MATLAB R2023b
%
% 知识产权声明：
%   辅助工具/主控脚本，不包含核心算法创新。
%   版权所有归属项目团队。
% ============================================================

function save_result_mat(results, filename)
    % 保存仿真结果到.mat文件
    %
    % 输入:
    %   results  - 仿真结果结构体
    %   filename - 输出文件名 (可选), 默认 'results_island.mat'

    if nargin < 2
        filename = 'results_island.mat';
    end

    % 确保.mat扩展名
    [~, ~, ext] = fileparts(filename);
    if ~strcmp(ext, '.mat')
        filename = [filename, '.mat'];
    end

    % 提取关键变量（便于直接load使用）
    hist = results.hist;
    eco  = results.eco_index;
    cfg  = results.cfg;
    alarms = results.alarms;

    save(filename, 'hist', 'eco', 'cfg', 'alarms', 'results', '-v7.3');

    fprintf('  结果已保存至: %s\n', fullfile(pwd, filename));
end
