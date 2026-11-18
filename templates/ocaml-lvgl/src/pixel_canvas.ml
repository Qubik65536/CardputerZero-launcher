(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Software rendering into an LVGL canvas: an RGB565 pixel buffer you draw into
   pixel by pixel, then [present] so LVGL redraws it. *)

type t = {
  width : int;
  height : int;
  pixels : Lvgl.rgb565_pixels;  (* also keeps the buffer alive for LVGL *)
  obj : Lvgl.obj;
}

(* Pack 0xRRGGBB into the RGB565 format of the canvas (and the panel). *)
let rgb565 hex = ((hex lsr 8) land 0xF800) lor ((hex lsr 5) land 0x07E0) lor ((hex lsr 3) land 0x001F)

let mix_channel under over alpha shift mask =
  let below = (under lsr shift) land mask and above = (over lsr shift) land mask in
  (((below * (255 - alpha)) + (above * alpha) + 127) / 255) lsl shift

(* Mix two RGB565 colors: [alpha] 0 = all [under], 255 = all [over]. *)
let blend565 under over alpha =
  mix_channel under over alpha 11 0x1F lor mix_channel under over alpha 5 0x3F lor mix_channel under over alpha 0 0x1F

let create parent ~width ~height =
  let pixels = Bigarray.Array1.create Bigarray.int16_unsigned Bigarray.c_layout (width * height) in
  Bigarray.Array1.fill pixels 0;
  let obj = Lvgl.Canvas.create parent in
  Lvgl.Canvas.set_buffer_rgb565 obj pixels ~width ~height;
  Lvgl.Obj.set_pos obj ~x:0 ~y:0;
  { width; height; pixels; obj }

let clear canvas color = Bigarray.Array1.fill canvas.pixels color

(* Fill a rectangle; parts outside the canvas are clipped. *)
let fill_rect canvas ~x ~y ~width ~height color =
  let clamp value limit = max 0 (min value limit) in
  let left = clamp x canvas.width and right = clamp (x + width) canvas.width in
  let top = clamp y canvas.height and bottom = clamp (y + height) canvas.height in
  if right > left then
    for row = top to bottom - 1 do
      Bigarray.Array1.fill (Bigarray.Array1.sub canvas.pixels ((row * canvas.width) + left) (right - left)) color
    done

(* Set one pixel; coordinates outside the canvas are ignored. *)
let set_pixel canvas x y color =
  if x >= 0 && y >= 0 && x < canvas.width && y < canvas.height then
    Bigarray.Array1.unsafe_set canvas.pixels ((y * canvas.width) + x) color

(* Mix [color] over the pixel at (x, y); [alpha] 0 = invisible, 255 = opaque. *)
let blend_pixel canvas x y color alpha =
  if x >= 0 && y >= 0 && x < canvas.width && y < canvas.height then begin
    let index = (y * canvas.width) + x in
    Bigarray.Array1.unsafe_set canvas.pixels index (blend565 (Bigarray.Array1.unsafe_get canvas.pixels index) color alpha)
  end

(* Fill a circle centered on (cx, cy), mixed in with [alpha]. *)
let fill_circle canvas cx cy radius color alpha =
  for dy = -radius to radius do
    for dx = -radius to radius do
      if (dx * dx) + (dy * dy) <= (radius * radius) + radius then blend_pixel canvas (cx + dx) (cy + dy) color alpha
    done
  done

(* Darken a rectangle, e.g. behind text drawn over the picture. [alpha] 255 = black. *)
let shade_rect canvas ~x ~y ~width ~height alpha =
  for row = y to y + height - 1 do
    for column = x to x + width - 1 do
      blend_pixel canvas column row 0x0000 alpha
    done
  done

(* Draw a 1-pixel line from (x0, y0) to (x1, y1) (Bresenham's algorithm). *)
let draw_line canvas x0 y0 x1 y1 color =
  let dx = abs (x1 - x0) and dy = -abs (y1 - y0) in
  let step_x = if x0 < x1 then 1 else -1 and step_y = if y0 < y1 then 1 else -1 in
  let rec step x y error =
    set_pixel canvas x y color;
    if x <> x1 || y <> y1 then begin
      let doubled = 2 * error in
      let x, error = if doubled >= dy then (x + step_x, error + dy) else (x, error) in
      let y, error = if doubled <= dx then (y + step_y, error + dx) else (y, error) in
      step x y error
    end
  in
  step x0 y0 (dx + dy)

(* Show what was drawn since the last call. *)
let present canvas = Lvgl.Obj.invalidate canvas.obj
