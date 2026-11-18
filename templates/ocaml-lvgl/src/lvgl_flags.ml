(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Build-time helper, run by src/dune (`ocaml lvgl_flags.ml <desktop|device>`),
   not part of the app. It finds the LVGL runtime built by
   scripts/lvgl-runtime/build.sh and writes, next to itself (in _build):

     cflags.sexp    C flags for lvgl_stubs.c: -I/-D for lvgl.h and cp0_app.h
     ldflags.sexp   link flags: the runtime's static libraries and the system
                    libraries they need, as -ccopt/-cclib for ocamlopt
     runtime.stamp  digests of the runtime's libraries, so rebuilding the
                    runtime relinks the app

   The runtime lives in the repository, two levels up from the app
   (projects/<App>/ or templates/<template>/); it is found by walking up from
   the build directory or the directory dune was started in, or set
   CP0_LVGL_RUNTIME=/path/to/scripts/lvgl-runtime. *)

let fail fmt = Printf.ksprintf (fun message -> prerr_endline ("hello-cardputer: " ^ message); exit 1) fmt

let read_lines path =
  let channel = open_in path in
  let rec loop lines =
    match input_line channel with
    | line -> loop (if String.trim line = "" then lines else String.trim line :: lines)
    | exception End_of_file ->
        close_in channel;
        List.rev lines
  in
  loop []

let write_file path text =
  let channel = open_out path in
  output_string channel text;
  close_out channel

let has_prefix prefix text = String.length text >= String.length prefix && String.sub text 0 (String.length prefix) = prefix

(* The directory of a -L<dir> argument. *)
let library_dir line = if has_prefix "-L" line then Some (String.sub line 2 (String.length line - 2)) else None

let absolute path = if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path

(* scripts/lvgl-runtime in the first directory above [start] that has it. *)
let find_runtime start =
  let rec up dir =
    let candidate = Filename.concat dir (Filename.concat "scripts" "lvgl-runtime") in
    if Sys.file_exists (Filename.concat candidate "build.sh") then Some candidate
    else
      let parent = Filename.dirname dir in
      if parent = dir then None else up parent
  in
  up start

let is_library line = has_prefix "-l" line || not (has_prefix "-" line)

(* The runtime lists some libraries twice (-lSDL2, -lpthread) for linkers that
   care about order, and OCaml's runtime links -lpthread itself; macOS's ld
   warns about repeats. Keep each library's last occurrence (everything that
   needs it still comes before it) and leave -lpthread to OCaml. *)
let without_repeated_libraries lines =
  let rec keep = function
    | [] -> []
    | line :: rest ->
        if line = "-lpthread" || (is_library line && List.mem line rest) then keep rest else line :: keep rest
  in
  keep lines

(* A link argument: libraries (-lfoo, /path/libfoo.so.6) go after the
   objects (-cclib), options before them (-ccopt). *)
let link_argument line = Printf.sprintf "%s %S" (if is_library line then "-cclib" else "-ccopt") line

let sexp_list items = "(" ^ String.concat "\n " items ^ ")\n"

(* The static libraries the link uses: lib*.a in the -L directories inside the runtime. *)
let runtime_libraries runtime ldflags =
  List.concat_map
    (fun line ->
      match library_dir line with
      | Some dir when has_prefix runtime dir && Sys.file_exists dir ->
          Sys.readdir dir |> Array.to_list |> List.sort compare
          |> List.filter (fun name -> Filename.check_suffix name ".a")
          |> List.map (Filename.concat dir)
      | _ -> [])
    ldflags

let () =
  let target = if Array.length Sys.argv > 1 then Sys.argv.(1) else "desktop" in
  if target <> "desktop" && target <> "device" then fail "CP0_LVGL_TARGET must be desktop or device, not '%s'" target;
  let here = Filename.dirname (absolute Sys.argv.(0)) in
  let runtime =
    match Sys.getenv_opt "CP0_LVGL_RUNTIME" with
    | Some dir when dir <> "" -> absolute dir
    | _ -> (
        (* From the build directory (usually _build inside the app), else from
           where dune was started (a build directory elsewhere). *)
        let started = Option.value (Sys.getenv_opt "PWD") ~default:here in
        match find_runtime here with
        | Some dir -> dir
        | None -> (
            match find_runtime started with
            | Some dir -> dir
            | None ->
                fail
                  "scripts/lvgl-runtime not found above %s; keep the app in projects/<Name>/ of the launcher repository or set CP0_LVGL_RUNTIME"
                  started))
  in
  let out = Filename.concat (Filename.concat runtime "out") target in
  let cflags_txt = Filename.concat out "cflags.txt" and ldflags_txt = Filename.concat out "ldflags.txt" in
  if not (Sys.file_exists cflags_txt && Sys.file_exists ldflags_txt) then
    fail "the LVGL runtime for the %s is not built (no %s).\n  Run: scripts/lvgl-runtime/build.sh %s   (in %s)"
      target out target (Filename.dirname (Filename.dirname runtime));
  let cflags = read_lines cflags_txt and ldflags = read_lines ldflags_txt in
  (* The flags hold absolute paths of the machine that built the runtime. *)
  List.iter
    (fun line ->
      match library_dir line with
      | Some dir when not (Sys.file_exists dir) ->
          fail "the LVGL runtime's link flags name %s, which does not exist here.\n  Rebuild it: scripts/lvgl-runtime/build.sh %s (in Docker: mount the repository at the same path it has on the host)"
            dir target
      | _ -> ())
    ldflags;
  let libraries = runtime_libraries runtime ldflags in
  if libraries = [] then fail "no libraries in %s; run scripts/lvgl-runtime/build.sh %s" out target;
  write_file (Filename.concat here "cflags.sexp") (sexp_list (List.map (Printf.sprintf "%S") cflags));
  write_file (Filename.concat here "ldflags.sexp") (sexp_list (List.map link_argument (without_repeated_libraries ldflags)));
  write_file (Filename.concat here "runtime.stamp")
    (String.concat "" (List.map (fun path -> Printf.sprintf "%s %s\n" (Digest.to_hex (Digest.file path)) path) libraries))
