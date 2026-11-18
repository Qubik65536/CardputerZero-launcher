(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   The app's one page: it owns the screens, shows one at a time and routes keys.

   The home screen greets you and opens four demos: color rendering
   (colors_screen.ml), an interactive animation with live physics numbers
   (motion_screen.ml), a terminal-style REPL (repl_screen.ml, running the
   little language in calc.ml) and a form of real LVGL widgets
   (widgets_screen.ml). Each is an App_ui.screen inside the content area; one
   shows at a time. TAB moves to the next demo, ESC goes back home, ESC at home
   quits. Keep what you need and delete the rest. *)

type t = {
  home : App_ui.screen;
  demos : App_ui.screen array;  (* in menu and TAB order (Home_screen.demos) *)
  mutable current : App_ui.screen option;
}

let show page screen =
  match page.current with
  | Some current when current == screen -> ()
  | current ->
      Option.iter App_ui.hide current;
      page.current <- Some screen;
      App_ui.show screen

let apply page (action : App_ui.action) =
  (match action with
  | Stay -> ()
  | Home -> show page page.home
  | Open demo -> show page page.demos.(demo)
  | Next ->
      let count = Array.length page.demos in
      let is_current index = match page.current with Some screen -> screen == page.demos.(index) | None -> false in
      let rec position index = if index >= count then 0 else if is_current index then index else position (index + 1) in
      show page page.demos.((position 0 + 1) mod count)
  | Quit -> Lvgl.App.quit ());
  (* The title follows the screen (and the Colors scene). *)
  Option.iter (fun (screen : App_ui.screen) -> Lvgl.App.set_title (screen.title ())) page.current

let handle_key page (key : Lvgl.App.key) =
  (* Key presses and auto-repeats; releases carry no new input. (Text sent by
     the automation RPC arrives as released keys without a key code.) *)
  let injected_text = key.code = 0 && key.text <> "" in
  match (key.state, page.current) with
  | Released, _ when not injected_text -> ()
  | _, Some screen -> apply page (screen.handle_key key)
  | _, None -> ()

let create content =
  Lvgl.Obj.set_style_bg_color content App_ui.background_color;
  Lvgl.Obj.set_style_bg_opa content Lvgl.Opa.cover;
  (* One at a time, in this order: OCaml does not fix the order in which a
     record's or an array's elements are evaluated. *)
  let home = Home_screen.create content in
  let colors = Colors_screen.create content in
  let motion = Motion_screen.create content in
  let repl = Repl_screen.create content in
  let widgets = Widgets_screen.create content in
  let page = { home; demos = [| colors; motion; repl; widgets |]; current = None } in
  apply page Home;
  page
