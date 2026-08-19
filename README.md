# OmniGraph Company Brain Demo: A company brain instead of a custom CRM software

> [!NOTE]
> Fictive example to help illustrate the features behind a company brain,
> accompanying the blog article.

My [Obsidian CRM](https://www.ssp.sh/brain/managing-my-business-with-obsidian/) —
one Markdown note per client, frontmatter like `Hotness: 5-Cold`, a kanban view
for the sales funnel — scaled up to a fictional 50-person version of my company
(SSP Data: data-engineering consulting + technical content), rebuilt as a
**typed, versioned graph** with [OmniGraph](https://github.com/ModernRelay/omnigraph).

No CRM app. No database server. The whole CRM is **three declarative files you
commit to git**, and the graph itself is just files on disk (or an `s3://`
bucket — same commands).

| In my Obsidian CRM | Here |
|---|---|
| A note per client ("Acme Inc") | A `Company` node |
| Frontmatter `Hotness: 5-Cold` | `hotness: enum(hot, warm, cold)` — a wrong value is **rejected at write time** |
| The `#crmssp` tag collecting CRM notes | The `Company` node type itself |
| `[[Wikilinks]]` | Typed edges: `WorksAt`, `DealWith`, `Knows`, … |
| The `## Log` section | `Interaction` nodes (call / email / meeting / note) |
| My Templater template | `schema.pg` — enforced, not suggested |
| Table + kanban plugin views | Stored queries in `queries/crm.gq`, invoked by name |
| One writer: me | 50 employees **plus agents**, each writing on their own branch |

## The three files

- **`schema.pg`** — 4 node types (`Company`, `Person`, `Deal`, `Interaction`),
  7 edge types. The CRM's data contract.
- **`queries/crm.gq`** — 8 stored queries: the "views" (`team`, `sales_funnel`,
  `hot_prospects`, `company_log`, `warm_intro`, …). Typed and lintable:
  `omnigraph lint --schema schema.pg --query queries/crm.gq`.
- **`seed.jsonl`** — the data: 98 nodes / 123 edges. 50 employees, 10 companies
  we chase, 12 deals across the funnel, the interaction log.

## Run it

Requires `omnigraph` on PATH (verified on 0.8.1). Don't want to run it? The
full captured output of every step is in [DEMO.md](DEMO.md). Then, in order:

```bash
make init      # cluster validate -> plan -> apply  (creates graphs/crm.omni)
make seed      # 98 nodes / 123 edges
make team      # all 50 employees — a stored query
make funnel    # the sales-funnel kanban, as data
make intro     # who can warm-intro us at Nordbahn?
```

```
$ make intro
teammate.name | contact.name  | contact.role | target.name
--------------+---------------+--------------+------------------
Tom Vermeer   | Lars Petersen | Head of BI   | Nordbahn Logistik
```

That's the query my Obsidian backlinks could never answer across 50 people's
networks — one graph traversal: teammate → knows → contact → works at target.

## The meat: agents write too — on branches

An Obsidian vault has one writer. A 50-person company has fifty, plus the
agents that keep a CRM from going stale: one scans the inbox, one syncs the
billing system. Nobody writes to `main` directly — every writer forks a branch
(copy-on-write, like git):

```bash
make agents
```

1. The **inbox agent** loads this morning's findings (VectorHut replied →
   `warm`→`hot`, a new inbound prospect) onto branch `agent/inbox-scan`.
2. The **billing agent** loads a signed PO (Alpenkraft PoC `proposal`→`won`)
   onto branch `agent/billing-sync` — concurrently.
3. `main` is provably untouched while both work (the demo shows it).
4. Both merges are clean (different rows) → they **auto-merge**. Three-way,
   row-level, one atomic commit each, actor recorded (`--as agent-inbox`).

And when two writers disagree?

```bash
make conflict
```

The inbox agent says Nordbahn is `hot` ("CEO replied today"); the hygiene agent
says `cold` ("no touchpoint in 60 days"). First merge lands. The second is
**blocked**:

```
Error: merge conflicts: [MergeConflict { row_id: "com-nordbahn",
       kind: DivergentUpdate, ... }]
```

Nothing published, no silent last-write-wins — a human (or a policy) decides.
That blocked merge is the governance: the same review discipline as a GitHub
pull request, on CRM data.

```bash
make commits   # audit trail: every commit has an actor — simu, agent-inbox, agent-billing
```

## How the pieces fit

```
you / 50 colleagues / N agents
        │  branch → write → merge (three-way, audited)
   OmniGraph      typed graph, .pg schema, .gq queries, branches, policies
        │
   DataFusion     the query engine (filter, sort, traverse)
        │
   Lance          open columnar files, versioned (the graph IS these files)
        │
   local disk     graphs/crm.omni — or s3://your-bucket, same commands
```

There is no server in this repo. Every command hits the Lance files directly.
`ls graphs/crm.omni/` shows what your "database" is: a `nodes/` and `edges/`
directory of Lance datasets plus a `__manifest` catalog. Delete it, run
`make init && make seed`, and the whole brain rebuilds from the three files —
declarative, like the rest of your infrastructure.

## Poking around

```bash
# ad-hoc query, inline GQ: braces for patterns, $vars, verb-form edge traversal
omnigraph query q -e 'query q(){ match { $c: Company { hotness: "hot" } } return { $c.name, $c.notes } }' \
  --store graphs/crm.omni --format table

make reset-data   # back to the clean baseline
make clean        # nuke everything; make init && make seed rebuilds
make demo         # the whole story end-to-end
```

GQ gotchas (cost me a few tries): patterns use **braces** not arrows
(`$p worksAt $c`, lowerCamelCase verb form even though the schema declares
`edge WorksAt`); params bind by **name** (`--params '{"slug":"com-nordbahn"}'`
needs a query declaring `$slug`).

---

*Adapted from the [`vc-os` cookbook](https://github.com/ModernRelay/omnigraph-cookbooks/tree/main/vc-os)
— the full VC operating-system graph (17 node types, 207-node seed). This CRM
showcase is its minimal, single-idea sibling.*
