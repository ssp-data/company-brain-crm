# SSP Data CRM — a company brain instead of CRM software (omnigraph 0.8.1)
#
# The story, in order:
#
#   make check      # 0. CLI present?
#   make init       # 1. cluster: validate -> import/refresh -> plan -> apply
#   make seed       # 2. load 98 nodes / 123 edges (50-person company + funnel)
#   make team       # 3. the whole team (a stored query)
#   make funnel     #    the sales-funnel kanban — as a query
#   make hot        #    who to call today
#   make log        #    everything that happened with one company
#   make intro      #    who can warm-intro us at Nordbahn?
#   make agents     # 4. two agents write on parallel branches -> AUTO-MERGE
#   make conflict   # 5. two agents disagree on one row -> merge BLOCKED
#   make commits    #    git-style audit trail (who wrote what, human or agent)
#
# Resets:
#   make reset-data # re-seed main to the clean baseline
#   make clean      # nuke cluster state + graph store (start from zero)
#   make demo       # run the whole sequence end-to-end

STORE := graphs/crm.omni
ACTOR := simu
FMT   := --format table
GQ    := --query queries/crm.gq --store $(STORE) $(FMT)

.DEFAULT_GOAL := help

.PHONY: help check init seed team funnel hot log intro pipeline agents \
        conflict commits branches reset-data clean demo

help:
	@echo ""
	@echo "SSP Data CRM — run these in order:"
	@echo "  make check        0. omnigraph version"
	@echo "  make init         1. cluster validate -> import/refresh -> plan -> apply"
	@echo "  make seed         2. load seed (98 nodes / 123 edges)"
	@echo "  make team         3. all 50 employees (stored query)"
	@echo "  make funnel          the sales funnel (the kanban, as a query)"
	@echo "  make hot             hot prospects — who to call today"
	@echo "  make log             full history with Alpenkraft"
	@echo "  make intro           warm-intro path into Nordbahn"
	@echo "  make agents       4. 2 agents on parallel branches -> auto-merge"
	@echo "  make conflict     5. 2 agents disagree -> merge blocked, human decides"
	@echo "  make commits         audit trail (actor on every commit)"
	@echo ""
	@echo "  make demo         everything end-to-end"
	@echo "  make reset-data   re-seed main to clean baseline"
	@echo "  make clean        remove __cluster/ and graphs/ (full reset)"
	@echo ""

check:
	@echo "== omnigraph version =="
	omnigraph --version

# 1. Converge the declared cluster: schema + 8 stored queries -> creates graphs/crm.omni.
#    `import` only works on a missing ledger; use `refresh` if it already exists.
init:
	@echo "== validate cluster config =="
	omnigraph cluster validate --config .
	@echo "== import (or refresh) local state ledger =="
	@if [ -f __cluster/state.json ]; then \
	  echo "state.json exists -> refresh"; omnigraph cluster refresh --config . ; \
	else \
	  echo "no state -> import"; omnigraph cluster import --config . ; \
	fi
	@echo "== plan (read-only diff) =="
	omnigraph cluster plan --config .
	@echo "== apply (schema + stored queries) =="
	omnigraph cluster apply --config . --as $(ACTOR)

# 2. The company: SSP Data, 50 employees, 10 companies we chase, 12 deals, the log.
seed:
	@echo "== load seed.jsonl (overwrite = clean baseline) =="
	omnigraph load --data seed.jsonl --mode overwrite --as $(ACTOR) $(STORE)

# 3. The "views" — each one a stored, typed query invoked by name.
team:
	@echo "== stored query: team (everyone WorksAt com-ssp) =="
	omnigraph query team $(GQ)

funnel:
	@echo "== stored query: sales_funnel (the kanban board, as data) =="
	omnigraph query sales_funnel $(GQ)

hot:
	@echo "== stored query: hot_prospects =="
	omnigraph query hot_prospects $(GQ)

log:
	@echo "== stored query: company_log for Alpenkraft =="
	omnigraph query company_log --params '{"slug":"com-alpenkraft"}' $(GQ)

intro:
	@echo "== stored query: warm_intro — who knows someone at Nordbahn? =="
	omnigraph query warm_intro --params '{"slug":"com-nordbahn"}' $(GQ)

pipeline:
	@echo "== stored query: my_pipeline for Lea (Head of Content) =="
	omnigraph query my_pipeline --params '{"slug":"per-lea-brunner"}' $(GQ)

# 4. THE MEAT: two agents write concurrently, each on its own branch forked
#    from main. Their changes don't touch main until merged. Both merges are
#    clean (they touched different rows), so they AUTO-merge — no human needed.
agents:
	@echo "== agent 1 (inbox-scan): new interactions + VectorHut warm->hot, on its own branch =="
	@omnigraph branch delete agent/inbox-scan --as $(ACTOR) --store $(STORE) >/dev/null 2>&1 || true
	omnigraph load --data agents/inbox-scan.jsonl --mode merge \
	  --branch agent/inbox-scan --from main --as agent-inbox --store $(STORE)
	@echo ""
	@echo "== agent 2 (billing-sync): Alpenkraft PoC proposal->won, on ITS own branch =="
	@omnigraph branch delete agent/billing-sync --as $(ACTOR) --store $(STORE) >/dev/null 2>&1 || true
	omnigraph load --data agents/billing-sync.jsonl --mode merge \
	  --branch agent/billing-sync --from main --as agent-billing --store $(STORE)
	@echo ""
	@echo "== isolation: on main, VectorHut is still 'warm' =="
	omnigraph query q -e 'query q(){ match { $$c: Company { slug: "com-vectorhut" } } return { $$c.name, $$c.hotness } }' --store $(STORE) $(FMT)
	@echo ""
	@echo "== both merges are clean -> auto-merge, branches deleted =="
	omnigraph branch merge agent/inbox-scan   --into main --as agent-inbox   --store $(STORE)
	omnigraph branch merge agent/billing-sync --into main --as agent-billing --store $(STORE)
	@omnigraph branch delete agent/inbox-scan   --as $(ACTOR) --store $(STORE) >/dev/null 2>&1 || true
	@omnigraph branch delete agent/billing-sync --as $(ACTOR) --store $(STORE) >/dev/null 2>&1 || true
	@echo ""
	@echo "== main after auto-merge: VectorHut hot, Alpenkraft won =="
	omnigraph query q -e 'query q(){ match { $$c: Company { slug: "com-vectorhut" } } return { $$c.name, $$c.hotness } }' --store $(STORE) $(FMT)
	omnigraph query q -e 'query q(){ match { $$d: Deal { slug: "deal-alpenkraft-poc" } } return { $$d.name, $$d.stage } }' --store $(STORE) $(FMT)

# 5. GOVERNANCE: two agents update the SAME row with different values.
#    First merge lands; second is BLOCKED with a typed conflict (DivergentUpdate)
#    and publishes nothing — a human (or a policy) has to decide. No silent
#    last-write-wins, ever.
conflict:
	@echo "== inbox agent: Nordbahn CEO replied -> hotness=hot (branch A) =="
	@omnigraph branch delete agent/inbox-scan2 --as $(ACTOR) --store $(STORE) >/dev/null 2>&1 || true
	omnigraph load --data agents/conflict-inbox.jsonl --mode merge \
	  --branch agent/inbox-scan2 --from main --as agent-inbox --store $(STORE)
	@echo ""
	@echo "== hygiene agent: no touchpoint in 60 days -> hotness=cold (branch B) =="
	@omnigraph branch delete agent/crm-hygiene --as $(ACTOR) --store $(STORE) >/dev/null 2>&1 || true
	omnigraph load --data agents/conflict-hygiene.jsonl --mode merge \
	  --branch agent/crm-hygiene --from main --as agent-hygiene --store $(STORE)
	@echo ""
	@echo "== merge A: clean =="
	omnigraph branch merge agent/inbox-scan2 --into main --as agent-inbox --store $(STORE)
	@echo ""
	@echo "== merge B: BLOCKED — DivergentUpdate on com-nordbahn (this error is the feature) =="
	-omnigraph branch merge agent/crm-hygiene --into main --as agent-hygiene --store $(STORE) 2>&1 | grep -vi -e backtrace -e "^Location" -e "crates/" || true
	@echo ""
	@echo "== main untouched by the blocked merge — Nordbahn stays as merge A set it =="
	omnigraph query q -e 'query q(){ match { $$c: Company { slug: "com-nordbahn" } } return { $$c.name, $$c.hotness, $$c.notes } }' --store $(STORE) $(FMT)
	@omnigraph branch delete agent/inbox-scan2 --as $(ACTOR) --store $(STORE) >/dev/null 2>&1 || true
	@omnigraph branch delete agent/crm-hygiene --as $(ACTOR) --store $(STORE) >/dev/null 2>&1 || true

commits:
	@echo "== commit history — every write has an actor (human or agent) =="
	omnigraph commit list --store $(STORE)

branches:
	omnigraph branch list --store $(STORE)

# --- resets -------------------------------------------------------------------

reset-data:
	@echo "== re-seed main to clean baseline (drops agent-written rows) =="
	omnigraph load --data seed.jsonl --mode overwrite --as $(ACTOR) $(STORE)

clean:
	@echo "== removing __cluster/ and graphs/ (full reset) =="
	rm -rf __cluster graphs
	@echo "done. run 'make init && make seed' to rebuild."

# --- everything at once -------------------------------------------------------

demo: check init seed team funnel hot log intro agents conflict commits
	@echo ""
	@echo "== demo complete: 50-person CRM, agents merged, conflict blocked, all audited =="
