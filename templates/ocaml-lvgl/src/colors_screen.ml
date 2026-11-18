(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Demo 1, color rendering: a spinning RGB triangle and an HSV color wheel,
   computed pixel by pixel every frame into an LVGL canvas. *)

let tau = 6.28318530718
let center_x = 160.0

(* Content coordinates, between the "TAB next  ESC home" line (top 18 px) and
   the hint line, so neither covers the picture. *)
let center_y = 72.0
let radius = 54.0
let spin_per_frame = 0.02 (* radians *)
let turn_step = 0.15 (* radians per Z/C press *)

type scene = Triangle | Wheel

type t = {
  canvas : Pixel_canvas.t;
  backdrop : int array;  (* one color per row *)
  mutable scene : scene;
  mutable angle : float;
  mutable spinning : bool;
}

let rgb red green blue =
  let channel value = int_of_float value land 0xFF in
  Pixel_canvas.rgb565 ((channel red lsl 16) lor (channel green lsl 8) lor channel blue)

(* Hue (0..1, wrapping), saturation and value (0..1) to RGB565. *)
let hsv hue saturation value =
  let sector = (hue -. floor hue) *. 6.0 in
  let fraction = sector -. floor sector in
  let p = value *. (1.0 -. saturation) in
  let q = value *. (1.0 -. (saturation *. fraction)) in
  let t = value *. (1.0 -. (saturation *. (1.0 -. fraction))) in
  let v = value *. 255.0 and p = p *. 255.0 and q = q *. 255.0 and t = t *. 255.0 in
  match int_of_float sector with
  | 0 -> rgb v t p
  | 1 -> rgb q v p
  | 2 -> rgb p v t
  | 3 -> rgb p q v
  | 4 -> rgb t p v
  | _ -> rgb v p q

(* Gouraud shading: each pixel mixes the corner colors red, green and blue by how
   close it is to each corner (its barycentric weights), scaled so the brightest
   channel is full. *)
let draw_triangle canvas angle =
  let corner index =
    let theta = angle +. (Float.of_int index *. tau /. 3.0) in
    (center_x +. (radius *. cos theta), center_y +. (radius *. sin theta))
  in
  let ax, ay = corner 0 and bx, by = corner 1 and cx, cy = corner 2 in
  let area = ((bx -. ax) *. (cy -. ay)) -. ((by -. ay) *. (cx -. ax)) in
  let left = int_of_float (floor (Float.min ax (Float.min bx cx))) in
  let right = int_of_float (ceil (Float.max ax (Float.max bx cx))) in
  let top = int_of_float (floor (Float.min ay (Float.min by cy))) in
  let bottom = int_of_float (ceil (Float.max ay (Float.max by cy))) in
  for y = top to bottom do
    for x = left to right do
      let px = Float.of_int x +. 0.5 and py = Float.of_int y +. 0.5 in
      let red = (((cx -. bx) *. (py -. by)) -. ((cy -. by) *. (px -. bx))) /. area in
      let green = (((ax -. cx) *. (py -. cy)) -. ((ay -. cy) *. (px -. cx))) /. area in
      let blue = 1.0 -. red -. green in
      if red >= 0.0 && green >= 0.0 && blue >= 0.0 then begin
        let brightest = Float.max red (Float.max green blue) in
        Pixel_canvas.set_pixel canvas x y
          (rgb (red /. brightest *. 255.0) (green /. brightest *. 255.0) (blue /. brightest *. 255.0))
      end
    done
  done

(* Hue around the circle, saturation from the center out. *)
let draw_wheel canvas angle =
  let r = int_of_float radius in
  for dy = -r to r do
    for dx = -r to r do
      let distance = sqrt (Float.of_int ((dx * dx) + (dy * dy))) in
      if distance <= radius then begin
        let hue = (atan2 (Float.of_int dy) (Float.of_int dx) +. angle) /. tau in
        Pixel_canvas.set_pixel canvas
          (int_of_float center_x + dx)
          (int_of_float center_y + dy)
          (hsv hue (distance /. radius) 1.0)
      end
    done
  done

let draw colors =
  Array.iteri
    (fun y color -> Pixel_canvas.fill_rect colors.canvas ~x:0 ~y ~width:App_ui.content_width ~height:1 color)
    colors.backdrop;
  (match colors.scene with
  | Triangle -> draw_triangle colors.canvas colors.angle
  | Wheel -> draw_wheel colors.canvas colors.angle);
  Pixel_canvas.present colors.canvas

let title colors = match colors.scene with Triangle -> "Colors: triangle" | Wheel -> "Colors: wheel"

let on_frame colors =
  if colors.spinning then begin
    colors.angle <- Float.rem (colors.angle +. spin_per_frame) tau;
    draw colors
  end

let handle_key colors (key : Lvgl.App.key) : App_ui.action =
  let open Lvgl.Keys in
  let action : App_ui.action =
    match App_ui.direction key.code with
    | Some Left ->
        colors.angle <- colors.angle -. turn_step;
        Stay
    | Some Right ->
        colors.angle <- colors.angle +. turn_step;
        Stay
    | Some (Up | Down) -> Stay
    | None ->
        if key.code = enter then begin
          colors.scene <- (match colors.scene with Triangle -> Wheel | Wheel -> Triangle);
          Stay
        end
        else if key.code = space then begin
          colors.spinning <- not colors.spinning;
          Stay
        end
        else if key.code = tab then Next
        else if key.code = esc then Home
        else Stay
  in
  if action = Stay then draw colors;
  action

let create parent =
  let root = App_ui.screen_root parent in
  let canvas = Pixel_canvas.create root ~width:App_ui.content_width ~height:App_ui.content_height in
  (* Dark vertical gradient behind the picture, worked out once. *)
  let backdrop =
    Array.init App_ui.content_height (fun y ->
        Pixel_canvas.blend565 (Pixel_canvas.rgb565 0x161C24) (Pixel_canvas.rgb565 0x06080B)
          (y * 255 / App_ui.content_height))
  in
  let colors = { canvas; backdrop; scene = Triangle; angle = 0.0; spinning = true } in
  (* Widgets created after the canvas are drawn on top of it. *)
  ignore (App_ui.make_demo_keys root);
  ignore (App_ui.make_hint root "Z/C turn  SPACE pause  ENTER switch");
  let screen =
    App_ui.make_screen ~root
      ~title:(fun () -> title colors)
      ~handle_key:(handle_key colors)
      ~on_show:(fun () -> draw colors)
      ~frame:(fun () -> on_frame colors)
      ()
  in
  draw colors;
  screen
