# odin-gtk4 cheat sheet

The idioms a GTK 4 program needs, in the order it uses them. This is not a reference: the package
declares every public name of GTK, GDK and GSK (about ten thousand, listed in [API.md](API.md)),
and the GTK documentation says what each one does. Every name below written with the `gtk` prefix is declared there, and
every one with a `glib`, `gobj` or `gio` prefix is declared in odin-glib's API.md; `make lint` fails when one
is not. GLib's own idioms (sources, errors, `glib.free`) are in odin-glib's `docs/CHEATSHEET.md`.

Conventions that hold everywhere: the collection is `gtk4` (`-collection:gtk4=../odin-gtk4`,
with `glib` beside it); packages are imported as `gtk`, `glib`, `gobj` (package `gobject`) and
`gio`; the `gtk_` prefix is gone (`gtk_box_append` is `gtk.box_append`), but a GDK procedure keeps
`gdk_` (`gtk.gdk_display_get_default`); a constructor returns `^gtk.Widget`, and a procedure that
wants a class takes a cast of it; an `on_` callback is a `proc "c"` that starts with
`context = app_ctx`; a `glib.boolean` parameter takes `true`, `false` or `glib.boolean(expr)`.

## gtk4:application — start, window, run

```odin
import "base:runtime"
import glib "glib:glib"
import gobj "glib:gobject"
import gio "glib:gio"
import gtk "gtk4:gtk4"

app_ctx: runtime.Context

on_activate :: proc "c" (app: ^gio.Application, data: glib.pointer) {
	context = app_ctx
	win := gtk.application_window_new(gtk.APPLICATION(app))   // ^Widget; GTK keeps it until it is closed
	gtk.window_set_title(gtk.WINDOW(win), "Example")
	gtk.window_set_default_size(gtk.WINDOW(win), 640, 480)
	gtk.window_set_child(gtk.WINDOW(win), build_ui())         // the window takes the child
	gtk.window_present(gtk.WINDOW(win))
}

app_ctx = context
app := gtk.application_new("org.example.App", {.APPLICATION_NON_UNIQUE})   // gio.ApplicationFlags
defer gobj.object_unref(app)
gobj.signal_connect(app, "activate", on_activate, nil)
status := gio.application_run(gio.APPLICATION(app))              // the exit status; args default to os.args

// Without a GtkApplication: initialise, show, run a GLib main loop.
if !bool(gtk.init_check()) {return}                              // no display
win := gtk.window_new()
gobj.signal_connect(win, "close-request", on_close, &state)      // return glib.FALSE to let it close
gtk.window_present(gtk.WINDOW(win))
loop := glib.main_loop_new(nil, false)
defer glib.main_loop_unref(loop)
glib.main_loop_run(loop)                                         // on_close calls glib.main_loop_quit
gtk.window_destroy(gtk.WINDOW(win))                              // closes it; the toplevel list drops its ref
```

| remember | |
|---|---|
| Every widget call is on the main thread | from another thread, `glib.idle_add` or `glib.main_context_invoke` hands the work over; timers are `glib.timeout_add` |
| `gtk.application_new` returns the `gtk` type | `gio.APPLICATION(app)` casts it for `application_run`; the `activate` handler receives the `gio` type back |
| One GLib per program | the binding imports GLib from odin-glib and declares none; two declarations of one C function fail to link ([README](../README.md#use)) |
| A procedure added after 4.14 resolves only against a newer libgtk-4 | on a stock machine the program fails to link or load; Amber apps run against amber-gtk4's 4.16.13 ([README](../README.md#use)) |
| `init_check` returns `false` with no display | `init` aborts the process instead; use `init_check` where a headless run is possible |

## gtk4:widgets — build, cast, own, style

```odin
import "core:strings"
import glib "glib:glib"
import gobj "glib:gobject"
import gtk "gtk4:gtk4"

on_save :: proc "c" (button: ^gtk.Button, data: glib.pointer) {
	context = app_ctx
}

box := gtk.box_new(.VERTICAL, 6)                         // ^Widget, floating
label := gtk.label_new("Name")
entry := gtk.entry_new()
btn := gtk.button_new_with_label("Save")
gtk.box_append(gtk.BOX(box), label)                      // BOX(w): the upper-case cast to the class
gtk.box_append(gtk.BOX(box), entry)                      // the box sinks each floating ref and owns it
gtk.box_append(gtk.BOX(box), btn)
gobj.signal_connect(btn, "clicked", on_save, nil)

gtk.widget_set_hexpand(entry, true)                      // glib.boolean from a literal
gtk.widget_set_sensitive(btn, glib.boolean(len(name) > 0))   // from an expression: convert
gtk.widget_add_css_class(box, "card")
gtk.label_set_text(gtk.LABEL(label), "Other")            // GTK copies the string
gtk.editable_set_text(gtk.EDITABLE(entry), "x")
text := strings.clone(string(gtk.editable_get_text(gtk.EDITABLE(entry))))   // borrowed: clone to keep
if gtk.IS_BOX(box) {}                                    // IS_FOO: the runtime check as glib.boolean

gobj.object_ref(label)                                   // your own ref, so removal does not destroy it
gtk.box_remove(gtk.BOX(box), label)                      // drops the box's ref
defer gobj.object_unref(label)

provider := gtk.css_provider_new()                       // not a widget: yours to unref
gtk.css_provider_load_from_string(provider, ".card { padding: 6px; }")
gtk.style_context_add_provider_for_display(gtk.gdk_display_get_default(), gtk.STYLE_PROVIDER(provider), 600)
gobj.object_unref(provider)                              // the display took its own ref
```

| remember | |
|---|---|
| `BOX(w)` is `gobj.type_cast` | with `gobj.GTK_SAFE_CAST` (on unless built with `-o:speed` or higher) a wrong cast logs a GObject critical and returns the pointer; otherwise it reinterprets silently ([DECISIONS §6](DECISIONS.md#6-gobject-casts-are-generated-boxw-is_boxw)) |
| A new widget is floating | the first container that takes it owns it; a widget no container takes needs `gobj.object_ref_sink` and a later `object_unref`; `window_destroy` ends a window |
| Removing a child drops its owner's reference | `box_remove`, `list_box_remove` and `widget_unparent` can finalise the widget: take a ref first if you still hold the pointer |
| A `cstring` a getter returns is borrowed | valid until the next change; `gtk.editable_get_text` and `string_object_get_string` must be cloned to outlive it |
| A flag set is `FooBit` plus `bit_set` | `gtk.ModifierType{.CONTROL_MASK}`, `.CONTROL_MASK in state`; the zero member is `Foo{}` ([DECISIONS §5](DECISIONS.md#5-flag-enums-are-bit_sets-chosen-by-a-list)) |
| `glib.boolean` is `b32` | results compare as `bool(x)` and `if !call()` works; assigning a `bool` variable needs `glib.boolean(v)` |

## gtk4:events — signals, key and click controllers

```odin
import glib "glib:glib"
import gobj "glib:gobject"
import gtk "gtk4:gtk4"

on_key :: proc "c" (ctl: ^gtk.EventController, keyval, keycode: glib.uint_, state: gtk.ModifierType, data: glib.pointer) -> glib.boolean {
	context = app_ctx
	if keyval == gtk.KEY_Escape && .CONTROL_MASK not_in state {
		return glib.TRUE                                 // handled: propagation stops
	}
	return glib.FALSE
}

on_press :: proc "c" (g: ^gtk.Gesture, n_press: i32, x, y: f64, data: glib.pointer) {
	context = app_ctx
}

on_changed :: proc "c" (e: ^gtk.Editable, data: glib.pointer) {
	context = app_ctx
}

keys := gtk.event_controller_key_new()                   // ^EventController
gtk.event_controller_set_propagation_phase(keys, .PHASE_CAPTURE)   // before the focused child sees the key
gobj.signal_connect(keys, "key-pressed", on_key, &state)
gtk.widget_add_controller(widget, keys)                  // the widget owns the controller: no unref

click := gtk.gesture_click_new()                         // ^Gesture
gtk.gesture_single_set_button(gtk.GESTURE_SINGLE(click), 3)   // 3 is the right button, 0 any
gobj.signal_connect(click, "pressed", on_press, &state)
gtk.widget_add_controller(widget, gtk.EVENT_CONTROLLER(click))

changed := gobj.signal_connect(entry, "changed", on_changed, &state)
gobj.signal_handler_block(entry, changed)                // while code sets the value, "changed" stays quiet
gtk.editable_set_text(gtk.EDITABLE(entry), "x")
gobj.signal_handler_unblock(entry, changed)
gtk.widget_queue_draw(widget)                            // ask for a redraw; never draw directly
```

| remember | |
|---|---|
| The handler's parameters are the signal's | instance, the signal's own arguments, then `data`; `key-pressed` returns `glib.boolean`, `clicked` and `pressed` return nothing; the binding does not check the match |
| `signal_connect` takes the proc itself | it is generic over the proc type; `gobj.Callback` is only needed for a stored handler |
| A controller belongs to the widget it was added to | `widget_add_controller` takes the reference; `widget_remove_controller` gives it up |
| `data` is a raw pointer and outlives the widget | disconnect with `gobj.signal_handlers_disconnect_by_data` before freeing what it points to |
| Key values are constants in the package | `gtk.KEY_Escape`, `gtk.KEY_Up`; modifiers are the `gtk.ModifierType` bit_set |

## gtk4:lists — string models, drop-downs, list views

```odin
import glib "glib:glib"
import gobj "glib:gobject"
import gio "glib:gio"
import gtk "gtk4:gtk4"

on_setup :: proc "c" (factory: ^gtk.ListItemFactory, item: ^gtk.ListItem, data: glib.pointer) {
	context = app_ctx
	gtk.list_item_set_child(item, gtk.label_new(nil))    // once per row widget; rows are recycled
}

on_bind :: proc "c" (factory: ^gtk.ListItemFactory, item: ^gtk.ListItem, data: glib.pointer) {
	context = app_ctx
	obj := gtk.STRING_OBJECT(gtk.list_item_get_item(item))   // the model's item, borrowed
	gtk.label_set_text(gtk.LABEL(gtk.list_item_get_child(item)), gtk.string_object_get_string(obj))
}

names := [?]cstring{"one", "two", nil}                   // C string arrays end in nil
model := gtk.string_list_new(raw_data(names[:]))         // new, yours; the strings are copied
gtk.string_list_append(model, "three")

dd := gtk.drop_down_new_from_strings(raw_data(names[:])) // builds and owns its own model
sel := gtk.drop_down_get_selected(gtk.DROP_DOWN(dd))     // gtk.INVALID_LIST_POSITION when none

factory := gtk.signal_list_item_factory_new()
gobj.signal_connect(factory, "setup", on_setup, nil)
gobj.signal_connect(factory, "bind", on_bind, nil)
selection := gtk.single_selection_new(gio.LIST_MODEL(model))        // takes your ref on model
view := gtk.list_view_new(gtk.SELECTION_MODEL(selection), factory)  // takes selection and factory
picked := gtk.single_selection_get_selected(selection)   // an index into the model

rows := gtk.list_box_new()                               // the simple form: one widget per row
gtk.list_box_append(gtk.LIST_BOX(rows), gtk.label_new("row"))
row := gtk.list_box_get_row_at_index(gtk.LIST_BOX(rows), 0)
gtk.list_box_select_row(gtk.LIST_BOX(rows), row)
```

| remember | |
|---|---|
| `_new` constructors may take your reference | `single_selection_new`, `list_view_new`, `filter_list_model_new` and `drop_down_new` consume the model, selection and factory you pass (`transfer full`); `gobj.object_ref` first to keep one |
| A setter takes no reference | after `drop_down_set_model`, `gobj.object_unref` the model you made; the widget holds its own |
| `list_item_get_item` is borrowed | `gio.list_model_get_item` returns a new reference to unref; unref only what the C documentation marks `transfer full` |
| `bind` runs for every reuse of a row | set every property there; `setup` makes the widgets once; widgets built in `bind` pile up |
| String arrays are `nil`-terminated | `raw_data(names[:])` is a `[^]cstring`; the cstrings must outlive the call only |
