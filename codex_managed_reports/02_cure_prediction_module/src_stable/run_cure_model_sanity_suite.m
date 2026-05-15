function report = run_cure_model_sanity_suite()
target = false(48, 48);
target(13:36, 13:36) = true;
dx = 1.0e-4;
params = default_cure_model_params(dx);

cases = build_pressure_validation_cases(target, params, dx);
[records, simulations] = evaluate_cure_validation_cases(cases, 0.06, params, target);

gradient_pressure = pressure_case(target, 1.85e6, 1.20e6);
gradient_pressure(target) = linspace(1.85e6, 2.25e6, nnz(target));
short_run = simulate_cure_from_pressure_map(gradient_pressure, 0.02, params, target);
long_run = simulate_cure_from_pressure_map(gradient_pressure, 0.10, params, target);

fprintf('\nCure model sanity suite\n');
fprintf('case | exposure s | IoU | coverage | over | under | cav dose ROI | thermal ROI/bg | quality risk ROI/peak\n');
for idx = 1:numel(records)
    r = records(idx);
    fprintf('%s | %.3f | %.4f | %.1f%% | %.1f%% | %.1f%% | %.4f | %.4f/%.4f | %.4f/%.4f\n', ...
        r.name, r.exposure_time, r.IoU, r.coverage * 100, ...
        r.over_cure * 100, r.under_cure * 100, ...
        r.cavitation_dose_roi_mean, r.thermal_dose_roi_mean, ...
        r.thermal_dose_background_mean, r.quality_risk_roi_mean, ...
        r.quality_risk_peak);
end
fprintf('monotonic_exposure | %.3f -> %.3f s | coverage %.1f%% -> %.1f%% | mean score %.4f -> %.4f\n', ...
    short_run.exposure_time, long_run.exposure_time, ...
    short_run.metrics.cured_coverage * 100, long_run.metrics.cured_coverage * 100, ...
    mean(short_run.cure_score(target)), mean(long_run.cure_score(target)));

report = struct();
report.records = records;
report.simulations = simulations;
report.short_exposure = short_run;
report.long_exposure = long_run;
end

function p_amp = pressure_case(target, target_pressure, background_pressure)
p_amp = ones(size(target)) .* background_pressure;
p_amp(target) = target_pressure;
end
