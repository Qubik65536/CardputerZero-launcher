(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Demo 4, widgets: a small form with a text field, a button, a slider, a
   counter, a chooser and a switch, drawn by hand on the framebuffer. One widget
   has the focus; F/X move it, Z/C change the value, ENTER presses. The text
   field takes typing. *)

type widget = Name | Button | Volume | Count | Color | Sound

(* The form, top to bottom, with each row's label. *)
let rows =
  [| (Name, "Name"); (Button, "Button"); (Volume, "Volume"); (Count, "Count"); (Color, "Color"); (Sound, "Sound") |]

(* The chooser's options: each template language and GitHub's color for it. *)
let choices =
  [|
    ("Rust", Display.rgb 0xDE 0xA5 0x84);
    ("Zig", Display.rgb 0xEC 0x91 0x5C);
    ("OCaml", Display.rgb 0xEF 0x7A 0x08);
    ("C++", Display.rgb 0xF3 0x4B 0x7D);
  |]

let top = Ui.header_height + 2
let row_height = 18
let widget_left = 72 (* labels on the left, widgets from here *)
let widget_width = 242
let max_name = 24
let slider_width = 176
let volume_step = 5
let press_frames = 10 (* how long the button shows as pressed *)
let field = Display.rgb 8 10 14
let border = Display.rgb 60 70 82
let face = Display.rgb 28 34 42

type t = {
  mutable focus : int; (* index into rows *)
  mutable name : string;
  mutable volume : int; (* 0..100 *)
  mutable count : int;
  mutable choice : int; (* index into choices *)
  mutable sound : bool;
  mutable pressed_frames : int;
  mutable status : string; (* what the last action did *)
}

(* Index of this template's language among the choices (0 if it is missing). *)
let language_choice () =
  let rec find index =
    if index >= Array.length choices then 0 else if fst choices.(index) = Ui.language then index else find (index + 1)
  in
  find 0

let create () =
  {
    focus = 0;
    name = "";
    volume = 50;
    count = 0;
    choice = language_choice ();
    sound = true;
    pressed_frames = 0;
    status = "Try every widget";
  }

(* The accent color is whatever the chooser picked. *)
let accent widgets = snd choices.(widgets.choice)

let focused widgets = fst rows.(widgets.focus)

(* True while the button shows its pressed state. *)
let animated widgets = widgets.pressed_frames > 0

let tick widgets = widgets.pressed_frames <- max 0 (widgets.pressed_frames - 1)

(* [a] modulo [b], never negative. *)
let wrap a b = ((a mod b) + b) mod b

let move_focus widgets step = widgets.focus <- wrap (widgets.focus + step) (Array.length rows)

(* Z/C (or left/right): step the focused widget's value. *)
let change widgets step =
  match focused widgets with
  | Volume ->
      widgets.volume <- max 0 (min 100 (widgets.volume + (step * volume_step)));
      widgets.status <- Printf.sprintf "Volume %d" widgets.volume
  | Count ->
      widgets.count <- widgets.count + step;
      widgets.status <- Printf.sprintf "Count %d" widgets.count
  | Color ->
      widgets.choice <- wrap (widgets.choice + step) (Array.length choices);
      widgets.status <- Printf.sprintf "Color %s" (fst choices.(widgets.choice))
  | Sound ->
      widgets.sound <- not widgets.sound;
      widgets.status <- Printf.sprintf "Sound %s" (if widgets.sound then "on" else "off")
  | Name | Button -> ()

(* ENTER or SPACE on the focused widget. *)
let activate widgets =
  match focused widgets with
  | Button ->
      widgets.pressed_frames <- press_frames;
      let name = String.trim widgets.name in
      widgets.status <- Printf.sprintf "Hello, %s!" (if name = "" then "stranger" else name)
  | Count ->
      widgets.count <- 0;
      widgets.status <- "Count reset"
  | Color | Sound -> change widgets 1
  | Name -> move_focus widgets 1
  | Volume -> ()

(* [typed] is the character the key produces, if any (see Input.char_for). *)
let handle_key widgets (event : Input.event) typed : Ui.action =
  if not (Input.is_down event) then Stay
  else
    let code = event.code in
    if code = Input.Keys.esc then Home
    else if code = Input.Keys.tab then Next
    else begin
      (* Real arrow keys always move the focus, even out of the text field. *)
      if code = Input.Keys.up then move_focus widgets (-1)
      else if code = Input.Keys.down then move_focus widgets 1
      else if focused widgets = Name then begin
        (* In the text field F/X/Z/C are letters; ENTER moves on. *)
        if code = Input.Keys.enter then move_focus widgets 1
        else if code = Input.Keys.backspace then begin
          let length = String.length widgets.name in
          if length > 0 then widgets.name <- String.sub widgets.name 0 (length - 1)
        end
        else
          match typed with
          | Some character when String.length widgets.name < max_name ->
              widgets.name <- widgets.name ^ String.make 1 character
          | _ -> ()
      end
      else (
        match Input.direction code with
        | Some Up -> move_focus widgets (-1)
        | Some Down -> move_focus widgets 1
        | Some Left -> change widgets (-1)
        | Some Right -> change widgets 1
        | None -> if code = Input.Keys.enter || code = Input.Keys.space then activate widgets);
      Stay
    end

let draw_text_field widgets display y focused =
  let accent = accent widgets in
  Display.fill_rect display widget_left y widget_width row_height field;
  Display.stroke_rect display widget_left y widget_width row_height (if focused then accent else border);
  if widgets.name = "" && not focused then Display.draw_text display (widget_left + 4) (y + 1) "your name" Ui.muted 1
  else begin
    Display.draw_text display (widget_left + 4) (y + 1) widgets.name Ui.text 1;
    if focused then
      Display.fill_rect display
        (widget_left + 4 + Display.text_width widgets.name 1)
        (y + 3) Display.char_width (Display.char_height - 4) accent (* cursor *)
  end

let draw_button widgets display y focused =
  let accent = accent widgets in
  let width = 120 and label = "Say hello" in
  let pressed = widgets.pressed_frames > 0 in
  Display.fill_rect display widget_left y width row_height (if pressed then accent else face);
  Display.stroke_rect display widget_left y width row_height (if focused then accent else border);
  let x = widget_left + ((width - Display.text_width label 1) / 2) in
  Display.draw_text display x (y + 1) label (if pressed then Ui.background else Ui.text) 1

let draw_slider widgets display y focused =
  let accent = accent widgets in
  let filled = widgets.volume * slider_width / 100 in
  Display.fill_rect display widget_left (y + 7) slider_width 4 border;
  Display.fill_rect display widget_left (y + 7) filled 4 accent;
  let knob = widget_left + filled - 3 in
  Display.fill_rect display knob (y + 2) 6 (row_height - 4) (if focused then Ui.text else Ui.muted);
  Display.draw_text display (widget_left + slider_width + 12) (y + 1) (string_of_int widgets.volume) Ui.text 1

let draw_counter widgets display y focused =
  let outline = if focused then accent widgets else border in
  List.iter
    (fun (x, sign) ->
      Display.fill_rect display x y 24 row_height face;
      Display.stroke_rect display x y 24 row_height outline;
      Display.draw_text display (x + 8) (y + 1) sign Ui.text 1)
    [ (widget_left, "-"); (widget_left + 84, "+") ];
  let value = string_of_int widgets.count in
  let x = widget_left + 24 + ((60 - Display.text_width value 1) / 2) in
  Display.draw_text display x (y + 1) value Ui.text 1

let draw_chooser widgets display y focused =
  let name, color = choices.(widgets.choice) in
  let arrows = if focused then accent widgets else Ui.muted in
  Display.draw_text display widget_left (y + 1) "<" arrows 1;
  Display.draw_text display (widget_left + 16) (y + 1) name color 1;
  Display.draw_text display (widget_left + 16 + (6 * Display.char_width)) (y + 1) ">" arrows 1;
  Display.fill_rect display (widget_left + 16 + (8 * Display.char_width)) (y + 2) 14 (row_height - 4) color (* swatch *)

let draw_switch widgets display y focused =
  let accent = accent widgets in
  Display.fill_rect display widget_left (y + 2) 32 (row_height - 4) (if widgets.sound then accent else border);
  if focused then Display.stroke_rect display (widget_left - 2) y 36 row_height Ui.text;
  let knob = if widgets.sound then widget_left + 18 else widget_left + 2 in
  Display.fill_rect display knob (y + 4) 12 (row_height - 8) Ui.text;
  Display.draw_text display (widget_left + 40) (y + 1) (if widgets.sound then "on" else "off") Ui.text 1

let draw widgets display =
  let accent = accent widgets in
  Display.clear display Ui.background;
  Array.iteri
    (fun index (widget, label) ->
      let y = top + (index * row_height) in
      let focused = index = widgets.focus in
      if focused then Display.fill_rect display 0 y 3 row_height accent;
      Display.draw_text display 8 (y + 1) label (if focused then accent else Ui.muted) 1;
      match widget with
      | Name -> draw_text_field widgets display y focused
      | Button -> draw_button widgets display y focused
      | Volume -> draw_slider widgets display y focused
      | Count -> draw_counter widgets display y focused
      | Color -> draw_chooser widgets display y focused
      | Sound -> draw_switch widgets display y focused)
    rows;
  Display.draw_text display 8 (top + (Array.length rows * row_height) + 2) widgets.status accent 1;
  Ui.draw_header display "Widgets";
  Ui.draw_hint display
    (if focused widgets = Name then "type a name  ENTER next" else "F/X move  Z/C change  ENTER press")
