# --- project.mk: house-rules scripts/binding/project.mk, the same in every repository ---
# What a repository's project.toml says, for house.mk and the kind Makefiles, read through
# project-toml.sh beside this file (docs/PROJECT_TOML.md). Without a project.toml it sets
# nothing, and the Makefile sets STEPS and COLLECTIONS itself. Included once, before anything
# reads what it sets.

ifndef PROJECT_MK
PROJECT_MK := $(lastword $(MAKEFILE_LIST))
PROJECT_TOML_SH := $(patsubst %/,%,$(dir $(PROJECT_MK)))/project-toml.sh

ifneq ($(wildcard project.toml),)
# A checkout somewhere else is set per machine in the gitignored local.mk (ODIN_WEB_DIR = ...).
# The reader is given it, and every root, as make sees them: make 4.3's $(shell) passes no
# exported variable on.
project_before := $(.VARIABLES)
-include local.mk
# A root the Makefile sets itself (a binding's fallback, AMBER_ROOT ?= the folder above) is
# handed on too; a <NAME>_DIR only from local.mk or outside make, as the Makefiles set
# variables of their own with that ending.
project_given := $(filter-out $(project_before),$(.VARIABLES)) $(foreach v,$(.VARIABLES),$(if $(filter environment% command%,$(origin $(v))),$(v),$(if $(and $(filter %_ROOT,$(v)),$(filter file,$(origin $(v)))),$(v))))
project_env = $(foreach v,$(sort $(filter %_ROOT %_DIR,$(project_given))),$(v)='$($(v))')
# $(call project,<arguments>): project-toml.sh's answer; make stops with its words when it
# refuses, so a file out of the layout or a sibling not there is never read as an empty answer.
project = $(strip $(eval project_out := $(shell env $(project_env) '$(PROJECT_TOML_SH)' $(1) 2>&1))$(if $(filter 0,$(.SHELLSTATUS)),$(project_out),$(error $(project_out))))
KIND := $(call project,get project kind)
STEPS := $(call project,steps)
# Read when first used and kept, so that init-siblings runs before the siblings are there. A
# rule's prerequisites can name them, and make expands those while it reads the Makefile, before
# any recipe: for the goals that fetch the siblings, and help and deb-path, which only print (the
# apt archive asks each repository's deb-path with no siblings cloned), a sibling not there yet
# gives no collections, read again at each use, rather than stopping make before it can clone it.
PROJECT_SETUP_GOALS := init-siblings init-packages setup help deb-path
ifeq ($(filter-out $(PROJECT_SETUP_GOALS),$(or $(MAKECMDGOALS),help)),)
COLLECTIONS = $(shell env $(project_env) '$(PROJECT_TOML_SH)' collections 2>/dev/null)
else
COLLECTIONS = $(eval COLLECTIONS := $(call project,collections))$(COLLECTIONS)
endif
# A kind's own settings: $(call setting,<key>), "" when the file does not hold it.
setting = $(call project,get $(KIND) $(1))
ODIN_REPO := $(filter binding lib web-app desktop,$(KIND))
else
ODIN_REPO := $(strip $(COLLECTIONS))
endif
endif
