# Architecture — odin-gtk4

## Generation

`make generate` runs runic over each package's `rune.yml`. The headers are amber-gtk4/build/gtk/stage/usr/include/gtk-4.0 (amber-gtk4's `make` stages it).
The output is committed, so consumers need neither runic nor the headers to build.

## Patches

Where runic gets a signature wrong, the fix is made by hand, listed in
[PATCHED.md](PATCHED.md), and pinned in `<pkg>/patched.odin` by a typed variable. A
regeneration that drops a patch then fails to compile.

## Collections

The collection `gtk4` points at this repo's root. Packages import their siblings and the
bindings below them through collections, never by relative path.

![dependency graph](../diags/odin-gtk4.svg)
