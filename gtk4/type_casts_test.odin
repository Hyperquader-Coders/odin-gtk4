#+test
package gtk4

import "core:testing"

import glib "glib:glib"
import gobj "glib:gobject"

@(private = "file")
criticals: int

@(private = "file")
count_critical :: proc "c" (domain: cstring, level: glib.LogLevelFlags, message: cstring, data: rawptr) {
    criticals += 1
}

@(test)
test_casts_and_checks_on_instances :: proc(t: ^testing.T) {
    c_ := event_controller_scroll_new({.EVENT_CONTROLLER_SCROLL_VERTICAL})
    defer gobj.object_unref(rawptr(c_))
    testing.expect(t, EVENT_CONTROLLER(c_) == c_)
    testing.expect(t, EVENT_CONTROLLER_SCROLL(c_) == cast(^EventControllerScroll)c_)
    testing.expect(t, bool(IS_EVENT_CONTROLLER(c_)))
    testing.expect(t, bool(IS_EVENT_CONTROLLER_SCROLL(c_)))
    testing.expect(t, !bool(IS_GESTURE(c_)))
    testing.expect(t, !bool(IS_WIDGET(c_)))

    list := string_list_new(nil)
    defer gobj.object_unref(rawptr(list))
    testing.expect(t, STRING_LIST(list) == list)
    testing.expect(t, bool(IS_STRING_LIST(list)))
    testing.expect(t, bool(IS_BUILDABLE(list)))
    testing.expect(t, !bool(IS_EVENT_CONTROLLER(list)))
}

@(test)
test_wrong_cast_is_reported :: proc(t: ^testing.T) {
    when gobj.GTK_SAFE_CAST {
        list := string_list_new(nil)
        defer gobj.object_unref(rawptr(list))
        criticals = 0
        id := glib.log_set_handler("GLib-GObject", {.LOG_LEVEL_CRITICAL}, count_critical, nil)
        _ = WIDGET(list)
        glib.log_remove_handler("GLib-GObject", id)
        testing.expect_value(t, criticals, 1)
        criticals = 0
        _ = STRING_LIST(list)
        testing.expect_value(t, criticals, 0)
    }
}
