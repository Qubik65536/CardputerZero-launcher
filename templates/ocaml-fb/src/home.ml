(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   The home screen: wallpaper, greeting and a menu of the demos.

   The wallpaper is src/wallpaper.rgb565 (320x170 RGB565, made with
   scripts/png_to_rgb565.py): src/dune turns it into the module [Wallpaper] at
   build time, so it is compiled into the binary. Replace it with your own. *)

(* The demos, in menu order: name and a short description. *)
let demos =
  [|
    ("Colors", "color triangle and wheel");
    ("Motion", "steer a glowing ball");
    ("REPL", "a tiny calculator language");
    ("Widgets", "text field, slider, more");
  |]

let menu_top = 68
let row_height = 20

type t = { mutable selected : int }

let create () = { selected = 0 }

let handle_key home (event : Input.event) : Ui.action =
  if not (Input.is_down event) then Stay
  else
    let count = Array.length demos in
    match Input.direction event.code with
    | Some (Up | Left) ->
        home.selected <- (home.selected + count - 1) mod count;
        Stay
    | Some (Down | Right) ->
        home.selected <- (home.selected + 1) mod count;
        Stay
    | None ->
        let code = event.code in
        if code = Input.Keys.enter || code = Input.Keys.space then Open home.selected
        else if code = Input.Keys.digit_1 then Open 0
        else if code = Input.Keys.digit_2 then Open 1
        else if code = Input.Keys.digit_3 then Open 2
        else if code = Input.Keys.digit_4 then Open 3
          (* Quit on a short ESC press. (Holding ESC for 3 s makes the launcher kill the app.) *)
        else if code = Input.Keys.esc then Quit
        else Stay

let draw home display =
  let width = Display.width display in
  Display.draw_image display 0 0 Wallpaper.data;
  Ui.draw_shadowed_text display 16 8 (Printf.sprintf "Hello, %s!" Ui.language) Ui.language_color 2;
  Ui.draw_shadowed_text display 18 44 "Your CardputerZero app" Ui.muted 1;

  Display.shade_rect display 8 (menu_top - 4) (width - 16) ((row_height * Array.length demos) + 6) 150;
  Array.iteri
    (fun index (name, description) ->
      let y = menu_top + (index * row_height) in
      let selected = index = home.selected in
      if selected then Display.fill_rect display 8 (y - 2) 3 (row_height - 2) Ui.language_color;
      let color = if selected then Ui.text else Ui.muted in
      Display.draw_text display 18 y (Printf.sprintf "%d %-7s" (index + 1) name) color 1;
      Display.draw_text display (18 + (10 * 8)) y description (if selected then Ui.language_color else Ui.muted) 1)
    demos;

  Display.shade_rect display 0 (Ui.hint_top - 1) width (Display.height display - Ui.hint_top + 1) 170;
  Ui.draw_hint display "F/X choose  ENTER open  ESC quit"
