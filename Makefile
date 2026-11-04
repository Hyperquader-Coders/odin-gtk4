# odin-gtk4: Odin bindings for GTK 4, GDK and GSK. Consumed via -collection:gtk4=/path/to/odin-gtk4
# What every runic binding does is in house/binding.mk, a copy of house-rules'
# scripts/binding/binding.mk: this repository is public, and its runner has no house-rules.
# project.toml names the kind, the packages, the siblings and the system packages.
include house/binding.mk

# The GTK the binding is generated from and tested against is the suite's bundle, amber-gtk4
# (libgtk-4 4.16.13, from amber-gtk4-dev), in its own folder off the linker's path: a test links
# it from there and runs it through the run path, as every program built on the binding does.
# The distro's 4.14.5 is the floor a program may load; the tests load the bundle, so the version
# test is exact (GTK_BUNDLE_EXPECTED). generate reads the bundle's headers (GTK_INCLUDE).
GTK_LIB = /usr/lib/amber-gtk4
ODIN_TEST_FLAGS += -extra-linker-flags:"-L$(GTK_LIB) -Wl,-rpath,$(GTK_LIB)"
test: export GTK_BUNDLE_EXPECTED = 1
generate: export GTK_INCLUDE = $(GTK_LIB)/include
