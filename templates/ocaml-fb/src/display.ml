(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   The 320x170 LCD as a Linux framebuffer: an RGB565 canvas you draw into, then
   [present] to copy it to the screen.

   On the device this opens the panel's framebuffer device. Under fbsim on a
   desktop it opens the file named by CARDPUTER_FB instead, so the same code
   runs on both. *)

(* Pack 8-bit-per-channel red/green/blue into the panel's RGB565 format. *)
let rgb r g b = ((r land 0xF8) lsl 8) lor ((g land 0xFC) lsl 3) lor (b lsr 3)

let black = rgb 0 0 0
let white = rgb 255 255 255

type t = {
  fd : Unix.file_descr;
  width : int;
  height : int;
  stride : int; (* bytes per framebuffer row *)
  bytes_per_pixel : int; (* 2 = RGB565, 4 = XRGB8888 *)
  pixels : int array; (* RGB565 canvas, width * height *)
  frame : Bytes.t; (* what gets written to the framebuffer *)
}

let width display = display.width
let height display = display.height

let getenv_nonempty name =
  match Sys.getenv_opt name with Some "" | None -> None | Some value -> Some value

let read_proc path =
  (* in_channel_length is 0 for procfs/sysfs, so always read line by line *)
  try
    let channel = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
        let lines = ref [] in
        (try
           while true do
             lines := input_line channel :: !lines
           done
         with End_of_file -> ());
        Some (List.rev !lines))
  with Sys_error _ -> None

let parse_pair text separator =
  match String.split_on_char separator (String.trim text) with
  | [ a; b ] -> (
      match (int_of_string_opt (String.trim a), int_of_string_opt (String.trim b)) with
      | Some a, Some b -> Some (a, b)
      | _ -> None)
  | _ -> None

let contains_ci haystack needle =
  let haystack = String.lowercase_ascii haystack and n = String.length needle in
  let rec scan i = i + n <= String.length haystack && (String.sub haystack i n = needle || scan (i + 1)) in
  scan 0

(* The panel's framebuffer device, found the same way APPLaunch finds it:
   LV_LINUX_FBDEV_DEVICE (APPLaunch exports it to the apps it starts), then
   /dev/fb_lcd, then the ST7789 entry of /proc/fb, then /dev/fb0. *)
let device_path () =
  match getenv_nonempty "LV_LINUX_FBDEV_DEVICE" with
  | Some path -> path
  | None -> (
      match getenv_nonempty "APPLAUNCH_LINUX_FBDEV_DEVICE" with
      | Some path -> path
      | None when Sys.file_exists "/dev/fb_lcd" -> "/dev/fb_lcd"
      | None -> (
          let panel =
            Option.bind (read_proc "/proc/fb") (fun lines ->
                List.find_opt (fun line -> contains_ci line "st7789") lines)
          in
          match Option.map (String.split_on_char ' ') panel with
          | Some (index :: _) -> "/dev/fb" ^ index
          | _ -> "/dev/fb0"))

let sysfs_value name attribute =
  Option.map (fun lines -> String.trim (String.concat "" lines))
    (read_proc (Printf.sprintf "/sys/class/graphics/%s/%s" name attribute))

(* path, width, height, stride, bytes per pixel *)
let device_geometry () =
  let path = device_path () in
  let resolved = try Unix.realpath path with Unix.Unix_error _ -> path in
  let name = Filename.basename resolved in
  let width, height =
    Option.value ~default:(320, 170) (Option.bind (sysfs_value name "virtual_size") (fun s -> parse_pair s ','))
  in
  let bits = Option.value ~default:16 (Option.bind (sysfs_value name "bits_per_pixel") int_of_string_opt) in
  if bits <> 16 && bits <> 32 then failwith (Printf.sprintf "%d bpp framebuffer; expected 16 or 32" bits);
  let bytes_per_pixel = bits / 8 in
  let stride =
    Option.value ~default:(width * bytes_per_pixel) (Option.bind (sysfs_value name "stride") int_of_string_opt)
  in
  (path, width, height, stride, bytes_per_pixel)

let simulated_geometry () =
  match getenv_nonempty "CARDPUTER_FB" with
  | None -> None
  | Some path ->
      let size = Option.value ~default:"320x170" (getenv_nonempty "CARDPUTER_FB_SIZE") in
      let width, height = Option.value ~default:(320, 170) (parse_pair size 'x') in
      Some (path, width, height, width * 2, 2)

let open_display () =
  let path, width, height, stride, bytes_per_pixel =
    match simulated_geometry () with Some geometry -> geometry | None -> device_geometry ()
  in
  let fd = Unix.openfile path [ Unix.O_RDWR ] 0 in
  {
    fd;
    width;
    height;
    stride;
    bytes_per_pixel;
    pixels = Array.make (width * height) black;
    frame = Bytes.make (stride * height) '\000';
  }

let close display = Unix.close display.fd
let clear display color = Array.fill display.pixels 0 (Array.length display.pixels) color

(* Character cell of the built-in font at scale 1, in pixels. *)
let char_width = 8
let char_height = Font.height

let mix_channel under over alpha shift mask =
  let below = (under lsr shift) land mask and above = (over lsr shift) land mask in
  (((below * (255 - alpha)) + (above * alpha) + 127) / 255) lsl shift

(* Mix two RGB565 colors: [alpha] 0 = all [under], 255 = all [over]. *)
let blend under over alpha =
  mix_channel under over alpha 11 0x1F lor mix_channel under over alpha 5 0x3F lor mix_channel under over alpha 0 0x1F

(* Fill a rectangle; parts outside the screen are clipped. *)
let fill_rect display x y w h color =
  let clamp value limit = max 0 (min value limit) in
  let left = clamp x display.width and right = clamp (x + w) display.width in
  let top = clamp y display.height and bottom = clamp (y + h) display.height in
  if left < right then
    for row = top to bottom - 1 do
      Array.fill display.pixels ((row * display.width) + left) (right - left) color
    done

let inside display x y = x >= 0 && y >= 0 && x < display.width && y < display.height

(* Set one pixel; coordinates outside the screen are ignored. *)
let set_pixel display x y color = if inside display x y then display.pixels.((y * display.width) + x) <- color

(* Mix [color] over the pixel at (x, y); [alpha] 0 = invisible, 255 = opaque. *)
let blend_pixel display x y color alpha =
  if inside display x y then begin
    let index = (y * display.width) + x in
    display.pixels.(index) <- blend display.pixels.(index) color alpha
  end

(* Darken a rectangle, e.g. behind text drawn over a picture. [alpha] 255 = black. *)
let shade_rect display x y w h alpha =
  for row = y to y + h - 1 do
    for column = x to x + w - 1 do
      blend_pixel display column row black alpha
    done
  done

(* Fill a circle centered on (cx, cy), mixed in with [alpha] (255 = opaque). *)
let fill_circle display cx cy radius color alpha =
  for dy = -radius to radius do
    for dx = -radius to radius do
      if (dx * dx) + (dy * dy) <= (radius * radius) + radius then blend_pixel display (cx + dx) (cy + dy) color alpha
    done
  done

(* Draw an image made by scripts/png_to_rgb565.py (with or without --alpha),
   e.g. [draw_image display 0 0 Wallpaper.data] (src/dune embeds the file). *)
let draw_image display x y image =
  let width = String.get_uint16_le image 0 and height = String.get_uint16_le image 2 in
  let alpha_start = 4 + (width * height * 2) in
  let has_alpha = String.length image - alpha_start >= width * height in
  for row = 0 to height - 1 do
    for column = 0 to width - 1 do
      let index = (row * width) + column in
      let color = String.get_uint16_le image (4 + (index * 2)) in
      let opacity = if has_alpha then Char.code image.[alpha_start + index] else 255 in
      blend_pixel display (x + column) (y + row) color opacity
    done
  done

(* Draw ASCII text with the built-in 8x16 font, enlarged [scale] times
   (scale 1 = 8x16 pixels per character, 2 = 16x32). *)
let draw_text display x y text color scale =
  let glyph_count = String.length Font.glyphs / Font.height in
  String.iteri
    (fun index char ->
      let glyph = Char.code char - Font.first in
      let glyph = if glyph >= 0 && glyph < glyph_count then glyph else Char.code '?' - Font.first in
      for row = 0 to Font.height - 1 do
        let bits = Char.code Font.glyphs.[(glyph * Font.height) + row] in
        for column = 0 to 7 do
          if bits land (0x80 lsr column) <> 0 then
            fill_rect display
              (x + (((index * char_width) + column) * scale))
              (y + (row * scale))
              scale scale color
        done
      done)
    text

(* Width in pixels that [draw_text] would use, e.g. for centering. *)
let text_width text scale = String.length text * char_width * scale

(* Expand RGB565 to XRGB8888, for panels that report a 32 bpp framebuffer. *)
let rgb565_to_xrgb8888 pixel =
  let r = (pixel lsr 11) land 0x1F and g = (pixel lsr 5) land 0x3F and b = pixel land 0x1F in
  0xFF000000 lor (((r lsl 3) lor (r lsr 2)) lsl 16) lor (((g lsl 2) lor (g lsr 4)) lsl 8) lor ((b lsl 3) lor (b lsr 2))

let rec write_all fd bytes offset length =
  if length > 0 then
    let written = Unix.write fd bytes offset length in
    write_all fd bytes (offset + written) (length - written)

(* Copy the canvas to the screen. *)
let present display =
  for row = 0 to display.height - 1 do
    for column = 0 to display.width - 1 do
      let pixel = display.pixels.((row * display.width) + column) in
      let offset = (row * display.stride) + (column * display.bytes_per_pixel) in
      if display.bytes_per_pixel = 2 then Bytes.set_uint16_le display.frame offset pixel
      else Bytes.set_int32_le display.frame offset (Int32.of_int (rgb565_to_xrgb8888 pixel))
    done
  done;
  ignore (Unix.lseek display.fd 0 Unix.SEEK_SET);
  write_all display.fd display.frame 0 (Bytes.length display.frame)
