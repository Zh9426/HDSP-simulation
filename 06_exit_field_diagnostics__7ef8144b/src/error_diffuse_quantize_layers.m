function layer_map = error_diffuse_quantize_layers(layer_cont, mask, base_layers, max_layer_index)
[n_row, n_col] = size(layer_cont);
work = double(layer_cont);
layer_map = base_layers * ones(size(layer_cont));

for row = 1:n_row
    if mod(row, 2) == 1
        cols = 1:n_col;
        neighbor_pattern = [0, 1, 7/16; 1, -1, 3/16; 1, 0, 5/16; 1, 1, 1/16];
    else
        cols = n_col:-1:1;
        neighbor_pattern = [0, -1, 7/16; 1, 1, 3/16; 1, 0, 5/16; 1, -1, 1/16];
    end

    for col = cols
        if ~mask(row, col)
            continue;
        end

        quantized_val = round(work(row, col));
        quantized_val = min(max(quantized_val, base_layers), max_layer_index);
        layer_map(row, col) = quantized_val;
        quant_error = work(row, col) - quantized_val;

        for n = 1:size(neighbor_pattern, 1)
            n_row_idx = row + neighbor_pattern(n, 1);
            n_col_idx = col + neighbor_pattern(n, 2);
            if n_row_idx >= 1 && n_row_idx <= n_row && n_col_idx >= 1 && n_col_idx <= n_col && mask(n_row_idx, n_col_idx)
                work(n_row_idx, n_col_idx) = work(n_row_idx, n_col_idx) + quant_error * neighbor_pattern(n, 3);
            end
        end
    end
end
end
