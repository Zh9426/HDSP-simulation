function comparison = compare_initial_phase_history(current_summary, cfg)
%COMPARE_INITIAL_PHASE_HISTORY Compare this run against prior branch outputs.
% The main ranking score is the k-Wave pressure quality score because it
% already combines efficiency, target uniformity, low-percentile pressure,
% and leakage penalties.
comparison = empty_comparison();
comparison.current_commit = cfg.git_commit_short;
comparison.output_root_dir = cfg.output_root_dir;
comparison.ranking_metric = 'target_pressure_quality_score';
comparison.primary_case_label = 'Pure Python';

current_case = find_case_by_label(current_summary.cases, comparison.primary_case_label);
if isempty(current_case)
    comparison.status = 'current_case_missing';
    comparison.recommendation = 'Current Pure Python case was not found; cannot compare history.';
    return;
end

comparison.current = compact_case_record(cfg.git_commit_short, cfg.output_dir, current_case);

records = collect_history_records(cfg, comparison.primary_case_label);
records = append_record(records, comparison.current);
records = sort_records(records);

comparison.leaderboard = records;
comparison.rank = find_record_rank(records, cfg.git_commit_short, cfg.output_dir);
comparison.num_compared_runs = numel(records);

best_record = records(1);
comparison.best = best_record;
comparison.is_new_best = strcmp(best_record.commit, comparison.current.commit) && ...
    strcmp(best_record.output_dir, comparison.current.output_dir);

prior_records = records(~strcmp({records.output_dir}, comparison.current.output_dir));
if isempty(prior_records)
    comparison.status = 'no_prior_baseline';
    comparison.recommendation = 'No prior baseline was found; keep this run as the initial baseline.';
    return;
end

prior_best = prior_records(1);
comparison.prior_best = prior_best;
comparison.delta_vs_prior_best = calculate_delta(comparison.current, prior_best);

if comparison.is_new_best
    comparison.status = 'new_best';
    comparison.recommendation = 'Current run replaces the previous best baseline.';
else
    comparison.status = 'not_best';
    comparison.recommendation = build_optimization_direction(comparison.current, prior_best);
end
end

function comparison = empty_comparison()
comparison = struct();
comparison.status = 'not_evaluated';
comparison.current_commit = '';
comparison.output_root_dir = '';
comparison.ranking_metric = '';
comparison.primary_case_label = '';
comparison.current = struct();
comparison.prior_best = struct();
comparison.best = struct();
comparison.delta_vs_prior_best = struct();
comparison.leaderboard = struct([]);
comparison.rank = NaN;
comparison.num_compared_runs = 0;
comparison.is_new_best = false;
comparison.recommendation = '';
end

function records = collect_history_records(cfg, case_label)
records = struct([]);
summary_files = dir(fullfile(cfg.output_root_dir, '*', 'summary.json'));
for idx = 1:numel(summary_files)
    summary_path = fullfile(summary_files(idx).folder, summary_files(idx).name);
    if strcmp(summary_path, fullfile(cfg.output_dir, 'summary.json'))
        continue;
    end
    try
        raw_text = fileread(summary_path);
        summary_data = jsondecode(raw_text);
    catch
        continue;
    end
    if ~isfield(summary_data, 'cases')
        continue;
    end
    case_now = find_case_by_label(summary_data.cases, case_label);
    if isempty(case_now) || ~isfield(case_now, 'target_pressure_quality_score')
        continue;
    end
    [~, commit_name] = fileparts(summary_files(idx).folder);
    record = compact_case_record(commit_name, summary_files(idx).folder, case_now);
    records = append_record(records, record);
end
end

function case_now = find_case_by_label(cases, label)
case_now = [];
if isempty(cases)
    return;
end
for idx = 1:numel(cases)
    if isfield(cases(idx), 'label') && strcmp(char(cases(idx).label), label)
        case_now = cases(idx);
        return;
    end
end
end

function record = compact_case_record(commit_name, output_dir, case_now)
record = struct();
record.commit = char(commit_name);
record.output_dir = char(output_dir);
record.score = read_metric(case_now, 'target_pressure_quality_score');
record.pcc = read_metric(case_now, 'pcc');
record.energy_efficiency = read_metric(case_now, 'energy_efficiency');
record.target_uniformity_cv = read_metric(case_now, 'target_uniformity_cv');
record.target_p10_over_p50 = read_metric(case_now, 'target_p10_over_p50');
record.target_p95_over_mean = read_metric(case_now, 'target_p95_over_mean');
record.target_peak_over_mean = read_metric(case_now, 'target_peak_over_mean');
record.dark_energy_leakage = read_metric(case_now, 'dark_energy_leakage');
record.mean_target_pressure_pa = read_metric(case_now, 'mean_target_pressure_pa');
record.peak_target_pressure_pa = read_metric(case_now, 'peak_target_pressure_pa');
record.asm_target_pcc = read_metric(case_now, 'asm_target_pcc');
record.optimizer_metrics = struct();
if isfield(case_now, 'optimizer_metrics')
    record.optimizer_metrics = case_now.optimizer_metrics;
end
end

function value = read_metric(case_now, name)
if isfield(case_now, name)
    value = double(case_now.(name));
else
    value = NaN;
end
end

function records = append_record(records, record)
if isempty(records)
    records = record;
else
    records(end + 1) = record;
end
end

function records = sort_records(records)
if isempty(records)
    return;
end
scores = [records.score];
pcc_values = [records.pcc];
cv_values = [records.target_uniformity_cv];
[~, order] = sortrows([-scores(:), -pcc_values(:), cv_values(:)]);
records = records(order);
end

function rank = find_record_rank(records, commit_name, output_dir)
rank = NaN;
for idx = 1:numel(records)
    if strcmp(records(idx).commit, commit_name) && strcmp(records(idx).output_dir, output_dir)
        rank = idx;
        return;
    end
end
end

function delta = calculate_delta(current, baseline)
delta = struct();
fields = {'score', 'pcc', 'energy_efficiency', 'target_uniformity_cv', ...
    'target_p10_over_p50', 'target_p95_over_mean', 'target_peak_over_mean', ...
    'dark_energy_leakage', 'mean_target_pressure_pa', 'peak_target_pressure_pa', ...
    'asm_target_pcc'};
for idx = 1:numel(fields)
    field = fields{idx};
    delta.(field) = current.(field) - baseline.(field);
end
end

function recommendation = build_optimization_direction(current, baseline)
directions = {};
if current.target_uniformity_cv > baseline.target_uniformity_cv
    directions{end + 1} = 'target CV is worse; prioritize target pressure uniformity';
end
if current.target_p10_over_p50 < baseline.target_p10_over_p50
    directions{end + 1} = 'low-percentile pressure is worse; lift weak target pixels';
end
if current.target_peak_over_mean > baseline.target_peak_over_mean
    directions{end + 1} = 'target peak/mean is worse; suppress in-target hot spots';
end
if current.energy_efficiency < baseline.energy_efficiency
    directions{end + 1} = 'energy efficiency is worse; reduce dark-field energy leakage';
end
if current.pcc < baseline.pcc
    directions{end + 1} = 'pattern PCC is worse; recover target shape fidelity';
end
if isempty(directions)
    recommendation = 'Current run is close to the baseline; inspect images and training history for secondary tradeoffs.';
else
    recommendation = strjoin(directions, '; ');
end
end
