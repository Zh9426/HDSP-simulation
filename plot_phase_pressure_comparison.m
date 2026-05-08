function plot_phase_pressure_comparison(results, figure_path)
%PLOT_PHASE_PRESSURE_COMPARISON Overview figure for phase and pressure metrics.
target = results.target;
cases = results.phase_cases;

fig = figure('Color', 'w', 'Position', [60, 60, 1750, 980]);
tiledlayout(3, 4, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
imagesc(target.x * 1e3, target.y * 1e3, target.amp);
axis image; colormap(gca, 'gray'); colorbar;
title('A Target'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile;
imagesc(target.x * 1e3, target.y * 1e3, target.source_mask);
axis image; colormap(gca, 'gray'); colorbar;
title('Source Aperture'); xlabel('x (mm)'); ylabel('y (mm)');

for idx = 1:numel(cases)
    nexttile;
    imagesc(target.x * 1e3, target.y * 1e3, cases(idx).phase);
    axis image; colormap(gca, 'hsv'); colorbar; clim([0, 2*pi]);
    title([cases(idx).label, ' Phase']); xlabel('x (mm)'); ylabel('y (mm)');
end

for idx = 1:numel(cases)
    nexttile;
    imagesc(target.x * 1e3, target.y * 1e3, cases(idx).asm_amp_norm);
    axis image; colormap(gca, 'hot'); colorbar;
    title(sprintf('ASM %s\\nPCC %.4f | EE %.1f%%', cases(idx).label, ...
        cases(idx).asm_metrics.pcc, cases(idx).asm_metrics.energy_efficiency * 100));
    xlabel('x (mm)'); ylabel('y (mm)');
end

for idx = 1:numel(cases)
    nexttile;
    imagesc(target.x * 1e3, target.y * 1e3, cases(idx).kwave.amp_norm);
    axis image; colormap(gca, 'jet'); colorbar;
    title(sprintf('k-Wave %s\\nMean %.2g Pa | CV %.3f', cases(idx).label, ...
        cases(idx).kwave.metrics.mean_target_pressure_pa, cases(idx).kwave.metrics.target_uniformity_cv));
    xlabel('x (mm)'); ylabel('y (mm)');
end

nexttile;
labels = categorical({cases.label});
labels = reordercats(labels, {cases.label});
mean_vals = arrayfun(@(c) c.kwave.metrics.mean_target_pressure_pa, cases);
xpos = 1:numel(cases);
yyaxis left;
bar(xpos, mean_vals);
ylabel('Target mean pressure (Pa)');
yyaxis right;
plot(xpos, arrayfun(@(c) c.kwave.metrics.target_peak_over_mean, cases), 'ko-', 'LineWidth', 1.6);
ylabel('Target peak / mean');
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels));
title('k-Wave Pressure Metrics');
grid on;

fig2 = figure('Color', 'w', 'Position', [120, 120, 1500, 720]);
tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

labels = categorical({cases.label});
labels = reordercats(labels, {cases.label});
xpos = 1:numel(cases);

nexttile;
bar(xpos, arrayfun(@(c) c.kwave.metrics.energy_efficiency * 100, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels));
ylabel('Energy in target (%)');
title('Energy Utilization');
grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.kwave.metrics.target_uniformity_score, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels));
ylim([0, 1]);
ylabel('1 / (1 + pressure CV)');
title('Pressure Uniformity');
grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.kwave.metrics.target_p10_over_p50, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels));
ylabel('Target P10 / P50');
title('Low Quantile Coverage');
grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.kwave.metrics.target_peak_over_mean, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels));
ylabel('Target peak / mean');
title('Target Spike Penalty');
grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.phase_metrics.phase_gradient_p90_rad, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels));
ylabel('P90 wrapped gradient (rad)');
title('Phase Smoothness Cost');
grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.phase_metrics.asm_target_pcc, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels));
ylabel('ASM PCC');
title('Phase-to-ASM Match');
grid on;

exportgraphics(fig2, strrep(figure_path, '_overview.png', '_metrics.png'), 'Resolution', 300);
close(fig2);

for idx = 1:numel(cases)
    if ~isfield(cases(idx), 'history') || isempty(cases(idx).history) || size(cases(idx).history, 2) < 8
        continue;
    end
    history = cases(idx).history;
    fig_history = figure('Color', 'w', 'Position', [160, 160, 1300, 760]);
    tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    plot(history(:, 8), 'LineWidth', 1.5);
    hold on;
    if isfield(cases(idx), 'optimizer_metrics') && isfield(cases(idx).optimizer_metrics, 'selected_epoch')
        selected_epoch = cases(idx).optimizer_metrics.selected_epoch;
        plot(selected_epoch, history(selected_epoch, 8), 'ro', 'MarkerSize', 7, 'LineWidth', 1.5);
    end
    xlabel('Epoch'); ylabel('Loop quality score'); title([cases(idx).label, ' Loop Score']); grid on;

    nexttile;
    plot(history(:, 4), 'LineWidth', 1.3);
    xlabel('Epoch'); ylabel('Target CV'); title('Target Uniformity CV'); grid on;

    nexttile;
    plot(history(:, 5), 'LineWidth', 1.3);
    xlabel('Epoch'); ylabel('P10 / P50'); title('Low-Quantile Coverage'); grid on;

    nexttile;
    plot(history(:, 7), 'LineWidth', 1.3);
    xlabel('Epoch'); ylabel('Peak / mean'); title('Target Spike Ratio'); grid on;

    safe_label = regexprep(cases(idx).label, '[^A-Za-z0-9]+', '_');
    exportgraphics(fig_history, strrep(figure_path, '_overview.png', ['_', safe_label, '_loop_history.png']), 'Resolution', 300);
    close(fig_history);
end

exportgraphics(fig, figure_path, 'Resolution', 300);
close(fig);
end
