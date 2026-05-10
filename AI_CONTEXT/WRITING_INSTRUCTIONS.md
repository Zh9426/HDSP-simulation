# AI Writing Instructions

This file defines how Prism should collaborate on the thesis materials in this repository.

## Source of truth

- Thesis formatting rules come from `paper/FORMAT_RULES.md`.
- If a future LaTeX class or template file exists, the executable template rules override this Markdown description.
- If there is a conflict between content polish and format compliance, keep format compliance.

## Current project boundary

This branch does not yet provide:
- project overview
- current research status
- experiment log
- result summary

Therefore Prism must not infer missing research facts from code fragments or generic domain assumptions.

## Prism may edit

- Chinese abstract wording
- English abstract wording
- chapter prose
- conclusion and outlook prose
- acknowledgements prose
- figure captions
- table captions
- equation explanations in the surrounding text
- bibliography entry wording and normalization, if a bibliography file exists

## Prism must not edit unless explicitly asked

- page layout
- fonts, font sizes, or line spacing rules
- heading numbering rules
- figure, table, or equation numbering rules
- page header and footer logic
- front-matter page numbering style
- appendix numbering style
- citation style policy
- any future `.cls`, `.sty`, or layout-control block in `main.tex`

## Hard constraints

- Do not invent experimental results, parameter values, figures, tables, or references.
- Do not claim that a conclusion is verified unless the repository or the user has provided evidence.
- If data is missing, write `TODO` or ask for the missing material instead of fabricating content.
- Keep terminology consistent across the whole thesis.
- Chinese text should use formal academic style, not chatty language.
- English abstract content must remain consistent with the Chinese abstract.
- Figures, tables, and equations must be referenced in the body text before or where they appear.

## Preferred working mode

When asked to revise text, Prism should:
1. read `paper/FORMAT_RULES.md` first
2. preserve all formatting-control files
3. revise only content files
4. surface unresolved missing facts as `TODO`
5. report any format requirement that cannot be satisfied by the current template

## Import guidance for Prism

When these files are uploaded into Prism, use instructions equivalent to:

`Please follow paper/FORMAT_RULES.md and AI_CONTEXT/WRITING_INSTRUCTIONS.md. You may revise thesis content files, but do not modify layout-control rules or invent missing research facts. If required information is missing, mark it as TODO and explain what is needed.`
