# CLAUDE.md — SSP Data CRM showcase

A minimal OmniGraph demo: my Obsidian CRM scaled to a 50-person company as a
typed, versioned graph. Three source files (`schema.pg`, `queries/crm.gq`,
`seed.jsonl`) + agent write demos (`agents/*.jsonl`). README.md is the story;
the Makefile is the ordered walkthrough. Verified on omnigraph **0.8.1**.

## Rules

- **Keep it small.** 4 node types, 7 edge types, 8 queries. New concepts must
  earn their place — this repo exists to teach branches/typing/auto-merge, not
  to model a real CRM completely. The full-scale example lives at git tag
  `vc-os`.
- **Slug prefixes:** `com-` (Company, including `com-ssp` = us), `per-`,
  `deal-`, `int-`. Company `kind=us` exists exactly once (`com-ssp`).
- **Never commit `__cluster/` or `graphs/`** (gitignored local state).
- After schema/query edits: `omnigraph lint --schema schema.pg --query queries/crm.gq`
  (offline, no server needed), then `omnigraph cluster apply --config . --as simu`.
- **Enum changes are destructive** — widening an enum means rebuild:
  `make clean && make init && make seed`.
- `make conflict` intentionally ends in a `DivergentUpdate` error — that error
  is the demo, don't "fix" it.

## GQ gotchas (0.8.1)

- Patterns use braces: `match { $c: Company { slug: $slug } }`.
- Edge traversal is lowerCamelCase verb form: `$p worksAt $c` (schema declares
  `edge WorksAt`). No arrow syntax.
- Params bind by name: `--params '{"slug":…}'` needs `$slug` in the query.
- Edge properties can't be projected in `return` — node props only.
- `--query /dev/stdin` doesn't work; use `-e "<gq>"` or a file.
- `load` requires explicit `--mode` (`overwrite|append|merge`).
