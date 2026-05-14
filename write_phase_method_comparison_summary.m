function summary = write_phase_method_comparison_summary(results, txt_path, json_path, csv_path)
%WRITE_PHASE_METHOD_COMPARISON_SUMMARY Write six-method comparison reports.
summary = struct();
summary.created_at = results.created_at;
summary.output_dir = results.cfg.output_dir;
summary.git_commit_short = results.cfg.git_commit_short;
summary.ranking_metric = 'target_pressure_quality_score';
if isfield(results.cfg, 'method_case_mode')
    summary.method_case_mode = results.cfg.method_case_mode;
end
summary.cases = struct([]);

fid = fopen(txt_path, 'w');
if fid < 0
    error('Cannot write summary: %s', txt_path);
end
fprintf(fid, 'Initial phase method comparison\n');
fprintf(fid, 'Created at: %s\n', results.created_at);
fprintf(fid, 'Output directory: %s\n', results.cfg.output_dir);
if isfield(results.cfg, 'method_case_mode')
    fprintf(fid, 'Case mode: %s\n', results.cfg.method_case_mode);
end
fprintf(fid, 'IASA epochs: %d\n\n', results.cfg.iasa_epochs);

rows = cell(numel(results.phase_cases) + 1, 34);
rows(1, :) = {'label', 'best_z_offset_mm', 'quality_score', 'mean_target_pressure_pa', ...
    'peak_target_pressure_pa', 'target_cv', 'p10_over_p50', 'p05_over_p50', ...
    'p25_over_p50', 'p75_over_p50', 'p75_over_p25', 'p90_over_p10', ...
    'p95_over_p05', 'band_10_fraction', 'band_15_fraction', 'band_20_fraction', ...
    'below_70_p50_fraction', 'above_130_p50_fraction', 'peak_over_mean', ...
    'dark_p99_over_target_p50', 'dark_peak_over_target_p50', ...
    'dark_high_area_fraction', 'dark_above_target_p10_fraction', ...
    'dark_above_target_p50_fraction', 'dark_mean_over_target_mean', ...
    'energy_efficiency', 'dark_energy_leakage', 'pcc', 'nmse', ...
    'asm_pcc', 'asm_nmse', 'asm_minus_kwave_pcc', ...
    'optimizer_selected_epoch', 'optimizer_best_loop_quality_score'};

for idx = 1:numel(results.phase_cases)
    case_now = results.phase_cases(idx);
    km = case_now.kwave.metrics;
    pm = case_now.phase_metrics;
    om = struct();
    if isfield(case_now, 'optimizer_metrics')
        om = case_now.optimizer_metrics;
    end

    selected_epoch = NaN;
    best_loop_quality = NaN;
    if isfield(om, 'selected_epoch')
        selected_epoch = double(om.selected_epoch);
    end
    if isfield(om, 'best_loop_quality_score')
        best_loop_quality = double(om.best_loop_quality_score);
    end

    fprintf(fid, '[%s]\n', case_now.label);
    fprintf(fid, 'best_z_offset_mm: %.4f\n', case_now.kwave.best_z_offset_m * 1e3);
    fprintf(fid, 'target_pressure_quality_score: %.6f\n', km.target_pressure_quality_score);
    fprintf(fid, 'mean_target_pressure_pa: %.8g\n', km.mean_target_pressure_pa);
    fprintf(fid, 'peak_target_pressure_pa: %.8g\n', km.peak_target_pressure_pa);
    fprintf(fid, 'target_uniformity_cv: %.6f\n', km.target_uniformity_cv);
    fprintf(fid, 'target_p05_over_p50: %.6f\n', km.target_p05_over_p50);
    fprintf(fid, 'target_p10_over_p50: %.6f\n', km.target_p10_over_p50);
    fprintf(fid, 'target_p25_over_p50: %.6f\n', km.target_p25_over_p50);
    fprintf(fid, 'target_p75_over_p50: %.6f\n', km.target_p75_over_p50);
    fprintf(fid, 'target_p75_over_p25: %.6f\n', km.target_p75_over_p25);
    fprintf(fid, 'target_p90_over_p10: %.6f\n', km.target_p90_over_p10);
    fprintf(fid, 'target_p95_over_p05: %.6f\n', km.target_p95_over_p05);
    fprintf(fid, 'target_band_10_fraction: %.6f\n', km.target_band_10_fraction);
    fprintf(fid, 'target_band_15_fraction: %.6f\n', km.target_band_15_fraction);
    fprintf(fid, 'target_band_20_fraction: %.6f\n', km.target_band_20_fraction);
    fprintf(fid, 'target_below_70_p50_fraction: %.6f\n', km.target_below_70_p50_fraction);
    fprintf(fid, 'target_above_130_p50_fraction: %.6f\n', km.target_above_130_p50_fraction);
    fprintf(fid, 'target_peak_over_mean: %.6f\n', km.target_peak_over_mean);
    fprintf(fid, 'dark_p99_over_target_p50: %.6f\n', km.dark_p99_over_target_p50);
    fprintf(fid, 'dark_peak_over_target_p50: %.6f\n', km.dark_peak_over_target_p50);
    fprintf(fid, 'dark_high_area_fraction: %.6f\n', km.dark_high_area_fraction);
    fprintf(fid, 'dark_above_target_p10_fraction: %.6f\n', km.dark_above_target_p10_fraction);
    fprintf(fid, 'dark_above_target_p50_fraction: %.6f\n', km.dark_above_target_p50_fraction);
    fprintf(fid, 'dark_mean_over_target_mean: %.6f\n', km.dark_mean_over_target_mean);
    fprintf(fid, 'energy_efficiency: %.6f\n', km.energy_efficiency);
    fprintf(fid, 'dark_energy_leakage: %.6f\n', km.dark_energy_leakage);
    fprintf(fid, 'pcc: %.6f\n', km.pcc);
    fprintf(fid, 'nmse: %.6f\n', km.nmse);
    fprintf(fid, 'asm_target_pcc: %.6f\n', pm.asm_target_pcc);
    fprintf(fid, 'asm_nmse: %.6f\n', pm.asm_nmse);
    fprintf(fid, 'asm_minus_kwave_pcc: %.6f\n', pm.asm_target_pcc - km.pcc);
    fprintf(fid, 'optimizer_selected_epoch: %.0f\n', selected_epoch);
    fprintf(fid, 'optimizer_best_loop_quality_score: %.6f\n\n', best_loop_quality);
    if isfield(om, 'python_metrics') && isstruct(om.python_metrics)
        py = om.python_metrics;
        fprintf(fid, 'python_internal_selected_epoch: %.0f\n', read_metric(py, 'selected_epoch'));
        fprintf(fid, 'python_internal_quality_score: %.6f\n', read_metric(py, 'best_quality_score'));
        fprintf(fid, 'python_internal_amplitude_corr: %.6f\n', read_metric(py, 'amplitude_corr'));
        fprintf(fid, 'python_internal_energy_efficiency: %.6f\n', read_metric(py, 'energy_efficiency'));
        fprintf(fid, 'python_internal_target_cv: %.6f\n', read_metric(py, 'target_uniformity_cv'));
        fprintf(fid, 'python_internal_p10_over_p50: %.6f\n', read_metric(py, 'target_p10_over_p50'));
        fprintf(fid, 'python_internal_p75_over_p25: %.6f\n', read_metric(py, 'target_p75_over_p25'));
        fprintf(fid, 'python_internal_p90_over_p10: %.6f\n', read_metric(py, 'target_p90_over_p10'));
        fprintf(fid, 'python_internal_p95_over_p05: %.6f\n', read_metric(py, 'target_p95_over_p05'));
        fprintf(fid, 'python_internal_band_spread_loss: %.6f\n', read_metric(py, 'target_band_spread_loss'));
        fprintf(fid, 'python_internal_peak_over_mean: %.6f\n', read_metric(py, 'target_peak_over_mean'));
        fprintf(fid, 'python_internal_dark_p99_over_target_p50: %.6f\n', read_metric(py, 'dark_p99_over_target_p50'));
        fprintf(fid, 'python_internal_dark_peak_over_target_p50: %.6f\n', read_metric(py, 'dark_peak_over_target_p50'));
        fprintf(fid, 'python_to_kwave_delta_cv: %.6f\n', km.target_uniformity_cv - read_metric(py, 'target_uniformity_cv'));
        fprintf(fid, 'python_to_kwave_delta_p10_over_p50: %.6f\n', km.target_p10_over_p50 - read_metric(py, 'target_p10_over_p50'));
        fprintf(fid, 'python_to_kwave_delta_peak_over_mean: %.6f\n\n', km.target_peak_over_mean - read_metric(py, 'target_peak_over_mean'));
    end

    summary.cases(idx).label = case_now.label;
    summary.cases(idx).best_z_offset_mm = case_now.kwave.best_z_offset_m * 1e3;
    summary.cases(idx).target_pressure_quality_score = km.target_pressure_quality_score;
    summary.cases(idx).mean_target_pressure_pa = km.mean_target_pressure_pa;
    summary.cases(idx).peak_target_pressure_pa = km.peak_target_pressure_pa;
    summary.cases(idx).target_uniformity_cv = km.target_uniformity_cv;
    summary.cases(idx).target_p10_over_p50 = km.target_p10_over_p50;
    summary.cases(idx).target_p05_over_p50 = km.target_p05_over_p50;
    summary.cases(idx).target_p25_over_p50 = km.target_p25_over_p50;
    summary.cases(idx).target_p75_over_p50 = km.target_p75_over_p50;
    summary.cases(idx).target_p75_over_p25 = km.target_p75_over_p25;
    summary.cases(idx).target_p90_over_p10 = km.target_p90_over_p10;
    summary.cases(idx).target_p95_over_p05 = km.target_p95_over_p05;
    summary.cases(idx).target_band_10_fraction = km.target_band_10_fraction;
    summary.cases(idx).target_band_15_fraction = km.target_band_15_fraction;
    summary.cases(idx).target_band_20_fraction = km.target_band_20_fraction;
    summary.cases(idx).target_below_70_p50_fraction = km.target_below_70_p50_fraction;
    summary.cases(idx).target_above_130_p50_fraction = km.target_above_130_p50_fraction;
    summary.cases(idx).target_peak_over_mean = km.target_peak_over_mean;
    summary.cases(idx).dark_p99_over_target_p50 = km.dark_p99_over_target_p50;
    summary.cases(idx).dark_peak_over_target_p50 = km.dark_peak_over_target_p50;
    summary.cases(idx).dark_high_area_fraction = km.dark_high_area_fraction;
    summary.cases(idx).dark_above_target_p10_fraction = km.dark_above_target_p10_fraction;
    summary.cases(idx).dark_above_target_p50_fraction = km.dark_above_target_p50_fraction;
    summary.cases(idx).dark_mean_over_target_mean = km.dark_mean_over_target_mean;
    summary.cases(idx).energy_efficiency = km.energy_efficiency;
    summary.cases(idx).dark_energy_leakage = km.dark_energy_leakage;
    summary.cases(idx).pcc = km.pcc;
    summary.cases(idx).nmse = km.nmse;
    summary.cases(idx).asm_target_pcc = pm.asm_target_pcc;
    summary.cases(idx).asm_nmse = pm.asm_nmse;
    summary.cases(idx).asm_minus_kwave_pcc = pm.asm_target_pcc - km.pcc;
    summary.cases(idx).optimizer_selected_epoch = selected_epoch;
    summary.cases(idx).optimizer_best_loop_quality_score = best_loop_quality;
    if isfield(case_now, 'optimizer_metrics')
        summary.cases(idx).optimizer_metrics = case_now.optimizer_metrics;
        if isfield(case_now.optimizer_metrics, 'python_metrics') && isstruct(case_now.optimizer_metrics.python_metrics)
            py = case_now.optimizer_metrics.python_metrics;
            summary.cases(idx).python_internal = struct( ...
                'selected_epoch', read_metric(py, 'selected_epoch'), ...
                'best_quality_score', read_metric(py, 'best_quality_score'), ...
                'amplitude_corr', read_metric(py, 'amplitude_corr'), ...
                'energy_efficiency', read_metric(py, 'energy_efficiency'), ...
                'target_uniformity_cv', read_metric(py, 'target_uniformity_cv'), ...
                'target_p10_over_p50', read_metric(py, 'target_p10_over_p50'), ...
                'target_p75_over_p25', read_metric(py, 'target_p75_over_p25'), ...
                'target_p90_over_p10', read_metric(py, 'target_p90_over_p10'), ...
                'target_p95_over_p05', read_metric(py, 'target_p95_over_p05'), ...
                'target_band_spread_loss', read_metric(py, 'target_band_spread_loss'), ...
                'target_peak_over_mean', read_metric(py, 'target_peak_over_mean'), ...
                'dark_p99_over_target_p50', read_metric(py, 'dark_p99_over_target_p50'), ...
                'dark_peak_over_target_p50', read_metric(py, 'dark_peak_over_target_p50'), ...
                'delta_cv_to_kwave', km.target_uniformity_cv - read_metric(py, 'target_uniformity_cv'), ...
                'delta_p10_over_p50_to_kwave', km.target_p10_over_p50 - read_metric(py, 'target_p10_over_p50'), ...
                'delta_peak_over_mean_to_kwave', km.target_peak_over_mean - read_metric(py, 'target_peak_over_mean'));
        end
    end

    rows(idx + 1, :) = {case_now.label, case_now.kwave.best_z_offset_m * 1e3, ...
        km.target_pressure_quality_score, km.mean_target_pressure_pa, ...
        km.peak_target_pressure_pa, km.target_uniformity_cv, km.target_p10_over_p50, ...
        km.target_p05_over_p50, km.target_p25_over_p50, km.target_p75_over_p50, ...
        km.target_p75_over_p25, km.target_p90_over_p10, km.target_p95_over_p05, ...
        km.target_band_10_fraction, km.target_band_15_fraction, km.target_band_20_fraction, ...
        km.target_below_70_p50_fraction, km.target_above_130_p50_fraction, ...
        km.target_peak_over_mean, km.dark_p99_over_target_p50, ...
        km.dark_peak_over_target_p50, km.dark_high_area_fraction, ...
        km.dark_above_target_p10_fraction, km.dark_above_target_p50_fraction, ...
        km.dark_mean_over_target_mean, km.energy_efficiency, ...
        km.dark_energy_leakage, km.pcc, km.nmse, pm.asm_target_pcc, pm.asm_nmse, ...
        pm.asm_target_pcc - km.pcc, ...
        selected_epoch, best_loop_quality};
end

scores = arrayfun(@(c) c.target_pressure_quality_score, summary.cases);
[~, order] = sort(scores, 'descend');
summary.ranking = summary.cases(order);
fprintf(fid, '[Ranking]\n');
for rank_idx = 1:numel(order)
    case_now = summary.cases(order(rank_idx));
    fprintf(fid, '%d. %s | score %.6f | CV %.4f | P10/P50 %.4f | DarkP99/P50 %.3f | EE %.2f%%\n', ...
        rank_idx, case_now.label, case_now.target_pressure_quality_score, ...
        case_now.target_uniformity_cv, case_now.target_p10_over_p50, ...
        case_now.dark_p99_over_target_p50, case_now.energy_efficiency * 100);
end
fclose(fid);

fid_json = fopen(json_path, 'w');
if fid_json < 0
    error('Cannot write JSON summary: %s', json_path);
end
fwrite(fid_json, jsonencode(summary, 'PrettyPrint', true));
fclose(fid_json);

writecell(rows, csv_path);
write_metric_guide(fullfile(results.cfg.output_dir, 'method_metrics_guide.txt'));
end

function value = read_metric(data, field_name)
if isstruct(data) && isfield(data, field_name) && ~isempty(data.(field_name))
    value = double(data.(field_name)(1));
else
    value = NaN;
end
end

function write_metric_guide(guide_path)
fid = fopen(guide_path, 'w');
if fid < 0
    error('Cannot write metric guide: %s', guide_path);
end
cleanup_obj = onCleanup(@() fclose(fid));
fprintf(fid, 'Initial phase method metrics guide\n');
fprintf(fid, 'The main objective is a narrow, uniform pressure distribution inside the target.\n');
fprintf(fid, 'Energy efficiency is diagnostic only for Python-focused runs; lower EE is acceptable if target pressure quality improves.\n\n');
fprintf(fid, 'Target pressure distribution\n');
fprintf(fid, '  target_cv: std(target pressure) / mean(target pressure). Lower means more uniform.\n');
fprintf(fid, '  p05_over_p50, p10_over_p50: low-tail pressure relative to median. Closer to 1 means fewer weak target pixels.\n');
fprintf(fid, '  p25_over_p50, p75_over_p50, p75_over_p25: interquartile spread around the median. Closer to 1 means a tighter target band.\n');
fprintf(fid, '  p90_over_p10, p95_over_p05: wide percentile spread. Lower means fewer weak/overbright extremes.\n');
fprintf(fid, '  band_10_fraction, band_15_fraction, band_20_fraction: fraction of target pixels within +/-10%%, +/-15%%, +/-20%% of the target median. Higher is better.\n');
fprintf(fid, '  below_70_p50_fraction: fraction of target pixels below 70%% of median. Lower means fewer underpowered zones.\n');
fprintf(fid, '  above_130_p50_fraction: fraction of target pixels above 130%% of median. Lower means fewer overpowered target zones.\n');
fprintf(fid, '  peak_over_mean: max target pressure / mean target pressure. Lower means fewer target hot spots.\n\n');
fprintf(fid, 'Background leakage\n');
fprintf(fid, '  dark_p99_over_target_p50: 99th percentile background pressure / target median. Tracks broad high background.\n');
fprintf(fid, '  dark_peak_over_target_p50: max background pressure / target median. Tracks isolated bright spots.\n');
fprintf(fid, '  dark_high_area_fraction: area fraction of background above the configured high-background threshold.\n');
fprintf(fid, '  dark_above_target_p10_fraction: background area above target P10. Lower means cleaner target/background separation.\n');
fprintf(fid, '  dark_above_target_p50_fraction: background area above target median. Should stay near zero.\n');
fprintf(fid, '  dark_mean_over_target_mean: mean background pressure / mean target pressure. Lower is better.\n\n');
fprintf(fid, 'Global shape and propagation consistency\n');
fprintf(fid, '  pcc: k-Wave pressure map correlation with the target mask. Higher is better but can miss local uniformity issues.\n');
fprintf(fid, '  nmse: normalized mean squared error against the target mask. Lower is better.\n');
fprintf(fid, '  asm_pcc, asm_nmse: same metrics before k-Wave, using ASM reconstruction.\n');
fprintf(fid, '  asm_minus_kwave_pcc: ASM PCC - k-Wave PCC. Large positive values indicate propagation/model mismatch.\n');
fprintf(fid, '  energy_efficiency: target-region energy / total plane energy. Diagnostic only when the design intentionally dumps energy outside the target.\n');
fprintf(fid, '  dark_energy_leakage: non-target energy / total plane energy.\n\n');
fprintf(fid, 'Python optimizer diagnostics\n');
fprintf(fid, '  optimizer_selected_epoch: Python-selected best epoch imported into MATLAB.\n');
fprintf(fid, '  optimizer_best_loop_quality_score: best optimizer-loop quality score when available.\n');
fprintf(fid, '  python_internal_*: metrics computed by the Python ASM optimizer before k-Wave validation.\n');
fprintf(fid, '  python_to_kwave_delta_*: k-Wave metric minus Python internal metric. Large deltas mean Python optimization did not transfer well to k-Wave.\n');
end
