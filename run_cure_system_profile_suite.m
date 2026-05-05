function report = run_cure_system_profile_suite()
target = false(48, 48);
target(13:36, 13:36) = true;
dx = 1.0e-4;
system_names = {'water_arrhenius', 'pdms_cavitation', 'sonoink_self_enhancing'};
exposure_time = 0.60;

base_params = build_cure_system_profile('pdms_cavitation', dx);
cases = build_pressure_validation_cases(target, base_params, dx);
case_def = cases(strcmp({cases.name}, 'speckle_nonuniform'));
if isempty(case_def)
    case_def = cases(1);
end

fprintf('\nCure system profile suite\n');
fprintf('case: %s | exposure %.3f s\n', case_def.name, exposure_time);
fprintf('system | mechanism | material | IoU | coverage | over | under | score ROI | Tmax C | quality risk peak\n');

records = repmat(empty_record(), 1, numel(system_names));
simulations = cell(1, numel(system_names));
for idx = 1:numel(system_names)
    params = build_cure_system_profile(system_names{idx}, dx);
    sim = simulate_cure_from_pressure_map( ...
        case_def.pressure_map, exposure_time, params, target);
    simulations{idx} = sim;
    records(idx) = record_from_simulation(params, sim, target);
    fprintf('%s | %s | %s | %.4f | %.1f%% | %.1f%% | %.1f%% | %.4f | %.1f | %.4f\n', ...
        records(idx).system, records(idx).mechanism, records(idx).material, ...
        records(idx).IoU, records(idx).coverage * 100, ...
        records(idx).over_cure * 100, records(idx).under_cure * 100, ...
        records(idx).score_roi_mean, records(idx).Tmax_C, records(idx).quality_risk_peak);
end

report = struct();
report.case = case_def;
report.exposure_time = exposure_time;
report.records = records;
report.simulations = simulations;
end

function record = empty_record()
record = struct( ...
    'system', '', ...
    'mechanism', '', ...
    'material', '', ...
    'IoU', 0, ...
    'Dice', 0, ...
    'coverage', 0, ...
    'over_cure', 0, ...
    'under_cure', 0, ...
    'score_roi_mean', 0, ...
    'Tmax_C', 0, ...
    'quality_risk_peak', 0);
end

function record = record_from_simulation(params, sim, target)
record = empty_record();
record.system = params.model_name;
record.mechanism = params.cure_mechanism;
record.material = params.material;
record.IoU = sim.metrics.IoU;
record.Dice = sim.metrics.Dice;
record.coverage = sim.metrics.cured_coverage;
record.over_cure = sim.metrics.over_cure_ratio;
record.under_cure = sim.metrics.under_cure_ratio;
record.score_roi_mean = mean(sim.cure_score(target));
if isempty(sim.temperature_C)
    record.Tmax_C = NaN;
else
    record.Tmax_C = max(sim.temperature_C(:));
end
record.quality_risk_peak = max(sim.score_components.quality_risk(:));
end
