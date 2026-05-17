function write_phase_pressure_summary(results, txt_path, json_path)
%WRITE_PHASE_PRESSURE_SUMMARY Write compact text and JSON metric reports.
fid = fopen(txt_path, 'w');
if fid < 0
    error('Cannot write summary: %s', txt_path);
end
fprintf(fid, 'Initial phase pressure study\n');
fprintf(fid, 'Created at: %s\n', results.created_at);
fprintf(fid, 'Output directory: %s\n\n', results.cfg.output_dir);
fprintf(fid, 'No curing module is used. Metrics are pressure-amplitude metrics at the best scanned k-Wave plane.\n\n');

summary = struct();
summary.created_at = results.created_at;
summary.output_dir = results.cfg.output_dir;
summary.cases = struct([]);

for idx = 1:numel(results.phase_cases)
    case_now = results.phase_cases(idx);
    m = case_now.kwave.metrics;
    fprintf(fid, '[%s]\n', case_now.label);
    fprintf(fid, 'best_z_offset_mm: %.4f\n', case_now.kwave.best_z_offset_m * 1e3);
    fprintf(fid, 'peak_target_pressure_pa: %.8g\n', m.peak_target_pressure_pa);
    fprintf(fid, 'mean_target_pressure_pa: %.8g\n', m.mean_target_pressure_pa);
    fprintf(fid, 'target_pressure_p05_pa: %.8g\n', m.target_pressure_p05_pa);
    fprintf(fid, 'target_pressure_p10_pa: %.8g\n', m.target_pressure_p10_pa);
    fprintf(fid, 'target_pressure_p50_pa: %.8g\n', m.target_pressure_p50_pa);
    fprintf(fid, 'target_pressure_p90_pa: %.8g\n', m.target_pressure_p90_pa);
    fprintf(fid, 'target_pressure_p95_pa: %.8g\n', m.target_pressure_p95_pa);
    fprintf(fid, 'target_uniformity_cv: %.6f\n', m.target_uniformity_cv);
    fprintf(fid, 'target_p05_over_p50: %.6f\n', m.target_p05_over_p50);
    fprintf(fid, 'target_p10_over_p50: %.6f\n', m.target_p10_over_p50);
    fprintf(fid, 'target_p90_over_mean: %.6f\n', m.target_p90_over_mean);
    fprintf(fid, 'target_p95_over_mean: %.6f\n', m.target_p95_over_mean);
    fprintf(fid, 'target_peak_over_mean: %.6f\n', m.target_peak_over_mean);
    fprintf(fid, 'target_pressure_quality_score: %.6f\n', m.target_pressure_quality_score);
    fprintf(fid, 'focus_contrast: %.6f\n', m.focus_contrast);
    fprintf(fid, 'energy_efficiency: %.6f\n', m.energy_efficiency);
    fprintf(fid, 'target_energy_uniformity_score: %.6f\n', m.target_energy_uniformity_score);
    fprintf(fid, 'dark_energy_leakage: %.6f\n', m.dark_energy_leakage);
    fprintf(fid, 'peak_sidelobe_ratio: %.6f\n', m.peak_sidelobe_ratio);
    fprintf(fid, 'target_pressure_coverage_50: %.6f\n', m.target_pressure_coverage_50);
    fprintf(fid, 'target_pressure_coverage_70: %.6f\n', m.target_pressure_coverage_70);
    fprintf(fid, 'pcc: %.6f\n', m.pcc);
    fprintf(fid, 'nmse: %.6f\n\n', m.nmse);

    pm = case_now.phase_metrics;
    fprintf(fid, 'phase_circular_variance: %.6f\n', pm.phase_circular_variance);
    fprintf(fid, 'phase_gradient_mean_rad: %.6f\n', pm.phase_gradient_mean_rad);
    fprintf(fid, 'phase_gradient_p90_rad: %.6f\n', pm.phase_gradient_p90_rad);
    fprintf(fid, 'phase_wrap_fraction: %.6f\n', pm.phase_wrap_fraction);
    fprintf(fid, 'asm_target_pcc: %.6f\n', pm.asm_target_pcc);
    fprintf(fid, 'asm_nmse: %.6f\n\n', pm.asm_nmse);

    summary.cases(idx).label = case_now.label;
    summary.cases(idx).best_z_offset_mm = case_now.kwave.best_z_offset_m * 1e3;
    summary.cases(idx).peak_target_pressure_pa = m.peak_target_pressure_pa;
    summary.cases(idx).mean_target_pressure_pa = m.mean_target_pressure_pa;
    summary.cases(idx).target_pressure_p05_pa = m.target_pressure_p05_pa;
    summary.cases(idx).target_pressure_p10_pa = m.target_pressure_p10_pa;
    summary.cases(idx).target_pressure_p50_pa = m.target_pressure_p50_pa;
    summary.cases(idx).target_pressure_p90_pa = m.target_pressure_p90_pa;
    summary.cases(idx).target_pressure_p95_pa = m.target_pressure_p95_pa;
    summary.cases(idx).target_uniformity_cv = m.target_uniformity_cv;
    summary.cases(idx).target_p05_over_p50 = m.target_p05_over_p50;
    summary.cases(idx).target_p10_over_p50 = m.target_p10_over_p50;
    summary.cases(idx).target_p90_over_mean = m.target_p90_over_mean;
    summary.cases(idx).target_p95_over_mean = m.target_p95_over_mean;
    summary.cases(idx).target_peak_over_mean = m.target_peak_over_mean;
    summary.cases(idx).target_pressure_quality_score = m.target_pressure_quality_score;
    summary.cases(idx).focus_contrast = m.focus_contrast;
    summary.cases(idx).energy_efficiency = m.energy_efficiency;
    summary.cases(idx).target_energy_uniformity_score = m.target_energy_uniformity_score;
    summary.cases(idx).dark_energy_leakage = m.dark_energy_leakage;
    summary.cases(idx).peak_sidelobe_ratio = m.peak_sidelobe_ratio;
    summary.cases(idx).target_pressure_coverage_50 = m.target_pressure_coverage_50;
    summary.cases(idx).target_pressure_coverage_70 = m.target_pressure_coverage_70;
    summary.cases(idx).pcc = m.pcc;
    summary.cases(idx).nmse = m.nmse;
    summary.cases(idx).phase_circular_variance = pm.phase_circular_variance;
    summary.cases(idx).phase_gradient_mean_rad = pm.phase_gradient_mean_rad;
    summary.cases(idx).phase_gradient_p90_rad = pm.phase_gradient_p90_rad;
    summary.cases(idx).phase_wrap_fraction = pm.phase_wrap_fraction;
    summary.cases(idx).asm_target_pcc = pm.asm_target_pcc;
    summary.cases(idx).asm_nmse = pm.asm_nmse;
    if isfield(case_now, 'optimizer_metrics')
        summary.cases(idx).optimizer_metrics = case_now.optimizer_metrics;
    end
end
fclose(fid);

fid_json = fopen(json_path, 'w');
if fid_json < 0
    error('Cannot write JSON summary: %s', json_path);
end
fwrite(fid_json, jsonencode(summary, 'PrettyPrint', true));
fclose(fid_json);
end