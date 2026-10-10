AGENT      ?=
# <persona>-<role>, e.g. polly-planner -> persona polly
PERSONA     = $(firstword $(subst -, ,$(AGENT)))
KIT         = agents/$(AGENT)
KITS        = --kit ./$(KIT) --kit ./no-attribution
SKILLS_OUT  = $(KIT)/files/home/.claude/skills
SOURCES    := skills/borrowed/SOURCES.yaml
# <source>/<skill> for every borrowed skill, e.g. mattpocock/grilling
SKILLS     := $(shell awk -f scripts/sources.awk $(SOURCES) | awk '$$2 == "skill" {print $$1 "/" $$3}')

REPO ?=
NAME  = $(PERSONA)-$(notdir $(abspath $(REPO)))

.PHONY: help sync build secrets run smoke clean check-agent

help:
	@echo "make sync SOURCE=<name> [REF=<sha|branch>]  re-fetch one borrowed source at its pinned (or new) ref"
	@echo "make build AGENT=<persona>-<role>           compile borrowed skills into the agent's kit and validate it"
	@echo "make secrets                                store a global GitHub secret backed by host 'gh auth token'"
	@echo "make run AGENT=<persona>-<role> REPO=<path> launch the agent on a clean checkout"
	@echo "make smoke AGENT=<persona>-<role>           spin up a throwaway sandbox and check the agent's kit"
	@echo "make clean                                  remove build output for every agent"
	@echo
	@echo "agents: $(notdir $(wildcard agents/*))"

check-agent:
	@test -n "$(AGENT)" || { echo "AGENT=<persona>-<role> is required (one of: $(notdir $(wildcard agents/*)))"; exit 1; }
	@test -f "$(KIT)/spec.yaml" || { echo "no agent at $(KIT)/ (one of: $(notdir $(wildcard agents/*)))"; exit 1; }

sync:
	scripts/sync.sh "$(SOURCE)" $(REF)

build: check-agent
	rm -rf $(SKILLS_OUT)
	mkdir -p $(SKILLS_OUT)
	$(foreach s,$(SKILLS),cp -R skills/borrowed/$(s) $(SKILLS_OUT)/$(notdir $(s));)
	sbx kit validate ./$(KIT)
	sbx kit validate ./no-attribution

secrets:
	sbx secret set github --command "gh auth token"

run: build
	@test -n "$(REPO)" || { echo "usage: make run AGENT=$(AGENT) REPO=<path>"; exit 1; }
	@git -C "$(REPO)" rev-parse --git-dir >/dev/null 2>&1 || { echo "$(REPO) is not a git repo"; exit 1; }
	@test -z "$$(git -C "$(REPO)" status --porcelain)" || { echo "$(REPO) has uncommitted changes; commit or stash them before running $(AGENT)"; exit 1; }
	@if sbx ls | awk 'NR>1 {print $$1}' | grep -qx "$(NAME)"; then \
		sbx run --name $(NAME); \
	else \
		sbx run --skills=off --name $(NAME) claude $(KITS) "$(abspath $(REPO))"; \
	fi

smoke: build
	scripts/smoke.sh "$(AGENT)"

clean:
	rm -rf agents/*/files/home/.claude
