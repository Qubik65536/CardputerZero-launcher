(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   The app's look, shared by every screen: colors, the header bar and the hint line. *)

(* The language this template is written in, and GitHub's color for it. *)
let language = "OCaml"
let language_color = Display.rgb 0xEF 0x7A 0x08
let background = Display.rgb 14 18 23
let header = Display.rgb 28 34 42
let text = Display.white
let muted = Display.rgb 150 160 170
let error = Display.rgb 255 110 110

(* Height of the header bar; demo content starts below it. *)
let header_height = 20

(* Top of the hint line at the bottom of the screen. *)
let hint_top = 170 - Display.char_height - 1

(* What a screen asks the app to do after a key press. *)
type action =
  | Stay
  | Home  (* Back to the home screen. *)
  | Next  (* On to the next demo (TAB). *)
  | Open of int  (* Open demo number N (0-based) from the home screen. *)
  | Quit

(* The bar at the top of a demo: its title, and how to leave. *)
let draw_header display title =
  let width = Display.width display in
  Display.fill_rect display 0 0 width header_height header;
  Display.draw_text display 6 2 title language_color 1;
  let keys = "TAB next  ESC home" in
  Display.draw_text display (width - Display.text_width keys 1 - 6) 2 keys muted 1

(* One line of key help, centered at the bottom of the screen. *)
let draw_hint display hint =
  let x = (Display.width display - Display.text_width hint 1) / 2 in
  Display.draw_text display x hint_top hint muted 1

(* Text with a dark shadow, readable on top of a picture. *)
let draw_shadowed_text display x y text color scale =
  Display.draw_text display (x + scale) (y + scale) text (Display.rgb 0 0 0) scale;
  Display.draw_text display x y text color scale
