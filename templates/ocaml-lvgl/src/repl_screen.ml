(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Demo 3, a terminal-style tool: a read-eval-print loop for the calc language
   (calc.ml). Type a line, ENTER runs it; the screen scrolls like a terminal. *)

let font = Lvgl.Font.montserrat_14
let left = 4
let top = 2
let line_height = 16 (* montserrat_14's line height *)
let text_width_max = App_ui.content_width - (2 * left)
let cursor_width = 7
let rows = 8 (* text rows above the hint line; the last one is the input line *)
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
  mutable scrollback : (string * int) list;  (* line and color, newest first *)
  mutable input : string;
  mutable history : string array;
  mutable history_index : int;  (* = Array.length history while editing a new line *)
  line_labels : Lvgl.obj array;  (* rows - 1 output lines *)
  prompt_label : Lvgl.obj;
  input_label : Lvgl.obj;
  cursor : Lvgl.obj;
}

let rec take count list = match list with item :: rest when count > 0 -> item :: take (count - 1) rest | _ -> []

(* Width of [text] in pixels as a label draws it (the text is ASCII). *)
let text_width text =
  let length = String.length text in
  let width = ref 0 in
  for index = 0 to length - 1 do
    let next = if index + 1 < length then Char.code text.[index + 1] else 0 in
    width := !width + Lvgl.Font.glyph_width font (Char.code text.[index]) ~next
  done;
  !width

(* The longest end of [text] that fits in [room] pixels. *)
let tail_that_fits text room =
  let length = String.length text in
  let rec grow start = if start > 0 && text_width (String.sub text (start - 1) (length - start + 1)) <= room then grow (start - 1) else start in
  let start = grow length in
  String.sub text start (length - start)

(* Add output, wrapped to the screen width. *)
let print repl text color =
  let line = Buffer.create 64 in
  String.iter
    (fun character ->
      if Buffer.length line > 0 && text_width (Buffer.contents line ^ String.make 1 character) > text_width_max then begin
        repl.scrollback <- (Buffer.contents line, color) :: repl.scrollback;
        Buffer.clear line
      end;
      Buffer.add_char line character)
    text;
  repl.scrollback <- take max_scrollback ((Buffer.contents line, color) :: repl.scrollback)

let submit repl =
  let line = repl.input in
  repl.input <- "";
  print repl (prompt ^ line) App_ui.text_color;
  let command = String.trim line in
  if command <> "" then begin
    let count = Array.length repl.history in
    if count = 0 || repl.history.(count - 1) <> command then repl.history <- Array.append repl.history [| command |];
    repl.history_index <- Array.length repl.history;
    match command with
    | "help" -> List.iter (fun line -> print repl line App_ui.muted_color) help
    | "clear" -> repl.scrollback <- []
    | "vars" -> (
        match Calc.variables repl.calculator with
        | [] -> print repl "no variables yet" App_ui.muted_color
        | variables ->
            List.iter
              (fun (name, value) -> print repl (Printf.sprintf "%s = %Ld" name value) App_ui.language_color)
              variables)
    | _ -> (
        match Calc.run repl.calculator command with
        | Ok result -> print repl result App_ui.language_color
        | Error message -> print repl ("error: " ^ message) App_ui.error_color)
  end

(* Step through earlier lines: -1 = older, +1 = newer. *)
let recall repl step =
  let index = repl.history_index + step in
  let count = Array.length repl.history in
  if index >= 0 && index <= count then begin
    repl.history_index <- index;
    repl.input <- (if index < count then repl.history.(index) else "")
  end

let refresh repl =
  let visible = List.rev (take (Array.length repl.line_labels) repl.scrollback) in
  Array.iteri
    (fun row label ->
      match List.nth_opt visible row with
      | Some (text, color) ->
          Lvgl.Label.set_text label text;
          Lvgl.Obj.set_style_text_color label color;
          Lvgl.Obj.remove_flag label Lvgl.Flag.hidden
      | None -> Lvgl.Obj.add_flag label Lvgl.Flag.hidden)
    repl.line_labels;

  (* The input line sits under the output; long input scrolls to keep the end visible. *)
  let y = top + (List.length visible * line_height) in
  let prompt_width = text_width prompt in
  let shown = tail_that_fits repl.input (text_width_max - prompt_width - cursor_width - 1) in
  Lvgl.Label.set_text repl.input_label shown;
  Lvgl.Obj.set_pos repl.prompt_label ~x:left ~y;
  Lvgl.Obj.set_pos repl.input_label ~x:(left + prompt_width) ~y;
  Lvgl.Obj.set_pos repl.cursor ~x:(left + prompt_width + text_width shown + 1) ~y:(y + 2)

let handle_key repl (key : Lvgl.App.key) : App_ui.action =
  let open Lvgl.Keys in
  if key.code = esc then Home
  else if key.code = tab then Next
  else begin
    if key.code = enter then submit repl
    else if key.code = backspace then begin
      let length = String.length repl.input in
      if length > 0 then repl.input <- String.sub repl.input 0 (length - 1)
    end
      (* Only the real arrow keys: F/X/Z/C are letters here. *)
    else if key.code = up then recall repl (-1)
    else if key.code = down then recall repl 1
    else begin
      match App_ui.typed_text key with
      | Some text when String.length repl.input < max_input -> repl.input <- repl.input ^ text
      | _ -> ()
    end;
    refresh repl;
    Stay
  end

let create parent =
  let root = App_ui.screen_root parent in
  let line_labels =
    Array.init (rows - 1) (fun row ->
        let label = App_ui.make_label root "" font App_ui.text_color in
        Lvgl.Obj.set_pos label ~x:left ~y:(top + (row * line_height));
        label)
  in
  let prompt_label = App_ui.make_label root prompt font App_ui.language_color in
  let input_label = App_ui.make_label root "" font App_ui.text_color in
  let cursor =
    App_ui.make_panel root ~x:0 ~y:0 ~width:cursor_width ~height:(line_height - 4) App_ui.language_color Lvgl.Opa.cover
  in
  ignore (App_ui.make_hint root "UP/DOWN history  TAB next  ESC home");
  let repl =
    {
      calculator = Calc.create ();
      scrollback = [];
      input = "";
      history = [||];
      history_index = 0;
      line_labels;
      prompt_label;
      input_label;
      cursor;
    }
  in
  print repl "calc: whole-number calculator" App_ui.muted_color;
  print repl "type help and press ENTER" App_ui.muted_color;
  refresh repl;
  App_ui.make_screen ~root
    ~title:(fun () -> "REPL")
    ~handle_key:(handle_key repl)
      (* F/X/Z/C type letters here instead of acting as arrows. *)
    ~on_show:(fun () -> Lvgl.App.set_text_input true)
    ~on_hide:(fun () -> Lvgl.App.set_text_input false)
    ()
