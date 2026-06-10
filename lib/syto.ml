type flag =
  [ `PATHNAME
  | `NOESCAPE
  | `PERIOD
  | `CASEFOLD
  | `GLOBSTAR
  ]

type error_kind = Token.error_kind =
  | Unterminated_bracket
  | Invalid_range
  | Unknown_class of string
  | Trailing_escape
  | Unsupported_bracket_syntax

exception Error of { kind : error_kind; pattern : string; offset : int }

let parse_pattern flags pattern =
  let noescape = List.mem `NOESCAPE flags in
  let globstar = List.mem `GLOBSTAR flags in
  match Parser.parse ~noescape ~globstar pattern with
  | tokens -> tokens
  | exception Parser.Parse_error { kind; offset } ->
    raise (Error { kind; pattern; offset })

let[@warning "-16"] match_pattern ?(flags = []) ~pattern ~name =
  Matcher.match_ flags (parse_pattern flags pattern) name

let[@warning "-16"] filter ?(flags = []) ~pattern names =
  let tokens = parse_pattern flags pattern in
  List.filter (fun name -> Matcher.match_ flags tokens name) names
