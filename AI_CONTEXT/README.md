# Prism Constraint Layer

This branch is reserved for files that constrain how Prism should read and edit the thesis materials.

Current scope:
- writing constraints for Prism
- thesis format constraints derived from the user-provided XJTU thesis template PDF
- import and usage guidance for the AI writing workflow

Not in scope yet:
- project overview
- current research status
- experiment summaries
- methodology summaries tied to the HDSP codebase

Files in this directory:
- `WRITING_INSTRUCTIONS.md`: what Prism may change, what it must not change, and how it should behave when information is missing

Related file outside this directory:
- `paper/FORMAT_RULES.md`: fixed thesis-format requirements

Recommended Prism input set for this branch:
1. `paper/FORMAT_RULES.md`
2. `AI_CONTEXT/WRITING_INSTRUCTIONS.md`
3. LaTeX source files after they are created later (`main.tex`, `chapters/*.tex`, `references.bib`, figures)

At the current stage, Prism should be used as a constrained writing assistant, not as a project-state inference tool.
