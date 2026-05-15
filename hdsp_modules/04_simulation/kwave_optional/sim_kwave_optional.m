function ctx = sim_kwave_optional(ctx)
if exist('kspaceFirstOrder3D', 'file') ~= 2
    ctx = sim_asm_focus_scan(ctx);
    ctx.field.name = 'kwave_optional';
    ctx.field.status = "kwave_missing_asm_fallback";
    return;
end
error('k-Wave execution wrapper is intentionally not enabled in the code-only modular skeleton yet.');
end

