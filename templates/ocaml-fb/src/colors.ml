(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Demo 1, color rendering: a spinning RGB triangle and an HSV color wheel,
   computed pixel by pixel every frame. *)

let tau = 2.0 *. Float.pi
let center_x = 160.0
let center_y = 86.0
let radius = 60.0
let spin_per_frame = 0.02 (* radians *)
let turn_step = 0.15 (* radians per Z/C press *)

type scene = Triangle | Wheel

(* Hue (0..1, wrapping), saturation and value (0..1) to RGB565. *)
let hsv hue saturation value =
  let hue = Float.rem hue 1.0 in
  let sector = (if hue < 0.0 then hue +. 1.0 else hue) *. 6.0 in
  let fraction = sector -. Float.of_int (int_of_float sector) in
  let p = value *. (1.0 -. saturation)
  and q = value *. (1.0 -. (saturation *. fraction))
  and t = value *. (1.0 -. (saturation *. (1.0 -. fraction))) in
  let red, green, blue =
    match int_of_float sector with
    | 0 -> (value, t, p)
    | 1 -> (q, value, p)
    | 2 -> (p, value, t)
    | 3 -> (p, q, value)
    | 4 -> (t, p, value)
    | _ -> (value, p, q)
  in
  Display.rgb (int_of_float (red *. 255.0)) (int_of_float (green *. 255.0)) (int_of_float (blue *. 255.0))

(* Dark vertical gradient behind the demo. *)
let draw_backdrop display =
  let width = Display.width display and height = Display.height display in
  let top = Display.rgb 22 28 36 and bottom = Display.rgb 6 8 11 in
  for y = Ui.header_height to height - 1 do
    let alpha = (y - Ui.header_height) * 255 / (height - Ui.header_height) in
    Display.fill_rect display 0 y width 1 (Display.blend top bottom alpha)
  done

(* Gouraud shading: each pixel mixes the corner colors red, green and blue by how
   close it is to each corner (its barycentric weights), scaled so the brightest
   channel is full. *)
let draw_triangle display angle =
  let corner index =
    let theta = angle +. (Float.of_int index *. tau /. 3.0) in
    (center_x +. (radius *. cos theta), center_y +. (radius *. sin theta))
  in
  let (ax, ay), (bx, by), (cx, cy) = (corner 0, corner 1, corner 2) in
  let area = ((bx -. ax) *. (cy -. ay)) -. ((by -. ay) *. (cx -. ax)) in
  let left = int_of_float (Float.floor (Float.min ax (Float.min bx cx)))
  and right = int_of_float (Float.ceil (Float.max ax (Float.max bx cx))) in
  let top = int_of_float (Float.floor (Float.min ay (Float.min by cy)))
  and bottom = int_of_float (Float.ceil (Float.max ay (Float.max by cy))) in
  for y = top to bottom do
    for x = left to right do
      let px = Float.of_int x +. 0.5 and py = Float.of_int y +. 0.5 in
      let red = (((cx -. bx) *. (py -. by)) -. ((cy -. by) *. (px -. bx))) /. area in
      let green = (((ax -. cx) *. (py -. cy)) -. ((ay -. cy) *. (px -. cx))) /. area in
      let blue = 1.0 -. red -. green in
      if red >= 0.0 && green >= 0.0 && blue >= 0.0 then begin
        let brightest = Float.max red (Float.max green blue) in
        let channel weight = int_of_float (weight /. brightest *. 255.0) in
        Display.set_pixel display x y (Display.rgb (channel red) (channel green) (channel blue))
      end
    done
  done

(* Hue around the circle, saturation from the center out. *)
let draw_wheel display angle =
  let r = int_of_float radius in
  for dy = -r to r do
    for dx = -r to r do
      let distance = Float.sqrt (Float.of_int ((dx * dx) + (dy * dy))) in
      if distance <= radius then begin
        let hue = (Float.atan2 (Float.of_int dy) (Float.of_int dx) +. angle) /. tau in
        Display.set_pixel display
          (int_of_float center_x + dx)
          (int_of_float center_y + dy)
          (hsv hue (distance /. radius) 1.0)
      end
    done
  done

type t = { mutable scene : scene; mutable angle : float; mutable spinning : bool }

let create () = { scene = Triangle; angle = 0.0; spinning = true }

(* True while the picture changes on its own, so it needs drawing every frame. *)
let animated colors = colors.spinning

let tick colors = if colors.spinning then colors.angle <- Float.rem (colors.angle +. spin_per_frame) tau

let handle_key colors (event : Input.event) : Ui.action =
  if not (Input.is_down event) then Stay
  else
    match Input.direction event.code with
    | Some Left ->
        colors.angle <- colors.angle -. turn_step;
        Stay
    | Some Right ->
        colors.angle <- colors.angle +. turn_step;
        Stay
    | Some (Up | Down) -> Stay
    | None ->
        let code = event.code in
        if code = Input.Keys.enter then begin
          colors.scene <- (if colors.scene = Triangle then Wheel else Triangle);
          Stay
        end
        else if code = Input.Keys.space then begin
          colors.spinning <- not colors.spinning;
          Stay
        end
        else if code = Input.Keys.tab then Next
        else if code = Input.Keys.esc then Home
        else Stay

let draw colors display =
  draw_backdrop display;
  (match colors.scene with Triangle -> draw_triangle display colors.angle | Wheel -> draw_wheel display colors.angle);
  Ui.draw_header display (if colors.scene = Triangle then "Colors: triangle" else "Colors: wheel");
  Ui.draw_hint display "Z/C turn  SPACE pause  ENTER switch"
