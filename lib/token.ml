type error_kind =
  | Unterminated_bracket
  | Invalid_range
  | Unknown_class of string
  | Trailing_escape
  | Unsupported_bracket_syntax

type bracket_item =
  | Char  of int
  | Range of int * int
  | Class of string

type token =
  | Literal  of int
  | Question
  | Star
  | Globstar
  | Bracket  of { negated : bool; items : bracket_item list }
