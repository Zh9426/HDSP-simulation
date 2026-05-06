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
    axis image; colormap(gca, 'hsv'); colorbar; caxis([0, 2*pi]);
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
title('Pressure Metrics');
grid on;

exportgraphics(fig, figure_path, 'Resolution', 300);
close(fig);
end
