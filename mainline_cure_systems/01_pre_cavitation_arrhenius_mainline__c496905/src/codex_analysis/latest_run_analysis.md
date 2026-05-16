# Codex Run Analysis

- Source: `HDSPdebug.m`
- Run id: `20260516T165247048`
- Policy: `proposal_only`

## Recommendations

### P1 domain_gap

- Target: `HDSPdebug.m` / exit-plane diagnostics and discrete-board transmission
- Reason: ASM/design-model to k-Wave agreement is weak, so algorithm changes should first reduce forward-model mismatch.
- Proposed change: Export or fit an effective transmission correction using thickness, gradient, aperture-edge distance, exit amplitude, and exit phase residual.
- Evidence: `{"asm_kwave_corr": 0.6346463101129249, "asm_kwave_nmse": 1.8479352823898543, "board_exit_kwave_corr": 0.22297717519503576}`

### P2 curing_gap

- Target: `HDSPdebug.m` / thermal dose and curing decision block
- Reason: Curing shape metrics are below a useful target or the model is trading target fill for over/under-cure.
- Proposed change: Compare thermal-only result against sidecar cavitation activation and metric profiles before changing the main Arrhenius path.
- Evidence: `{"IoU": 0.26938663369733234, "Dice": 0.4244359071478357, "over_cure_ratio": 2.7104337631887456, "under_cure_ratio": 0.0004587389775217901}`
