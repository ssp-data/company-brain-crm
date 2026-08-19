# Demo transcript — one full run, real output

Captured from `make demo` on omnigraph 0.8.1. Every block below is actual CLI
output; each section anchor is stable, so you can deep-link a single result
(e.g. `DEMO.md#make-conflict`). Reproduce everything from a clean checkout with
`make init && make seed`, then the targets in order.

## make seed

```
loaded graphs/crm.omni on branch main with overwrite: 98 nodes across 4 node types, 123 edges across 7 edge types
```

## make team

All 50 employees — a stored query (`team` in [`queries/crm.gq`](queries/crm.gq)):

```
50 rows from branch main via team
p.slug             | p.name         | p.role             | p.email
-------------------+----------------+--------------------+----------------------
per-aisha-diallo   | Aisha Diallo   | Data Engineer      | aisha.diallo@ssp.sh
per-aline-roth     | Aline Roth     | People Ops         | aline.roth@ssp.sh
per-amara-okafor   | Amara Okafor   | Technical Writer   | amara.okafor@ssp.sh
per-anna-keller    | Anna Keller    | COO                | anna.keller@ssp.sh
per-bram-visser    | Bram Visser    | Data Engineer      | bram.visser@ssp.sh
…                                             (45 more rows)
```

## make funnel

The sales-funnel kanban from my Obsidian CRM — as a query result. Group by
`d.stage` in whatever renders it (terminal, notebook, agent):

```
12 rows from branch main via sales_funnel
d.stage   | d.name                           | c.name                | d.kind           | d.value_usd
----------+----------------------------------+-----------------------+------------------+------------
contacted | DataWelt monthly column          | DataWelt Verlag       | article          | 12000.0
contacted | Nordbahn DWH modernization       | Nordbahn Logistik     | consulting       | 180000.0
contacted | VectorHut RAG deep-dive          | VectorHut             | article          | 6000.0
lead      | Helvetia phase 2 (governance)    | Helvetia Retail Group | consulting       | 150000.0
lead      | LakeCraft first article          | LakeCraft             | article          | 6000.0
lead      | VectorHut team workshop          | VectorHut             | workshop         | 15000.0
lost      | StreamSense Kafka workshop       | StreamSense           | workshop         | 18000.0
proposal  | Alpenkraft smart-meter PoC       | Alpenkraft Energie AG | consulting       | 60000.0
proposal  | Orchestron launch article series | Orchestron            | article          | 30000.0
won       | DuckPond writing retainer 2026   | DuckPond Analytics    | writing-retainer | 96000.0
won       | Helvetia lakehouse migration     | Helvetia Retail Group | consulting       | 240000.0
won       | TableWise retainer renewal       | TableWise             | writing-retainer | 84000.0
```

## make hot

Who to call today:

```
2 rows from branch main via hot_prospects
c.name                | c.segment     | c.notes
----------------------+---------------+----------------------------------------------------
Alpenkraft Energie AG | energy        | Consulting PoC proposal out — smart-meter pipeline.
Orchestron            | orchestration | Proposal sent for a 6-article launch series.
```

## make log

Everything that ever happened with one company (the `## Log` section of the
Obsidian note — across all 50 employees):

```
2 rows from branch main via company_log
i.date     | i.kind | i.summary
-----------+--------+-------------------------------------------------------
2026-06-02 | call   | Alpenkraft CIO call — PoC scope: smart-meter pipeline.
2026-07-29 | email  | Alpenkraft procurement questions answered.
```

## make intro

Who can warm-intro us at Nordbahn? One traversal:
teammate → knows → contact → works at target:

```
1 rows from branch main via warm_intro
teammate.name | contact.name  | contact.role | target.name
--------------+---------------+--------------+------------------
Tom Vermeer   | Lars Petersen | Head of BI   | Nordbahn Logistik
```

## make agents

Two agents write **concurrently, each on its own branch** forked from `main`.

Agent 1 — inbox-scan (VectorHut replied → `warm`→`hot`, plus a new inbound
prospect and two logged interactions):

```
loaded graphs/crm.omni on branch agent/inbox-scan with merge: 4 nodes across 2 node types, 4 edges across 2 edge types
branch agent/inbox-scan created from main
```

Agent 2 — billing-sync (signed PO arrived → Alpenkraft PoC `proposal`→`won`):

```
loaded graphs/crm.omni on branch agent/billing-sync with merge: 2 nodes across 2 node types, 2 edges across 2 edge types
branch agent/billing-sync created from main
```

**Isolation** — while both branches hold changes, `main` is untouched:

```
c.name    | c.hotness
----------+----------
VectorHut | warm
```

Both changes touch different rows → both merges are clean → **auto-merged**,
no human in the loop (three-way, row-level, one atomic commit each):

```
merged agent/inbox-scan into main: fast_forward
merged agent/billing-sync into main: merged
```

`main` afterwards:

```
c.name    | c.hotness
----------+----------
VectorHut | hot

d.name                     | d.stage
---------------------------+--------
Alpenkraft smart-meter PoC | won
```

## make conflict

The governance case: two agents update the **same row** with different values.
The inbox agent says Nordbahn is `hot` ("CEO replied today"); the CRM-hygiene
agent says `cold` ("no touchpoint in 60+ days"). Each writes on its own branch;
the first merge lands:

```
merged agent/inbox-scan2 into main: fast_forward
```

The second merge is **blocked** — this error is the feature:

```
Error:
   0: merge conflicts: [MergeConflict { table_key: "node:Company",
      row_id: Some("com-nordbahn"), kind: DivergentUpdate,
      message: "divergent update for id 'com-nordbahn'" }]
```

Nothing was published, no silent last-write-wins. `main` still holds what
merge A set — a human (or a policy) now decides:

```
c.name            | c.hotness | c.notes
------------------+-----------+----------------------------------------------------
Nordbahn Logistik | hot       | Inbox agent: CEO replied today, wants a call — HOT.
```

## make commits

The audit trail — every commit records its actor, human or agent, so
"who set this client to cold, and when?" has an actual answer:

```
01M0E1M5TAR666W76AH9TJWE9G branch=main version=13 actor=simu
01M0E1M6F6F2QR100S05PHEMF8 branch=main version=14 actor=agent-inbox
01M0E1M6K4QCHANXXB2Y8Q3KHT branch=main version=15 actor=agent-billing
01M0E1M73NTNVHE6PKJ7SDQVAQ branch=main version=16 actor=agent-inbox
```
