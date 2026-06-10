let hex_val = function
  | '0'..'9' as c -> Char.code c - Char.code '0'
  | 'a'..'f' as c -> Char.code c - Char.code 'a' + 10
  | 'A'..'F' as c -> Char.code c - Char.code 'A' + 10
  | c -> failwith (Printf.sprintf "invalid hex digit: %C" c)

let percent_decode s =
  let n = String.length s in
  let buf = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '%' && !i + 2 < n then begin
      Buffer.add_char buf
        (Char.chr (hex_val s.[!i + 1] lsl 4 lor hex_val s.[!i + 2]));
      i := !i + 3
    end else begin
      Buffer.add_char buf s.[!i];
      i := !i + 1
    end
  done;
  Buffer.contents buf

let parse_flag = function
  | "PATHNAME" -> `PATHNAME
  | "NOESCAPE" -> `NOESCAPE
  | "PERIOD"   -> `PERIOD
  | "CASEFOLD" -> `CASEFOLD
  | "GLOBSTAR" -> `GLOBSTAR
  | s          -> failwith ("unknown flag: " ^ s)

let parse_flags s =
  if s = "-" then []
  else List.map parse_flag (String.split_on_char ',' s)

type vector = {
  flags    : Syto.flag list;
  pattern  : string;
  name     : string;
  expected : bool;
  line_no  : int;
  raw      : string;
}

let load_vectors path =
  let ic = open_in path in
  let acc = ref [] in
  let lno = ref 0 in
  (try
    while true do
      incr lno;
      let line = input_line ic in
      let trimmed = String.trim line in
      if trimmed = "" || trimmed.[0] = '#' then ()
      else
        match List.filter (( <> ) "") (String.split_on_char ' ' trimmed) with
        | [ flags_s; pattern_s; name_s; expected_s ] ->
          acc := {
            flags    = parse_flags flags_s;
            pattern  = percent_decode pattern_s;
            name     = percent_decode name_s;
            expected = (match expected_s with
              | "true"  -> true
              | "false" -> false
              | other   ->
                failwith (Printf.sprintf "line %d: bad expected value: %s" !lno other));
            line_no  = !lno;
            raw      = trimmed;
          } :: !acc
        | _ ->
          failwith (Printf.sprintf "line %d: expected 4 fields: %s" !lno trimmed)
    done
  with End_of_file -> ());
  close_in ic;
  List.rev !acc

let error_kind_to_string = function
  | Syto.Unterminated_bracket      -> "Unterminated_bracket"
  | Syto.Invalid_range             -> "Invalid_range"
  | Syto.Unknown_class s           -> Printf.sprintf "Unknown_class(%s)" s
  | Syto.Trailing_escape           -> "Trailing_escape"
  | Syto.Unsupported_bracket_syntax -> "Unsupported_bracket_syntax"

let make_vector_test v =
  let flag_str =
    String.concat "," (List.map (function
      | `PATHNAME -> "PATHNAME" | `NOESCAPE -> "NOESCAPE"
      | `PERIOD   -> "PERIOD"   | `CASEFOLD -> "CASEFOLD"
      | `GLOBSTAR -> "GLOBSTAR") v.flags)
  in
  let name = Printf.sprintf "line %d [%s] %S %S"
    v.line_no flag_str v.pattern v.name
  in
  name, `Quick, fun () ->
    let got =
      (try Syto.match_pattern ~flags:v.flags ~pattern:v.pattern ~name:v.name
       with Syto.Error { kind; pattern; offset } ->
         Alcotest.failf
           "unexpected Error{%s} on %S at offset %d (line %d: %s)"
           (error_kind_to_string kind) pattern offset v.line_no v.raw)
    in
    Alcotest.(check bool) "match result" v.expected got

let expect_kind label pattern expected () =
  match Syto.match_pattern ~flags:[] ~pattern ~name:"x" with
  | _  ->
    Alcotest.failf "%s: expected Error to be raised, got bool" label
  | exception Syto.Error { kind; _ } ->
    if kind <> expected then
      Alcotest.failf "%s: expected %s, got %s"
        label (error_kind_to_string expected) (error_kind_to_string kind)

let expect_offset label pattern expected () =
  match Syto.match_pattern ~flags:[] ~pattern ~name:"x" with
  | _  ->
    Alcotest.failf "%s: expected Error to be raised, got bool" label
  | exception Syto.Error { offset; _ } ->
    Alcotest.(check int) "error byte offset" expected offset

let error_tests = [
  "unterminated [abc",
    `Quick, expect_kind "unterminated" "[abc" Syto.Unterminated_bracket;
  "unterminated foo[",
    `Quick, expect_kind "unterminated foo[" "foo[" Syto.Unterminated_bracket;
  "invalid range [z-a]",
    `Quick, expect_kind "invalid range" "[z-a]" Syto.Invalid_range;
  "invalid range [a-b-c]",
    `Quick, expect_kind "invalid [a-b-c]" "[a-b-c]" Syto.Invalid_range;
  "unknown class [[:foo:]]",
    `Quick, expect_kind "unknown class" "[[:foo:]]" (Syto.Unknown_class "foo");
  "trailing escape foo\\",
    `Quick, expect_kind "trailing escape" "foo\\" Syto.Trailing_escape;
  "collating element [[.ch.]]",
    `Quick, expect_kind "collating" "[[.ch.]]" Syto.Unsupported_bracket_syntax;
  "equivalence class [[=a=]]",
    `Quick, expect_kind "equivalence" "[[=a=]]" Syto.Unsupported_bracket_syntax;
  "offset: [abc -> 0",
    `Quick, expect_offset "offset [abc" "[abc" 0;
  "offset: foo[abc -> 3",
    `Quick, expect_offset "offset foo[abc" "foo[abc" 3;
  "offset: foo\\ -> 3",
    `Quick, expect_offset "offset foo\\" "foo\\" 3;
]

let flag_str flags =
  String.concat "," (List.map (function
    | `PATHNAME -> "PATHNAME" | `NOESCAPE -> "NOESCAPE"
    | `PERIOD   -> "PERIOD"   | `CASEFOLD -> "CASEFOLD"
    | `GLOBSTAR -> "GLOBSTAR") flags)

let sample_cases = [
  ([],               "*",    ["foo"; "bar"; ".hidden"; "a/b"; ""]);
  ([],               "?.ml", ["a.ml"; "ab.ml"; ".ml"]);
  ([`PATHNAME],      "a/*",  ["a/b"; "a/bc"; "a/b/c"; "b/c"]);
  ([`PERIOD],        "*",    ["foo"; ".hidden"; "."]);
  ([`CASEFOLD],      "FOO",  ["foo"; "FOO"; "Foo"; "bar"]);
  ([`PATHNAME; `GLOBSTAR], "a/**", ["a/"; "a/b"; "a/b/c"; "a"]);
]

let test_determinism () =
  List.iter (fun (flags, pattern, names) ->
    List.iter (fun name ->
      let r1 = Syto.match_pattern ~flags ~pattern ~name in
      let r2 = Syto.match_pattern ~flags ~pattern ~name in
      if r1 <> r2 then
        Alcotest.failf "non-deterministic [%s] %S %S" (flag_str flags) pattern name
    ) names
  ) sample_cases

let test_filter_consistency () =
  List.iter (fun (flags, pattern, names) ->
    let via_filter = Syto.filter ~flags ~pattern names in
    let via_list   =
      List.filter (fun name -> Syto.match_pattern ~flags ~pattern ~name) names in
    if via_filter <> via_list then
      Alcotest.failf "filter <> List.filter [%s] %S" (flag_str flags) pattern
  ) sample_cases

let test_pathological () =
  let pattern = String.concat "" (List.init 10 (fun _ -> "*a")) in
  let name    = String.make 30 'a' ^ "b" in
  Alcotest.(check bool) "pathological result" false
    (Syto.match_pattern ~flags:[] ~pattern ~name)

let test_long_inputs () =
  let n = 10000 in
  Alcotest.(check bool) "n ? vs n a" true
    (Syto.match_pattern ~flags:[]
       ~pattern:(String.make n '?')
       ~name:(String.make n 'a'));
  Alcotest.(check bool) "n+1 ? vs n a" false
    (Syto.match_pattern ~flags:[]
       ~pattern:(String.make (n + 1) '?')
       ~name:(String.make n 'a'));
  Alcotest.(check bool) "* vs n a" true
    (Syto.match_pattern ~flags:[] ~pattern:"*" ~name:(String.make n 'a'))

let property_tests = [
  "determinism",               `Quick, test_determinism;
  "filter consistency",        `Quick, test_filter_consistency;
  "pathological backtracking", `Quick, test_pathological;
  "long inputs",               `Quick, test_long_inputs;
]

let () =
  let vectors = load_vectors "vectors.txt" in
  Alcotest.run "syto" [
    "vectors",    List.map make_vector_test vectors;
    "errors",     error_tests;
    "properties", property_tests;
  ]
