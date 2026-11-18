(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Hello Cardputer: a CardputerZero app in OCaml with LVGL.

   Lvgl.App.run sets up LVGL, the display (SDL window, the simulator's
   framebuffer or the device panel), the keyboard and the platform services,
   shows a page with the standard top bar, calls [setup] to build the UI in
   its content area, then runs the event loop until Lvgl.App.quit (ESC on the
   home screen). See app_page.ml. *)

let () =
  let page = ref None in
  let status =
    Lvgl.App.run ~title:"Hello Cardputer"
      ~setup:(fun content -> page := Some (App_page.create content))
      ~on_key:(fun key -> Option.iter (fun page -> App_page.handle_key page key) !page)
  in
  exit status
