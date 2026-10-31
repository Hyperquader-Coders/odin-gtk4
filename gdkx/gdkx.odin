package gdkx

import glib "glib:glib"
import gobj "glib:gobject"
import gtk "gtk4:gtk4"
import xlib "x11:xlib"

TYPE_X11_APP_LAUNCH_CONTEXT :: app_launch_context_get_type
TYPE_X11_DEVICE_XI2 :: device_xi2_get_type
TYPE_X11_DEVICE_MANAGER_XI2 :: device_manager_xi2_get_type
TYPE_X11_SCREEN :: screen_get_type
TYPE_X11_DISPLAY :: display_get_type
TYPE_X11_DRAG :: drag_get_type
TYPE_X11_GL_CONTEXT :: gl_context_get_type
TYPE_X11_MONITOR :: monitor_get_type
TYPE_X11_SURFACE :: surface_get_type

X11AppLaunchContext :: gtk.AppLaunchContext
X11AppLaunchContextClass :: struct #packed {}

X11DeviceXI2 :: struct #packed {}

X11DeviceXI2Class :: struct #packed {}

X11DeviceType :: enum u32 {DEVICE_TYPE_LOGICAL = 0, DEVICE_TYPE_PHYSICAL = 1, DEVICE_TYPE_FLOATING = 2 }
X11DeviceManagerXI2 :: struct #packed {}

X11DeviceManagerXI2Class :: struct #packed {}

X11Screen :: struct #packed {}

X11ScreenClass :: struct #packed {}

X11Display :: gtk.Display
X11DisplayClass :: struct #packed {}

X11Drag :: gtk.Drag
X11DragClass :: struct #packed {}

X11GLContext :: struct #packed {}

X11GLContextClass :: struct #packed {}

X11Monitor :: struct #packed {}

X11MonitorClass :: struct #packed {}

X11Surface :: gtk.Surface
X11SurfaceClass :: struct #packed {}


@(default_calling_convention = "c")
foreign gdkx_runic {
    @(link_name = "gdk_x11_app_launch_context_get_type")
    app_launch_context_get_type :: proc() -> gobj.Type ---

    @(link_name = "gdk_x11_device_get_id")
    device_get_id :: proc(device: ^gtk.Device) -> i32 ---

    @(link_name = "gdk_x11_device_xi2_get_type")
    device_xi2_get_type :: proc() -> gobj.Type ---

    @(link_name = "gdk_x11_device_manager_xi2_get_type")
    device_manager_xi2_get_type :: proc() -> gobj.Type ---

    @(link_name = "gdk_x11_device_manager_lookup")
    device_manager_lookup :: proc(device_manager: ^X11DeviceManagerXI2, device_id: i32) -> ^gtk.Device ---

    @(link_name = "gdk_x11_screen_get_type")
    screen_get_type :: proc() -> gobj.Type ---

    @(link_name = "gdk_x11_screen_get_xscreen")
    screen_get_xscreen :: proc(screen: ^X11Screen) -> ^xlib.Screen ---

    @(link_name = "gdk_x11_screen_get_screen_number")
    screen_get_screen_number :: proc(screen: ^X11Screen) -> i32 ---

    @(link_name = "gdk_x11_screen_get_window_manager_name")
    screen_get_window_manager_name :: proc(screen: ^X11Screen) -> cstring ---

    @(link_name = "gdk_x11_screen_supports_net_wm_hint")
    screen_supports_net_wm_hint :: proc(screen: ^X11Screen, property_name: cstring) -> glib.boolean ---

    @(link_name = "gdk_x11_screen_get_monitor_output")
    screen_get_monitor_output :: proc(screen: ^X11Screen, monitor_num: i32) -> xlib.XID ---

    @(link_name = "gdk_x11_screen_get_number_of_desktops")
    screen_get_number_of_desktops :: proc(screen: ^X11Screen) -> glib.uint32 ---

    @(link_name = "gdk_x11_screen_get_current_desktop")
    screen_get_current_desktop :: proc(screen: ^X11Screen) -> glib.uint32 ---

    @(link_name = "gdk_x11_display_get_type")
    display_get_type :: proc() -> gobj.Type ---

    @(link_name = "gdk_x11_display_open")
    display_open :: proc(display_name: cstring) -> ^gtk.Display ---

    @(link_name = "gdk_x11_display_get_xdisplay")
    display_get_xdisplay :: proc(display: ^gtk.Display) -> ^xlib.Display ---

    @(link_name = "gdk_x11_display_get_xscreen")
    display_get_xscreen :: proc(display: ^gtk.Display) -> ^xlib.Screen ---

    @(link_name = "gdk_x11_display_get_xrootwindow")
    display_get_xrootwindow :: proc(display: ^gtk.Display) -> xlib.Window ---

    @(link_name = "gdk_x11_display_get_xcursor")
    display_get_xcursor :: proc(display: ^gtk.Display, cursor: ^gtk.Cursor) -> xlib.Cursor ---

    @(link_name = "gdk_x11_display_get_user_time")
    display_get_user_time :: proc(display: ^gtk.Display) -> glib.uint32 ---

    @(link_name = "gdk_x11_display_get_startup_notification_id")
    display_get_startup_notification_id :: proc(display: ^gtk.Display) -> cstring ---

    @(link_name = "gdk_x11_display_set_startup_notification_id")
    display_set_startup_notification_id :: proc(display: ^gtk.Display, startup_id: cstring) ---

    @(link_name = "gdk_x11_display_set_program_class")
    display_set_program_class :: proc(display: ^gtk.Display, program_class: cstring) ---

    @(link_name = "gdk_x11_display_set_cursor_theme")
    display_set_cursor_theme :: proc(display: ^gtk.Display, theme: cstring, size: i32) ---

    @(link_name = "gdk_x11_display_broadcast_startup_message")
    display_broadcast_startup_message :: proc(display: ^gtk.Display, message_type: cstring, #c_vararg var_args: ..any) ---

    @(link_name = "gdk_x11_lookup_xdisplay")
    lookup_xdisplay :: proc(xdisplay: ^xlib.Display) -> ^gtk.Display ---

    @(link_name = "gdk_x11_display_get_screen")
    display_get_screen :: proc(display: ^gtk.Display) -> ^X11Screen ---

    @(link_name = "gdk_x11_display_get_primary_monitor")
    display_get_primary_monitor :: proc(display: ^gtk.Display) -> ^gtk.Monitor ---

    @(link_name = "gdk_x11_display_grab")
    display_grab :: proc(display: ^gtk.Display) ---

    @(link_name = "gdk_x11_display_ungrab")
    display_ungrab :: proc(display: ^gtk.Display) ---

    @(link_name = "gdk_x11_display_set_surface_scale")
    display_set_surface_scale :: proc(display: ^gtk.Display, scale: i32) ---

    @(link_name = "gdk_x11_display_error_trap_push")
    display_error_trap_push :: proc(display: ^gtk.Display) ---

    @(link_name = "gdk_x11_display_error_trap_pop")
    display_error_trap_pop :: proc(display: ^gtk.Display) -> i32 ---

    @(link_name = "gdk_x11_display_error_trap_pop_ignored")
    display_error_trap_pop_ignored :: proc(display: ^gtk.Display) ---

    @(link_name = "gdk_x11_set_sm_client_id")
    set_sm_client_id :: proc(sm_client_id: cstring) ---

    @(link_name = "gdk_x11_display_get_default_group")
    display_get_default_group :: proc(display: ^gtk.Display) -> ^gtk.Surface ---

    @(link_name = "gdk_x11_drag_get_type")
    drag_get_type :: proc() -> gobj.Type ---

    @(link_name = "gdk_x11_gl_context_get_type")
    gl_context_get_type :: proc() -> gobj.Type ---

    @(link_name = "gdk_x11_display_get_glx_version")
    display_get_glx_version :: proc(display: ^gtk.Display, major: ^i32, minor: ^i32) -> glib.boolean ---

    @(link_name = "gdk_x11_display_get_egl_version")
    display_get_egl_version :: proc(display: ^gtk.Display, major: ^i32, minor: ^i32) -> glib.boolean ---

    @(link_name = "gdk_x11_display_get_egl_display")
    display_get_egl_display :: proc(display: ^gtk.Display) -> glib.pointer ---

    @(link_name = "gdk_x11_monitor_get_type")
    monitor_get_type :: proc() -> gobj.Type ---

    @(link_name = "gdk_x11_monitor_get_output")
    monitor_get_output :: proc(monitor: ^gtk.Monitor) -> xlib.XID ---

    @(link_name = "gdk_x11_monitor_get_workarea")
    monitor_get_workarea :: proc(monitor: ^gtk.Monitor, workarea: ^gtk.Rectangle) ---

    @(link_name = "gdk_x11_get_xatom_by_name_for_display")
    get_xatom_by_name_for_display :: proc(display: ^gtk.Display, atom_name: cstring) -> xlib.Atom ---

    @(link_name = "gdk_x11_get_xatom_name_for_display")
    get_xatom_name_for_display :: proc(display: ^gtk.Display, xatom: xlib.Atom) -> cstring ---

    @(link_name = "gdk_x11_display_text_property_to_text_list")
    display_text_property_to_text_list :: proc(display: ^gtk.Display, encoding: cstring, format: i32, text: [^]glib.uchar, length: i32, list: ^^cstring) -> i32 ---

    @(link_name = "gdk_x11_free_text_list")
    free_text_list :: proc(list: [^]cstring) ---

    @(link_name = "gdk_x11_display_string_to_compound_text")
    display_string_to_compound_text :: proc(display: ^gtk.Display, str: cstring, encoding: ^cstring, format: ^i32, ctext: ^^glib.uchar, length: ^i32) -> i32 ---

    @(link_name = "gdk_x11_display_utf8_to_compound_text")
    display_utf8_to_compound_text :: proc(display: ^gtk.Display, str: cstring, encoding: ^cstring, format: ^i32, ctext: ^^glib.uchar, length: ^i32) -> glib.boolean ---

    @(link_name = "gdk_x11_free_compound_text")
    free_compound_text :: proc(ctext: [^]glib.uchar) ---

    @(link_name = "gdk_x11_surface_get_type")
    surface_get_type :: proc() -> gobj.Type ---

    @(link_name = "gdk_x11_surface_get_xid")
    surface_get_xid :: proc(surface: ^gtk.Surface) -> xlib.Window ---

    @(link_name = "gdk_x11_surface_set_user_time")
    surface_set_user_time :: proc(surface: ^gtk.Surface, timestamp: glib.uint32) ---

    @(link_name = "gdk_x11_surface_set_utf8_property")
    surface_set_utf8_property :: proc(surface: ^gtk.Surface, name: cstring, value: cstring) ---

    @(link_name = "gdk_x11_surface_set_theme_variant")
    surface_set_theme_variant :: proc(surface: ^gtk.Surface, variant: cstring) ---

    @(link_name = "gdk_x11_surface_move_to_current_desktop")
    surface_move_to_current_desktop :: proc(surface: ^gtk.Surface) ---

    @(link_name = "gdk_x11_surface_get_desktop")
    surface_get_desktop :: proc(surface: ^gtk.Surface) -> glib.uint32 ---

    @(link_name = "gdk_x11_surface_move_to_desktop")
    surface_move_to_desktop :: proc(surface: ^gtk.Surface, desktop: glib.uint32) ---

    @(link_name = "gdk_x11_surface_set_frame_sync_enabled")
    surface_set_frame_sync_enabled :: proc(surface: ^gtk.Surface, frame_sync_enabled: glib.boolean) ---

    @(link_name = "gdk_x11_get_server_time")
    get_server_time :: proc(surface: ^gtk.Surface) -> glib.uint32 ---

    @(link_name = "gdk_x11_surface_lookup_for_display")
    surface_lookup_for_display :: proc(display: ^gtk.Display, window: xlib.Window) -> ^gtk.Surface ---

    @(link_name = "gdk_x11_surface_set_skip_taskbar_hint")
    surface_set_skip_taskbar_hint :: proc(surface: ^gtk.Surface, skips_taskbar: glib.boolean) ---

    @(link_name = "gdk_x11_surface_set_skip_pager_hint")
    surface_set_skip_pager_hint :: proc(surface: ^gtk.Surface, skips_pager: glib.boolean) ---

    @(link_name = "gdk_x11_surface_set_urgency_hint")
    surface_set_urgency_hint :: proc(surface: ^gtk.Surface, urgent: glib.boolean) ---

    @(link_name = "gdk_x11_surface_set_group")
    surface_set_group :: proc(surface: ^gtk.Surface, leader: ^gtk.Surface) ---

    @(link_name = "gdk_x11_surface_get_group")
    surface_get_group :: proc(surface: ^gtk.Surface) -> ^gtk.Surface ---

}

foreign import gdkx_runic "system:gtk-4"

