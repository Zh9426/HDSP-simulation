function board = board_project_phase_only(phase_map, params, source_mask)
best_score = inf;
best_layers = zeros(params.Nx, params.Ny);
for bias = linspace(0, 2 * pi, 33)
    shifted = mod(phase_map + bias, 2 * pi);
    layers = round(shifted / params.phase_step);
    layers = min(max(layers, params.min_base_layers), params.max_board_layers);
    actual = mod(layers * params.phase_step - bias, 2 * pi);
    residual = angle(exp(1i * (actual - phase_map)));
    score = mean(abs(residual(source_mask)));
    if score < best_score
        best_score = score;
        best_layers = layers;
        best_bias = bias;
    end
end
layers = error_diffuse_layers(best_layers, phase_map, params, source_mask, best_bias);
layers(~source_mask) = 0;
actual_phase = mod(layers * params.phase_step - best_bias, 2 * pi);
board = struct();
board.layer_map = layers;
board.thickness_map = layers * params.layer_thickness;
board.actual_phase = actual_phase;
board.phase_bias = best_bias;
board.residual = angle(exp(1i * (actual_phase - phase_map)));
end

function layers = error_diffuse_layers(layers, phase_map, params, source_mask, bias)
err = zeros(size(layers));
for r = 1:params.Nx
    if mod(r, 2) == 1
        cols = 1:params.Ny;
        dir = 1;
    else
        cols = params.Ny:-1:1;
        dir = -1;
    end
    for c = cols
        if ~source_mask(r, c)
            continue;
        end
        desired = mod(phase_map(r, c) + bias, 2 * pi) / params.phase_step + err(r, c);
        q = min(max(round(desired), params.min_base_layers), params.max_board_layers);
        quant_err = desired - q;
        layers(r, c) = q;
        if c + dir >= 1 && c + dir <= params.Ny
            err(r, c + dir) = err(r, c + dir) + quant_err * 7 / 16;
        end
        if r + 1 <= params.Nx
            if c - dir >= 1 && c - dir <= params.Ny
                err(r + 1, c - dir) = err(r + 1, c - dir) + quant_err * 3 / 16;
            end
            err(r + 1, c) = err(r + 1, c) + quant_err * 5 / 16;
            if c + dir >= 1 && c + dir <= params.Ny
                err(r + 1, c + dir) = err(r + 1, c + dir) + quant_err * 1 / 16;
            end
        end
    end
end
end

