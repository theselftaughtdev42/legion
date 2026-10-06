KIT        := polly-planner
SKILLS_OUT := $(KIT)/files/home/.claude/skills
SOURCES    := skills/borrowed/SOURCES.yaml
# <source>/<skill> for every borrowed skill, e.g. mattpocock/grilling
SKILLS     := $(shell awk -f scripts/sources.awk $(SOURCES) | awk '$$2 == "skill" {print $$1 "/" $$3}')

REPO ?=
NAME  = polly-$(notdir $(abspath $(REPO)))

.PHONY: help sync build secrets polly smoke clean

help:
	@echo "make sync SOURCE=<name> [REF=<sha|branch>]  re-fetch one borrowed source at its pinned (or new) ref"
	@echo "make build                                  compile borrowed skills into the kit and validate it"
	@echo "make secrets                                store a global GitHub secret backed by host 'gh auth token'"
	@echo "make polly REPO=<path>                      launch Polly on a clean checkout"
	@echo "make smoke                                  spin up a throwaway sandbox and check the kit"
	@echo "make clean                                  remove build output"

sync:
	scripts/sync.sh "$(SOURCE)" $(REF)

build:
	rm -rf $(SKILLS_OUT)
	mkdir -p $(SKILLS_OUT)
	$(foreach s,$(SKILLS),cp -R skills/borrowed/$(s) $(SKILLS_OUT)/$(notdir $(s));)
	sbx kit validate ./$(KIT)

secrets:
	sbx secret set github --command "gh auth token"

polly: build
	@test -n "$(REPO)" || { echo "usage: make polly REPO=<path>"; exit 1; }
	@git -C "$(REPO)" rev-parse --git-dir >/dev/null 2>&1 || { echo "$(REPO) is not a git repo"; exit 1; }
	@test -z "$$(git -C "$(REPO)" status --porcelain)" || { echo "$(REPO) has uncommitted changes; commit or stash them before running Polly"; exit 1; }
	@if sbx ls | awk 'NR>1 {print $$1}' | grep -qx "$(NAME)"; then \
		sbx run --name $(NAME); \
	else \
		sbx run --skills=off --name $(NAME) claude --kit ./$(KIT) "$(abspath $(REPO))"; \
	fi

smoke: build
	scripts/smoke.sh

clean:
	rm -rf $(KIT)/files/home/.claude
