(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Hello Cardputer: a minimal CardputerZero app in OCaml.

   Move the square with F/X/Z/C (or the arrow keys), press ENTER to change its
   color, ESC to quit. Start editing in [handle_key] and [draw]. *)

let frame_time = 0.016 (* ~60 frames per second *)
let background = Display.rgb 16 20 24
let title_bar = Display.rgb 30 36 44
let muted = Display.rgb 150 160 170
let colors = [| Display.rgb 79 195 247; Display.rgb 129 199 132; Display.rgb 255 183 77; Display.rgb 240 98 146 |]
let square = 24

type app = { mutable x : int; mutable y : int; mutable color : int; mutable running : bool }

let create display =
  { x = (Display.width display - square) / 2; y = (Display.height display - square) / 2; color = 0; running = true }

let handle_key app display (event : Input.event) =
  if Input.is_down event then begin
    let step = 6 in
    (match Input.direction event.code with
    | Some Left -> app.x <- app.x - step
    | Some Right -> app.x <- app.x + step
    | Some Up -> app.y <- app.y - step
    | Some Down -> app.y <- app.y + step
    | None ->
        if event.code = Input.Keys.enter || event.code = Input.Keys.space then
          app.color <- (app.color + 1) mod Array.length colors
        (* Quit on a short ESC press. (Holding ESC for 3 s makes the launcher kill the app.) *)
        else if event.code = Input.Keys.esc then app.running <- false);
    app.x <- max 0 (min app.x (Display.width display - square));
    app.y <- max 20 (min app.y (Display.height display - square - 14))
  end

let draw app display =
  let width = Display.width display and height = Display.height display in
  Display.clear display background;
  Display.fill_rect display 0 0 width 18 title_bar;
  Display.draw_text display 6 5 "Hello Cardputer" Display.white 1;
  Display.fill_rect display app.x app.y square square colors.(app.color);
  let hint = "F/X/Z/C move  ENTER color  ESC quit" in
  Display.draw_text display ((width - Display.text_width hint 1) / 2) (height - 11) hint muted 1

let rec drain_keys app display keyboard dirty =
  match Input.poll keyboard with
  | Some event ->
      handle_key app display event;
      drain_keys app display keyboard true
  | None -> dirty

let () =
  let display = Display.open_display () in
  let keyboard = Input.open_keyboard () in
  let app = create display in
  let dirty = ref true in
  while app.running do
    dirty := drain_keys app display keyboard !dirty;
    if !dirty then begin
      draw app display;
      Display.present display;
      dirty := false
    end;
    Unix.sleepf frame_time
  done;
  Input.close keyboard;
  Display.close display
