(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Demo 3, a terminal-style tool: a read-eval-print loop for the calc language.
   Type a line, ENTER runs it; the screen scrolls like a terminal. *)

let columns = 40 (* 320 px / 8 px per character *)
let rows = 9 (* text rows below the header; the last one is the input line *)
let top = Ui.header_height + 2
let max_input = 120
let max_scrollback = 200
let prompt = "> "

let help =
  [
    "numbers, + - * / % ^ ( )";
    "x = 6 * 7   ans   abs(x) min(a,b) max";
    "commands: help  vars  clear";
    "UP/DOWN history  TAB next  ESC home";
  ]

type t = {
  calculator : Calc.t;
  mutable scrollback : (string * int) list; (* line and color, newest first *)
  mutable input : string;
  mutable history : string array;
  mutable history_index : int; (* = Array.length history while editing a new line *)
}

let rec take count list = match list with item :: rest when count > 0 -> item :: take (count - 1) rest | _ -> []

(* Add output, wrapped to the screen width. *)
let print repl text color =
  let length = String.length text in
  let rec chunks start =
    if start < length then begin
      repl.scrollback <- (String.sub text start (min columns (length - start)), color) :: repl.scrollback;
      chunks (start + columns)
    end
  in
  if length = 0 then repl.scrollback <- ("", color) :: repl.scrollback else chunks 0;
  repl.scrollback <- take max_scrollback repl.scrollback

let create () =
  let repl = { calculator = Calc.create (); scrollback = []; input = ""; history = [||]; history_index = 0 } in
  print repl "calc: whole-number calculator" Ui.muted;
  print repl "type help and press ENTER" Ui.muted;
  repl

let submit repl =
  let line = repl.input in
  repl.input <- "";
  print repl (prompt ^ line) Ui.text;
  let command = String.trim line in
  if command <> "" then begin
    let count = Array.length repl.history in
    if count = 0 || repl.history.(count - 1) <> command then repl.history <- Array.append repl.history [| command |];
    repl.history_index <- Array.length repl.history;
    match command with
    | "help" -> List.iter (fun line -> print repl line Ui.muted) help
    | "clear" -> repl.scrollback <- []
    | "vars" -> (
        match Calc.variables repl.calculator with
        | [] -> print repl "no variables yet" Ui.muted
        | variables ->
            List.iter (fun (name, value) -> print repl (Printf.sprintf "%s = %Ld" name value) Ui.language_color) variables)
    | _ -> (
        match Calc.run repl.calculator command with
        | Ok result -> print repl result Ui.language_color
        | Error message -> print repl ("error: " ^ message) Ui.error)
  end

(* Step through earlier lines: -1 = older, +1 = newer. *)
let recall repl step =
  let index = repl.history_index + step in
  let count = Array.length repl.history in
  if index >= 0 && index <= count then begin
    repl.history_index <- index;
    repl.input <- (if index < count then repl.history.(index) else "")
  end

(* [typed] is the character the key produces, if any (see Input.char_for). *)
let handle_key repl (event : Input.event) typed : Ui.action =
  if not (Input.is_down event) then Stay
  else
    let code = event.code in
    if code = Input.Keys.esc then Home
    else if code = Input.Keys.tab then Next
    else begin
      if code = Input.Keys.enter then submit repl
      else if code = Input.Keys.backspace then begin
        let length = String.length repl.input in
        if length > 0 then repl.input <- String.sub repl.input 0 (length - 1)
      end
        (* Only the real arrow keys: F/X/Z/C are letters here. *)
      else if code = Input.Keys.up then recall repl (-1)
      else if code = Input.Keys.down then recall repl 1
      else (
        match typed with
        | Some character when String.length repl.input < max_input ->
            repl.input <- repl.input ^ String.make 1 character
        | _ -> ());
      Stay
    end

let draw repl display =
  Display.clear display Ui.background;
  Ui.draw_header display "REPL";
  let visible = List.rev (take (rows - 1) repl.scrollback) in
  List.iteri (fun row (line, color) -> Display.draw_text display 0 (top + (row * Display.char_height)) line color 1) visible;
  (* The input line sits under the output; long input scrolls to keep the end visible. *)
  let y = top + (List.length visible * Display.char_height) in
  let room = columns - String.length prompt - 1 in
  let length = String.length repl.input in
  let shown = if length > room then String.sub repl.input (length - room) room else repl.input in
  Display.draw_text display 0 y prompt Ui.language_color 1;
  let x = Display.text_width prompt 1 in
  Display.draw_text display x y shown Ui.text 1;
  let x = x + Display.text_width shown 1 in
  Display.fill_rect display x (y + 2) Display.char_width (Display.char_height - 4) Ui.language_color (* cursor *)
