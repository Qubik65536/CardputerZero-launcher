(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Hello Cardputer: a CardputerZero app in OCaml.

   The home screen greets you and opens three demos: color rendering
   (colors.ml), an interactive animation (motion.ml) and a terminal-style REPL
   (repl.ml, running the little language in calc.ml). TAB moves to the next
   demo, ESC goes back home, ESC at home quits. Keep what you need and delete
   the rest. *)

let frame_time = 0.016 (* ~60 frames per second *)

(* Which screen is showing. The demos are in Home.demos order. *)
type screen = Home_screen | Colors_screen | Motion_screen | Repl_screen

let demo_screens = [| Colors_screen; Motion_screen; Repl_screen |]

type app = {
  mutable screen : screen;
  home : Home.t;
  colors : Colors.t;
  motion : Motion.t;
  repl : Repl.t;
  mutable running : bool;
}

let create () =
  {
    screen = Home_screen;
    home = Home.create ();
    colors = Colors.create ();
    motion = Motion.create ();
    repl = Repl.create ();
    running = true;
  }

let apply app (action : Ui.action) =
  match action with
  | Stay -> ()
  | Home -> app.screen <- Home_screen
  | Open index -> app.screen <- demo_screens.(index)
  | Next ->
      let rec position index =
        if index >= Array.length demo_screens then 0 else if demo_screens.(index) = app.screen then index else position (index + 1)
      in
      app.screen <- demo_screens.((position 0 + 1) mod Array.length demo_screens)
  | Quit -> app.running <- false

let handle_key app event typed =
  let action =
    match app.screen with
    | Home_screen -> Home.handle_key app.home event
    | Colors_screen -> Colors.handle_key app.colors event
    | Motion_screen -> Motion.handle_key app.motion event
    | Repl_screen -> Repl.handle_key app.repl event typed
  in
  apply app action

(* Advance animations by one frame. Returns true if the screen needs redrawing. *)
let tick app =
  match app.screen with
  | Colors_screen ->
      Colors.tick app.colors;
      Colors.animated app.colors
  | Motion_screen ->
      Motion.tick app.motion;
      true
  | Home_screen | Repl_screen -> false

let draw app display =
  match app.screen with
  | Home_screen -> Home.draw app.home display
  | Colors_screen -> Colors.draw app.colors display
  | Motion_screen -> Motion.draw app.motion display
  | Repl_screen -> Repl.draw app.repl display

(* Handle every pending key event. Returns true if there were any. *)
let rec drain_keys app keyboard typist dirty =
  match Input.poll keyboard with
  | Some event ->
      let typed = Input.char_for typist event in
      (* every event, so Shift is tracked *)
      handle_key app event typed;
      drain_keys app keyboard typist true
  | None -> dirty

let run () =
  let display = Display.open_display () in
  let keyboard = Input.open_keyboard () in
  let typist = Input.create_typist () in
  let app = create () in
  let dirty = ref true in
  while app.running do
    dirty := drain_keys app keyboard typist !dirty;
    if tick app || !dirty then begin
      draw app display;
      Display.present display;
      dirty := false
    end;
    Unix.sleepf frame_time
  done;
  Input.close keyboard;
  Display.close display

let () =
  try run () with
  | Unix.Unix_error (error, _, "") ->
      prerr_endline ("hello-cardputer: " ^ Unix.error_message error);
      exit 1
  | Unix.Unix_error (error, _, path) ->
      Printf.eprintf "hello-cardputer: %s: %s\n" path (Unix.error_message error);
      exit 1
  | Failure message ->
      prerr_endline ("hello-cardputer: " ^ message);
      exit 1
