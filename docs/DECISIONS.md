# Decisions — odin-gtk4

Settled choices. An entry that stops being true is rewritten, not appended to.

## 1. Generated, not hand-written

The bindings are generated with runic from the headers Amber ships, so a library bump is a
regeneration. Hand fixes are the exception and are tracked in [PATCHED.md](PATCHED.md).

## 2. One package, `gtk4`

GTK, GDK and GSK are bound as one package, as the PucklaJ fork binds them: the headers include
each other's types freely and runic cannot split them without duplicating declarations. Apps
alias the import on migration.

## 3. The version test and the loaded library

The bound version is 4.16.13, the GTK that amber-gtk4 builds. The distro's libgtk-4 is 4.14.5.
The test treats them as follows:

- the header macros must equal the README's `**Bound version:**` line, always;
- the loaded library must have the same major version and a minor of at least 4.14;
- when amber-gtk4's bundle is built, `make test` puts it on `LD_LIBRARY_PATH` and sets
  `GTK_BUNDLE_EXPECTED`, and the loaded library must then be 4.16.13 exactly. A wrong path fails
  the test; it does not fall back to the distro's library.

Rejected: requiring the exact version everywhere, which fails on a machine without the bundle
built; and checking only the major version, which would let a header bump pass against a
library that lacks its procs.

## 4. gtk-layer-shell is not bound

The fork also bound gtk-layer-shell. No repo in the suite uses it, so it is left out; add it
when a consumer appears.

## 5. Flag enums are bit_sets, chosen by a list

C flag types (`ModifierType`, `DragAction`, `StateFlags`, `ToplevelState`, …) are
`bit_set[FooBit; u32]`, so callers write `{.SHIFT_MASK, .CONTROL_MASK}`. `postprocess.sh` rewrites
the enums runic emits; the members of `FooBit` are bit indices, and the type keeps the C size
(4 bytes) and bits, so procedures take and return it by value unchanged. A zero member is the
constant `Foo{}` and a composite (`ANCHOR_FLIP`, `SEAT_CAPABILITY_ALL`, `MODIFIER_MASK`) a
constant set, both under their C names; a zero or composite name with no underscore (`NONE`,
`FAMILY`) gets the type's name as a prefix (`FRAME_CLOCK_PHASE_NONE`), since constants share one
namespace.

The list is the `<bitfield>` entries of the Gdk, Gsk and Gtk GIR files plus
`TextBufferNotifyFlags` (new in 4.16). A value rule was rejected: `Orientation` and `SortType`
are 0 and 1 and are not flags. Generation fails if a listed enum is missing, negative or has no
single-bit member. A new GFlags type in a header bump is added to the list by hand.
`PrintCapabilities` is a GIR bitfield but gtk.h does not include its header, so it is not bound.

## 6. GObject casts are generated: `BOX(w)`, `IS_BOX(w)`

GTK's C macros (`GTK_BOX`, `GTK_IS_BOX`) become `BOX` and `IS_BOX` in package `gtk4`, with the
upper-case names of the `TYPE_FOO` constants (so GDK and GSK types need no prefix, as in the
fork). `BOX(w)` returns `^Box` through `gobject.type_cast`; `IS_BOX(w)` returns `glib.boolean`
through `gobject.type_is`. Semantics are odin-glib's: with `GTK_SAFE_CAST` (on unless the build
optimises for speed) a wrong cast logs a GObject critical and returns the pointer; without it
the cast is a plain pointer conversion. `scripts/type-casts.sh` writes `gtk4/type_casts.odin`
from `gtk4.odin` alone.

Skipped, each listed on stderr during `make generate`:

- error domains (a `*_quark` exists for the type), as odin-glib does;
- enums and flags: they have no instance;
- boxed types and param specs (`Rgba`, `Border`, `Rectangle`, `TextIter`, `Bitset`, `Path`, …): a
  fixed list in the script, because the headers do not say boxed from class. The fork cast
  these too, which only ever critical-logs; its `RGBA` cast was renamed `RGBA_CAST` to dodge a
  constant, and is gone here with the rest;
- a name already declared in the package. None is today; a clash is skipped, not renamed or
  prefixed, so a call site never means two things, and the type is then reached with
  `cast(^Foo)`. Enum members are scoped to their enum and cannot clash.

Pascal-case type names are not derived from the snake_case name (`Gl`, `Dbus`, `Io`, `Fd`, …):
the script looks the lower-cased name, without underscores or the `gdk_`/`gsk_`/`gtk_` prefix,
up among the types declared in `gtk4.odin`. A type that is not declared is skipped and listed.
Instantiatable fundamental types (`RenderNode` and its subtypes, `Event` and its subtypes,
`Expression`) are cast like classes: their instances start with a `GTypeInstance`.

Rejected: copying the fork's pascal-case fix-up list, which breaks on the next odd name;
generating a cast per boxed type, which has no instance to check.

## 7. Parameters are single objects unless declared

runic 0.8 writes `[^]T` for a pointer parameter whose C name ends in `s` (`settings`, `lines`),
however many elements it holds, which lets a caller index past one element, and drops a trailing
`va_list`, binding the procedure as `#c_vararg ..any`. Amber's runic fork (branch `amber-patched`)
has `parameters: declared`: with it every procedure parameter is `^T` (`T **` is `^^T`) unless
`arrays:` in the package's `rune.yml` lists it, chosen against the C headers, and a va_list
procedure is skipped. Struct members, variables and typedefs keep runic's name guess, and the
parameters of function-pointer types are plain `^T`: a limit of the fork, true in every binding.
Where a binding needs it, the `param_rules` table in `postprocess.sh` restores the `[^]` for
those parameters' real arrays, rewrites single-object struct members and corrects `T ***` outs;
a row that matches nothing fails the build. Rejected: rewriting the output in `postprocess.sh`,
which had to be told each parameter, matched `va_list` procedures by name pattern (it deleted
`list_store_insert_with_values` for containing `_va`) and was a second place to keep in step
with the headers. `scripts/check-generated.sh` stays as the guard that any regeneration, with
any runic, keeps the listed parameters right.

In this repo: the `postprocess.sh` rewrite this replaced had to name 238 single-object parameters. `list_store_insert_with_values` and `tree_store_insert_with_values` are bound again, as the real `...` procedures they are.
