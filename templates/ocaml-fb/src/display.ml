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

(* Fill a rectangle; parts outside the screen are clipped. *)
let fill_rect display x y w h color =
  let clamp value limit = max 0 (min value limit) in
  let left = clamp x display.width and right = clamp (x + w) display.width in
  let top = clamp y display.height and bottom = clamp (y + h) display.height in
  if left < right then
    for row = top to bottom - 1 do
      Array.fill display.pixels ((row * display.width) + left) (right - left) color
    done

(* Draw ASCII text with the built-in 8x8 font, enlarged [scale] times
   (scale 1 = 8px tall, 2 = 16px). *)
let draw_text display x y text color scale =
  String.iteri
    (fun index char ->
      let code = Char.code char in
      let glyph =
        if code >= Font.first && code - Font.first < Array.length Font.glyphs then Font.glyphs.(code - Font.first)
        else Font.glyphs.(Char.code '?' - Font.first)
      in
      Array.iteri
        (fun row bits ->
          for column = 0 to 7 do
            if bits land (0x80 lsr column) <> 0 then
              fill_rect display (x + (((index * 8) + column) * scale)) (y + (row * scale)) scale scale color
          done)
        glyph)
    text

(* Width in pixels that [draw_text] would use, e.g. for centering. *)
let text_width text scale = String.length text * 8 * scale

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
