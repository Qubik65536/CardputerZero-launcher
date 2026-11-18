(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   The app's look and plumbing, shared by every screen: colors, the theme,
   key helpers, label/panel helpers and the screen type. *)

(* The language this template is written in, and GitHub's color for it. *)
let language = "OCaml"
let language_color = 0xEF7A08
let background_color = 0x0E1217
let text_color = 0xFFFFFF
let muted_color = 0x96A0AA
let error_color = 0xFF6E6E

(* The content area below the 20 px top bar that every screen fills. *)
let content_width = 320
let content_height = 150

(* Top of the key-help line at the bottom of a screen (content coordinates). *)
let hint_top = content_height - 17

(* Animation frame period: about 60 frames per second. *)
let frame_ms = 16

(* What a screen asks the app to do after a key press. *)
type action =
  | Stay
  | Home  (* back to the home screen *)
  | Next  (* on to the next demo (TAB) *)
  | Open of int  (* open demo N (0-based) from the home screen *)
  | Quit

type direction = Up | Down | Left | Right

(* The CardputerZero keyboard has no arrow keys: like the launcher, F/X/Z/C
   act as up/down/left/right. Real arrow keys (desktop, USB keyboards) work too. *)
let direction code =
  let open Lvgl.Keys in
  if code = up || code = f then Some Up
  else if code = down || code = x then Some Down
  else if code = left || code = z then Some Left
  else if code = right || code = c then Some Right
  else None

(* Text the key typed (cp0_lvgl applies Shift and the symbol layer), or None
   for keys that type nothing printable. *)
let typed_text (key : Lvgl.App.key) =
  if String.length key.text = 1 && key.text.[0] >= ' ' && key.text.[0] < '\127' then Some key.text else None

let make_label parent text font color =
  let label = Lvgl.Label.create parent in
  Lvgl.Label.set_text label text;
  Lvgl.Obj.set_style_text_font label font;
  Lvgl.Obj.set_style_text_color label color;
  label

(* A plain rectangle; [opa] below Opa.cover shades what is under it. *)
let make_panel parent ~x ~y ~width ~height color opa =
  let panel = Lvgl.Obj.create parent in
  Lvgl.Obj.remove_style_all panel;
  Lvgl.Obj.set_pos panel ~x ~y;
  Lvgl.Obj.set_size panel ~width ~height;
  Lvgl.Obj.set_style_bg_color panel color;
  Lvgl.Obj.set_style_bg_opa panel opa;
  Lvgl.Obj.remove_flag panel Lvgl.Flag.(clickable lor scrollable);
  panel

(* Makes LVGL's default theme (dark, Montserrat 14) the app's theme, with
   [primary] as its accent color. Widgets created afterwards take their look
   from it; calling it again restyles the existing ones (the Widgets demo's
   Color row). main.ml calls it before the first screen exists. *)
let set_theme primary =
  let display = Lvgl.Display.get_default () in
  let secondary = Lvgl.Palette.(main blue) in
  Lvgl.Display.set_theme display (Lvgl.Theme.default_init display ~primary ~secondary ~dark:true Lvgl.Font.montserrat_14)

(* One line of key help, centered at the bottom of a screen. *)
let make_hint parent text =
  let hint = make_label parent text Lvgl.Font.montserrat_14 muted_color in
  Lvgl.Obj.align hint Lvgl.Align.top_mid ~x:0 ~y:hint_top;
  hint

(* "TAB next  ESC home", top right: how to leave a demo. *)
let make_demo_keys parent =
  let keys = make_label parent "TAB next  ESC home" Lvgl.Font.montserrat_12 muted_color in
  Lvgl.Obj.align keys Lvgl.Align.top_right ~x:(-6) ~y:2;
  keys

(* One screen of the app: a full-size container inside the content area that
   is shown while the screen is active. Each screen module's [create] fills in
   the functions. A screen with [frame] gets a timer that calls it every
   frame_ms while the screen shows. *)
type screen = {
  root : Lvgl.obj;
  title : unit -> string;  (* shown in the top bar while the screen is active *)
  handle_key : Lvgl.App.key -> action;  (* key presses and auto-repeats, not releases *)
  on_show : unit -> unit;
  on_hide : unit -> unit;
  timer : Lvgl.timer option;
}

(* The container a screen builds its widgets in; hidden until shown. *)
let screen_root parent =
  let root =
    make_panel parent ~x:0 ~y:0 ~width:content_width ~height:content_height background_color Lvgl.Opa.cover
  in
  Lvgl.Obj.add_flag root Lvgl.Flag.hidden;
  root

(* Whether the screen with this [root] is the one showing. *)
let shown root = not (Lvgl.Obj.has_flag root Lvgl.Flag.hidden)

let make_screen ~root ~title ~handle_key ?(on_show = ignore) ?(on_hide = ignore) ?frame () =
  let timer =
    Option.map
      (fun frame ->
        let timer = Lvgl.Timer.create ~period:frame_ms (fun _ -> frame ()) in
        Lvgl.Timer.pause timer;
        timer)
      frame
  in
  { root; title; handle_key; on_show; on_hide; timer }

let show screen =
  Lvgl.Obj.remove_flag screen.root Lvgl.Flag.hidden;
  Option.iter Lvgl.Timer.resume screen.timer;
  screen.on_show ()

let hide screen =
  Option.iter Lvgl.Timer.pause screen.timer;
  Lvgl.Obj.add_flag screen.root Lvgl.Flag.hidden;
  screen.on_hide ()
