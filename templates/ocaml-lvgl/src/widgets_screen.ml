(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Demo 4, widgets: a small form of real LVGL widgets (lv_textarea, lv_button,
   lv_slider, a -/+ counter, lv_roller, lv_switch) in an lv_group. F/X move the
   focus, Z/C change the value, ENTER presses; the text field takes typing.

   How keys reach the widgets
   --------------------------
   cp0_lvgl delivers every key twice: first to the app (Lvgl.App.run's on_key,
   with the Linux key code and the text it types), then through LVGL's keypad
   input device to the focused widget of an lv_group, as LV_EVENT_KEY. That
   second path cannot drive a form on the CardputerZero: the keyboard has no
   arrow keys (F/X/Z/C turn into arrows, so they could not be typed into the
   text field), letters arrive as key codes rather than characters, and LVGL
   only moves the focus on LV_KEY_NEXT/LV_KEY_PREV, which the keyboard never
   sends.

   So while this screen shows it turns that path off
   (Lvgl.App.set_keypad_intercept) and handles the keys itself, using LVGL's
   own machinery for the rest:
   - the widgets sit in an lv_group: F/X call Group.focus_prev/next, and the
     focused widget gets State.focused, which its styles react to;
   - Z/C and ENTER set the focused widget's value through its API and send the
     event LVGL itself would send (Event.value_changed, Event.clicked);
   - the form reacts to those events only, so a mouse click in the desktop
     window (or a touch screen) works the same way as the keys;
   - typed text goes into the lv_textarea with Textarea.add_text, and the
     keyboard is in text mode while the text field has the focus.
   The same works on the device and on the desktop. *)

let field = 0x080A0E
let border = 0x3C4652
let face = 0x1C222A

(* The form's rows, top to bottom; the status line sits above them. *)
let row_labels = [| "Name"; "Button"; "Volume"; "Count"; "Color"; "Sound" |]
let rows_top = 18
let row_height = 18
let widget_left = 72 (* labels on the left, widgets from here *)
let widget_width = 242
let slider_width = 176
let volume_step = 5
let max_name = 24
let press_ms = 10 * App_ui.frame_ms (* how long the button shows as pressed *)

(* The chooser's options: each template language and GitHub's color for it. *)
let choices = [| ("Rust", 0xDEA584); ("Zig", 0xEC915C); ("OCaml", 0xEF7A08); ("C++", 0xF34B7D) |]

type t = {
  root : Lvgl.obj;
  group : Lvgl.group;
  bars : Lvgl.obj array;
  labels : Lvgl.obj array;
  widgets : Lvgl.obj array;  (* the focusable widget of each row *)
  name : Lvgl.obj;
  button : Lvgl.obj;
  volume : Lvgl.obj;
  volume_value : Lvgl.obj;
  counter : Lvgl.obj;
  minus : Lvgl.obj;
  plus : Lvgl.obj;
  count_value : Lvgl.obj;
  chooser : Lvgl.obj;
  chooser_left : Lvgl.obj;
  chooser_right : Lvgl.obj;
  swatch : Lvgl.obj;
  sound : Lvgl.obj;
  sound_value : Lvgl.obj;
  status : Lvgl.obj;
  hint : Lvgl.obj;
  release_timer : Lvgl.timer;
  mutable count : int;
}

let default_choice () =
  let rec find index =
    if index >= Array.length choices then 0 else if fst choices.(index) = App_ui.language then index else find (index + 1)
  in
  find 0

(* The form's widgets are styled from scratch (no theme), flat like the rest of the app. *)
let style_box obj background =
  Lvgl.Obj.set_style_bg_color obj background;
  Lvgl.Obj.set_style_bg_opa obj Lvgl.Opa.cover;
  Lvgl.Obj.set_style_border_width obj 1;
  Lvgl.Obj.set_style_border_color obj border;
  Lvgl.Obj.set_style_text_font obj Lvgl.Font.montserrat_14;
  Lvgl.Obj.set_style_text_color obj App_ui.text_color

let make_box_button parent text ~x ~y ~width =
  let button = Lvgl.Button.create parent in
  Lvgl.Obj.remove_style_all button;
  style_box button face;
  Lvgl.Obj.set_pos button ~x ~y;
  Lvgl.Obj.set_size button ~width ~height:row_height;
  let label = Lvgl.Label.create button in
  Lvgl.Label.set_text label text;
  Lvgl.Obj.center label;
  button

(* Each row's focus bar and label. *)
let make_rows root =
  let rows =
    Array.mapi
      (fun row text ->
        let y = rows_top + (row * row_height) in
        let bar = App_ui.make_panel root ~x:0 ~y ~width:3 ~height:row_height App_ui.language_color Lvgl.Opa.cover in
        let label = App_ui.make_label root text Lvgl.Font.montserrat_14 App_ui.muted_color in
        Lvgl.Obj.set_pos label ~x:8 ~y:(y + 1);
        (bar, label))
      row_labels
  in
  (Array.map fst rows, Array.map snd rows)

let make_name root y =
  let name = Lvgl.Textarea.create root in
  Lvgl.Obj.remove_style_all name;
  style_box name field;
  Lvgl.Textarea.set_one_line name true;
  Lvgl.Textarea.set_placeholder_text name "your name";
  Lvgl.Textarea.set_max_length name max_name;
  Lvgl.Obj.set_style_pad_hor name 4;
  Lvgl.Obj.set_pos name ~x:widget_left ~y;
  Lvgl.Obj.set_size name ~width:widget_width ~height:row_height;
  Lvgl.Obj.set_style_text_color name App_ui.muted_color ~part:Lvgl.Part.textarea_placeholder;
  (* An empty focused field shows just the cursor: a solid block that does not blink. *)
  Lvgl.Obj.set_style_text_opa name Lvgl.Opa.transp ~part:Lvgl.Part.textarea_placeholder ~state:Lvgl.State.focused;
  Lvgl.Obj.set_style_bg_opa name Lvgl.Opa.cover ~part:Lvgl.Part.cursor ~state:Lvgl.State.focused;
  Lvgl.Obj.set_style_pad_right name 4 ~part:Lvgl.Part.cursor;
  Lvgl.Obj.set_style_anim_duration name 0 ~part:Lvgl.Part.cursor;
  name

let make_button root y =
  let button = make_box_button root "Say hello" ~x:widget_left ~y ~width:120 in
  Lvgl.Obj.set_style_text_color button App_ui.background_color ~state:Lvgl.State.pressed;
  button

let make_volume root y =
  let volume = Lvgl.Slider.create root in
  Lvgl.Obj.remove_style_all volume;
  Lvgl.Obj.set_pos volume ~x:widget_left ~y:(y + 7);
  Lvgl.Obj.set_size volume ~width:slider_width ~height:4;
  Lvgl.Slider.set_range volume ~min:0 ~max:100;
  Lvgl.Slider.set_value volume 50 ~anim:false;
  Lvgl.Obj.set_style_bg_color volume border;
  Lvgl.Obj.set_style_bg_opa volume Lvgl.Opa.cover;
  Lvgl.Obj.set_style_bg_opa volume Lvgl.Opa.cover ~part:Lvgl.Part.indicator;
  (* The knob is the 4 px track height grown by its padding: 6 x 14. *)
  Lvgl.Obj.set_style_bg_color volume App_ui.muted_color ~part:Lvgl.Part.knob;
  Lvgl.Obj.set_style_bg_color volume App_ui.text_color ~part:Lvgl.Part.knob ~state:Lvgl.State.focused;
  Lvgl.Obj.set_style_bg_opa volume Lvgl.Opa.cover ~part:Lvgl.Part.knob;
  Lvgl.Obj.set_style_pad_hor volume 1 ~part:Lvgl.Part.knob;
  Lvgl.Obj.set_style_pad_ver volume 5 ~part:Lvgl.Part.knob;
  let value = App_ui.make_label root "50" Lvgl.Font.montserrat_14 App_ui.text_color in
  Lvgl.Obj.set_pos value ~x:(widget_left + slider_width + 12) ~y:(y + 1);
  (volume, value)

(* One focusable container holding "-", the value and "+". *)
let make_counter root y =
  let counter =
    App_ui.make_panel root ~x:widget_left ~y ~width:108 ~height:row_height App_ui.background_color Lvgl.Opa.transp
  in
  let minus = make_box_button counter "-" ~x:0 ~y:0 ~width:24 in
  let plus = make_box_button counter "+" ~x:84 ~y:0 ~width:24 in
  let value = App_ui.make_label counter "0" Lvgl.Font.montserrat_14 App_ui.text_color in
  Lvgl.Obj.set_width value 60;
  Lvgl.Obj.set_style_text_align value Lvgl.Text_align.center;
  Lvgl.Obj.set_pos value ~x:24 ~y:1;
  (counter, minus, plus, value)

let make_chooser root y =
  let left = App_ui.make_label root "<" Lvgl.Font.montserrat_14 App_ui.muted_color in
  Lvgl.Obj.set_pos left ~x:widget_left ~y:(y + 1);
  let chooser = Lvgl.Roller.create root in
  Lvgl.Obj.remove_style_all chooser;
  Lvgl.Obj.set_style_text_font chooser Lvgl.Font.montserrat_14;
  Lvgl.Obj.set_style_text_font chooser Lvgl.Font.montserrat_14 ~part:Lvgl.Part.selected;
  Lvgl.Obj.set_style_text_align chooser Lvgl.Text_align.center;
  Lvgl.Roller.set_options chooser (Array.to_list (Array.map fst choices));
  Lvgl.Roller.set_visible_row_count chooser 1;
  Lvgl.Roller.set_selected chooser (default_choice ()) ~anim:false;
  Lvgl.Obj.set_pos chooser ~x:(widget_left + 12) ~y:(y + 1);
  Lvgl.Obj.set_width chooser 56;
  let right = App_ui.make_label root ">" Lvgl.Font.montserrat_14 App_ui.muted_color in
  Lvgl.Obj.set_pos right ~x:(widget_left + 72) ~y:(y + 1);
  let swatch =
    App_ui.make_panel root ~x:(widget_left + 88) ~y:(y + 2) ~width:14 ~height:(row_height - 4) App_ui.language_color
      Lvgl.Opa.cover
  in
  (left, chooser, right, swatch)

let make_switch root y =
  let sound = Lvgl.Switch.create root in
  Lvgl.Obj.remove_style_all sound;
  Lvgl.Obj.set_pos sound ~x:widget_left ~y:(y + 2);
  Lvgl.Obj.set_size sound ~width:32 ~height:(row_height - 4);
  Lvgl.Obj.set_style_bg_color sound border;
  Lvgl.Obj.set_style_bg_opa sound Lvgl.Opa.cover;
  Lvgl.Obj.set_style_bg_opa sound Lvgl.Opa.cover ~part:Lvgl.Part.indicator ~state:Lvgl.State.checked;
  Lvgl.Obj.set_style_bg_color sound App_ui.text_color ~part:Lvgl.Part.knob;
  Lvgl.Obj.set_style_bg_opa sound Lvgl.Opa.cover ~part:Lvgl.Part.knob;
  Lvgl.Obj.set_style_pad_all sound (-2) ~part:Lvgl.Part.knob;
  Lvgl.Obj.set_style_outline_color sound App_ui.text_color ~state:Lvgl.State.focused;
  Lvgl.Obj.set_style_outline_width sound 1 ~state:Lvgl.State.focused;
  Lvgl.Obj.set_style_outline_pad sound 2 ~state:Lvgl.State.focused;
  Lvgl.Obj.add_state sound Lvgl.State.checked;
  let value = App_ui.make_label root "on" Lvgl.Font.montserrat_14 App_ui.text_color in
  Lvgl.Obj.set_pos value ~x:(widget_left + 40) ~y:(y + 1);
  (sound, value)

let accent form = snd choices.(Lvgl.Roller.get_selected form.chooser)
let set_status form text = Lvgl.Label.set_text form.status text

let set_count form count status =
  form.count <- count;
  Lvgl.Label.set_text form.count_value (string_of_int count);
  set_status form status

let show_if obj visible = if visible then Lvgl.Obj.remove_flag obj Lvgl.Flag.hidden else Lvgl.Obj.add_flag obj Lvgl.Flag.hidden

(* The row markers that are not LVGL focus styles: accent bar, label colors,
   counter and chooser decorations, the hint, and the keyboard mode. *)
let refresh_focus form =
  let focused = Lvgl.Group.get_focused form.group in
  let accent_color = accent form in
  Array.iteri
    (fun row widget ->
      let is_focused = widget == focused in
      show_if form.bars.(row) is_focused;
      Lvgl.Obj.set_style_text_color form.labels.(row) (if is_focused then accent_color else App_ui.muted_color))
    form.widgets;
  let counter_border = if focused == form.counter then accent_color else border in
  Lvgl.Obj.set_style_border_color form.minus counter_border;
  Lvgl.Obj.set_style_border_color form.plus counter_border;
  let arrows = if focused == form.chooser then accent_color else App_ui.muted_color in
  Lvgl.Obj.set_style_text_color form.chooser_left arrows;
  Lvgl.Obj.set_style_text_color form.chooser_right arrows;

  let typing = focused == form.name in
  Lvgl.Label.set_text form.hint (if typing then "type a name  ENTER next" else "F/X move  Z/C change  ENTER press");
  if not (Lvgl.Obj.has_flag form.root Lvgl.Flag.hidden) then Lvgl.App.set_text_input typing

(* The accent color is whatever the chooser picked; every focus style uses it. *)
let apply_accent form =
  let color = accent form in
  let open Lvgl in
  Obj.set_style_border_color form.name color ~state:State.focused;
  Obj.set_style_bg_color form.name color ~part:Part.cursor ~state:State.focused;
  Obj.set_style_border_color form.button color ~state:State.focused;
  Obj.set_style_bg_color form.button color ~state:State.pressed;
  Obj.set_style_bg_color form.volume color ~part:Part.indicator;
  Obj.set_style_text_color form.chooser color ~part:Part.selected;
  Obj.set_style_bg_color form.swatch color;
  Obj.set_style_bg_color form.sound color ~part:Part.indicator ~state:State.checked;
  Obj.set_style_text_color form.status color;
  refresh_focus form

(* The form reacts to LVGL events, whether a key or a pointer caused them. *)
let connect form =
  Lvgl.Obj.add_event_cb form.button Lvgl.Event.clicked (fun _ ->
      let name = String.trim (Lvgl.Textarea.get_text form.name) in
      set_status form (Printf.sprintf "Hello, %s!" (if name = "" then "stranger" else name)));
  Lvgl.Obj.add_event_cb form.volume Lvgl.Event.value_changed (fun _ ->
      let value = string_of_int (Lvgl.Slider.get_value form.volume) in
      Lvgl.Label.set_text form.volume_value value;
      set_status form ("Volume " ^ value));
  Lvgl.Obj.add_event_cb form.minus Lvgl.Event.clicked (fun _ ->
      set_count form (form.count - 1) (Printf.sprintf "Count %d" (form.count - 1)));
  Lvgl.Obj.add_event_cb form.plus Lvgl.Event.clicked (fun _ ->
      set_count form (form.count + 1) (Printf.sprintf "Count %d" (form.count + 1)));
  Lvgl.Obj.add_event_cb form.chooser Lvgl.Event.value_changed (fun _ ->
      apply_accent form;
      set_status form ("Color " ^ fst choices.(Lvgl.Roller.get_selected form.chooser)));
  Lvgl.Obj.add_event_cb form.sound Lvgl.Event.value_changed (fun _ ->
      let state = if Lvgl.Obj.has_state form.sound Lvgl.State.checked then "on" else "off" in
      Lvgl.Label.set_text form.sound_value state;
      set_status form ("Sound " ^ state))

(* ENTER on the button: show it pressed for a moment and click it. *)
let press_button form =
  Lvgl.Obj.add_state form.button Lvgl.State.pressed;
  Lvgl.Timer.reset form.release_timer;
  Lvgl.Timer.resume form.release_timer;
  Lvgl.Obj.send_event form.button Lvgl.Event.clicked

(* Z/C (or left/right): step the focused widget's value. *)
let change form step =
  let focused = Lvgl.Group.get_focused form.group in
  if focused == form.volume then begin
    let value = Lvgl.Slider.get_value form.volume + (step * volume_step) in
    Lvgl.Slider.set_value form.volume (max 0 (min 100 value)) ~anim:false;
    Lvgl.Obj.send_event form.volume Lvgl.Event.value_changed
  end
  else if focused == form.counter then Lvgl.Obj.send_event (if step < 0 then form.minus else form.plus) Lvgl.Event.clicked
  else if focused == form.chooser then begin
    let count = Array.length choices in
    Lvgl.Roller.set_selected form.chooser ((Lvgl.Roller.get_selected form.chooser + count + step) mod count) ~anim:false;
    Lvgl.Obj.send_event form.chooser Lvgl.Event.value_changed
  end
  else if focused == form.sound then begin
    Lvgl.Obj.set_state form.sound Lvgl.State.checked (not (Lvgl.Obj.has_state form.sound Lvgl.State.checked));
    Lvgl.Obj.send_event form.sound Lvgl.Event.value_changed
  end

(* ENTER or SPACE on the focused widget. *)
let activate form =
  let focused = Lvgl.Group.get_focused form.group in
  if focused == form.button then press_button form
  else if focused == form.counter then set_count form 0 "Count reset"
  else if focused == form.chooser || focused == form.sound then change form 1

let on_show form =
  (* Keys come only through on_key while the form shows (see the top of this file). *)
  Lvgl.App.set_keypad_intercept true;
  refresh_focus form

let on_hide () =
  Lvgl.App.set_keypad_intercept false;
  Lvgl.App.set_text_input false

let handle_key form (key : Lvgl.App.key) : App_ui.action =
  let open Lvgl.Keys in
  let code = key.code in
  if code = esc then Home
  else if code = tab then Next
  else begin
    (* Real arrow keys always move the focus, even out of the text field. *)
    if code = up then Lvgl.Group.focus_prev form.group
    else if code = down then Lvgl.Group.focus_next form.group
    else if Lvgl.Group.get_focused form.group == form.name then begin
      (* In the text field F/X/Z/C are letters; ENTER moves on. *)
      if code = enter then Lvgl.Group.focus_next form.group
      else if code = backspace then Lvgl.Textarea.delete_char form.name
      else Option.iter (Lvgl.Textarea.add_text form.name) (App_ui.typed_text key)
    end
    else begin
      match App_ui.direction code with
      | Some Up -> Lvgl.Group.focus_prev form.group
      | Some Down -> Lvgl.Group.focus_next form.group
      | Some Left -> change form (-1)
      | Some Right -> change form 1
      | None -> if code = enter || code = space then activate form
    end;
    Stay
  end

let create parent =
  let root = App_ui.screen_root parent in
  let status = App_ui.make_label root "Try every widget" Lvgl.Font.montserrat_14 App_ui.language_color in
  Lvgl.Obj.set_pos status ~x:8 ~y:0;
  ignore (App_ui.make_demo_keys root);
  let bars, labels = make_rows root in
  let row_top row = rows_top + (row * row_height) in
  let name = make_name root (row_top 0) in
  let button = make_button root (row_top 1) in
  let volume, volume_value = make_volume root (row_top 2) in
  let counter, minus, plus, count_value = make_counter root (row_top 3) in
  let chooser_left, chooser, chooser_right, swatch = make_chooser root (row_top 4) in
  let sound, sound_value = make_switch root (row_top 5) in
  let hint = App_ui.make_hint root "" in
  (* Paused until the button is pressed; then it releases the button once and pauses again. *)
  let release_timer =
    Lvgl.Timer.create ~period:press_ms (fun timer ->
        Lvgl.Obj.remove_state button Lvgl.State.pressed;
        Lvgl.Timer.pause timer)
  in
  Lvgl.Timer.pause release_timer;

  let widgets = [| name; button; volume; counter; chooser; sound |] in
  let group = Lvgl.Group.create () in
  Lvgl.Group.set_wrap group true;
  Array.iter (Lvgl.Group.add_obj group) widgets;
  Lvgl.Group.focus_obj name;
  let form =
    {
      root;
      group;
      bars;
      labels;
      widgets;
      name;
      button;
      volume;
      volume_value;
      counter;
      minus;
      plus;
      count_value;
      chooser;
      chooser_left;
      chooser_right;
      swatch;
      sound;
      sound_value;
      status;
      hint;
      release_timer;
      count = 0;
    }
  in
  connect form;
  Lvgl.Group.set_focus_cb group (fun _ -> refresh_focus form);
  apply_accent form;
  App_ui.make_screen ~root
    ~title:(fun () -> "Widgets")
    ~handle_key:(handle_key form)
    ~on_show:(fun () -> on_show form)
    ~on_hide ()
