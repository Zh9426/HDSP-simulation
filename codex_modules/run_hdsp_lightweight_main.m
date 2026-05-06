%% Lightweight HDSP modular main script
% This script should stay light: choose module versions here, keep algorithm
% details inside each module folder.

clearvars;
clc;

root_dir = fileparts(mfilename('fullpath'));
registry = codex_module_registry(root_dir);

%% Module selection keys

target_model = 1;
% target_model = 1 -> A_letter_edge_blur_0302
% target_model = 2 -> grid_scaffold_circle_current

initial_phase_model = 1;
% initial_phase_model = 1 -> IASA_0211_basic
% initial_phase_model = 0 -> skip initial-phase calculation

phase_board_model = 1;
% phase_board_model = 1 -> phase_to_layers_error_diffusion
% phase_board_model = 0 -> skip phase-board projection

kwave_model = 0;
% kwave_model = 0 -> skip k-Wave simulation
% kwave_model = 1 -> KWAVE_full_pipeline_current legacy profile
% kwave_model = 2 -> KWAVE_full_pipeline_report_snapshot legacy profile

cure_model = 0;
% cure_model = 0 -> skip cure prediction
% cure_model = 1 -> cavitation_V0_trigger_activity_map
% cure_model = 2 -> cavitation_V3_dose_led_score

metrics_model = 0;
% metrics_model = 0 -> skip metrics
% metrics_model = 1 -> PCC_SSIM_IoU_metrics

%% Shared parameters

cfg = struct();
cfg.Nx = 96;
cfg.Lx = 40e-3;
cfg.iasa_epoch = 5;
cfg.phase_step = 2 * pi / 8;
cfg.base_layers = 1;
cfg.exposure_time = 0.04;
cfg.pressure_map = [];

%% Lightweight module links

result = struct();

[result.target, used_paths] = run_target_model(target_model, cfg, registry);
add_selected_paths(used_paths);

if initial_phase_model > 0
    [result.initial_phase, used_paths] = run_initial_phase_model( ...
        initial_phase_model, result.target, cfg, registry);
    add_selected_paths(used_paths);
else
    result.initial_phase = [];
end

if phase_board_model > 0
    [result.phase_board, used_paths] = run_phase_board_model( ...
        phase_board_model, result.initial_phase, result.target, cfg, registry);
    add_selected_paths(used_paths);
else
    result.phase_board = [];
end

if kwave_model > 0
    result.kwave = run_kwave_model(kwave_model, registry);
else
    result.kwave = [];
end

if cure_model > 0
    [result.cure, used_paths] = run_cure_model(cure_model, cfg, registry, result.target);
    add_selected_paths(used_paths);
else
    result.cure = [];
end

if metrics_model > 0
    [result.metrics, used_paths] = run_metrics_model(metrics_model, result, registry);
    add_selected_paths(used_paths);
else
    result.metrics = [];
end

fprintf('HDSP modular main completed: target_model=%d, initial_phase_model=%d, phase_board_model=%d, kwave_model=%d, cure_model=%d, metrics_model=%d\n', ...
    target_model, initial_phase_model, phase_board_model, kwave_model, cure_model, metrics_model);

%% Local dispatchers

function [target, module_paths] = run_target_model(target_model, cfg, registry)
switch target_model
    case 1
        % =1 calls target version 1: A_letter_edge_blur_0302.
        module_paths = {registry.modules.target_pattern.A_letter_edge_blur_0302};
        add_selected_paths(module_paths);
        target = build_target_A_letter_edge_blur_0302(cfg.Nx, cfg.Lx);
    case 2
        % =2 calls target version 2: grid_scaffold_circle_current.
        module_paths = {registry.modules.target_pattern.grid_scaffold_circle_current};
        add_selected_paths(module_paths);
        target = build_hdsp_validation_target(cfg.Nx, cfg.Lx);
        target.name = 'grid_scaffold_circle_current';
    otherwise
        error('Unknown target_model=%d.', target_model);
end
end

function [phase_result, module_paths] = run_initial_phase_model(initial_phase_model, target, cfg, registry)
switch initial_phase_model
    case 1
        % =1 calls initial phase version 1: IASA_0211_basic.
        module_paths = {registry.modules.initial_phase.IASA_0211_basic};
        add_selected_paths(module_paths);
        phase_result = compute_initial_phase_IASA_0211(target.image, struct( ...
            'Lx', target.Lx, ...
            'epoch', cfg.iasa_epoch, ...
            'pad_factor', 2));
    otherwise
        error('Unknown initial_phase_model=%d.', initial_phase_model);
end
end

function [board_result, module_paths] = run_phase_board_model(phase_board_model, phase_result, target, cfg, registry)
if isempty(phase_result)
    error('phase_board_model requires an initial phase result.');
end

switch phase_board_model
    case 1
        % =1 calls phase-board version 1: phase_to_layers_error_diffusion.
        module_paths = {registry.modules.phase_board.phase_to_layers_error_diffusion};
        add_selected_paths(module_paths);
        [phase_projected, layer_map, best_offset] = project_phase_to_board( ...
            phase_result.phase, cfg.phase_step, cfg.base_layers, target.mask, 0, true);
        board_result = struct( ...
            'name', 'phase_to_layers_error_diffusion', ...
            'phase_projected', phase_projected, ...
            'layer_map', layer_map, ...
            'best_offset', best_offset);
    otherwise
        error('Unknown phase_board_model=%d.', phase_board_model);
end
end

function kwave_result = run_kwave_model(kwave_model, registry)
switch kwave_model
    case 1
        % =1 calls k-Wave version 1: KWAVE_full_pipeline_current legacy profile.
        kwave_result = run_legacy_profile(registry.profiles.KWAVE_full_pipeline_current);
    case 2
        % =2 calls k-Wave version 2: KWAVE_full_pipeline_report_snapshot legacy profile.
        kwave_result = run_legacy_profile(registry.profiles.KWAVE_full_pipeline_report_snapshot);
    otherwise
        error('Unknown kwave_model=%d.', kwave_model);
end
end

function [cure_result, module_paths] = run_cure_model(cure_model, cfg, registry, target)
if isempty(cfg.pressure_map)
    error('cure_model requires cfg.pressure_map. Set cure_model=0 until a pressure field module is connected.');
end

switch cure_model
    case 1
        % =1 calls cure version 1: cavitation_V0_trigger_activity_map.
        module_paths = {registry.modules.cure_prediction.cavitation.V0_trigger_activity_map};
        add_selected_paths(module_paths);
        cure_result = compute_cavitation_activity_map(cfg.pressure_map, struct('mask', target.mask));
    case 2
        % =2 calls cure version 2: cavitation_V3_dose_led_score.
        module_paths = {registry.modules.cure_prediction.cavitation.V0_trigger_activity_map, ...
            registry.modules.cure_prediction.cavitation.V2_cloud_consistency_dose, ...
            registry.modules.cure_prediction.cavitation.V3_dose_led_score, ...
            registry.modules.result_metrics.PCC_SSIM_IoU_metrics};
        add_selected_paths(module_paths);
        cure_result = simulate_cure_from_pressure_map( ...
            cfg.pressure_map, cfg.exposure_time, struct('mask', target.mask), target.mask);
    otherwise
        error('Unknown cure_model=%d.', cure_model);
end
end

function [metrics_result, module_paths] = run_metrics_model(metrics_model, result, registry)
switch metrics_model
    case 1
        % =1 calls metrics version 1: PCC_SSIM_IoU_metrics.
        module_paths = {registry.modules.result_metrics.PCC_SSIM_IoU_metrics};
        add_selected_paths(module_paths);
        if isempty(result.cure) || ~isfield(result.cure, 'cure_score')
            error('metrics_model=1 requires result.cure.cure_score.');
        end
        metrics_result = evaluate_cure_prediction( ...
            result.cure.cure_score, result.target.mask, result.cure.threshold);
    otherwise
        error('Unknown metrics_model=%d.', metrics_model);
end
end

function profile_result = run_legacy_profile(profile)
warning('Running legacy profile "%s"; this is not yet a functionized module chain.', profile.name);
run_codex_module_pipeline(profile.name);
profile_result = struct('name', profile.name, 'mode', 'legacy_profile');
end

function add_selected_paths(module_paths)
for idx = 1:numel(module_paths)
    if ~exist(module_paths{idx}, 'dir')
        error('Selected module path does not exist: %s', module_paths{idx});
    end
    addpath(genpath(module_paths{idx}));
end
end
