# --- binding.mk: house-rules scripts/binding/binding.mk, the same in every runic binding ---
# What every runic binding does, for a project.toml whose kind is "binding": check and test each
# package, regenerate them with runic, keep docs/API.md and the cheat sheet current, and lint
# with the house's checks in a private binding, the one whose project.toml names house-rules (a
# public binding's runner has none, and its own scripts/cheatsheet-compile.sh, where it has one,
# compiles the cheat sheet).
# [build] lib names the packages, [test] lib any test package beside them; the collections come
# from the siblings (project.mk).
# The binding's Makefile is the bootstrap, or `include house/binding.mk` in a public one, then
# what is its own: link flags its tests need (`ODIN_TEST_FLAGS += ...`), a check of its own
# (`[project] steps` names it, or `lint: <check>` adds it to lint).

BINDING_MK_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
# AMBER_ROOT is the Amber tree, the folder holding the suite's checkouts: mise sets it on a
# development machine and the workflow sets it to its workspace. Unset, it is the folder holding
# this checkout: that fallback is for people outside the house, who clone the bindings side by side.
AMBER_ROOT ?= $(abspath $(CURDIR)/..)
include $(BINDING_MK_DIR)project.mk
$(if $(filter binding,$(KIND)),,$(error binding.mk is for a project.toml whose kind is binding, not '$(KIND)'))

# Each package is a folder at the top; one with no .odin file yet is skipped.
PACKAGES := $(strip $(foreach p,$(call project,get build lib) $(call project,get test lib),$(if $(wildcard $(p)/*.odin),$(p))))
# runic: github.com/Hyperquader-Coders/runic branch amber-patched, built by its amber-build.sh;
# see odin-glib/docs/DECISIONS.md §2.
RUNIC ?= $(AMBER_ROOT)/runic/build/runic

# A test that leaks or frees badly fails, rather than only warning. `make test ASAN=1` runs the
# tests under AddressSanitizer as well. -vet -strict-style matter beyond this repo: odin test
# compiles the #+test files of every imported package with the consumer's flags, so a vet error
# here breaks every program that tests against it. One test thread in every binding: GTK and
# GObject type registration is not thread-safe, and two tests that first touch a type on
# different threads collide and hang the runner.
ASAN ?=
# The compiler, as lib.mk names it: a binding whose tests need a display runs them under Xvfb
# with `test: ODIN = xvfb-run -a odin`, the display the recipe clears being Xvfb's own.
ODIN ?= odin
ODIN_FLAGS = $(COLLECTIONS) -vet -strict-style
ODIN_TEST_FLAGS = $(ODIN_FLAGS) -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true $(if $(ASAN),-debug -sanitize:address)

##@ The binding's
.PHONY: generate check test clean push lint api check-api check-generated

check: check-test-tag ## type-check every package with -vet -strict-style
	@for p in $(PACKAGES); do echo "== check $$p =="; $(ODIN) check $$p $(ODIN_FLAGS) -no-entry-point || exit 1; done

test: ## run every package's tests (ASAN=1 adds AddressSanitizer)
	@mkdir -p build
	@for p in $(PACKAGES); do echo "== test $$p =="; env -u DISPLAY -u WAYLAND_DISPLAY $(ODIN) test $$p $(ODIN_TEST_FLAGS) -out:build/$${p}_test || exit 1; done

generate: ## run runic over every package's rune.yml, then the post-processing rules
	@test -x $(RUNIC) || { echo "runic not found at $(RUNIC): clone github.com/Hyperquader-Coders/runic beside this repo, check out amber-patched and run its amber-build.sh"; exit 2; }
	RUNIC=$(abspath $(RUNIC)) scripts/generate.sh

clean: ## remove build/
	rm -rf build

push: ## push the branch
	git push "$(REMOTE)" "$(BRANCH)"

check-generated: ## fail when a single-object parameter is `[^]` again or a va_list procedure is bound
	@scripts/check-generated.sh

lint: ## the generated-output guard, API and cheat sheet freshness, the host check, shellcheck, package names, narration, the cheat sheet's compile
	@$(MAKE) --no-print-directory check-generated
	@$(MAKE) --no-print-directory check-api
	@scripts/cheatsheet.sh
	@if [ -x "$(HOUSE)/scripts/check-example-hosts" ]; then "$(HOUSE)/scripts/check-example-hosts" "$(CURDIR)"; \
	else echo "check-example-hosts not found in $(HOUSE)/scripts: skipping (house-rules is private; HOUSE_ROOT or HOUSE finds it)"; fi
	@if grep -q '^house-rules = ' project.toml; then \
		"$(HOUSE)/scripts/check-package-names" --library $(NAME) . && "$(HOUSE)/scripts/check-narration" && \
		{ [ ! -f docs/CHEATSHEET.md ] || "$(HOUSE)/scripts/cheatsheet-compile.sh" $(COLLECTIONS); }; \
	elif [ -f docs/CHEATSHEET.md ] && [ -x scripts/cheatsheet-compile.sh ]; then scripts/cheatsheet-compile.sh $(COLLECTIONS); fi
	@if command -v shellcheck >/dev/null; then \
		git ls-files | while read -r f; do \
			case "$$f" in *.sh|*.bash) echo "$$f";; \
			*) head -1 "$$f" 2>/dev/null | grep -q '^#!.*sh' && echo "$$f";; esac; \
		done | xargs -r shellcheck --severity=warning && echo "shellcheck OK"; \
	elif [ "$$GITHUB_ACTIONS" = true ]; then echo "shellcheck is not installed on this runner; project.toml's test packages name it"; exit 1; \
	else echo "shellcheck not installed: skipping (apt install shellcheck)"; fi

# docs/API.md: every public declaration, from odin doc. check-api (in lint) fails when it is
# stale. scripts/api.sh hands its arguments to odin doc; everything else is in scripts/api.conf.
api: ## regenerate docs/API.md
	scripts/api.sh $(ODIN_FLAGS) > docs/API.md

check-api: ## fail when docs/API.md is stale
	@mkdir -p build
	@scripts/api.sh $(ODIN_FLAGS) > build/API.md
	@cmp -s build/API.md docs/API.md || { echo 'docs/API.md is stale: run make api'; exit 1; }
	@echo "docs/API.md: current"

include $(BINDING_MK_DIR)house.mk
