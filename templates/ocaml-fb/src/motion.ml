(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Demo 2, interactive rendering: push a glowing ball around. It keeps its
   momentum, leaves a trail and throws sparks when it bounces off the walls. A
   readout shows its physics live: speed, direction, velocity, kinetic energy,
   wall hits and a speed graph. *)

let radius = 9.0
let push = 1.2 (* speed added per key press, pixels per frame *)
let friction = 0.99 (* speed kept each frame *)
let bounce = 0.85 (* speed kept when bouncing *)
let trail_length = 14
let sparks_per_bounce = 10
let spark_life = 30 (* frames *)
let grid = Display.rgb 36 44 54
let mass = 1.0 (* for the kinetic energy readout *)
let arrow_scale = 8.0 (* velocity arrow length per pixel/frame of speed *)
let graph_samples = 96 (* one per frame, also the graph's width in pixels *)
let graph_height = 36
let graph_max_speed = 10.0 (* pixels/frame at the top of the graph *)
let colors = [| Ui.language_color; Display.rgb 79 195 247; Display.rgb 129 199 132; Display.rgb 240 98 146 |]

(* The area the ball moves in: below the header, above the hint line. *)
let left = 0.0
let right = 320.0
let top = Float.of_int Ui.header_height
let bottom = Float.of_int (Ui.hint_top - 2)

type spark = { mutable x : float; mutable y : float; vx : float; mutable vy : float; mutable life : int }

(* A small pseudo-random generator (xorshift), so the sparks need no dependencies.
   The state is a 32-bit number kept in an int. *)
let next_signed state =
  let value = !state in
  let value = value lxor ((value lsl 13) land 0xFFFFFFFF) in
  let value = value lxor (value lsr 17) in
  let value = value lxor ((value lsl 5) land 0xFFFFFFFF) in
  state := value;
  (* A number from -1 to 1. *)
  (Float.of_int (value mod 2001) /. 1000.0) -. 1.0

type t = {
  mutable x : float;
  mutable y : float;
  mutable vx : float;
  mutable vy : float;
  mutable trail : (float * float) list; (* newest first *)
  mutable sparks : spark list;
  mutable color : int;
  random : int ref;
  mutable hits : int;
  mutable speeds : float list; (* newest first *)
}

let create () =
  {
    x = (left +. right) /. 2.0;
    y = (top +. bottom) /. 2.0;
    vx = 0.0;
    vy = 0.0;
    trail = [];
    sparks = [];
    color = 0;
    random = ref 0x2545F491;
    hits = 0;
    speeds = [];
  }

let speed motion = Float.sqrt ((motion.vx *. motion.vx) +. (motion.vy *. motion.vy))

(* Keep the first [count] items of a list. *)
let rec take count list = match list with item :: rest when count > 0 -> item :: take (count - 1) rest | _ -> []

(* A wall hit: count it and throw sparks from the contact point. *)
let burst motion x y =
  motion.hits <- motion.hits + 1;
  for _ = 1 to sparks_per_bounce do
    let vx = next_signed motion.random *. 2.5 in
    let vy = (next_signed motion.random *. 2.5) -. 1.0 in
    motion.sparks <- motion.sparks @ [ ({ x; y; vx; vy; life = spark_life } : spark) ]
  done

(* Advance one frame: move, bounce, age the trail and the sparks. *)
let tick motion =
  motion.x <- motion.x +. motion.vx;
  motion.y <- motion.y +. motion.vy;
  motion.vx <- motion.vx *. friction;
  motion.vy <- motion.vy *. friction;
  if motion.x < left +. radius || motion.x > right -. radius then begin
    motion.x <- Float.max (left +. radius) (Float.min motion.x (right -. radius));
    motion.vx <- -.motion.vx *. bounce;
    if Float.abs motion.vx > 0.6 then
      burst motion (if motion.vx > 0.0 then motion.x -. radius else motion.x +. radius) motion.y
  end;
  if motion.y < top +. radius || motion.y > bottom -. radius then begin
    motion.y <- Float.max (top +. radius) (Float.min motion.y (bottom -. radius));
    motion.vy <- -.motion.vy *. bounce;
    if Float.abs motion.vy > 0.6 then
      burst motion motion.x (if motion.vy > 0.0 then motion.y -. radius else motion.y +. radius)
  end;
  motion.trail <- take trail_length ((motion.x, motion.y) :: motion.trail);
  motion.speeds <- take graph_samples (speed motion :: motion.speeds);
  List.iter
    (fun (spark : spark) ->
      spark.x <- spark.x +. spark.vx;
      spark.y <- spark.y +. spark.vy;
      spark.vy <- spark.vy +. 0.08 (* gravity *);
      spark.life <- spark.life - 1)
    motion.sparks;
  motion.sparks <- List.filter (fun (spark : spark) -> spark.life > 0) motion.sparks

let handle_key motion (event : Input.event) : Ui.action =
  if not (Input.is_down event) then Stay
  else
    match Input.direction event.code with
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
        let code = event.code in
        if code = Input.Keys.enter then begin
          motion.color <- (motion.color + 1) mod Array.length colors;
          Stay
        end
        else if code = Input.Keys.space then begin
          motion.vx <- 0.0;
          motion.vy <- 0.0;
          Stay
        end
        else if code = Input.Keys.tab then Next
        else if code = Input.Keys.esc then Home
        else Stay

(* Numbers about the ball's motion, top left. *)
let draw_readout motion display =
  let speed = speed motion in
  (* Screen y grows downwards; flip it so 90 degrees points up, as in math. *)
  let degrees = Float.atan2 (-.motion.vy) motion.vx *. 180.0 /. Float.pi in
  let degrees = Float.rem degrees 360.0 in
  let direction = int_of_float (Float.round (if degrees < 0.0 then degrees +. 360.0 else degrees)) mod 360 in
  let energy = 0.5 *. mass *. speed *. speed in
  let lines =
    [
      Printf.sprintf "speed %.2f  dir %d" speed direction;
      Printf.sprintf "vx %+.2f  vy %+.2f" motion.vx motion.vy;
      Printf.sprintf "energy %.2f  hits %d" energy motion.hits;
    ]
  in
  let top = int_of_float top + 2 in
  Display.shade_rect display 0 top 172 ((List.length lines * Display.char_height) + 4) 150;
  List.iteri (fun row line -> Display.draw_text display 4 (top + 2 + (row * Display.char_height)) line Ui.text 1) lines

(* Speed over the last [graph_samples] frames, top right, newest on the right. *)
let draw_graph motion display color =
  let left = int_of_float right - graph_samples - 4 and top = int_of_float top + 2 in
  let bottom = top + graph_height - 1 in
  Display.shade_rect display (left - 2) top (graph_samples + 4) (graph_height + 2) 150;
  let height_of speed = int_of_float (Float.min (speed /. graph_max_speed) 1.0 *. Float.of_int (graph_height - 2)) in
  (* Join each sample to the one before it, newest (age 0) first. *)
  let rec plot age previous speeds =
    match speeds with
    | [] -> ()
    | speed :: older ->
        let x = left + graph_samples - 1 - age and y = bottom - height_of speed in
        Option.iter (fun (previous_x, previous_y) -> Display.draw_line display previous_x previous_y x y color) previous;
        plot (age + 1) (Some (x, y)) older
  in
  plot 0 None motion.speeds

let draw motion display =
  let color = colors.(motion.color) in
  Display.clear display Ui.background;
  let y = ref (int_of_float top + 8) in
  while !y < int_of_float bottom do
    let x = ref 8 in
    while !x < int_of_float right do
      Display.set_pixel display !x !y grid;
      x := !x + 16
    done;
    y := !y + 16
  done;
  (* Oldest trail first, so newer, brighter circles land on top. *)
  let length = Float.of_int (List.length motion.trail) in
  List.iteri
    (fun index (x, y) ->
      let age = List.length motion.trail - 1 - index in
      let fade = 1.0 -. (Float.of_int age /. length) in
      Display.fill_circle display (int_of_float x) (int_of_float y)
        (int_of_float (radius *. (0.3 +. (0.6 *. fade))))
        color
        (int_of_float (90.0 *. fade)))
    (List.rev motion.trail);
  List.iter
    (fun (spark : spark) ->
      Display.fill_circle display (int_of_float spark.x) (int_of_float spark.y) 1 color (spark.life * 255 / spark_life))
    motion.sparks;
  let x = int_of_float motion.x and y = int_of_float motion.y and r = int_of_float radius in
  Display.fill_circle display x y (r + 6) color 35 (* glow *);
  Display.fill_circle display x y (r + 3) color 70;
  Display.fill_circle display x y r color 255;
  Display.fill_circle display (x - 3) (y - 3) 3 Display.white 140 (* highlight *);
  if speed motion > 0.05 then begin
    (* Velocity arrow: where the ball is heading, and how fast. *)
    let tip_x = int_of_float (motion.x +. (motion.vx *. arrow_scale))
    and tip_y = int_of_float (motion.y +. (motion.vy *. arrow_scale)) in
    Display.draw_line display x y tip_x tip_y Display.white;
    Display.fill_circle display tip_x tip_y 2 Display.white 255
  end;
  draw_readout motion display;
  draw_graph motion display color;
  Ui.draw_header display "Motion";
  Ui.draw_hint display "F/X/Z/C push  ENTER color  SPACE stop"
