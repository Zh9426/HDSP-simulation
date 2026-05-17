# Arrhenius Full Pipeline - BIASA

This flow keeps the thermal diffusion + Arrhenius curing mainline and replaces
the initial phase stage with board-constrained IASA.

Algorithm boundary:

- start from the WIASA weighted target-plane constraint loop
- project each source-plane candidate phase into the discrete phase-plate layer map
- use the projected phase as the next iteration state
- carry the final `net_num_board` directly from the iterative phase-plate construction

BIASA therefore folds phase-plate construction into the IASA loop instead of
treating the board as a final post-processing step.
