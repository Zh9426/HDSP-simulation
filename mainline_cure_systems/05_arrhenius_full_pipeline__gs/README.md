# Arrhenius Full Pipeline - GS

This flow keeps the thermal diffusion + Arrhenius curing mainline and replaces
the initial phase stage with classical GS.

Algorithm boundary:

- propagate source field to target plane
- replace the target-plane amplitude with the fixed target amplitude
- back-propagate phase to the source plane
- build the discrete phase plate only after the GS phase loop converges

There is no target-weight update and no phase-plate projection inside the
iteration loop.
