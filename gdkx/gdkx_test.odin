#+test
package gdkx

import "core:c"
import "core:testing"

import gobj "glib:gobject"
import gtk "gtk4:gtk4"
import xlib "x11:xlib"

// Each X11 class links and is the GDK class it extends, so a program may ask a display or a
// surface which backend it is before it calls the X11 getters, which are unchecked casts.
@(test)
test_x11_types_extend_gdk :: proc(t: ^testing.T) {
	cases := [?]struct {
		name:        string,
		x11, parent: gobj.Type,
	} {
		{"display", TYPE_X11_DISPLAY(), gtk.TYPE_DISPLAY()},
		{"surface", TYPE_X11_SURFACE(), gtk.TYPE_SURFACE()},
		{"drag", TYPE_X11_DRAG(), gtk.TYPE_DRAG()},
		{"monitor", TYPE_X11_MONITOR(), gtk.TYPE_MONITOR()},
	}
	for k in cases {
		testing.expectf(t, k.x11 != 0, "%s: no X11 type", k.name)
		testing.expectf(t, bool(gobj.type_is_a(k.x11, k.parent)), "%s: the X11 type is not a GDK one", k.name)
	}
}

// IS_X11_DISPLAY is GDK_IS_X11_DISPLAY: false for no display, and for an object of another class.
@(test)
test_is_x11_display :: proc(t: ^testing.T) {
	testing.expect(t, !bool(IS_X11_DISPLAY((^gtk.Display)(nil))), "no display is an X11 one")
	obj := (^gobj.Object)(gobj.object_new(gobj.TYPE_OBJECT, nil))
	defer gobj.object_unref(obj)
	testing.expect(t, !bool(IS_X11_DISPLAY(obj)), "a plain GObject is an X11 display")
}

// Xlib's types are odin-x11's, the C sizes: a window and an atom are XIDs, unsigned long.
@(test)
test_xlib_types_are_c_sized :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(xlib.Window), size_of(c.ulong))
	testing.expect_value(t, size_of(xlib.Atom), size_of(c.ulong))
}
