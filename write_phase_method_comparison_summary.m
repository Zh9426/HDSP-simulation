function summary = write_phase_method_comparison_summary(results, txt_path, json_path, csv_path)
%WRITE_PHASE_METHOD_COMPARISON_SUMMARY Write six-method comparison reports.
summary = struct();
summary.created_at = results.created_at;
summary.output_dir = results.cfg.output_dir;
summary.git_commit_short = results.cfg.git_commit_short;
summary.ranking_metric = 'target_pressure_quality_score';
summary.cases = struct([]);

fid = fopen(txt_path, 'w');
if fid < 0
    error('Cannot write summary: %s', txt_path);
end
fprintf(fid, 'Initial phase method comparison\n');
fprintf(fid, 'Created at: %s\n', results.created_at);
fprintf(fid, 'Output directory: %s\n', results.cfg.output_dir);
fprintf(fid, 'IASA epochs: %d\n\n', results.cfg.iasa_epochs);

rows = cell(numel(results.phase_cases) + 1, 16);
rows(1, :) = {'label', 'best_z_offset_mm', 'quality_score', 'mean_target_pressure_pa', ...
    'peak_target_pressure_pa', 'target_cv', 'p10_over_p50', 'p05_over_p50', ...
    'peak_over_mean', 'energy_efficiency', 'dark_energy_leakage', 'pcc', 'nmse', ...
    'asm_pcc', 'optimizer_selected_epoch', 'optimizer_best_loop_quality_score'};

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
    fprintf(fid, 'target_p10_over_p50: %.6f\n', km.target_p10_over_p50);
    fprintf(fid, 'target_peak_over_mean: %.6f\n', km.target_peak_over_mean);
    fprintf(fid, 'energy_efficiency: %.6f\n', km.energy_efficiency);
    fprintf(fid, 'dark_energy_leakage: %.6f\n', km.dark_energy_leakage);
    fprintf(fid, 'pcc: %.6f\n', km.pcc);
    fprintf(fid, 'nmse: %.6f\n', km.nmse);
    fprintf(fid, 'asm_target_pcc: %.6f\n', pm.asm_target_pcc);
    fprintf(fid, 'optimizer_selected_epoch: %.0f\n', selected_epoch);
    fprintf(fid, 'optimizer_best_loop_quality_score: %.6f\n\n', best_loop_quality);

    summary.cases(idx).label = case_now.label;
    summary.cases(idx).best_z_offset_mm = case_now.kwave.best_z_offset_m * 1e3;
    summary.cases(idx).target_pressure_quality_score = km.target_pressure_quality_score;
    summary.cases(idx).mean_target_pressure_pa = km.mean_target_pressure_pa;
    summary.cases(idx).peak_target_pressure_pa = km.peak_target_pressure_pa;
    summary.cases(idx).target_uniformity_cv = km.target_uniformity_cv;
    summary.cases(idx).target_p10_over_p50 = km.target_p10_over_p50;
    summary.cases(idx).target_p05_over_p50 = km.target_p05_over_p50;
    summary.cases(idx).target_peak_over_mean = km.target_peak_over_mean;
    summary.cases(idx).energy_efficiency = km.energy_efficiency;
    summary.cases(idx).dark_energy_leakage = km.dark_energy_leakage;
    summary.cases(idx).pcc = km.pcc;
    summary.cases(idx).nmse = km.nmse;
    summary.cases(idx).asm_target_pcc = pm.asm_target_pcc;
    summary.cases(idx).optimizer_selected_epoch = selected_epoch;
    summary.cases(idx).optimizer_best_loop_quality_score = best_loop_quality;
    if isfield(case_now, 'optimizer_metrics')
        summary.cases(idx).optimizer_metrics = case_now.optimizer_metrics;
    end

    rows(idx + 1, :) = {case_now.label, case_now.kwave.best_z_offset_m * 1e3, ...
        km.target_pressure_quality_score, km.mean_target_pressure_pa, ...
        km.peak_target_pressure_pa, km.target_uniformity_cv, km.target_p10_over_p50, ...
        km.target_p05_over_p50, km.target_peak_over_mean, km.energy_efficiency, ...
        km.dark_energy_leakage, km.pcc, km.nmse, pm.asm_target_pcc, ...
        selected_epoch, best_loop_quality};
end

scores = arrayfun(@(c) c.target_pressure_quality_score, summary.cases);
[~, order] = sort(scores, 'descend');
summary.ranking = summary.cases(order);
fprintf(fid, '[Ranking]\n');
for rank_idx = 1:numel(order)
    case_now = summary.cases(order(rank_idx));
    fprintf(fid, '%d. %s | score %.6f | CV %.4f | P10/P50 %.4f | EE %.2f%%\n', ...
        rank_idx, case_now.label, case_now.target_pressure_quality_score, ...
        case_now.target_uniformity_cv, case_now.target_p10_over_p50, ...
        case_now.energy_efficiency * 100);
end
fclose(fid);

fid_json = fopen(json_path, 'w');
if fid_json < 0
    error('Cannot write JSON summary: %s', json_path);
end
fwrite(fid_json, jsonencode(summary, 'PrettyPrint', true));
fclose(fid_json);

writecell(rows, csv_path);
end
