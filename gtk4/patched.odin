package gtk4

import cairo "cairo:cairo"
import gio "glib:gio"
import glib "glib:glib"
import gobj "glib:gobject"
import graphene "graphene:graphene"
import pango "pango:pango"

// Typed pins for the post-generation rules (docs/PATCHED.md). A regeneration that drops one
// fails to compile here.

// A C array parameter decays to a pointer; runic binds it as the array by value.
@(private = "file")
patched_snapshot_append_border: proc "c" (_: ^Snapshot, _: ^RoundedRect, _: ^[4]f32, _: ^[4]RGBA) = snapshot_append_border

@(private = "file")
patched_border_node_new: proc "c" (_: ^RoundedRect, _: ^[4]f32, _: ^[4]RGBA) -> ^RenderNode = gsk_border_node_new

// runic names cairo's context `cairo.cairo_t`; odin-cairo calls it `cairo.context_t`.
@(private = "file")
patched_cairo_set_source_rgba: proc "c" (_: ^cairo.context_t, _: ^RGBA) = gdk_cairo_set_source_rgba

// gchar * is cstring, not ^char.
@(private = "file")
patched_check_version: proc "c" (_: u32, _: u32, _: u32) -> cstring = check_version

// Single-object parameters: the C header passes one `T *`, so the parameter is `^T`, not the
// `[^]T` runic writes for a name ending in "s" (scripts/single-object-params.*.txt). One pin per
// type; a regeneration that brings `[^]T` back fails to compile here.

@(private = "file")
patched_accelerator_parse_single_object: proc "c" (_: cstring, _: ^glib.uint_, _: ^ModifierType) -> glib.boolean = accelerator_parse

@(private = "file")
patched_builder_list_item_factory_new_from_bytes_single_object: proc "c" (_: ^BuilderScope, _: ^glib.Bytes) -> ^ListItemFactory = builder_list_item_factory_new_from_bytes

@(private = "file")
patched_cell_area_class_find_cell_property_single_object: proc "c" (_: ^CellAreaClass, _: cstring) -> ^gobj.ParamSpec = cell_area_class_find_cell_property

@(private = "file")
patched_cell_area_class_list_cell_properties_single_object: proc "c" (_: ^CellAreaClass, _: ^glib.uint_) -> ^^gobj.ParamSpec = cell_area_class_list_cell_properties

@(private = "file")
patched_constraint_layout_add_constraints_from_descriptionv_single_object: proc "c" (_: ^ConstraintLayout, _: [^]cstring, _: glib.size, _: i32, _: i32, _: ^glib.HashTable, _: ^^glib.Error) -> ^glib.List = constraint_layout_add_constraints_from_descriptionv

@(private = "file")
patched_drop_target_async_new_single_object: proc "c" (_: ^ContentFormats, _: DragAction) -> ^DropTargetAsync = drop_target_async_new

@(private = "file")
patched_drop_target_get_gtypes_single_object: proc "c" (_: ^DropTarget, _: ^glib.size) -> ^gobj.Type = drop_target_get_gtypes

@(private = "file")
patched_editable_get_selection_bounds_single_object: proc "c" (_: ^Editable, _: ^i32, _: ^i32) -> glib.boolean = editable_get_selection_bounds

@(private = "file")
patched_editable_install_properties_single_object: proc "c" (_: ^gobj.ObjectClass, _: glib.uint_) -> glib.uint_ = editable_install_properties

@(private = "file")
patched_entry_set_attributes_single_object: proc "c" (_: ^Entry, _: ^pango.AttrList) = entry_set_attributes

@(private = "file")
patched_entry_set_tabs_single_object: proc "c" (_: ^Entry, _: ^pango.TabArray) = entry_set_tabs

@(private = "file")
patched_file_dialog_set_filters_single_object: proc "c" (_: ^FileDialog, _: ^gio.ListModel) = file_dialog_set_filters

@(private = "file")
patched_gdk_dmabuf_formats_contains_single_object: proc "c" (_: ^DmabufFormats, _: glib.uint32, _: glib.uint64) -> glib.boolean = gdk_dmabuf_formats_contains

@(private = "file")
patched_gdk_file_list_new_from_list_single_object: proc "c" (_: ^glib.SList) -> ^FileList = gdk_file_list_new_from_list

@(private = "file")
patched_gdk_frame_timings_get_complete_single_object: proc "c" (_: ^FrameTimings) -> glib.boolean = gdk_frame_timings_get_complete

@(private = "file")
patched_gdk_toplevel_set_icon_list_single_object: proc "c" (_: ^Toplevel, _: ^glib.List) = gdk_toplevel_set_icon_list

@(private = "file")
patched_gsk_cairo_node_new_single_object: proc "c" (_: ^graphene.rect_t) -> ^RenderNode = gsk_cairo_node_new

@(private = "file")
patched_gsk_text_node_new_single_object: proc "c" (_: ^pango.Font, _: ^pango.GlyphString, _: ^RGBA, _: ^graphene.point_t) -> ^RenderNode = gsk_text_node_new

@(private = "file")
patched_gsk_transform_rotate_3d_single_object: proc "c" (_: ^Transform, _: f32, _: ^graphene.vec3_t) -> ^Transform = gsk_transform_rotate_3d

@(private = "file")
patched_icon_view_get_dest_item_at_pos_single_object: proc "c" (_: ^IconView, _: i32, _: i32, _: ^^TreePath, _: ^IconViewDropPosition) -> glib.boolean = icon_view_get_dest_item_at_pos

@(private = "file")
patched_media_controls_get_media_stream_single_object: proc "c" (_: ^MediaControls) -> ^MediaStream = media_controls_get_media_stream

@(private = "file")
patched_print_dialog_set_print_settings_single_object: proc "c" (_: ^PrintDialog, _: ^PrintSettings) = print_dialog_set_print_settings

@(private = "file")
patched_root_set_focus_single_object: proc "c" (_: ^Root, _: ^Widget) = root_set_focus

@(private = "file")
patched_settings_reset_property_single_object: proc "c" (_: ^Settings, _: cstring) = settings_reset_property

@(private = "file")
patched_shortcut_action_activate_single_object: proc "c" (_: ^ShortcutAction, _: ShortcutActionFlags, _: ^Widget, _: ^glib.Variant) -> glib.boolean = shortcut_action_activate

@(private = "file")
patched_snapshot_push_rounded_clip_single_object: proc "c" (_: ^Snapshot, _: ^RoundedRect) = snapshot_push_rounded_clip

@(private = "file")
patched_text_buffer_select_range_single_object: proc "c" (_: ^TextBuffer, _: ^TextIter, _: ^TextIter) = text_buffer_select_range

@(private = "file")
patched_tree_view_get_dest_row_at_pos_single_object: proc "c" (_: ^TreeView, _: i32, _: i32, _: ^^TreePath, _: ^TreeViewDropPosition) -> glib.boolean = tree_view_get_dest_row_at_pos

@(private = "file")
patched_widget_class_add_shortcut_single_object: proc "c" (_: ^WidgetClass, _: ^Shortcut) = widget_class_add_shortcut

@(private = "file")
patched_widget_set_font_options_single_object: proc "c" (_: ^Widget, _: ^cairo.font_options_t) = widget_set_font_options

// `T **` out-parameters that return one pointer: runic writes `[^]^T`, which lets a caller index
// past one pointer; they are `^^T` (or `^cstring` for `char **`). Same lists and check as above.

@(private = "file")
patched_im_context_get_preedit_string_single_pointer: proc "c" (_: ^IMContext, _: ^cstring, _: ^^pango.AttrList, _: ^i32) = im_context_get_preedit_string

@(private = "file")
patched_font_dialog_choose_font_and_features_finish_single_pointer: proc "c" (_: ^FontDialog, _: ^gio.AsyncResult, _: ^^pango.FontDescription, _: ^cstring, _: ^^pango.Language, _: ^^glib.Error) -> glib.boolean = font_dialog_choose_font_and_features_finish

// GtkIMContextClass.get_preedit_string is an anonymous callback type that postprocess.sh
// (preedit_callbacks) rewrites: `attrs` and `cursor_pos` are one pointer each.
@(private = "file")
patched_im_context_class_get_preedit_string_single_pointer: proc "c" (_: ^IMContext, _: ^cstring, _: ^^pango.AttrList, _: ^i32) = IMContextClass{}.get_preedit_string
