(* SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
   SPDX-License-Identifier: MIT

   Tests for the calc language (src/calc.ml): `dune test`. *)

let failures = ref 0

let show = function Ok text -> Printf.sprintf "Ok %S" text | Error text -> Printf.sprintf "Error %S" text

let check name actual expected =
  if actual <> expected then begin
    incr failures;
    Printf.printf "FAIL %s: got %s, expected %s\n" name (show actual) (show expected)
  end

let run line = Calc.run (Calc.create ()) line

let arithmetic_follows_the_usual_rules () =
  check "1 + 2 * 3" (run "1 + 2 * 3") (Ok "7");
  check "(1 + 2) * 3" (run "(1 + 2) * 3") (Ok "9");
  check "7 / 2" (run "7 / 2") (Ok "3");
  check "-7 / 2" (run "-7 / 2") (Ok "-3");
  check "-7 % 3" (run "-7 % 3") (Ok "-1");
  check "2 ^ 3 ^ 2" (run "2 ^ 3 ^ 2") (Ok "512");
  check "-2 ^ 2" (run "-2 ^ 2") (Ok "-4");
  check "10 - 4 - 3" (run "10 - 4 - 3") (Ok "3");
  check "max(3, abs(-8)) + min(1, 2)" (run "max(3, abs(-8)) + min(1, 2)") (Ok "9")

let variables_and_ans_persist () =
  let calculator = Calc.create () in
  check "x = 6 * 7" (Calc.run calculator "x = 6 * 7") (Ok "x = 42");
  check "x + 1" (Calc.run calculator "x + 1") (Ok "43");
  check "ans * 2" (Calc.run calculator "ans * 2") (Ok "86");
  if Calc.variables calculator <> [ ("ans", 86L); ("x", 42L) ] then begin
    incr failures;
    print_endline "FAIL variables: expected ans = 86, x = 42"
  end

let mistakes_are_explained () =
  let error line message = check line (run line) (Error message) in
  error "1 / 0" "division by zero";
  error "y + 1" "unknown name 'y'";
  error "(1 + 2" "expected ')'";
  error "1 +" "incomplete expression";
  error "1 2" "unexpected '2'";
  error "2 $ 3" "unexpected '$'";
  error "2 ^ -1" "negative exponent";
  error "2 ^ 64" "overflow";
  error "abs(1, 2)" "abs takes 1 argument";
  error "sqrt(4)" "unknown function 'sqrt'";
  error "max = 3" "max is a function";
  error "99999999999999999999" "number too large"

let () =
  arithmetic_follows_the_usual_rules ();
  variables_and_ans_persist ();
  mistakes_are_explained ();
  if !failures > 0 then begin
    Printf.printf "%d failed\n" !failures;
    exit 1
  end;
  print_endline "calc: all tests passed"
