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
    fprintf(fid, 'target_uniformity_cv: %.6f\n', m.target_uniformity_cv);
    fprintf(fid, 'focus_contrast: %.6f\n', m.focus_contrast);
    fprintf(fid, 'energy_efficiency: %.6f\n', m.energy_efficiency);
    fprintf(fid, 'pcc: %.6f\n', m.pcc);
    fprintf(fid, 'nmse: %.6f\n\n', m.nmse);

    summary.cases(idx).label = case_now.label;
    summary.cases(idx).best_z_offset_mm = case_now.kwave.best_z_offset_m * 1e3;
    summary.cases(idx).peak_target_pressure_pa = m.peak_target_pressure_pa;
    summary.cases(idx).mean_target_pressure_pa = m.mean_target_pressure_pa;
    summary.cases(idx).target_uniformity_cv = m.target_uniformity_cv;
    summary.cases(idx).focus_contrast = m.focus_contrast;
    summary.cases(idx).energy_efficiency = m.energy_efficiency;
    summary.cases(idx).pcc = m.pcc;
    summary.cases(idx).nmse = m.nmse;
end
fclose(fid);

fid_json = fopen(json_path, 'w');
if fid_json < 0
    error('Cannot write JSON summary: %s', json_path);
end
fwrite(fid_json, jsonencode(summary, 'PrettyPrint', true));
fclose(fid_json);
end
