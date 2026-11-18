(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   The home screen: wallpaper, greeting and a menu of the demos. *)

(* The demos, in menu order (and TAB order): name and description. *)
let demos =
  [|
    ("Colors", "color triangle and wheel");
    ("Motion", "steer a glowing ball");
    ("REPL", "a tiny calculator language");
    ("Widgets", "text field, slider, more");
  |]

let menu_top = 50
let row_height = 20
let description_x = 98

type menu_row = { accent : Lvgl.obj; name : Lvgl.obj; description : Lvgl.obj }

type t = { rows : menu_row array; mutable selected : int }

(* Text with a dark shadow, readable on top of a picture. *)
let make_shadowed_label parent text font color ~x ~y ~offset =
  let shadow = App_ui.make_label parent text font 0x000000 in
  Lvgl.Obj.set_pos shadow ~x:(x + offset) ~y:(y + offset);
  let label = App_ui.make_label parent text font color in
  Lvgl.Obj.set_pos label ~x ~y;
  label

let update_selection home =
  Array.iteri
    (fun index row ->
      let selected = index = home.selected in
      if selected then Lvgl.Obj.remove_flag row.accent Lvgl.Flag.hidden else Lvgl.Obj.add_flag row.accent Lvgl.Flag.hidden;
      Lvgl.Obj.set_style_text_color row.name (if selected then App_ui.text_color else App_ui.muted_color);
      Lvgl.Obj.set_style_text_color row.description (if selected then App_ui.language_color else App_ui.muted_color))
    home.rows

let make_row root index (name, description) =
  let y = menu_top + (index * row_height) in
  let accent =
    App_ui.make_panel root ~x:8 ~y:(y - 2) ~width:3 ~height:(row_height - 2) App_ui.language_color Lvgl.Opa.cover
  in
  let name = App_ui.make_label root (Printf.sprintf "%d %s" (index + 1) name) Lvgl.Font.montserrat_14 App_ui.muted_color in
  Lvgl.Obj.set_pos name ~x:18 ~y;
  let description = App_ui.make_label root description Lvgl.Font.montserrat_14 App_ui.muted_color in
  Lvgl.Obj.set_pos description ~x:description_x ~y;
  { accent; name; description }

let handle_key home (key : Lvgl.App.key) : App_ui.action =
  let count = Array.length demos in
  let open Lvgl.Keys in
  let action : App_ui.action =
    match App_ui.direction key.code with
    | Some (Up | Left) ->
        home.selected <- (home.selected + count - 1) mod count;
        Stay
    | Some (Down | Right) ->
        home.selected <- (home.selected + 1) mod count;
        Stay
    | None ->
        if key.code = enter || key.code = space then Open home.selected
        else if key.code = digit_1 then Open 0
        else if key.code = digit_2 then Open 1
        else if key.code = digit_3 then Open 2
        else if key.code = digit_4 then Open 3
          (* Quit on a short ESC press. (Holding ESC for 3 s makes the launcher kill the app.) *)
        else if key.code = esc then Quit
        else Stay
  in
  if action = Stay then update_selection home;
  action

let create parent =
  let root = App_ui.screen_root parent in
  (* Images from APPLaunch/share/images/: App.file_path resolves the name for
     both the device (/usr/share/APPLaunch) and the desktop (./APPLaunch). *)
  let wallpaper = Lvgl.Image.create root in
  Lvgl.Image.set_src_file wallpaper (Lvgl.App.file_path "wallpaper.png");
  Lvgl.Obj.set_pos wallpaper ~x:0 ~y:0;

  let greeting = "Hello, " ^ App_ui.language ^ "!" in
  ignore (make_shadowed_label root greeting Lvgl.Font.montserrat_28 App_ui.language_color ~x:14 ~y:(-2) ~offset:2);
  ignore (make_shadowed_label root "Your CardputerZero app" Lvgl.Font.montserrat_14 App_ui.muted_color ~x:16 ~y:29 ~offset:1);

  ignore
    (App_ui.make_panel root ~x:8 ~y:(menu_top - 4) ~width:(App_ui.content_width - 16)
       ~height:((row_height * Array.length demos) + 6)
       0x000000 150);
  let home = { rows = Array.mapi (make_row root) demos; selected = 0 } in

  ignore
    (App_ui.make_panel root ~x:0 ~y:(App_ui.hint_top - 1) ~width:App_ui.content_width
       ~height:(App_ui.content_height - App_ui.hint_top + 1)
       0x000000 170);
  ignore (App_ui.make_hint root "F/X choose  ENTER open  ESC quit");
  update_selection home;
  App_ui.make_screen ~root ~title:(fun () -> "Hello Cardputer") ~handle_key:(handle_key home) ()
