(* SPDX-License-Identifier: ISC *)
(* Copyright (c) 2026 Sergiy Duras <sergiy@duras.org> *)

(** Syto — POSIX fnmatch(3) pattern matching.

    Entry points are {!match_pattern} for testing a single name and {!filter}
    for filtering a list. Both accept an optional [flags] argument and raise
    {!Error} on a syntactically invalid pattern. *)

(** Flags that modify matching behaviour. Multiple flags may be combined. *)
type flag =
  [ `PATHNAME  (** [*] and [?] do not match [/]; bracket expressions do not match [/] *)
  | `NOESCAPE  (** backslash is a literal character, not an escape *)
  | `PERIOD    (** a leading [.] in a name component requires an explicit [.] in the pattern *)
  | `CASEFOLD  (** case-insensitive matching; ASCII A-Z only; non-POSIX extension *)
  | `GLOBSTAR  (** [**] as a complete path component matches zero or more name components; non-POSIX extension *)
  ]

(** Reason a pattern is syntactically invalid. Carried by {!Error}. *)
type error_kind =
  | Unterminated_bracket       (** bracket expression has no closing bracket *)
  | Invalid_range              (** range endpoints in a bracket expression are invalid or out of order *)
  | Unknown_class of string    (** unrecognised POSIX character class; the name is carried as a string *)
  | Trailing_escape            (** pattern ends with an unmatched backslash *)
  | Unsupported_bracket_syntax (** collating element or equivalence class syntax *)

exception Error of { kind : error_kind; pattern : string; offset : int }
(** Raised on a syntactically invalid [pattern]. [offset] is the byte offset
    in [pattern] where parsing failed. Never raised due to the contents of
    [name] or the name list. *)

val match_pattern : ?flags:flag list -> pattern:string -> name:string -> bool
(** [match_pattern ~pattern ~name] returns [true] if [name] matches [pattern].
    With no flags, [*] and [?] match any character including [/], and a
    leading [.] is matched by any wildcard.

    @raise Error if [pattern] is syntactically invalid. *)

val filter : ?flags:flag list -> pattern:string -> string list -> string list
(** [filter ~pattern names] returns the elements of [names] that match
    [pattern], in original order. Equivalent to
    [List.filter (fun n -> match_pattern ?flags ~pattern ~name:n) names];
    the pattern is parsed once internally.

    @raise Error if [pattern] is syntactically invalid. *)
