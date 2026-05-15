function ctx = target_A_letter_narrowband_current(ctx)
target = build_A_letter_target(ctx.params, 0.5, 0.55, 'A_letter_narrowband_current');
target.line_mask = target.amp >= 0.55;
target.halo_mask = imdilate(target.line_mask, strel('disk', 4)) & ~target.line_mask;
target.dark_mask = ~(target.line_mask | target.halo_mask);
ctx.target = target;
end

