(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Keyboard input as Linux evdev events.

   On the device this reads the built-in keyboard's evdev device. Under fbsim it
   reads the FIFO named by CARDPUTER_INPUT, which carries the same 24-byte
   struct input_event records. Reads are non-blocking: [poll] returns None when
   nothing is pending.

   Keys report Linux key codes. Letters, digits, ENTER, ESC, BACKSPACE, TAB and
   SPACE are standard; the keyboard's symbol layer uses its own codes (see
   docs/app-development/device-reference.md). *)

(* Linux key codes (linux/input-event-codes.h) that apps commonly need. *)
module Keys = struct
  let esc = 1
  let backspace = 14
  let tab = 15
  let enter = 28
  let space = 57
  let up = 103
  let left = 105
  let right = 106
  let down = 108
  let q = 16
  let f = 33
  let z = 44
  let x = 45
  let c = 46
end

type state = Released | Pressed | Repeated
type event = { code : int; state : state }

(* True for a fresh press or an auto-repeat: what most UIs act on. *)
let is_down event = event.state <> Released

type direction = Up | Down | Left | Right

(* The CardputerZero keyboard has no arrow keys: like the launcher, treat
   F/X/Z/C as up/down/left/right. Real arrow keys (desktop simulator, external
   keyboards) work too. *)
let direction code =
  if code = Keys.up || code = Keys.f then Some Up
  else if code = Keys.down || code = Keys.x then Some Down
  else if code = Keys.left || code = Keys.z then Some Left
  else if code = Keys.right || code = Keys.c then Some Right
  else None

let ev_key = 1
let input_event_size = 24 (* struct input_event on 64-bit Linux *)

type t = { fd : Unix.file_descr; record : Bytes.t; mutable filled : int }

let parse record =
  let kind = Bytes.get_uint16_le record 16 and code = Bytes.get_uint16_le record 18 in
  let value = Int32.to_int (Bytes.get_int32_le record 20) in
  if kind <> ev_key then None
  else Some { code; state = (match value with 0 -> Released | 1 -> Pressed | _ -> Repeated) }

(* The built-in keyboard's event device. APPLaunch exports its path to the apps
   it starts; the fixed by-path name is the same device when run another way. *)
let device_path () =
  let candidates = [ "CARDPUTER_INPUT"; "LV_LINUX_KEYBOARD_DEVICE"; "APPLAUNCH_LINUX_KEYBOARD_DEVICE" ] in
  match List.find_map (fun name -> match Sys.getenv_opt name with Some "" | None -> None | path -> path) candidates with
  | Some path -> path
  | None -> "/dev/input/by-path/platform-3f804000.i2c-event"

let open_keyboard () =
  { fd = Unix.openfile (device_path ()) [ Unix.O_RDONLY; Unix.O_NONBLOCK ] 0; record = Bytes.create input_event_size; filled = 0 }

let close keyboard = Unix.close keyboard.fd

(* The next pending key event, if any. Never blocks. *)
let rec poll keyboard =
  match Unix.read keyboard.fd keyboard.record keyboard.filled (input_event_size - keyboard.filled) with
  | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> None
  | 0 -> None (* writer closed (simulator exited) *)
  | got ->
      keyboard.filled <- keyboard.filled + got;
      if keyboard.filled < input_event_size then poll keyboard
      else begin
        keyboard.filled <- 0;
        match parse keyboard.record with Some event -> Some event | None -> poll keyboard
      end
