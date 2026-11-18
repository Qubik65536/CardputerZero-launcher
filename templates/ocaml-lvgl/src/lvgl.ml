(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   OCaml bindings for the parts of LVGL 9.5 and cp0_app.h this app uses.

   Each [external] names a C function in lvgl_stubs.c, which converts the
   arguments and calls LVGL. The modules follow LVGL's names: lv_label_set_text
   is [Label.set_text], lv_obj_set_style_bg_color is [Obj.set_style_bg_color],
   cp0_app_quit is [App.quit].

   - Widgets, groups, input devices, timers, fonts, events, the display and
     its theme are abstract values ([obj], [group], ...). They are C pointers stored as OCaml ints (see the top of
     lvgl_stubs.c), so the garbage collector never touches them; compare them
     with [==]. A C function that may return NULL returns an option here.
   - Colors are 0xRRGGBB ints. Coordinates and sizes are pixels.
   - Style setters take ?part and ?state (LVGL's selector, default: the main
     part in the default state), e.g.
       Obj.set_style_bg_color obj 0xFFFFFF ~part:Part.knob ~state:State.focused
   - Callbacks are ordinary closures: [Obj.add_event_cb], [Timer.create]. The C side keeps them alive (GC roots) for as long as
     LVGL can call them.
   - Everything runs on the LVGL thread: inside [App.run]'s setup and key
     callbacks, event callbacks and timers. There is no other thread.

   Calling more of LVGL: find the function in
   SDK/github_source/lvgl/lvgl_9_5/lvgl/src (widgets/<name>/lv_<name>.h,
   core/lv_obj*.h, misc/lv_*.h), add a stub to lvgl_stubs.c (the comment at its
   top shows how) and an [external] line here. Constants: copy the value from
   the header and add it to the _Static_assert list at the end of
   lvgl_stubs.c, so a changed value fails the build. *)

(* lv_obj_t *: a widget (label, button, ...) or a plain container. *)
type obj [@@immediate]

(* const lv_font_t * *)
type font [@@immediate]

(* lv_group_t *: widgets that take keyboard focus in turn. *)
type group [@@immediate]

(* lv_indev_t *: an input device (keypad, mouse, ...). *)
type indev [@@immediate]

(* lv_display_t * and lv_theme_t * *)
type display [@@immediate]
type theme [@@immediate]

(* lv_timer_t * *)
type timer [@@immediate]

(* lv_event_t *: only valid inside the event callback that received it. *)
type event [@@immediate]

(* 16-bit RGB565 pixels, for a canvas. *)
type rgb565_pixels = (int, Bigarray.int16_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

(* An exception escaping into LVGL's C code cannot be caught anywhere: report
   it and stop, like OCaml does for an uncaught exception. Every callback goes
   through this. *)
let guard callback argument =
  try callback argument
  with error ->
    let backtrace = Printexc.get_raw_backtrace () in
    Printf.eprintf "Fatal error: exception %s\n" (Printexc.to_string error);
    Printexc.print_raw_backtrace stderr backtrace;
    exit 2

(* Sizes (misc/lv_area.h): [pct 100] is LV_PCT(100), a percentage of the
   parent; [size_content] (LV_SIZE_CONTENT) fits the children. *)
external pct : int -> int = "ml_lv_pct"

let size_content = 0x3FFFFFFF

(* lv_align_t (misc/lv_area.h) *)
module Align = struct
  let top_left = 1
  let top_mid = 2
  let top_right = 3
  let center = 9
end

(* lv_part_t (core/lv_obj_style.h, widgets/textarea/lv_textarea.h) *)
module Part = struct
  let main = 0x000000
  let indicator = 0x020000
  let knob = 0x030000
  let selected = 0x040000
  let cursor = 0x060000
  let textarea_placeholder = 0x080000
end

(* lv_state_t (core/lv_obj_style.h); combine with [lor]. *)
module State = struct
  let default = 0x00
  let checked = 0x04
  let focused = 0x08
  let pressed = 0x80
end

(* lv_obj_flag_t (core/lv_obj.h); combine with [lor]. *)
module Flag = struct
  let hidden = 0x01
  let clickable = 0x02
  let scrollable = 0x10
  let scroll_on_focus = 0x400  (* scroll the widget into view when it gets the focus *)
end

(* lv_opa_t (misc/lv_color.h): 0 = transparent .. 255 = opaque. *)
module Opa = struct
  let transp = 0
  let cover = 255
end

(* lv_text_align_t (misc/lv_text.h) *)
module Text_align = struct
  let left = 1
  let center = 2
  let right = 3
end

(* lv_flex_flow_t and lv_flex_align_t (layouts/flex/lv_flex.h) *)
module Flex_flow = struct
  let row = 0
  let column = 1
end

module Flex_align = struct
  let start = 0
  let center = 2
end

(* lv_key_t (core/lv_group.h): the keys LVGL's keypad input device sends to
   the focused widget, besides the characters typed keys produce. (Linux key
   codes, as [App.key] has them, are in [Keys] at the end of this file.) *)
module Key = struct
  let up = 17
  let down = 18
  let right = 19
  let left = 20
end

(* lv_palette_t (misc/lv_palette.h) *)
module Palette = struct
  let blue = 5

  (* The palette's main color, as 0xRRGGBB. *)
  external main : int -> int = "ml_lv_palette_main"
end

(* lv_event_code_t (misc/lv_event.h) and reading an event. *)
module Event = struct
  let all = 0
  let pressed = 1
  let short_clicked = 4
  let long_pressed_repeat = 9
  let clicked = 10
  let released = 11
  let key = 17
  let focused = 19
  let defocused = 20
  let value_changed = 35
  let ready = 38
  let delete = 42

  (* A flag for an event filter: [key lor preprocess] runs the callback before
     the widget itself handles the key, so it can [stop_processing] it. *)
  let preprocess = 0x8000

  external code : event -> int = "ml_lv_event_get_code"
  external target : event -> obj = "ml_lv_event_get_target"

  (* The key of an Event.key event: a Key.* or the character typed. *)
  external get_key : event -> int = "ml_lv_event_get_key"

  (* No further callbacks (nor the widget itself) handle this event. *)
  external stop_processing : event -> unit = "ml_lv_event_stop_processing"
end

module Font = struct
  external montserrat_12 : unit -> font = "ml_lv_font_montserrat_12"
  external montserrat_14 : unit -> font = "ml_lv_font_montserrat_14"
  external montserrat_28 : unit -> font = "ml_lv_font_montserrat_28"

  (* The built-in Montserrat sizes enabled in the runtime's LVGL config. *)
  let montserrat_12 = montserrat_12 ()
  let montserrat_14 = montserrat_14 ()
  let montserrat_28 = montserrat_28 ()

  (* Advance width in pixels of character [letter] followed by [next] (kerning). *)
  external glyph_width : font -> int -> next:int -> int = "ml_lv_font_get_glyph_width"
end

(* lv_obj_*: what every widget can do. *)
module Obj = struct
  external create : obj -> obj = "ml_lv_obj_create"
  external remove_style_all : obj -> unit = "ml_lv_obj_remove_style_all"
  external set_pos : obj -> x:int -> y:int -> unit = "ml_lv_obj_set_pos"
  external set_size : obj -> width:int -> height:int -> unit = "ml_lv_obj_set_size"
  external set_width : obj -> int -> unit = "ml_lv_obj_set_width"

  (* Place [obj] at [align] of its parent (Align.top_mid, ...), moved by x and y. *)
  external align : obj -> int -> x:int -> y:int -> unit = "ml_lv_obj_align"
  external center : obj -> unit = "ml_lv_obj_center"
  external add_flag : obj -> int -> unit = "ml_lv_obj_add_flag"
  external remove_flag : obj -> int -> unit = "ml_lv_obj_remove_flag"
  external has_flag : obj -> int -> bool = "ml_lv_obj_has_flag"
  external add_state : obj -> int -> unit = "ml_lv_obj_add_state"
  external has_state : obj -> int -> bool = "ml_lv_obj_has_state"

  (* Mark for redrawing, e.g. after changing a canvas's pixels. *)
  external invalidate : obj -> unit = "ml_lv_obj_invalidate"

  (* Recompute how far the widget draws outside itself (outlines, shadows). *)
  external refresh_ext_draw_size : obj -> unit = "ml_lv_obj_refresh_ext_draw_size"

  (* Flex layout: the children in a row or a column (Flex_flow.row, ...). *)
  external set_flex_flow : obj -> int -> unit = "ml_lv_obj_set_flex_flow"

  (* Where the children go along the row (main), across it (cross) and where
     the rows go (track): Flex_align.start, .center, ... *)
  external set_flex_align : obj -> main:int -> cross:int -> track:int -> unit = "ml_lv_obj_set_flex_align"

  (* Take this share of the free space along the parent's flex row or column. *)
  external set_flex_grow : obj -> int -> unit = "ml_lv_obj_set_flex_grow"
  external add_event_cb_raw : obj -> int -> (event -> unit) -> unit = "ml_lv_obj_add_event_cb"

  (* Call [callback] for events with code [filter] (Event.clicked, ...; Event.all for every one). *)
  let add_event_cb obj filter callback = add_event_cb_raw obj filter (guard callback)

  (* Styles: lv_obj_set_style_<property>(obj, value, selector). *)
  external style_bg_color : obj -> int -> int -> unit = "ml_lv_obj_set_style_bg_color"
  external style_bg_opa : obj -> int -> int -> unit = "ml_lv_obj_set_style_bg_opa"
  external style_border_width : obj -> int -> int -> unit = "ml_lv_obj_set_style_border_width"
  external style_text_color : obj -> int -> int -> unit = "ml_lv_obj_set_style_text_color"
  external style_text_font : obj -> font -> int -> unit = "ml_lv_obj_set_style_text_font"
  external style_pad_all : obj -> int -> int -> unit = "ml_lv_obj_set_style_pad_all"
  external style_pad_ver : obj -> int -> int -> unit = "ml_lv_obj_set_style_pad_ver"
  external style_pad_row : obj -> int -> int -> unit = "ml_lv_obj_set_style_pad_row"
  external style_pad_column : obj -> int -> int -> unit = "ml_lv_obj_set_style_pad_column"

  (* The selector argument as optional ?part and ?state. *)
  let styled set ?(part = Part.main) ?(state = State.default) obj value = set obj value (part lor state)
  let set_style_bg_color = styled style_bg_color
  let set_style_bg_opa = styled style_bg_opa
  let set_style_border_width = styled style_border_width
  let set_style_text_color = styled style_text_color
  let set_style_text_font = styled style_text_font
  let set_style_pad_all = styled style_pad_all
  let set_style_pad_ver = styled style_pad_ver
  let set_style_pad_row = styled style_pad_row
  let set_style_pad_column = styled style_pad_column
end

module Label = struct
  external create : obj -> obj = "ml_lv_label_create"
  external set_text : obj -> string -> unit = "ml_lv_label_set_text"
end

module Image = struct
  external create : obj -> obj = "ml_lv_image_create"

  (* Show a PNG file; see App.file_path for the app's own images. *)
  external set_src_file : obj -> string -> unit = "ml_lv_image_set_src_file"
end

module Canvas = struct
  external create : obj -> obj = "ml_lv_canvas_create"

  (* Draw [pixels] (width * height, row by row). LVGL keeps using them: keep
     the Bigarray alive (stored somewhere) as long as the canvas exists. *)
  external set_buffer_rgb565 : obj -> rgb565_pixels -> width:int -> height:int -> unit
    = "ml_lv_canvas_set_buffer_rgb565"
end

module Button = struct
  external create : obj -> obj = "ml_lv_button_create"
end

module Textarea = struct
  external create : obj -> obj = "ml_lv_textarea_create"
  external set_one_line : obj -> bool -> unit = "ml_lv_textarea_set_one_line"
  external set_placeholder_text : obj -> string -> unit = "ml_lv_textarea_set_placeholder_text"
  external set_max_length : obj -> int -> unit = "ml_lv_textarea_set_max_length"
  external get_text : obj -> string = "ml_lv_textarea_get_text"
end

module Slider = struct
  external create : obj -> obj = "ml_lv_slider_create"
  external set_range : obj -> min:int -> max:int -> unit = "ml_lv_slider_set_range"
  external set_value : obj -> int -> anim:bool -> unit = "ml_lv_slider_set_value"
  external get_value : obj -> int = "ml_lv_slider_get_value"
end

(* A number with -/+ steps; a text area underneath. *)
module Spinbox = struct
  external create : obj -> obj = "ml_lv_spinbox_create"
  external set_range : obj -> min:int -> max:int -> unit = "ml_lv_spinbox_set_range"

  (* [digits] digits shown, the decimal point after [separator] of them (0: none). *)
  external set_digit_format : obj -> digits:int -> separator:int -> unit = "ml_lv_spinbox_set_digit_format"
  external set_value : obj -> int -> unit = "ml_lv_spinbox_set_value"
  external get_value : obj -> int = "ml_lv_spinbox_get_value"
  external increment : obj -> unit = "ml_lv_spinbox_increment"
  external decrement : obj -> unit = "ml_lv_spinbox_decrement"
end

(* A button that opens a list of options. *)
module Dropdown = struct
  external create : obj -> obj = "ml_lv_dropdown_create"
  external set_options_raw : obj -> string -> unit = "ml_lv_dropdown_set_options"

  (* The options, top to bottom. *)
  let set_options dropdown options = set_options_raw dropdown (String.concat "\n" options)

  external set_selected : obj -> int -> unit = "ml_lv_dropdown_set_selected"
  external get_selected : obj -> int = "ml_lv_dropdown_get_selected"

  (* The selected option's text. *)
  external get_selected_str : obj -> string = "ml_lv_dropdown_get_selected_str"
  external is_open : obj -> bool = "ml_lv_dropdown_is_open"
  external close : obj -> unit = "ml_lv_dropdown_close"
end

module Switch = struct
  (* On/off is the State.checked state. *)
  external create : obj -> obj = "ml_lv_switch_create"
end

module Checkbox = struct
  (* Ticked is the State.checked state. *)
  external create : obj -> obj = "ml_lv_checkbox_create"
  external set_text : obj -> string -> unit = "ml_lv_checkbox_set_text"
end

(* Keyboard focus: one widget of the group is focused (State.focused). *)
module Group = struct
  external create : unit -> group = "ml_lv_group_create"
  external delete : group -> unit = "ml_lv_group_delete"

  (* Delete [group] when [obj] gets Event.delete, before [obj]'s children are
     deleted: deleting the focused widget then moves no focus. (In C: app code
     no longer runs once the app is being torn down, see lvgl_stubs.c.) *)
  external delete_with : group -> obj -> unit = "ml_lv_group_delete_with"

  (* Whether focus_next on the last widget goes back to the first. *)
  external set_wrap : group -> bool -> unit = "ml_lv_group_set_wrap"

  (* The widget's group (if any) is replaced by [group]. *)
  external add_obj : group -> obj -> unit = "ml_lv_group_add_obj"

  (* Take the widget out of its group. *)
  external remove_obj : obj -> unit = "ml_lv_group_remove_obj"
  external focus_obj : obj -> unit = "ml_lv_group_focus_obj"
  external focus_next : group -> unit = "ml_lv_group_focus_next"
  external focus_prev : group -> unit = "ml_lv_group_focus_prev"
  external get_focused : group -> obj option = "ml_lv_group_get_focused"
end

(* Input devices (indev/lv_indev.h). A keypad device sends keys to the focused
   widget of its group. *)
module Indev = struct
  (* lv_indev_type_t *)
  module Type = struct
    let keypad = 2
  end

  (* The device after [indev] (the first one after None). *)
  external get_next : indev option -> indev option = "ml_lv_indev_get_next"

  let all () =
    let rec from previous =
      match get_next previous with Some indev -> indev :: from (Some indev) | None -> []
    in
    from None

  (* The device whose input LVGL is handling right now (inside an event callback). *)
  external active : unit -> indev option = "ml_lv_indev_active"
  external get_type : indev -> int = "ml_lv_indev_get_type"
  external get_group : indev -> group option = "ml_lv_indev_get_group"
  external set_group : indev -> group option -> unit = "ml_lv_indev_set_group"

  (* Ignore the key (or touch) that is down now until it is released. *)
  external wait_release : indev -> unit = "ml_lv_indev_wait_release"
end

module Display = struct
  external get_default : unit -> display = "ml_lv_display_get_default"
  external set_theme : display -> theme -> unit = "ml_lv_display_set_theme"
end

module Theme = struct
  (* LVGL's default theme for [display] with these colors (0xRRGGBB) and font.
     Calling it again updates the same theme: every widget that uses it
     restyles. *)
  external default_init : display -> primary:int -> secondary:int -> dark:bool -> font -> theme
    = "ml_lv_theme_default_init"
end

module Timer = struct
  external create_raw : int -> (timer -> unit) -> timer = "ml_lv_timer_create"

  (* Call [callback] every [period] milliseconds (it gets the timer, e.g. to pause it). *)
  let create ~period callback = create_raw period (guard callback)

  external delete : timer -> unit = "ml_lv_timer_delete"
  external pause : timer -> unit = "ml_lv_timer_pause"
  external resume : timer -> unit = "ml_lv_timer_resume"
end

(* cp0_app.h: the app's page (top bar + 320x150 content area), keys, and the event loop. *)
module App = struct
  type key_state = Released | Pressed | Repeated

  (* One key event. [code] is the Linux key code (see Keys), [text] the UTF-8
     text it types with Shift and the keyboard's symbol layer applied ("" if
     none), [mods] the Mod bits. *)
  type key = { code : int; state : key_state; mods : int; text : string }

  module Mod = struct
    let shift = 1
    let ctrl = 2
    let alt = 4
  end

  external run_raw : string -> (obj -> unit) -> (key -> unit) -> int = "ml_cp0_app_run"

  (* Set up LVGL, the display and the keyboard, call [setup] with the content
     area (build the UI there), then call [on_key] for every key event
     (releases included) until [quit]. Returns the exit status. *)
  let run ~title ~setup ~on_key = run_raw title (guard setup) (guard on_key)

  (* Leave the event loop; [run] returns soon after. *)
  external quit : unit -> unit = "ml_cp0_app_quit"

  (* The top bar's title. *)
  external set_title : string -> unit = "ml_cp0_app_set_title"

  (* The 320x150 area below the top bar, and the whole screen. *)
  external content : unit -> obj = "ml_cp0_app_content"
  external screen : unit -> obj = "ml_cp0_app_screen"

  (* true: keys type text (F/X/Z/C are letters). false (the default): F/X/Z/C
     double as up/down/left/right, like in the launcher. *)
  external set_text_input : bool -> unit = "ml_cp0_app_set_text_input"

  (* true: keys reach only [run]'s on_key, not LVGL's focused widget. *)
  external set_keypad_intercept : bool -> unit = "ml_cp0_app_set_keypad_intercept"

  (* The path of a file installed with the app (APPLaunch/share/images/<name>, ...),
     on the desktop and the device alike. *)
  external file_path : string -> string = "ml_cp0_app_file_path"
end

(* Linux key codes (linux/input-event-codes.h) that apps commonly need. *)
module Keys = struct
  let esc = 1
  let digit_1 = 2
  let digit_2 = 3
  let digit_3 = 4
  let digit_4 = 5
  let backspace = 14
  let tab = 15
  let enter = 28
  let f = 33
  let z = 44
  let x = 45
  let c = 46
  let space = 57
  let up = 103
  let left = 105
  let right = 106
  let down = 108
end
