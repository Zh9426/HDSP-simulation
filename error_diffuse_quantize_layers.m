function layer_map = error_diffuse_quantize_layers(layer_cont, mask, base_layers, max_layer_index)
%ERROR_DIFFUSE_QUANTIZE_LAYERS Quantize continuous layer values with local error diffusion.
work = double(layer_cont);
mask = logical(mask);
layer_map = base_layers * ones(size(work));

[rows, cols] = size(work);
for row = 1:rows
    if mod(row, 2) == 1
        col_range = 1:cols;
        direction = 1;
    else
        col_range = cols:-1:1;
        direction = -1;
    end

    for col = col_range
        if ~mask(row, col)
            continue;
        end

        quantized_val = round(work(row, col));
        quantized_val = min(max(quantized_val, base_layers), max_layer_index);
        layer_map(row, col) = quantized_val;
        quant_error = work(row, col) - quantized_val;

        next_col = col + direction;
        if next_col >= 1 && next_col <= cols && mask(row, next_col)
            work(row, next_col) = work(row, next_col) + quant_error * 7 / 16;
        end
        if row < rows
            below_col = col;
            if mask(row + 1, below_col)
                work(row + 1, below_col) = work(row + 1, below_col) + quant_error * 5 / 16;
            end
            diag_col = col - direction;
            if diag_col >= 1 && diag_col <= cols && mask(row + 1, diag_col)
                work(row + 1, diag_col) = work(row + 1, diag_col) + quant_error * 3 / 16;
            end
            diag_col = col + direction;
            if diag_col >= 1 && diag_col <= cols && mask(row + 1, diag_col)
                work(row + 1, diag_col) = work(row + 1, diag_col) + quant_error * 1 / 16;
            end
        end
    end
end

layer_map(~mask) = base_layers;
end
