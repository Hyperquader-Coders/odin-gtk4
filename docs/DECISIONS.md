# Decisions: odin-gtk4

Settled choices. An entry that stops being true is rewritten, not appended to.

## 1. Generated, not hand-written

The bindings are generated with runic from the headers Amber ships, so a library bump is a
regeneration. Hand fixes are the exception and are tracked in [PATCHED.md](PATCHED.md).

## 2. One package, `gtk4`; GDK's X11 backend is `gdkx`

GTK, GDK and GSK are bound as one package, as the PucklaJ fork binds them: the headers include
each other's types freely and runic cannot split them without duplicating declarations. Apps
alias the import on migration. GDK's X11 backend (`gdk/x11/gdkx.h`) is a package of its own,
`gdkx` (§8): it is a separate header GTK does not include, it needs Xlib's types, and a program
that never speaks to X11 does not import it.

## 3. The version test and the loaded library

The bound version is 4.16.13, the GTK that amber-gtk4 ships (amber-gtk4-dev, from the suite's
archive). The distro's libgtk-4 is 4.14.5. The test treats them as follows:

- the header macros must equal the README's `**Bound version:**` line, always;
- the loaded library must have the same major version and a minor of at least 4.14;
- `make test` links the bundle from `/usr/lib/amber-gtk4`, with that folder as the run path, and
  sets `GTK_BUNDLE_EXPECTED`; the loaded library must then be 4.16.13 exactly. A wrong path fails
  the test; it does not fall back to the distro's library.

Rejected: requiring the exact version without `GTK_BUNDLE_EXPECTED`, which fails a test run that
does not go through `make test` and loads the distro's library; and checking only the major
version, which would let a header bump pass against a library that lacks its procs.

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
from `gtk4.odin` alone, and `gdkx/type_casts.odin` from `gdkx.odin` the same way: `GDK_IS_X11_DISPLAY`
is `gdkx.IS_X11_DISPLAY`, the check a program makes before any X11 getter, which is an unchecked
cast.

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
the script looks the lower-cased upper-case name, without underscores (`X11_DISPLAY` is
`x11display`), up among the types declared in the package. A type that is not declared is skipped and listed.
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

## 8. `gdkx`: Xlib's types are odin-x11's, names kept whole

The suite's apps ask GDK which X11 window a surface is, and which desktop it is on, to send a
launch to the window on the desktop the user is looking at; a binding gap is closed in the
binding, so the X11 backend is bound here rather than declared in each app. Xlib's types are
odin-x11's (`x11:xlib`), the suite's one Xlib binding, which amber-canvas's `canvas_x11` uses too:
a program links one Xlib binding, as it links one GLib, and two that declare the same C function
with different types do not build together. GDK's `GdkDisplay` and Xlib's `Display` trim to one
name, and runic keys extern types by the trimmed name, so `gdkx` keeps extern names whole and
names GDK's and GLib's types through `remaps` in `gdkx/rune.yml`; `check-generated.sh` fails on a
type left without one. Runic reports parse errors inside Xlib.h (`wchar_t`, `Bool`), which are
harmless: Xlib is extern and only its type names are used. Rejected: Odin's `vendor:x11/xlib`,
which canvas_x11's own declarations clashed with and which the suite does not generate; opaque
handles of gdkx's own, which every program had to cast; a hand-written `gdkx` file, which a GTK
bump does not regenerate.
