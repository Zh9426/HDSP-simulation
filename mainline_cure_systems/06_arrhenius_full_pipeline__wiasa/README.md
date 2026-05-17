# Arrhenius Full Pipeline - WIASA

This flow keeps the thermal diffusion + Arrhenius curing mainline and replaces
the initial phase stage with multiplicative weighted IASA.

Algorithm boundary:

- start from the GS propagation and target-plane constraint loop
- update the target-plane weight map from the recovered amplitude during the loop
- use the weighted target constraint for back-propagation
- build the discrete phase plate only after the weighted IASA phase loop converges

There is no phase-plate projection inside the iteration loop.
