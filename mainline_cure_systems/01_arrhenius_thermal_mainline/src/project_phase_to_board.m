function [phase_projected, layer_map_best, best_offset] = project_phase_to_board(phase_in, phase_step, base_layers, mask, offset_seed, use_dither)
phase_wrapped = mod(phase_in, 2*pi);

if nargin < 6
    use_dither = true;
end
if nargin < 5
    offset_seed = 0;
end

offset_candidates = offset_seed + linspace(-0.5, 0.5, 9) * phase_step;
best_cost = inf;
best_offset = offset_seed;
layer_map_best = base_layers * ones(size(phase_in));
phase_projected = zeros(size(phase_in));
max_layer_index = base_layers + ceil((2*pi) / phase_step) + 1;

for idx = 1:numel(offset_candidates)
    offset_now = offset_candidates(idx);
    phase_shifted = mod(phase_wrapped + offset_now, 2*pi);
    layer_cont = phase_shifted / phase_step + base_layers;

    if use_dither
        layer_map = error_diffuse_quantize_layers(layer_cont, mask, base_layers, max_layer_index);
    else
        layer_map = round(layer_cont);
        layer_map = min(max(layer_map, base_layers), max_layer_index);
    end

    phase_candidate = mod(layer_map * phase_step, 2*pi);
    phase_residual = angle(exp(1i * (phase_candidate - phase_shifted)));
    phase_cost = mean(phase_residual(mask).^2);

    if phase_cost < best_cost
        best_cost = phase_cost;
        best_offset = offset_now;
        layer_map_best = layer_map;
        phase_projected = phase_candidate;
    end
end

phase_projected(~mask) = 0;
layer_map_best(~mask) = base_layers;
best_offset = mod(best_offset, 2*pi);
end
