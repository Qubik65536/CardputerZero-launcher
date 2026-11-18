(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Demo 2, interactive rendering: push a glowing ball around. It keeps its
   momentum, leaves a trail and throws sparks when it bounces off the walls. A
   readout shows its physics live: speed, direction, velocity, kinetic energy,
   wall hits and a speed graph. *)

let ball_radius = 9.0
let push = 1.2 (* speed added per key press, pixels per frame *)
let friction = 0.99 (* speed kept each frame *)
let bounce = 0.85 (* speed kept when bouncing *)
let trail_length = 14
let sparks_per_bounce = 10
let spark_life = 30 (* frames *)
let grid = Pixel_canvas.rgb565 0x242C36
let white = Pixel_canvas.rgb565 0xFFFFFF
let mass = 1.0 (* for the kinetic energy readout *)
let arrow_scale = 8.0 (* velocity arrow length per pixel/frame of speed *)
let graph_samples = 96 (* one speed sample per frame; also the graph's width in pixels *)
let graph_height = 36
let graph_max_speed = 10.0 (* pixels/frame at the top of the graph *)
let readout_width = 172
let readout_lines = 3
let line_height = 16 (* Lvgl.Font.montserrat_14 *)
let colors = Array.map Pixel_canvas.rgb565 [| App_ui.language_color; 0x4FC3F7; 0x81C784; 0xF06292 |]

(* The area the ball moves in: between the key line at the top and the hint line. *)
let left = 0.0
let right = Float.of_int App_ui.content_width
let top = 18.0 (* below the "TAB next  ESC home" line *)
let bottom = Float.of_int (App_ui.hint_top - 2)

type spark = { mutable sx : float; mutable sy : float; svx : float; mutable svy : float; mutable life : int }

type t = {
  canvas : Pixel_canvas.t;
  readout : Lvgl.obj;
  mutable x : float;
  mutable y : float;
  mutable vx : float;
  mutable vy : float;
  mutable trail : (float * float) list;  (* newest first *)
  mutable sparks : spark list;
  mutable color : int;  (* index into colors *)
  mutable random : int;  (* xorshift state, so the sparks need no dependencies *)
  mutable hits : int;
  mutable speeds : float list;  (* newest first *)
}

let rec take count list = match list with item :: rest when count > 0 -> item :: take (count - 1) rest | _ -> []

(* A number from -1 to 1 (32-bit xorshift). *)
let next_random motion =
  let r = motion.random in
  let r = r lxor ((r lsl 13) land 0xFFFFFFFF) in
  let r = r lxor (r lsr 17) in
  let r = r lxor ((r lsl 5) land 0xFFFFFFFF) in
  motion.random <- r;
  (Float.of_int (r mod 2001) /. 1000.0) -. 1.0

let speed motion = sqrt ((motion.vx *. motion.vx) +. (motion.vy *. motion.vy))

(* A wall hit: count it and throw sparks from the contact point. *)
let burst motion x y =
  motion.hits <- motion.hits + 1;
  for _ = 1 to sparks_per_bounce do
    let svx = next_random motion *. 2.5 in
    let svy = (next_random motion *. 2.5) -. 1.0 in
    motion.sparks <- motion.sparks @ [ { sx = x; sy = y; svx; svy; life = spark_life } ]
  done

(* Advance one frame: move, bounce, age the trail and the sparks. *)
let tick motion =
  motion.x <- motion.x +. motion.vx;
  motion.y <- motion.y +. motion.vy;
  motion.vx <- motion.vx *. friction;
  motion.vy <- motion.vy *. friction;
  let clamp value low high = Float.max low (Float.min value high) in
  if motion.x < left +. ball_radius || motion.x > right -. ball_radius then begin
    motion.x <- clamp motion.x (left +. ball_radius) (right -. ball_radius);
    motion.vx <- -.motion.vx *. bounce;
    if Float.abs motion.vx > 0.6 then
      burst motion (if motion.vx > 0.0 then motion.x -. ball_radius else motion.x +. ball_radius) motion.y
  end;
  if motion.y < top +. ball_radius || motion.y > bottom -. ball_radius then begin
    motion.y <- clamp motion.y (top +. ball_radius) (bottom -. ball_radius);
    motion.vy <- -.motion.vy *. bounce;
    if Float.abs motion.vy > 0.6 then
      burst motion motion.x (if motion.vy > 0.0 then motion.y -. ball_radius else motion.y +. ball_radius)
  end;
  motion.trail <- take trail_length ((motion.x, motion.y) :: motion.trail);
  motion.speeds <- take graph_samples (speed motion :: motion.speeds);
  List.iter
    (fun spark ->
      spark.sx <- spark.sx +. spark.svx;
      spark.sy <- spark.sy +. spark.svy;
      spark.svy <- spark.svy +. 0.08 (* gravity *);
      spark.life <- spark.life - 1)
    motion.sparks;
  motion.sparks <- List.filter (fun spark -> spark.life > 0) motion.sparks

(* Numbers about the ball's motion, top left: a shaded panel on the canvas, text in a label. *)
let draw_readout motion =
  let current = speed motion in
  (* Screen y grows downwards; flip it so 90 degrees points up, as in math. *)
  let degrees = Float.rem (atan2 (-.motion.vy) motion.vx *. (180.0 /. 3.14159265)) 360.0 in
  let degrees = if degrees < 0.0 then degrees +. 360.0 else degrees in
  let direction = int_of_float (Float.round degrees) mod 360 in
  let energy = 0.5 *. mass *. current *. current in
  Lvgl.Label.set_text motion.readout
    (Printf.sprintf "speed %.2f  dir %d\nvx %+.2f  vy %+.2f\nenergy %.2f  hits %d" current direction motion.vx
       motion.vy energy motion.hits);
  Pixel_canvas.shade_rect motion.canvas ~x:0
    ~y:(int_of_float top + 2)
    ~width:readout_width
    ~height:((readout_lines * line_height) + 4)
    150

(* Speed over the last graph_samples frames, top right, newest on the right. *)
let draw_graph motion color =
  let graph_left = int_of_float right - graph_samples - 4 in
  let graph_top = int_of_float top + 2 in
  let graph_bottom = graph_top + graph_height - 1 in
  Pixel_canvas.shade_rect motion.canvas ~x:(graph_left - 2) ~y:graph_top ~width:(graph_samples + 4)
    ~height:(graph_height + 2) 150;
  let height_of value = int_of_float (Float.min (value /. graph_max_speed) 1.0 *. Float.of_int (graph_height - 2)) in
  let rec segments age newer = function
    | older :: rest ->
        let x = graph_left + graph_samples - 1 - age in
        Pixel_canvas.draw_line motion.canvas (x + 1) (graph_bottom - height_of newer) x
          (graph_bottom - height_of older)
          color;
        segments (age + 1) older rest
    | [] -> ()
  in
  match motion.speeds with newest :: rest -> segments 1 newest rest | [] -> ()

let draw motion =
  let color = colors.(motion.color) in
  let canvas = motion.canvas in
  Pixel_canvas.clear canvas (Pixel_canvas.rgb565 App_ui.background_color);
  let y = ref (int_of_float top + 8) in
  while !y < int_of_float bottom do
    let x = ref 8 in
    while !x < int_of_float right do
      Pixel_canvas.set_pixel canvas !x !y grid;
      x := !x + 16
    done;
    y := !y + 16
  done;
  (* Oldest trail first, so newer, brighter circles land on top. *)
  let count = List.length motion.trail in
  List.iteri
    (fun index (tx, ty) ->
      let age = count - 1 - index in
      let fade = 1.0 -. (Float.of_int age /. Float.of_int count) in
      Pixel_canvas.fill_circle canvas (int_of_float tx) (int_of_float ty)
        (int_of_float (ball_radius *. (0.3 +. (0.6 *. fade))))
        color
        (int_of_float (90.0 *. fade)))
    (List.rev motion.trail);
  List.iter
    (fun spark ->
      Pixel_canvas.fill_circle canvas (int_of_float spark.sx) (int_of_float spark.sy) 1 color
        (spark.life * 255 / spark_life))
    motion.sparks;
  let x = int_of_float motion.x and y = int_of_float motion.y and radius = int_of_float ball_radius in
  Pixel_canvas.fill_circle canvas x y (radius + 6) color 35 (* glow *);
  Pixel_canvas.fill_circle canvas x y (radius + 3) color 70;
  Pixel_canvas.fill_circle canvas x y radius color 255;
  Pixel_canvas.fill_circle canvas (x - 3) (y - 3) 3 white 140 (* highlight *);
  if speed motion > 0.05 then begin
    (* Velocity arrow: where the ball is heading, and how fast. *)
    let tip_x = int_of_float (motion.x +. (motion.vx *. arrow_scale)) in
    let tip_y = int_of_float (motion.y +. (motion.vy *. arrow_scale)) in
    Pixel_canvas.draw_line canvas x y tip_x tip_y white;
    Pixel_canvas.fill_circle canvas tip_x tip_y 2 white 255
  end;
  draw_readout motion;
  draw_graph motion color;
  Pixel_canvas.present canvas

let on_frame motion =
  tick motion;
  draw motion

let handle_key motion (key : Lvgl.App.key) : App_ui.action =
  let open Lvgl.Keys in
  match App_ui.direction key.code with
  | Some Left ->
      motion.vx <- motion.vx -. push;
      Stay
  | Some Right ->
      motion.vx <- motion.vx +. push;
      Stay
  | Some Up ->
      motion.vy <- motion.vy -. push;
      Stay
  | Some Down ->
      motion.vy <- motion.vy +. push;
      Stay
  | None ->
      if key.code = enter then begin
        motion.color <- (motion.color + 1) mod Array.length colors;
        Stay
      end
      else if key.code = space then begin
        motion.vx <- 0.0;
        motion.vy <- 0.0;
        Stay
      end
      else if key.code = tab then Next
      else if key.code = esc then Home
      else Stay

let create parent =
  let root = App_ui.screen_root parent in
  let canvas = Pixel_canvas.create root ~width:App_ui.content_width ~height:App_ui.content_height in
  (* Widgets created after the canvas are drawn on top of it. *)
  let readout = App_ui.make_label root "" Lvgl.Font.montserrat_14 App_ui.text_color in
  Lvgl.Obj.set_pos readout ~x:4 ~y:(int_of_float top + 4);
  ignore (App_ui.make_demo_keys root);
  ignore (App_ui.make_hint root "F/X/Z/C push  ENTER color  SPACE stop");
  let motion =
    {
      canvas;
      readout;
      x = (left +. right) /. 2.0;
      y = (top +. bottom) /. 2.0;
      vx = 0.0;
      vy = 0.0;
      trail = [];
      sparks = [];
      color = 0;
      random = 0x2545F491;
      hits = 0;
      speeds = [];
    }
  in
  App_ui.make_screen ~root ~title:(fun () -> "Motion") ~handle_key:(handle_key motion) ~frame:(fun () -> on_frame motion) ()
