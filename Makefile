# odin-gtk4: Odin bindings for GTK 4, GDK and GSK. Consumed via -collection:gtk4=/path/to/odin-gtk4
# Each entry is a package directory at the repo root; one with no .odin file yet is skipped.
PACKAGES = $(foreach p,gtk4,$(if $(wildcard $(p)/*.odin),$(p)))
# runic: github.com/Hyperquader-Coders/runic on branch amber-patched, built by its amber-build.sh; see odin-glib/docs/DECISIONS.md §2.
RUNIC ?= ../runic/build/runic
BRANCH ?= main
REMOTE ?= origin
ROOT_COMMIT_MSG ?= Initial odin-gtk4
GTK_STAGE ?= ../amber-gtk4/build/gtk/stage
GLIB ?= ../odin-glib
CAIRO ?= ../odin-cairo
PANGO ?= ../odin-pango
GRAPHENE ?= ../odin-graphene
PIXBUF ?= ../odin-gdk-pixbuf
# A test that leaks or frees badly fails, rather than only warning. `make test ASAN=1` runs
# the tests under AddressSanitizer as well.
ASAN ?=
# amber-gtk4's bundle (libgtk-4 4.16.13), when built, is the library the tests load; the
# distro's 4.14.5 is the floor. With the bundle present the version test is exact.
GTK_BUNDLE = $(GTK_STAGE)/usr/lib/amber-gtk4
TEST_ENV = $(if $(wildcard $(GTK_BUNDLE)/libgtk-4.so.1),LD_LIBRARY_PATH=$(abspath $(GTK_BUNDLE)) GTK_BUNDLE_EXPECTED=1)
# -vet matters beyond this repo: odin test compiles the #+test files of every imported package
# with the consumer's flags, so a vet error here breaks every program that tests against it.
# One test thread: GTK type registration is not thread-safe before gtk_init, and two tests that
# first touch a widget type on different threads race ("cannot register existing type
# 'GtkWidget'", then a hung runner; reproduced under CPU load).
TEST_FLAGS = -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -vet -strict-style $(if $(ASAN),-debug -sanitize:address)
# Every collection the packages import; sibling paths are `?=` variables above.
COLLECTIONS ?= -collection:gtk4=. -collection:glib=$(GLIB) -collection:cairo=$(CAIRO) -collection:pango=$(PANGO) -collection:graphene=$(GRAPHENE) -collection:pixbuf=$(PIXBUF)

.PHONY: help deps generate check test ci clean push force-push lint api check-api check-generated check-no-agent-files check-test-tag

check: check-test-tag ## type-check every package with -vet -strict-style
	@for p in $(PACKAGES); do echo "== check $$p =="; odin check $$p $(COLLECTIONS) -no-entry-point -vet -strict-style || exit 1; done

test: ## run every package's tests (ASAN=1 adds AddressSanitizer)
	@mkdir -p build
	@for p in $(PACKAGES); do echo "== test $$p =="; env -u DISPLAY -u WAYLAND_DISPLAY $(TEST_ENV) odin test $$p $(COLLECTIONS) $(TEST_FLAGS) -out:build/$${p}_test || exit 1; done

# Everything a push has to pass; CI (.github/workflows/ci.yml) runs the same.
ci: check test check-no-agent-files lint ## everything a push has to pass
	@echo 'CI OK'

generate: ## run runic over every package's rune.yml, then the post-processing rules
	@test -x $(RUNIC) || { echo "runic not found at $(RUNIC): clone github.com/Hyperquader-Coders/runic beside this repo on branch amber-patched and run its amber-build.sh"; exit 2; }
	RUNIC=$(abspath $(RUNIC)) GTK_STAGE=$(GTK_STAGE) scripts/generate.sh

deps: ## check the tools and headers generation and tests need
	@test -x $(RUNIC) || echo "missing: runic at $(RUNIC) (github.com/Hyperquader-Coders/runic on amber-patched: run its amber-build.sh)"
	@command -v shellcheck >/dev/null || echo "missing: shellcheck (apt install shellcheck)"
	@for m in gtk4; do pkg-config --exists $$m && echo "$$m $$(pkg-config --modversion $$m)" || echo "missing: $$m (apt install libgtk-4-dev)"; done

clean: ## remove build/
	rm -rf build

push: ## push the branch
	git push "$(REMOTE)" "$(BRANCH)"

# Agent files are never published. Two ways they get in: already tracked, or
# present-and-unignored when `git add -A` below sweeps the whole tree. Both are
# checked here, because a squashed history shows no file being added: a stray
# path appears in the root commit like any other file.
check-no-agent-files: ## refuse agent files that are tracked or not ignored
	@bad=$$(git ls-files | grep -E '(^|/)(\.mcp\.json|\.claude/|\.claude-amber/)' || true); \
	if [ -n "$$bad" ]; then \
		echo "agent files are tracked and must not be published:"; \
		printf '  %s\n' $$bad; \
		echo "fix: git rm -r --cached <path>, then add it to .gitignore"; \
		exit 2; \
	fi
	@for p in .mcp.json .claude .claude-amber; do \
		if [ -e "$$p" ] && ! git check-ignore -q "$$p"; then \
			echo "$$p exists and is not gitignored — 'git add -A' would publish it"; \
			echo "fix: add $$p to .gitignore"; \
			exit 2; \
		fi; \
	done
	@echo "no agent files staged for publication"

force-push: test check-no-agent-files ## squash history into one signed root commit and force-push
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
	git branch -M "$$tmp_branch" "$(BRANCH)"; \
	git branch --set-upstream-to="$(REMOTE)/$(BRANCH)" "$(BRANCH)" >/dev/null 2>&1 || { git fetch "$(REMOTE)" "$(BRANCH)" >/dev/null 2>&1 && git branch --set-upstream-to="$(REMOTE)/$(BRANCH)" "$(BRANCH)" >/dev/null; } || echo "warning: could not set upstream"; \
	echo "Rewrote $$orig_branch as signed root commit on $(REMOTE)/$(BRANCH)."

lint: ## shellcheck the shell scripts; API, cheat sheet and generated-output checks
	@$(MAKE) --no-print-directory check-generated
	@$(MAKE) --no-print-directory check-api
	@scripts/cheatsheet.sh
	@if command -v shellcheck >/dev/null; then \
		git ls-files | while read -r f; do \
			case "$$f" in *.sh|*.bash) echo "$$f";; \
			*) head -1 "$$f" 2>/dev/null | grep -q '^#!.*sh' && echo "$$f";; esac; \
		done | xargs -r shellcheck --severity=warning && echo "shellcheck OK"; \
	else echo "shellcheck not installed — skipping (apt install shellcheck)"; fi

check-generated: ## fail when runic's va_list, [^]T or [^]^T faults are back in the output
	@scripts/check-generated.sh

# docs/API.md: every public declaration, from odin doc. check-api (in lint) fails when it is stale.
api: ## regenerate docs/API.md
	scripts/api.sh $(COLLECTIONS) > docs/API.md

check-api: ## fail when docs/API.md is stale
	@mkdir -p build
	@scripts/api.sh $(COLLECTIONS) > build/API.md
	@cmp -s build/API.md docs/API.md || { echo 'docs/API.md is stale: run make api'; exit 1; }
	@echo "docs/API.md: current"

# `odin build` compiles a package's _test.odin files like any other file unless they
# start with #+test, so a test's imports and @(init) procs would ship in every program
# that imports the package.
check-test-tag: ## refuse _test.odin files without #+test
	@bad=$$(git ls-files --cached --others --exclude-standard '*_test.odin' | grep -Ev '(^|/)tests/' | xargs -r grep -L '^#+test' || true); \
	if [ -n "$$bad" ]; then \
		echo "test files without #+test, which odin build compiles into programs:"; \
		printf '  %s\n' $$bad; \
		exit 2; \
	fi

help: ## this list
	@awk 'BEGIN {FS = ":.*## "} \
	    /^##@ / {printf "\n%s\n", substr($$0, 5)} \
	    /^[a-z][a-z0-9-]*:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
