(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Demo 4, widgets: a form of stock LVGL widgets with the default theme, laid
   out with flex and driven by LVGL's own focus group and widget events:
   lv_textarea, lv_button, lv_slider, lv_spinbox, lv_dropdown, lv_switch,
   lv_checkbox. F/X move the focus, Z/C change the value, ENTER presses; the
   text area takes typing.

   Stock LVGL, plus one adapter for the keyboard
   ---------------------------------------------
   Everything on this screen is plain LVGL:
   - the look is LVGL's default theme (App_ui.set_theme, called before any
     widget exists). The widgets get sizes, never colors; the Color row runs
     the theme again with another accent color and every widget follows;
   - the layout is flex: a scrolling column of rows, each a label and widgets;
   - the focus is an lv_group holding the form's widgets, which the keypad
     input device uses while the screen shows. The focused widget gets
     LV_STATE_FOCUS_KEY (the theme draws an outline) and scrolls into view;
   - cp0_lvgl's keypad input device sends each key to the focused widget as
     Event.key: arrows (F/X/Z/C on the CardputerZero), ENTER, ESC,
     BACKSPACE ... as LVGL's keys, and the character for a key that types
     one. Each widget reacts the way it always does: the text area takes
     typing and BACKSPACE, DEL, LEFT/RIGHT, HOME/END; ENTER clicks a button,
     toggles the switch and the checkbox, opens the dropdown and picks an
     option; LEFT/RIGHT move the slider; ESC closes the dropdown;
   - the form reacts only to widget events (Event.clicked,
     Event.value_changed, Event.ready), so a mouse click in the desktop
     window does exactly what the keys do.

   The CardputerZero keyboard needs one small adapter and one switch on top:
   - Moving the focus. LVGL moves it only on LV_KEY_NEXT/LV_KEY_PREV, which
     the keyboard never sends; it has no arrow keys either, so cp0_lvgl turns
     F/X/Z/C into UP/DOWN/LEFT/RIGHT. [focus_keys], an Event.key preprocess
     handler on every widget of the form, turns UP/DOWN into
     Group.focus_prev/next, except while the dropdown's list is open (there
     UP/DOWN choose an option). ([count_keys] gives the spinbox's LEFT/RIGHT,
     which would move between digits, to its value.)
   - Typing. While the text area has the focus the keyboard is in text mode,
     so F/X/Z/C type letters instead of acting as arrows
     (Lvgl.App.set_text_input). *)

let form_top = 18 (* below the status line *)
let label_width = 62 (* the column of row labels *)
let max_name = 24
let form_hint = "F/X move  Z/C change  ENTER press"
let typing_hint = "type a name  ENTER next"

(* The Color row: each template's language and GitHub's color for it, in the
   dropdown's order. This template starts on its own language, OCaml. *)
let color_options = [ "Rust"; "Zig"; "OCaml"; "C++" ]
let colors = [| 0xDEA584; 0xEC915C; 0xEF7A08; 0xF34B7D |]
let language_option = 2

(* Key events, before the widget itself handles them. *)
let key_preprocess = Lvgl.Event.(key lor preprocess)

type t = {
  root : Lvgl.obj;
  group : Lvgl.group;  (* the form's focusable widgets, in F/X order *)
  mutable previous_group : Lvgl.group option;  (* the keypad's group before this screen showed *)
  status : Lvgl.obj;
  hint : Lvgl.obj;
  name : Lvgl.obj;
  hello : Lvgl.obj;
  add_one : Lvgl.obj;
  volume : Lvgl.obj;
  volume_value : Lvgl.obj;
  minus : Lvgl.obj;
  count : Lvgl.obj;
  plus : Lvgl.obj;
  color : Lvgl.obj;
  sound : Lvgl.obj;
  sound_value : Lvgl.obj;
  like : Lvgl.obj;
}

(* ---- Building the form ---- *)

(* The form: a flex column that scrolls when the rows don't fit. It keeps the
   theme's scrollbar but not its card background. *)
let make_column root =
  let column = Lvgl.Obj.create root in
  Lvgl.Obj.set_pos column ~x:0 ~y:form_top;
  Lvgl.Obj.set_size column ~width:App_ui.content_width ~height:(App_ui.hint_top - form_top);
  Lvgl.Obj.set_style_bg_opa column Lvgl.Opa.transp;
  Lvgl.Obj.set_style_border_width column 0;
  Lvgl.Obj.set_style_pad_all column 2;
  Lvgl.Obj.set_style_pad_row column 0;
  Lvgl.Obj.set_flex_flow column Lvgl.Flex_flow.column;
  column

(* One row of the form: a transparent flex row holding a fixed-width label;
   the caller adds the row's widgets after it. *)
let make_row column text =
  let row = Lvgl.Obj.create column in
  Lvgl.Obj.remove_style_all row (* layout only: no background, border or padding *);
  Lvgl.Obj.set_size row ~width:(Lvgl.pct 100) ~height:Lvgl.size_content;
  Lvgl.Obj.set_flex_flow row Lvgl.Flex_flow.row;
  Lvgl.Obj.set_flex_align row ~main:Lvgl.Flex_align.start ~cross:Lvgl.Flex_align.center
    ~track:Lvgl.Flex_align.center;
  Lvgl.Obj.set_style_pad_all row 4 (* room for the theme's focus outline around the widgets *);
  Lvgl.Obj.set_style_pad_column row 6;
  let label = Lvgl.Label.create row in
  Lvgl.Label.set_text label text;
  Lvgl.Obj.set_width label label_width;
  row

(* The default theme pads widgets for bigger screens. On 320 x 150 the form
   trims the vertical padding of the taller widgets to fit more rows. *)
let compact widget = Lvgl.Obj.set_style_pad_ver widget 4

let make_button parent text =
  let button = Lvgl.Button.create parent in
  compact button;
  let label = Lvgl.Label.create button in
  Lvgl.Label.set_text label text;
  Lvgl.Obj.center label;
  button

(* The spinbox's -/+ buttons are for the mouse: Z/C do the same from the
   keyboard. Keep them out of every focus group (Button.create adds a button
   to the default group, if there is one). *)
let make_step_button row text =
  let button = make_button row text in
  Lvgl.Group.remove_obj button;
  button

let make_name_row column =
  let row = make_row column "Name" in
  let name = Lvgl.Textarea.create row in
  Lvgl.Textarea.set_one_line name true;
  Lvgl.Textarea.set_placeholder_text name "your name";
  Lvgl.Textarea.set_max_length name max_name;
  Lvgl.Obj.set_flex_grow name 1;
  compact name;
  name

let make_buttons_row column =
  let row = make_row column "Buttons" in
  let hello = make_button row "Say hello" in
  let add_one = make_button row "Count +1" in
  (hello, add_one)

let make_volume_row column =
  let row = make_row column "Volume" in
  let volume = Lvgl.Slider.create row in
  Lvgl.Slider.set_range volume ~min:0 ~max:100;
  Lvgl.Slider.set_value volume 50 ~anim:false;
  Lvgl.Obj.set_flex_grow volume 1;
  let value = Lvgl.Label.create row in
  Lvgl.Label.set_text value "50";
  Lvgl.Obj.set_width value 30;
  (volume, value)

let make_count_row column =
  let row = make_row column "Count" in
  let minus = make_step_button row "-" in
  let count = Lvgl.Spinbox.create row in
  Lvgl.Spinbox.set_range count ~min:(-999) ~max:999;
  Lvgl.Spinbox.set_digit_format count ~digits:3 ~separator:0;
  Lvgl.Obj.set_width count 64;
  compact count;
  let plus = make_step_button row "+" in
  (minus, count, plus)

let make_color_row column =
  let row = make_row column "Color" in
  let color = Lvgl.Dropdown.create row in
  Lvgl.Dropdown.set_options color color_options;
  Lvgl.Dropdown.set_selected color language_option;
  Lvgl.Obj.set_width color 100;
  compact color;
  color

let make_sound_row column =
  let row = make_row column "Sound" in
  let sound = Lvgl.Switch.create row in
  Lvgl.Obj.add_state sound Lvgl.State.checked;
  let value = Lvgl.Label.create row in
  Lvgl.Label.set_text value "on";
  (sound, value)

let make_like_row column =
  let row = make_row column "Like" in
  let like = Lvgl.Checkbox.create row in
  Lvgl.Checkbox.set_text like "I like LVGL";
  like

(* ---- The keyboard adapter ---- *)

(* F/X (UP/DOWN) move the focus to the previous/next widget. *)
let focus_keys form event =
  let key = Lvgl.Event.get_key event in
  let widget = Lvgl.Event.target event in
  let in_open_list = widget == form.color && Lvgl.Dropdown.is_open widget in
  if (key = Lvgl.Key.up || key = Lvgl.Key.down) && not in_open_list then begin
    if key = Lvgl.Key.up then Lvgl.Group.focus_prev form.group else Lvgl.Group.focus_next form.group;
    Lvgl.Event.stop_processing event (* the widget itself never sees the key *)
  end

(* Z/C (LEFT/RIGHT) step the spinbox's value; nothing else edits it (typed
   characters included: the spinbox is a text area underneath). *)
let count_keys event =
  let spinbox = Lvgl.Event.target event in
  let key = Lvgl.Event.get_key event in
  if key <> Lvgl.Key.up && key <> Lvgl.Key.down (* focus moves *) then begin
    if key = Lvgl.Key.left then Lvgl.Spinbox.decrement spinbox
    else if key = Lvgl.Key.right then Lvgl.Spinbox.increment spinbox;
    Lvgl.Event.stop_processing event
  end

(* ENTER in the one-line text area: on to the next widget. The ENTER key is
   still down; waiting for its release keeps it from clicking the newly
   focused button. *)
let name_ready form =
  Lvgl.Group.focus_next form.group;
  Option.iter Lvgl.Indev.wait_release (Lvgl.Indev.active ())

(* ---- Widget events ---- *)

let set_status form text = Lvgl.Label.set_text form.status text

(* The text area has the focus: keys type text, and the hint says so. *)
let set_typing form typing =
  Lvgl.Label.set_text form.hint (if typing then typing_hint else form_hint);
  if App_ui.shown form.root then Lvgl.App.set_text_input typing

let say_hello form =
  let name = String.trim (Lvgl.Textarea.get_text form.name) in
  set_status form (Printf.sprintf "Hello, %s!" (if name = "" then "stranger" else name))

(* The spinbox reports the change (Event.value_changed). *)
let count_plus_one form = Lvgl.Spinbox.set_value form.count (Lvgl.Spinbox.get_value form.count + 1)

let volume_changed form =
  let value = string_of_int (Lvgl.Slider.get_value form.volume) in
  Lvgl.Label.set_text form.volume_value value;
  set_status form ("Volume " ^ value)

let count_changed form = set_status form (Printf.sprintf "Count %d" (Lvgl.Spinbox.get_value form.count))

let color_changed form =
  let color = colors.(Lvgl.Dropdown.get_selected form.color) in
  App_ui.set_theme color (* every themed widget in the app takes the new accent color *);
  Lvgl.Obj.set_style_text_color form.status color;
  set_status form ("Color " ^ Lvgl.Dropdown.get_selected_str form.color)

let sound_changed form =
  let state = if Lvgl.Obj.has_state form.sound Lvgl.State.checked then "on" else "off" in
  Lvgl.Label.set_text form.sound_value state;
  set_status form ("Sound " ^ state)

let like_changed form =
  set_status form (if Lvgl.Obj.has_state form.like Lvgl.State.checked then "Thanks!" else "Oh no")

(* Every focusable widget: into the group (F/X order is the order of these
   calls), the adapter for F/X, and scrolled into view when it gets the focus. *)
let add_to_form form widget =
  Lvgl.Group.add_obj form.group widget;
  Lvgl.Obj.add_event_cb widget key_preprocess (focus_keys form);
  Lvgl.Obj.add_flag widget Lvgl.Flag.scroll_on_focus

let connect form =
  let open Lvgl in
  List.iter (add_to_form form)
    [ form.name; form.hello; form.add_one; form.volume; form.count; form.color; form.sound; form.like ];
  Obj.add_event_cb form.name Event.focused (fun _ -> set_typing form true);
  Obj.add_event_cb form.name Event.defocused (fun _ -> set_typing form false);
  Obj.add_event_cb form.name Event.ready (fun _ -> name_ready form);
  Obj.add_event_cb form.hello Event.clicked (fun _ -> say_hello form);
  Obj.add_event_cb form.add_one Event.clicked (fun _ -> count_plus_one form);
  Obj.add_event_cb form.volume Event.value_changed (fun _ -> volume_changed form);
  Obj.add_event_cb form.count key_preprocess count_keys;
  Obj.add_event_cb form.count Event.value_changed (fun _ -> count_changed form);
  (* As in LVGL's spinbox example: a click steps once, holding the mouse
     button repeats. *)
  List.iter
    (fun code ->
      Obj.add_event_cb form.minus code (fun _ -> Spinbox.decrement form.count);
      Obj.add_event_cb form.plus code (fun _ -> Spinbox.increment form.count))
    [ Event.short_clicked; Event.long_pressed_repeat ];
  Obj.add_event_cb form.color Event.value_changed (fun _ -> color_changed form);
  Obj.add_event_cb form.sound Event.value_changed (fun _ -> sound_changed form);
  Obj.add_event_cb form.like Event.value_changed (fun _ -> like_changed form)

(* ---- The screen ---- *)

let keypads () = List.filter (fun indev -> Lvgl.Indev.get_type indev = Lvgl.Indev.Type.keypad) (Lvgl.Indev.all ())

let on_show form =
  (* The keypad input device(s) use the form's group while the screen shows.
     The key that opened the screen (4, ENTER, TAB) is still being handled:
     Indev.wait_release keeps it from reaching the focused widget (ENTER would
     leave the text area, 4 would be typed into it). *)
  List.iter
    (fun keypad ->
      form.previous_group <- Lvgl.Indev.get_group keypad;
      Lvgl.Indev.set_group keypad (Some form.group);
      Lvgl.Indev.wait_release keypad)
    (keypads ());
  (* Focus a widget, now from the keypad, so it gets LV_STATE_FOCUS_KEY (the
     theme's outline) and its Event.focused handlers run: the one that had the
     focus, or the first time the first one (hidden widgets can't take the
     focus, so none has it yet). *)
  (match Lvgl.Group.get_focused form.group with
  | Some focused -> Lvgl.Group.focus_obj focused
  | None -> Lvgl.Group.focus_next form.group);
  (* LVGL 9.5 does not grow the drawing area of a widget that was never drawn
     when its new state also changes its layout, as the text area's cursor
     style does; without this the first outline would be clipped away. *)
  Option.iter Lvgl.Obj.refresh_ext_draw_size (Lvgl.Group.get_focused form.group)

let on_hide form =
  Lvgl.Dropdown.close form.color (* its list belongs to the LVGL screen, not to this container *);
  List.iter
    (fun indev ->
      match Lvgl.Indev.get_group indev with
      | Some group when group == form.group -> Lvgl.Indev.set_group indev form.previous_group
      | _ -> ())
    (Lvgl.Indev.all ());
  Lvgl.App.set_text_input false

(* Only the app's keys; LVGL's keypad device delivers every key to the
   focused widget as well. ESC first closes an open dropdown list: LVGL gets
   the same ESC right after this and closes it. *)
let handle_key form (key : Lvgl.App.key) : App_ui.action =
  let open Lvgl.Keys in
  if key.code = esc then if Lvgl.Dropdown.is_open form.color then Stay else Home
  else if key.code = tab then Next
  else Stay

let create parent =
  let root = App_ui.screen_root parent in
  let status = App_ui.make_label root "Try every widget" Lvgl.Font.montserrat_14 App_ui.language_color in
  Lvgl.Obj.set_pos status ~x:8 ~y:0;
  ignore (App_ui.make_demo_keys root);
  let column = make_column root in
  let hint = App_ui.make_hint root form_hint in
  let group = Lvgl.Group.create () in
  Lvgl.Group.set_wrap group true (* X on the last widget goes back to the first *);
  Lvgl.Group.delete_with group root;
  (* The rows, top to bottom, one at a time: OCaml does not fix the order in
     which a record's fields are evaluated. *)
  let name = make_name_row column in
  let hello, add_one = make_buttons_row column in
  let volume, volume_value = make_volume_row column in
  let minus, count, plus = make_count_row column in
  let color = make_color_row column in
  let sound, sound_value = make_sound_row column in
  let like = make_like_row column in
  let form =
    {
      root;
      group;
      previous_group = None;
      status;
      hint;
      name;
      hello;
      add_one;
      volume;
      volume_value;
      minus;
      count;
      plus;
      color;
      sound;
      sound_value;
      like;
    }
  in
  connect form;
  App_ui.make_screen ~root
    ~title:(fun () -> "Widgets")
    ~handle_key:(handle_key form)
    ~on_show:(fun () -> on_show form)
    ~on_hide:(fun () -> on_hide form)
    ()
