#+test
package gtk4

import "core:c"
import "core:os"
import "core:strings"
import "core:testing"

import glib "glib:glib"
import gobj "glib:gobject"
import pango "pango:pango"

// Version recorded in README.md: "**Bound version:** X.Y.Z".
README :: #load("../README.md", string)

// The distro libgtk-4 the suite still builds against (Mint 22: 4.14.5).
FLOOR_MINOR :: 14

bound_version :: proc() -> (major, minor, micro: int, ok: bool) {
    marker :: "**Bound version:** "
    readme := README
    i := strings.index(readme, marker)
    if i < 0 do return
    rest := readme[i + len(marker):]
    end := strings.index_any(rest, " \n")
    if end < 0 do return
    parts := strings.split(rest[:end], ".", context.temp_allocator)
    if len(parts) != 3 do return
    nums: [3]int
    for p, n in parts {
        v := 0
        if len(p) == 0 do return
        for c in p {
            if c < '0' || c > '9' do return
            v = v * 10 + int(c - '0')
        }
        nums[n] = v
    }
    return nums[0], nums[1], nums[2], true
}

@(test)
test_readme_version_matches_header_macros :: proc(t: ^testing.T) {
    major, minor, micro, ok := bound_version()
    testing.expect(t, ok, "README.md has no '**Bound version:** X.Y.Z'")
    testing.expect_value(t, major, MAJOR_VERSION)
    testing.expect_value(t, minor, MINOR_VERSION)
    testing.expect_value(t, micro, MICRO_VERSION)
}

@(test)
test_loaded_library_version :: proc(t: ^testing.T) {
    major, minor, micro, _ := bound_version()
    loaded_major := int(get_major_version())
    loaded_minor := int(get_minor_version())
    loaded_micro := int(get_micro_version())
    testing.expect_value(t, loaded_major, major)
    testing.expect(t, loaded_minor >= FLOOR_MINOR, "loaded libgtk-4 is older than the 4.14 floor")
    // `make test` puts amber-gtk4's bundle on LD_LIBRARY_PATH when it is built and sets
    // GTK_BUNDLE_EXPECTED: then the loaded library must be the bound version exactly, and a
    // wrong path fails here instead of falling back to the distro's.
    if os.get_env("GTK_BUNDLE_EXPECTED", context.temp_allocator) != "" {
        testing.expect_value(t, loaded_minor, minor)
        testing.expect_value(t, loaded_micro, micro)
    }
}

@(test)
test_check_version_accepts_floor :: proc(t: ^testing.T) {
    // gtk_check_version returns NULL when the loaded library is new enough.
    testing.expect(t, check_version(4, FLOOR_MINOR, 0) == nil, "loaded libgtk-4 rejects the 4.14 floor")
    testing.expect(t, check_version(4, 99, 0) != nil, "check_version accepts a version that does not exist")
}

@(test)
test_rgba_parse_and_to_string :: proc(t: ^testing.T) {
    rgba: RGBA
    testing.expect(t, bool(gdk_rgba_parse(&rgba, "rgb(255,128,0)")))
    testing.expect_value(t, rgba.red, 1)
    testing.expect_value(t, rgba.alpha, 1)
    s := gdk_rgba_to_string(&rgba)
    defer glib.free(rawptr(s))
    testing.expect_value(t, string(s), "rgb(255,128,0)")
}

@(test)
test_types_register_without_a_display :: proc(t: ^testing.T) {
    testing.expect(t, button_get_type() != 0)
    testing.expect(t, window_get_type() != button_get_type())
}

// Flag enums are bit_sets of the C bits (docs/DECISIONS.md §5): the size is that of the C enum
// (4 bytes) and a member's index is the position of its bit in the header (gdk/gdkenums.h,
// gdk/gdktoplevel.h, gdk/gdkframeclock.h, gtk/gtkenums.h, gtk/deprecated/gtkdialog.h).

bits :: proc(s: $S) -> u32 {
    return transmute(u32)s
}

@(test)
test_flag_sets_are_the_size_of_the_c_enum :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(ModifierType), 4)
    testing.expect_value(t, size_of(DragAction), 4)
    testing.expect_value(t, size_of(AxisFlags), 4)
    testing.expect_value(t, size_of(FrameClockPhase), 4)
    testing.expect_value(t, size_of(ToplevelState), 4)
    testing.expect_value(t, size_of(SeatCapabilities), 4)
    testing.expect_value(t, size_of(StateFlags), 4)
    testing.expect_value(t, size_of(DialogFlags), 4)
    testing.expect_value(t, size_of(InputHints), 4)
    testing.expect_value(t, size_of(EventControllerScrollFlags), 4)
    testing.expect_value(t, size_of(TextBufferNotifyFlags), 4)
    testing.expect_value(t, size_of(c.uint), 4)
}

@(test)
test_modifier_bits_match_the_header :: proc(t: ^testing.T) {
    testing.expect_value(t, bits(ModifierType{.SHIFT_MASK}), 1 << 0)
    testing.expect_value(t, bits(ModifierType{.CONTROL_MASK}), 1 << 2)
    testing.expect_value(t, bits(ModifierType{.ALT_MASK}), 1 << 3)
    testing.expect_value(t, bits(ModifierType{.BUTTON1_MASK}), 1 << 8)
    testing.expect_value(t, bits(ModifierType{.SUPER_MASK}), 1 << 26)
    testing.expect_value(t, bits(ModifierType{.META_MASK}), 1 << 28)
    testing.expect_value(t, bits(ModifierType{.SHIFT_MASK, .CONTROL_MASK}), 5)
    testing.expect_value(t, bits(MODIFIER_MASK), 0x1c001f0f)
    testing.expect_value(t, bits(NO_MODIFIER_MASK), 0)
}

@(test)
test_other_flag_bits_match_the_header :: proc(t: ^testing.T) {
    testing.expect_value(t, bits(DragAction{.ACTION_COPY}), 1)
    testing.expect_value(t, bits(DragAction{.ACTION_ASK}), 8)
    testing.expect_value(t, bits(ACTION_ALL), 7)
    // GDK_AXIS_FLAG_X is 1 << GDK_AXIS_X, and GDK_AXIS_X is 1
    testing.expect_value(t, bits(AxisFlags{.AXIS_FLAG_X}), 1 << 1)
    testing.expect_value(t, bits(AxisFlags{.AXIS_FLAG_SLIDER}), 1 << 11)
    testing.expect_value(t, bits(FrameClockPhase{.AFTER_PAINT}), 1 << 6)
    testing.expect_value(t, bits(ToplevelState{.SUSPENDED}), 1 << 16)
    testing.expect_value(t, bits(StateFlags{.STATE_FLAG_ACTIVE}), 1 << 0)
    testing.expect_value(t, bits(StateFlags{.STATE_FLAG_FOCUSED}), 1 << 5)
    testing.expect_value(t, bits(StateFlags{.STATE_FLAG_FOCUS_WITHIN}), 1 << 14)
    testing.expect_value(t, bits(DialogFlags{.DIALOG_USE_HEADER_BAR}), 1 << 2)
    testing.expect_value(t, bits(InputHints{.INPUT_HINT_PRIVATE}), 1 << 11)
}

@(test)
test_zero_members_are_the_empty_set :: proc(t: ^testing.T) {
    testing.expect_value(t, STATE_FLAG_NORMAL, StateFlags{})
    testing.expect_value(t, FRAME_CLOCK_PHASE_NONE, FrameClockPhase{})
    testing.expect_value(t, SEAT_CAPABILITY_NONE, SeatCapabilities{})
}

@(test)
test_composite_masks_are_sets :: proc(t: ^testing.T) {
    testing.expect_value(t, bits(EVENT_CONTROLLER_SCROLL_BOTH_AXES), 3)
    testing.expect_value(t, bits(SEAT_CAPABILITY_ALL_POINTING), 7)
    testing.expect_value(t, bits(SEAT_CAPABILITY_ALL), 31)
    testing.expect_value(t, bits(ANCHOR_RESIZE), 48)
}

@(test)
test_flag_sets_cross_the_c_boundary_unchanged :: proc(t: ^testing.T) {
    // gtk_event_controller_scroll_new takes the flags by value and the getter returns them
    c_ := event_controller_scroll_new({.EVENT_CONTROLLER_SCROLL_VERTICAL, .EVENT_CONTROLLER_SCROLL_KINETIC})
    defer gobj.object_unref(rawptr(c_))
    testing.expect_value(t, event_controller_scroll_get_flags(cast(^EventControllerScroll)c_), EventControllerScrollFlags{.EVENT_CONTROLLER_SCROLL_VERTICAL, .EVENT_CONTROLLER_SCROLL_KINETIC})
}

// Single-object parameters are ^T (docs/PATCHED.md); runic wrote [^]T for names ending in "s".
// The typed pins in patched.odin cover the type of each; this one calls through a receiver
// that used to be [^]PrintSettings. GtkPrintSettings needs no display.
@(test)
test_print_settings_receiver_is_one_object :: proc(t: ^testing.T) {
    s := print_settings_new()
    defer gobj.object_unref(s)
    testing.expect(t, s != nil)
    print_settings_set_n_copies(s, 3)
    testing.expect_value(t, print_settings_get_n_copies(s), 3)
}

// `PangoAttrList **attrs` is one out-pointer: ^^pango.AttrList, not the [^]^ runic wrote
// (docs/PATCHED.md). A simple context with no preedit returns an empty string and, as the
// header allows, may leave attrs alone. GtkIMContextSimple needs no display.
@(test)
test_preedit_attrs_is_one_out_pointer :: proc(t: ^testing.T) {
    ctx := im_context_simple_new()
    defer gobj.object_unref(rawptr(ctx))
    str: cstring
    attrs: ^pango.AttrList
    pos: i32 = -1
    im_context_get_preedit_string(ctx, &str, &attrs, &pos)
    defer glib.free(rawptr(str))
    testing.expect_value(t, string(str), "")
    testing.expect_value(t, pos, 0)
    if attrs != nil do pango.attr_list_unref(attrs)
}
