# --- house.mk: house-rules scripts/binding/house.mk, the same in every repository ---
# What every repository's Makefile shares: help, setup and its parts, the formatters, the agent
# file and test tag checks, ci and force-push. A Makefile sets its own variables, then includes
# this file (a private repository through the bootstrap in docs/TEMPLATES.md, a public one from
# its own copy in house/), then writes its own targets. What it sets before the include:
#
#   NAME         the repository's name (default: its main checkout's folder, from a worktree too)
#   STEPS        the targets `make ci` runs, in order, init-modules first
#   COLLECTIONS  an Odin repository's collections; `ols` writes ols.json from them, and the Odin
#                parts below (odinfmt, ols, the toolchain report) are there only when it is set
#   RUNIC        a runic binding's generator, which the toolchain report looks for
#   GENERATED_ODIN  Odin files the repository generates, which odinfmt leaves as generated (git
#                pathspecs; runic's outputs and type_casts.odin are left out without it)
#
# The packages are project.toml's: `make init-packages` installs what project-toml.sh, beside
# this file, prints. Nothing here needs another checkout.

HOUSE_MK_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
include $(HOUSE_MK_DIR)/project.mk
# The walk over the siblings, project-toml.sh's.
WALK_PACKAGES = env $(project_env) '$(PROJECT_TOML_SH)' packages
WALK_CLONE = env $(project_env) '$(PROJECT_TOML_SH)' clone
NAME ?= $(or $(notdir $(patsubst %/.git,%,$(abspath $(shell git rev-parse --git-common-dir 2>/dev/null)))),$(notdir $(CURDIR)))
HOUSE ?= $(HOUSE_ROOT)/house-rules
# house-rules' checks, in the folder HOUSE_ROOT names: $(call house_check,<script> <args>) fails,
# naming HOUSE_ROOT, when the script is not there. Every kind's Makefile runs its checks through it.
# Where the script is not there, a public repository, whose project.toml names no house-rules and
# whose runner has none, skips it and says so.
house_check = @s='$(HOUSE)/scripts/$(firstword $(1))'; \
	if [ -x "$$s" ]; then "$$s" $(wordlist 2,$(words $(1)),$(1)); \
	elif [ -f project.toml ] && ! grep -q '^house-rules = ' project.toml; then echo "$@: $(firstword $(1)) skipped: house-rules is private"; \
	else echo "$@: $$s not found: set HOUSE_ROOT to the folder holding house-rules; make init-siblings clones it"; exit 2; fi

.DEFAULT_GOAL := help

##@ The house's
.PHONY: help setup init-packages init-modules init-workstation init-siblings ci force-push check-no-agent-files check-test-tag fmt check-fmt fmt-sh check-fmt-sh fmt-tools

# The Odin targets below are listed only in an Odin repository, as they are only defined there.
help: ## this list
	@awk -v odin='$(if $(ODIN_REPO),1)' 'BEGIN {FS = ":.*## "} \
	    /^ifneq \(\$$\(ODIN_REPO\),\)$$/ {skip = (odin != 1); next} \
	    skip && /^endif$$/ {skip = 0; next} \
	    skip {next} \
	    /^##@ / {printf "\n%s\n", substr($$0, 5)} \
	    /^[a-z][a-z0-9-]*:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# --- setup ---
# `make setup` is the one command after a fresh clone: the siblings, the system packages (sudo
# apt), the language packages and the desk's own settings. CI runs `make init-siblings`, then
# `sudo apt-get update && make init-packages APT_FLAGS=-y`, then `make ci`; at a desk apt asks
# before it installs.
setup: init-siblings init-packages init-modules init-workstation ## everything a fresh clone needs: the siblings, the system packages (sudo apt), the language packages, the desk's settings

# This repository's build and test packages from project.toml, and the build packages of
# every sibling and of theirs in turn; a package missing on a runner is added there, never to a
# workflow.
APT_FLAGS ?=
init-packages: ## install the system packages project.toml names, with the siblings' (sudo apt)
	packages=$$($(WALK_PACKAGES)) && \
	sudo apt-get install $(APT_FLAGS) --no-install-recommends $$packages

# A repository with a lock adds its install to this rule's recipe; `ci` reaches it either way.
init-modules: ## install the language packages from the lock, where there is one

# project.toml's `[siblings.<ROOT_VARIABLE>]` tables name the repositories this one needs
# beside it, one a line as `<name> = "https://github.com/<owner>/<name>"`. `make init-siblings`
# clones each one that is missing into `$(<ROOT_VARIABLE>)/<name>`, then the siblings each of
# those names in turn: project-toml.sh's walk, the one init-packages reads the packages with. Each
# root variable is set in the environment or on the command line, at a desk by its shell and in
# CI by the workflow, each to a folder above its workspace.
init-siblings: ## clone the siblings project.toml names, and theirs in turn, that are missing from their roots; one already there is left as it is
	@$(WALK_CLONE)

# What only a desk needs; a repository adds its own (git hooks) as prerequisites.
init-workstation: fmt-tools ## set up a desk: what is missing of the formatters, and in an Odin repository the editor's ols.json and the toolchain report

# --- ci ---
# The steps are written out in STEPS, cheap first, so a push fails on formatting in seconds; the
# sandbox runs each on its own, with its own log and status.
ci: $(STEPS) ## everything a push has to pass

# Agent files are never published: tracked, or present and not ignored when a push is about to
# happen.
check-no-agent-files: ## refuse agent files that are tracked or not ignored
	@bad=$$(git ls-files | grep -E '(^|/)(\.mcp\.json|\.claude/|\.claude-amber/|\.codex/|AGENTS\.md$$|CLAUDE\.md$$)' || true); \
	if [ -n "$$bad" ]; then \
		echo "agent files are tracked and must not be published:"; \
		printf '  %s\n' $$bad; \
		echo "fix: git rm -r --cached <path>, then add it to .gitignore"; \
		exit 2; \
	fi
	@for p in .mcp.json .claude .claude-amber .codex AGENTS.md CLAUDE.md; do \
		if [ -e "$$p" ] && ! git check-ignore -q "$$p"; then \
			echo "$$p exists and is not gitignored"; \
			exit 2; \
		fi; \
	done
	@echo "no agent files staged for publication"

# --- formatting ---
# Shell scripts go through shfmt, with tabs: every tracked file that is a shell script by its name
# or its first line, but a public repository's copies in house/, checked where they come from.
# apt's shfmt, the one a runner has, comes before any other on the PATH:
# versions differ in layout.
SHFMT ?= $(firstword $(wildcard /usr/bin/shfmt) shfmt)
SHFMT_FLAGS = -i 0
# vendor/ holds other people's code (Go's), laid out as they lay it out.
SH_SOURCES = git ls-files -z --cached --others --exclude-standard -- . ':!house/' ':!vendor/' | grep -zv '/$$' | xargs -0 -r $(SHFMT) -f

fmt: fmt-sh ## format the code in place
check-fmt: check-fmt-sh ## fail when a file is not as make fmt leaves it
lint: check-fmt

fmt-sh: ## lay the shell scripts out in place
	@command -v $(SHFMT) >/dev/null || { echo "shfmt not installed: skipping (make init-packages installs it)"; exit 0; }; \
	$(SH_SOURCES) | xargs -r -d '\n' $(SHFMT) $(SHFMT_FLAGS) -w

# Without shfmt, a repository that tracks no shell script (by its name or its first line) has
# nothing to check; one that does fails on a runner, where project.toml installs it.
check-fmt-sh: ## fail when a shell script is not as make fmt-sh leaves it
	@if ! command -v $(SHFMT) >/dev/null; then \
		git ls-files -z -- . ':!house/' ':!vendor/' | xargs -0 -r head -qn1 -- 2>/dev/null | grep -aq '^#!.*sh' || \
			git ls-files -- '*.sh' '*.bash' ':!house/' ':!vendor/' | grep -q . || { echo "shfmt OK (no shell scripts)"; exit 0; }; \
		if [ "$$GITHUB_ACTIONS" = true ]; then echo "shfmt is not installed on this runner; it is in project.toml"; exit 1; fi; \
		echo "shfmt not installed: skipping (make init-packages installs it)"; exit 0; \
	fi; \
	bad=$$($(SH_SOURCES) | xargs -r -d '\n' $(SHFMT) $(SHFMT_FLAGS) -l) || exit 1; \
	if [ -n "$$bad" ]; then echo "not formatted:"; echo "$$bad"; echo "fix: make fmt"; exit 1; fi; \
	echo "shfmt OK"

fmt-tools: ## name a formatter that is missing
	@command -v $(SHFMT) >/dev/null || echo "missing: shfmt (make init-packages installs it)"

ifneq ($(ODIN_REPO),)
# `odin build` compiles a package's _test.odin files like any other file unless they start with
# #+test, so a test's imports would ship in the program. A program of its own under tests/ is
# not a package's test.
check-test-tag: ## refuse test files without #+test
	@bad=$$(git ls-files --cached --others --exclude-standard '*_test.odin' | grep -Ev '(^|/)tests/' | xargs -r grep -L '^#+test' || true); \
	if [ -n "$$bad" ]; then \
		echo "test files without #+test, which odin build compiles into programs:"; \
		printf '  %s\n' $$bad; \
		exit 2; \
	fi

# Hand-written Odin goes through odinfmt (amber-ols), with odinfmt.json. What runic writes (each
# rune.yml's `out:`) and type_casts.odin are generated and stay as generated. house-rules'
# odin-fmt, where it is there, formats until the output settles and refuses a file whose comments
# odinfmt would damage; without it, odinfmt runs once over each file.
ODINFMT ?= odinfmt
ODIN_FMT ?= $(HOUSE)/scripts/odin-fmt
GENERATED = $(GENERATED_ODIN) $(foreach y,$(wildcard */rune.yml),$(dir $(y))$(shell awk '$$1 == "out:" {print $$2}' $(y))) $(wildcard */type_casts.odin)
ODIN_SOURCES = git ls-files --cached --others --exclude-standard '*.odin' $(foreach g,$(GENERATED),':!$(g)')

fmt: fmt-odin
check-fmt: check-fmt-odin
.PHONY: fmt-odin check-fmt-odin ols check-toolchain

fmt-odin:
	@if [ -x '$(ODIN_FMT)' ]; then $(ODIN_SOURCES) | ODINFMT=$(ODINFMT) '$(ODIN_FMT)'; \
	else $(ODIN_SOURCES) | while IFS= read -r f; do $(ODINFMT) -w "$$f" || exit 1; done; fi

check-fmt-odin:
	@if ! command -v $(ODINFMT) >/dev/null; then if [ "$$GITHUB_ACTIONS" = true ]; then echo "odinfmt is not installed on this runner; the workflow asks for it (ols: true)"; exit 1; fi; echo "odinfmt not installed: skipping (apt install amber-ols)"; exit 0; fi; \
	bad=0; \
	for f in $$($(ODIN_SOURCES)); do \
		$(ODINFMT) -stdin < "$$f" | cmp -s - "$$f" || { echo "not formatted: $$f"; bad=1; }; \
	done; \
	if [ $$bad = 1 ]; then echo "fix: make fmt"; exit 1; fi; \
	echo "odinfmt OK"

# ols.json is the Odin language server's settings, which an editor reads for completion and
# go-to-definition. It names the same collections as the build and takes a path as written, with
# no variables: so it is written from the build's collections, with absolute paths, and is not
# tracked. Run it again after a collection moves.
OLS_COLLECTIONS ?= $(sort $(filter -collection:%,$(COLLECTIONS)))
ols: ## write ols.json, the editor's settings, from the build's collections
	@{ printf '{\n\t"collections": [\n'; sep=''; \
	for c in $(patsubst -collection:%,%,$(OLS_COLLECTIONS)); do \
		printf '%b\t\t{ "name": "%s", "path": "%s" }' "$$sep" "$${c%%=*}" "$$(realpath -m "$${c#*=}")"; sep=',\n'; \
	done; \
	printf '\n\t],\n\t"enable_document_symbols": true,\n\t"enable_hover": true,\n\t"enable_snippets": true\n}\n'; } > ols.json
	@echo "ols: wrote ols.json, $(words $(OLS_COLLECTIONS)) collections"

# What apt does not bring is reported and never installed: the Odin compiler, odinfmt and, in a
# runic binding, runic.
check-toolchain: ## report what is missing of the toolchain
	@ok=true; \
	if command -v odin >/dev/null; then echo "odin: $$(odin version)"; \
	else echo "missing: odin (https://odin-lang.org/docs/install)"; ok=false; fi; \
	if command -v $(ODINFMT) >/dev/null; then echo "odinfmt: $$(command -v $(ODINFMT))"; \
	else echo "missing: odinfmt (apt install amber-ols)"; ok=false; fi; \
	if [ -n '$(RUNIC)' ]; then \
		if [ -x '$(RUNIC)' ]; then echo "runic: $(RUNIC)"; \
		else echo "missing: runic at $(RUNIC) (clone github.com/Hyperquader-Coders/runic beside this repo, check out amber-patched and run its amber-build.sh)"; ok=false; fi; \
	fi; \
	$$ok

init-workstation: ols check-toolchain
endif

# --- force-push ---
# One signed root commit in place of the history, force-pushed: a public repository is published
# only this way, and only once `make ci` passes.
BRANCH ?= main
REMOTE ?= origin
ROOT_COMMIT_MSG ?= Initial $(NAME)
force-push: ci ## squash history into one signed root commit and force-push
	@test -z "$$(git status --porcelain)" || { \
		echo "Working tree is dirty. Commit, stash, or revert changes first."; \
		exit 2; \
	}
	@set -e; \
	orig_branch="$$(git branch --show-current)"; \
	test -n "$$orig_branch" || { echo "force-push: detached HEAD, check out a branch first"; exit 1; }; \
	tmp_branch="root-squash-$$(date +%s)"; \
	step="starting"; ok=0; \
	trap 'if [ "$$ok" != 1 ]; then echo "force-push FAILED while: $$step. Local history is intact on $$orig_branch; $(REMOTE)/$(BRANCH) was not replaced." >&2; git checkout -f "$$orig_branch" >/dev/null 2>&1 || true; git branch -D "$$tmp_branch" >/dev/null 2>&1 || true; exit 1; fi' EXIT; \
	step="creating the orphan branch"; git checkout --orphan "$$tmp_branch"; \
	step="staging the tree"; git add -A; \
	step="signing the root commit"; git commit -S -m "$(ROOT_COMMIT_MSG)"; \
	step="pushing to $(REMOTE)/$(BRANCH) (refused or unreachable)"; git push --force "$(REMOTE)" "$$tmp_branch:$(BRANCH)"; \
	step="verifying $(REMOTE)/$(BRANCH) equals the new commit"; \
	remote_sha="$$(git ls-remote "$(REMOTE)" "refs/heads/$(BRANCH)" | cut -f1)"; \
	test -n "$$remote_sha" && test "$$remote_sha" = "$$(git rev-parse HEAD)"; \
	ok=1; \
	other_wt="$$(git worktree list --porcelain | awk -v b="branch refs/heads/$(BRANCH)" '/^worktree /{w=substr($$0, 10)} $$0 == b {print w}')"; \
	if [ -n "$$other_wt" ] && [ "$$other_wt" != "$$(git rev-parse --show-toplevel)" ]; then \
		git fetch "$(REMOTE)" "$(BRANCH)" >/dev/null 2>&1 || true; \
		git checkout -q --detach; git branch -D "$$tmp_branch" >/dev/null; \
		echo "Rewrote $$orig_branch as signed root commit on $(REMOTE)/$(BRANCH)."; \
		echo "$(BRANCH) is checked out in $$other_wt; once it is clean: git -C $$other_wt fetch && git -C $$other_wt reset --keep $(REMOTE)/$(BRANCH)"; \
	else \
		git branch -M "$$tmp_branch" "$(BRANCH)"; \
		git branch --set-upstream-to="$(REMOTE)/$(BRANCH)" "$(BRANCH)" >/dev/null 2>&1 || { git fetch "$(REMOTE)" "$(BRANCH)" >/dev/null 2>&1 && git branch --set-upstream-to="$(REMOTE)/$(BRANCH)" "$(BRANCH)" >/dev/null; } || echo "warning: could not set upstream"; \
		echo "Rewrote $$orig_branch as signed root commit on $(REMOTE)/$(BRANCH)."; \
	fi
