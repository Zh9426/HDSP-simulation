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
    title(sprintf('k-Wave %s\\nPeak %.2g Pa | PCC %.4f', cases(idx).label, ...
        cases(idx).kwave.metrics.peak_target_pressure_pa, cases(idx).kwave.metrics.pcc));
    xlabel('x (mm)'); ylabel('y (mm)');
end

nexttile;
labels = categorical({cases.label});
labels = reordercats(labels, {cases.label});
peak_vals = arrayfun(@(c) c.kwave.metrics.peak_target_pressure_pa, cases);
xpos = 1:numel(cases);
yyaxis left;
bar(xpos, peak_vals);
ylabel('Target peak pressure (Pa)');
yyaxis right;
plot(xpos, arrayfun(@(c) c.kwave.metrics.energy_efficiency * 100, cases), 'ko-', 'LineWidth', 1.6);
ylabel('Energy efficiency (%)');
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
bar(xpos, arrayfun(@(c) c.kwave.metrics.target_energy_uniformity_score, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels));
ylim([0, 1]);
ylabel('1 / (1 + energy CV)');
title('Energy Uniformity');
grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.kwave.metrics.peak_sidelobe_ratio, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels));
ylabel('Target peak / dark peak');
title('Sidelobe Suppression');
grid on;

nexttile;
bar(xpos, arrayfun(@(c) c.phase_metrics.phase_circular_variance, cases));
set(gca, 'XTick', xpos, 'XTickLabel', cellstr(labels));
ylabel('Circular variance');
title('Phase Diversity');
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

exportgraphics(fig, figure_path, 'Resolution', 300);
close(fig);
end
