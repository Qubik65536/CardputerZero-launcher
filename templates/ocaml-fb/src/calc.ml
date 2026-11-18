(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   calc, the tiny language behind the REPL demo: whole numbers, + - * / % ^,
   parentheses, variables (x = 6 * 7, ans is the last result) and the functions
   abs, min and max. Pure logic, no screen: test/test_calc.ml checks it
   (dune test).

   Numbers are 64-bit (Int64), like the other templates, so results match on
   every language; OCaml's own int is 63-bit. *)

type token = Number of int64 | Name of string | Symbol of char

(* Every mistake ends evaluation with its message; [run] turns it into [Error]. *)
exception Failed of string

let fail message = raise (Failed message)

let describe = function
  | Number value -> Int64.to_string value
  | Name name -> name
  | Symbol symbol -> String.make 1 symbol

let is_digit character = character >= '0' && character <= '9'

let is_name_start = function 'a' .. 'z' | 'A' .. 'Z' | '_' -> true | _ -> false

let is_name_char character = is_name_start character || is_digit character

let is_space = function ' ' | '\t' | '\n' | '\r' | '\011' | '\012' -> true | _ -> false

let non_negative value = Int64.compare value 0L >= 0

let tokenize line =
  let length = String.length line in
  let rec scan index tokens =
    if index >= length then List.rev tokens
    else
      let character = line.[index] in
      let rec skip index test = if index < length && test line.[index] then skip (index + 1) test else index in
      if is_space character then scan (index + 1) tokens
      else if is_digit character then begin
        let finish = skip index is_digit in
        match Int64.of_string_opt (String.sub line index (finish - index)) with
        | Some value when non_negative value -> scan finish (Number value :: tokens)
        | _ -> fail "number too large"
      end
      else if is_name_start character then
        let finish = skip index is_name_char in
        scan finish (Name (String.sub line index (finish - index)) :: tokens)
      else if String.contains "+-*/%^()=," character then scan (index + 1) (Symbol character :: tokens)
      else fail (Printf.sprintf "unexpected '%c'" character)
  in
  scan 0 []

(* Checked 64-bit arithmetic: "overflow" instead of wrapping around. *)
let overflow () = fail "overflow"

let checked_add a b =
  let sum = Int64.add a b in
  if non_negative a = non_negative b && non_negative sum <> non_negative a then overflow () else sum

let checked_sub a b =
  let difference = Int64.sub a b in
  if non_negative a <> non_negative b && non_negative difference <> non_negative a then overflow () else difference

let checked_mul a b =
  if a = 0L || b = 0L then 0L
  else if (a = -1L && b = Int64.min_int) || (b = -1L && a = Int64.min_int) then overflow ()
  else
    let product = Int64.mul a b in
    if Int64.div product b <> a then overflow () else product

let checked_neg value = if value = Int64.min_int then overflow () else Int64.neg value

(* Truncating division and remainder; only min_int / -1 overflows. *)
let checked_div a b = if a = Int64.min_int && b = -1L then overflow () else Int64.div a b
let checked_rem a b = if a = Int64.min_int && b = -1L then overflow () else Int64.rem a b

(* Exponentiation by squaring, failing on overflow. *)
let power base exponent =
  if Int64.compare exponent 0L < 0 then fail "negative exponent";
  if Int64.compare exponent 0xFFFF_FFFFL > 0 then overflow ();
  let rec loop base exponent accumulator =
    let accumulator = if Int64.logand exponent 1L = 1L then checked_mul accumulator base else accumulator in
    if exponent = 1L then accumulator else loop (checked_mul base base) (Int64.shift_right exponent 1) accumulator
  in
  if exponent = 0L then 1L else loop base exponent 1L

let call name arguments =
  match (name, arguments) with
  | "abs", [ value ] -> if value = Int64.min_int then overflow () else Int64.abs value
  | "min", [ first; second ] -> if Int64.compare first second <= 0 then first else second
  | "max", [ first; second ] -> if Int64.compare first second >= 0 then first else second
  | "abs", _ -> fail "abs takes 1 argument"
  | ("min" | "max"), _ -> fail (Printf.sprintf "%s takes 2 arguments" name)
  | _ -> fail (Printf.sprintf "unknown function '%s'" name)

module Variables = Map.Make (String)

(* Recursive-descent evaluator. Grammar, loosest binding first:
     expression = term (("+" | "-") term)*
     term       = unary (("*" | "/" | "%") unary)*
     unary      = "-" unary | power
     power      = atom ("^" unary)?          (so 2^3^2 = 2^9 and -2^2 = -4)
     atom       = number | name | name "(" arguments ")" | "(" expression ")" *)
type parser = { tokens : token array; mutable position : int; variables : int64 Variables.t }

let peek parser = if parser.position < Array.length parser.tokens then Some parser.tokens.(parser.position) else None
let advance parser = parser.position <- parser.position + 1
let next_is parser symbol = peek parser = Some (Symbol symbol)

let unexpected parser =
  match peek parser with
  | Some token -> Printf.sprintf "unexpected '%s'" (describe token)
  | None -> "incomplete expression"

let expect parser symbol = if next_is parser symbol then advance parser else fail (Printf.sprintf "expected '%c'" symbol)

let rec arguments parser =
  if next_is parser ')' then []
  else
    let first = expression parser in
    let rec more values =
      if next_is parser ',' then begin
        advance parser;
        let value = expression parser in
        more (value :: values)
      end
      else List.rev values
    in
    more [ first ]

and atom parser =
  match peek parser with
  | Some (Number value) ->
      advance parser;
      value
  | Some (Name name) ->
      advance parser;
      if next_is parser '(' then begin
        advance parser;
        let values = arguments parser in
        expect parser ')';
        call name values
      end
      else (
        match Variables.find_opt name parser.variables with
        | Some value -> value
        | None -> fail (Printf.sprintf "unknown name '%s'" name))
  | Some (Symbol '(') ->
      advance parser;
      let value = expression parser in
      expect parser ')';
      value
  | _ -> fail (unexpected parser)

and power_of parser =
  let base = atom parser in
  if not (next_is parser '^') then base
  else begin
    advance parser;
    let exponent = unary parser in
    power base exponent
  end

and unary parser =
  if next_is parser '-' then begin
    advance parser;
    checked_neg (unary parser)
  end
  else power_of parser

and term parser =
  let rec loop value =
    match peek parser with
    | Some (Symbol (('*' | '/' | '%') as operator)) ->
        advance parser;
        let right = unary parser in
        if operator <> '*' && right = 0L then fail "division by zero";
        loop
          (match operator with
          | '*' -> checked_mul value right
          | '/' -> checked_div value right
          | _ -> checked_rem value right)
    | _ -> value
  in
  loop (unary parser)

and expression parser =
  let rec loop value =
    match peek parser with
    | Some (Symbol (('+' | '-') as operator)) ->
        advance parser;
        let right = term parser in
        loop (if operator = '+' then checked_add value right else checked_sub value right)
    | _ -> value
  in
  loop (term parser)

let functions = [ "abs"; "min"; "max" ]

(* The interpreter: variables live as long as it does. *)
type t = { mutable variables : int64 Variables.t }

let create () = { variables = Variables.empty }

(* Run one line: an expression (1 + 2) or an assignment (x = 1 + 2).
   Returns the text to show, "3" or "x = 3". *)
let run calculator line =
  try
    let tokens = tokenize line in
    let target = match tokens with Name name :: Symbol '=' :: _ -> Some name | _ -> None in
    (match target with
    | Some name when List.mem name functions -> fail (Printf.sprintf "%s is a function" name)
    | _ -> ());
    let tokens = Array.of_list tokens in
    let skip = if target = None then 0 else 2 in
    let parser =
      { tokens = Array.sub tokens skip (Array.length tokens - skip); position = 0; variables = calculator.variables }
    in
    let value = expression parser in
    if peek parser <> None then fail (unexpected parser);
    calculator.variables <- Variables.add "ans" value calculator.variables;
    match target with
    | Some name ->
        calculator.variables <- Variables.add name value calculator.variables;
        Ok (Printf.sprintf "%s = %Ld" name value)
    | None -> Ok (Int64.to_string value)
  with Failed message -> Error message

(* Every variable and its value, in name order. *)
let variables calculator = Variables.bindings calculator.variables
