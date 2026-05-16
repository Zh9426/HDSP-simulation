function phase_result = run_mainline_phase_modes(phase_refine_mode, ctx)
%RUN_MAINLINE_PHASE_MODES Select pure IASA, Python only, or Python + IASA.
mode_now = lower(strtrim(phase_refine_mode));
valid_modes = {'pure_iasa', 'python_only', 'python_iasa'};
if ~any(strcmp(mode_now, valid_modes))
    error('Unsupported phase_refine_mode: %s', phase_refine_mode);
end

cfg = ctx.optimizer_cfg;
target_amp_design = sqrt(max(ctx.imag_target_design, 0));

switch mode_now
    case 'pure_iasa'
        rng(ctx.rng_seed);
        pure_seed = zeros(ctx.Nx, ctx.Ny);
        pure_seed(ctx.source_mask) = 2 * pi * rand(nnz(ctx.source_mask), 1);

        [initial_phase, ~, initial_bias] = project_phase_to_board( ...
            pure_seed, ctx.phase_step, cfg.min_base_layers, ctx.source_mask, 0, true);

        pure_options = struct();
        pure_options.anchor_eta = cfg.iasa_anchor_eta;
        pure_options.use_dither = true;
        pure_options.phase_bias_seed = 0;
        pure_result = run_board_constrained_iasa_phase_optimizer( ...
            pure_seed, target_amp_design, ctx.source_mask, ctx.propagator, cfg, 'Pure IASA', pure_options);

        final_phase = pure_result.phase;
        layer_map = pure_result.layer_map;
        final_bias = pure_result.phase_bias;
        initial_label = 'Pure seed';
        final_label = 'Pure IASA';

    case 'python_only'
        py = load_python_phase_case(ctx);
        initial_phase = py.phase;
        final_phase = py.phase;
        initial_bias = py.phase_bias;
        final_bias = py.phase_bias;
        if isempty(py.layer_map)
            [~, layer_map, final_bias] = project_phase_to_board( ...
                final_phase, ctx.phase_step, cfg.min_base_layers, ctx.source_mask, final_bias, true);
        else
            layer_map = double(py.layer_map);
        end
        initial_label = 'Python';
        final_label = 'Python only';

    case 'python_iasa'
        py = load_python_phase_case(ctx);
        initial_phase = py.phase;
        initial_bias = py.phase_bias;

        py_options = struct();
        py_options.anchor_eta = cfg.iasa_anchor_eta;
        py_options.use_dither = true;
        py_options.phase_bias_seed = py.phase_bias;
        if ~isempty(py.halo_mask)
            py_options.halo_mask = py.halo_mask;
        end

        py_result = run_board_constrained_iasa_phase_optimizer( ...
            py.phase, py.target_amp_design, ctx.source_mask, ctx.propagator, cfg, 'Python + IASA', py_options);

        final_phase = py_result.phase;
        layer_map = py_result.layer_map;
        final_bias = py_result.phase_bias;
        initial_label = 'Python';
        final_label = 'Python + IASA';
end

initial_focus = compute_asm_focus_field(initial_phase, ctx.source_mask, ctx.propagator);
final_focus = compute_asm_focus_field(final_phase, ctx.source_mask, ctx.propagator);

phase_result = struct();
phase_result.initial_phase = wrap_phase(initial_phase);
phase_result.final_phase = wrap_phase(final_phase);
phase_result.layer_map = layer_map;
phase_result.initial_phase_bias = initial_bias;
phase_result.final_phase_bias = final_bias;
phase_result.initial_focus = initial_focus;
phase_result.final_focus = final_focus;
phase_result.initial_label = initial_label;
phase_result.final_label = final_label;
end

function py = load_python_phase_case(ctx)
import_path = fullfile(ctx.transport_dir, 'dl_phase_init.mat');
if ~exist(import_path, 'file')
    error('没有找到 dl_phase_init.mat. 请确保已经算出初相');
end

data = load(import_path);
if ~isfield(data, 'optimal_initial_phase')
    error('Python 输出缺少 optimal_initial_phase: %s', import_path);
end

phase = wrap_phase(double(data.optimal_initial_phase));
phase(~ctx.source_mask) = 0;

py = struct();
py.phase = phase;
py.phase_bias = read_optional_scalar(data, 'optimal_phase_bias', 0);
py.layer_map = read_optional_field(data, 'optimal_layer_map', []);
py.halo_mask = read_optional_field(data, 'halo_target_mask', []);
py.target_amp_design = sqrt(max(read_optional_field(data, 'target_dose_design', ctx.imag_target_design), 0));
end

function value = read_optional_scalar(data, field_name, default_value)
if isfield(data, field_name) && ~isempty(data.(field_name))
    value = double(data.(field_name)(1));
else
    value = default_value;
end
end

function value = read_optional_field(data, field_name, default_value)
if isfield(data, field_name) && ~isempty(data.(field_name))
    value = data.(field_name);
else
    value = default_value;
end
end
