function plot_phase_method_comparison(results, figure_path)
%PLOT_PHASE_METHOD_COMPARISON Dynamic overview for six phase-comparison cases.
target = results.target;
cases = results.phase_cases;
num_cases = numel(cases);

fig = figure('Color', 'w', 'Position', [40, 40, 2200, 1350]);
tiledlayout(4, max(2, num_cases), 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
imagesc(target.x * 1e3, target.y * 1e3, target.amp);
axis image; colormap(gca, 'gray'); colorbar;
title('A Target'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile;
imagesc(target.x * 1e3, target.y * 1e3, target.source_mask);
axis image; colormap(gca, 'gray'); colorbar;
title('Source Aperture'); xlabel('x (mm)'); ylabel('y (mm)');

for idx = 3:num_cases
    nexttile;
    axis off;
end

for idx = 1:num_cases
    nexttile;
    imagesc(target.x * 1e3, target.y * 1e3, cases(idx).phase);
    axis image; colormap(gca, 'hsv'); colorbar; clim([0, 2*pi]);
    title(sprintf('%s Phase', cases(idx).label), 'Interpreter', 'none');
    xlabel('x (mm)'); ylabel('y (mm)');
end

for idx = 1:num_cases
    nexttile;
    imagesc(target.x * 1e3, target.y * 1e3, cases(idx).asm_amp_norm);
    axis image; colormap(gca, 'hot'); colorbar;
    title(sprintf('ASM %s\\nPCC %.3f | EE %.1f%%', cases(idx).label, ...
        cases(idx).asm_metrics.pcc, cases(idx).asm_metrics.energy_efficiency * 100), 'Interpreter', 'none');
    xlabel('x (mm)'); ylabel('y (mm)');
end

for idx = 1:num_cases
    nexttile;
    imagesc(target.x * 1e3, target.y * 1e3, cases(idx).kwave.amp_norm);
    axis image; colormap(gca, 'jet'); colorbar;
    title(sprintf('k-Wave %s\\nScore %.3f | CV %.3f', cases(idx).label, ...
        cases(idx).kwave.metrics.target_pressure_quality_score, ...
        cases(idx).kwave.metrics.target_uniformity_cv), 'Interpreter', 'none');
    xlabel('x (mm)'); ylabel('y (mm)');
end

exportgraphics(fig, figure_path, 'Resolution', 300);
close(fig);

metric_path = strrep(figure_path, '_overview.png', '_metrics.png');
plot_metric_bars(results, metric_path);
plot_loop_histories(results, figure_path);
end

function plot_metric_bars(results, figure_path)
cases = results.phase_cases;
labels = categorical({cases.label});
labels = reordercats(labels, {cases.label});
xpos = 1:numel(cases);

fig = figure('Color', 'w', 'Position', [80, 80, 1900, 950]);
tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
bar(xpos, arrayfun(@(c) c.kwave.metrics.target_pressure_quality_score, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels), 'XTickLabelRotation', 25);
ylabel('Quality score'); title('k-Wave Quality Score'); grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.kwave.metrics.energy_efficiency * 100, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels), 'XTickLabelRotation', 25);
ylabel('Energy in target (%)'); title('Energy Utilization'); grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.kwave.metrics.target_uniformity_cv, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels), 'XTickLabelRotation', 25);
ylabel('CV'); title('Target Pressure CV'); grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.kwave.metrics.target_p10_over_p50, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels), 'XTickLabelRotation', 25);
ylabel('P10 / P50'); title('Low-Quantile Coverage'); grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.kwave.metrics.target_peak_over_mean, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels), 'XTickLabelRotation', 25);
ylabel('Peak / mean'); title('Hot-Spot Ratio'); grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.kwave.metrics.pcc, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels), 'XTickLabelRotation', 25);
ylabel('PCC'); title('k-Wave Pattern PCC'); grid on;

exportgraphics(fig, figure_path, 'Resolution', 300);
close(fig);
end

function plot_loop_histories(results, overview_path)
cases = results.phase_cases;
for idx = 1:numel(cases)
    if ~isfield(cases(idx), 'history') || isempty(cases(idx).history) || size(cases(idx).history, 2) < 8
        continue;
    end
    history = cases(idx).history;
    fig = figure('Color', 'w', 'Position', [120, 120, 1350, 780]);
    tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    plot(history(:, 8), 'LineWidth', 1.5); hold on;
    if isfield(cases(idx), 'optimizer_metrics') && isfield(cases(idx).optimizer_metrics, 'selected_epoch')
        selected_epoch = cases(idx).optimizer_metrics.selected_epoch;
        if selected_epoch >= 1 && selected_epoch <= size(history, 1)
            plot(selected_epoch, history(selected_epoch, 8), 'ro', 'MarkerSize', 7, 'LineWidth', 1.5);
        end
    end
    xlabel('Epoch'); ylabel('Loop quality score'); title([cases(idx).label, ' Loop Score'], 'Interpreter', 'none'); grid on;

    nexttile;
    plot(history(:, 4), 'LineWidth', 1.3);
    xlabel('Epoch'); ylabel('Target CV'); title('Target Uniformity CV'); grid on;

    nexttile;
    plot(history(:, 5), 'LineWidth', 1.3);
    xlabel('Epoch'); ylabel('P10 / P50'); title('Low-Quantile Coverage'); grid on;

    nexttile;
    plot(history(:, 7), 'LineWidth', 1.3);
    xlabel('Epoch'); ylabel('Peak / mean'); title('Target Hot-Spot Ratio'); grid on;

    safe_label = regexprep(cases(idx).label, '[^A-Za-z0-9]+', '_');
    exportgraphics(fig, strrep(overview_path, '_overview.png', ['_', safe_label, '_loop_history.png']), 'Resolution', 300);
    close(fig);
end
end
