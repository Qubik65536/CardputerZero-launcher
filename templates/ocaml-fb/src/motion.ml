(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Demo 2, interactive rendering: push a glowing ball around. It keeps its
   momentum, leaves a trail and throws sparks when it bounces off the walls. *)

let radius = 9.0
let push = 1.2 (* speed added per key press, pixels per frame *)
let friction = 0.99 (* speed kept each frame *)
let bounce = 0.85 (* speed kept when bouncing *)
let trail_length = 14
let sparks_per_bounce = 10
let spark_life = 30 (* frames *)
let grid = Display.rgb 36 44 54
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
  }

let burst motion x y =
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
  motion.trail <- List.filteri (fun age _ -> age < trail_length) ((motion.x, motion.y) :: motion.trail);
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
  Ui.draw_header display "Motion";
  Ui.draw_hint display "F/X/Z/C push  ENTER color  SPACE stop"
