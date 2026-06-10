# syto — Practical Guide

This guide covers common integration patterns for CLI tools and file-processing
programs. All examples require `syto` as a library dependency and OCaml 4.14+.

---

## Filtering a directory listing

The simplest use: take the output of `Sys.readdir` and filter by pattern.

```ocaml
let ml_files dir =
  dir
  |> Sys.readdir
  |> Array.to_list
  |> Syto.filter ~pattern:"*.ml"
```

Add `PATHNAME` to prevent `*.ml` from matching paths with slashes.
Without it, `"lib/foo.ml"` matches `*.ml` because `*` matches `/`.

```ocaml
let top_level_ml dir =
  dir
  |> Sys.readdir
  |> Array.to_list
  |> Syto.filter ~flags:[`PATHNAME] ~pattern:"*.ml"
  (* "lib/foo.ml" does not match; "foo.ml" does *)
```

---

## Dotfile-aware scanning

Without `PERIOD`, wildcards match names beginning with `.`.
With `PERIOD`, a leading dot requires an explicit `.` in the pattern.

```ocaml
(* All files except dotfiles *)
let visible_files dir =
  dir |> Sys.readdir |> Array.to_list
  |> Syto.filter ~flags:[`PERIOD] ~pattern:"*"

(* Only dotfiles *)
let hidden_files dir =
  dir |> Sys.readdir |> Array.to_list
  |> Syto.filter ~flags:[`PERIOD] ~pattern:".*"
```

With `PATHNAME` also set, the same rule applies after each `/`:

```ocaml
let flags = [`PATHNAME; `PERIOD]

(* src/*.ml matches src/foo.ml but not src/.hidden.ml *)
let () =
  let paths = ["src/foo.ml"; "src/.hidden.ml"; "lib/bar.ml"] in
  assert (Syto.filter ~flags ~pattern:"src/*.ml" paths = ["src/foo.ml"])
```

---

## Recursive file discovery

`GLOBSTAR` requires relative paths that include directory separators.
Build a recursive walker, then pass the flat list to `Syto.filter`.

```ocaml
(* Produce relative paths: ["src/foo.ml"; "src/lib/bar.ml"; ...] *)
let rec collect root prefix =
  let dir = if prefix = "" then root else Filename.concat root prefix in
  Sys.readdir dir
  |> Array.to_list
  |> List.concat_map (fun entry ->
    let rel  = if prefix = "" then entry else prefix ^ "/" ^ entry in
    let full = Filename.concat root rel in
    if Sys.is_directory full then collect root rel else [rel])

(* Find all OCaml sources under the project root *)
let find_ml root =
  collect root ""
  |> Syto.filter ~flags:[`PATHNAME; `GLOBSTAR] ~pattern:"**/*.ml"

(* Same but exclude _build/ *)
let find_sources root =
  collect root ""
  |> List.filter (fun p ->
       not (Syto.match_pattern
              ~flags:[`PATHNAME; `GLOBSTAR] ~pattern:"_build/**" ~name:p))
  |> Syto.filter ~flags:[`PATHNAME; `GLOBSTAR] ~pattern:"**/*.ml"
```

Key GLOBSTAR behaviours:

- `**/*.ml` matches `foo.ml` (zero components) and `a/b/foo.ml` (two components).
- `a/**` matches `a/` and `a/b/c` but **not** `a` — trailing `**` requires
  at least one path boundary.
- `**/.*` with `PERIOD` finds any dotfile at any depth while keeping the
  explicit-dot requirement.

---

## Building an ignore filter

A `.gitignore`-style filter: exclude any path that matches at least one rule.

```ocaml
let ignore_flags = [`PATHNAME; `PERIOD; `GLOBSTAR]

let is_ignored rules name =
  List.exists
    (fun pattern -> Syto.match_pattern ~flags:ignore_flags ~pattern ~name)
    rules

let apply_ignore rules names =
  List.filter (fun name -> not (is_ignored rules name)) names

let default_rules = [
  "_build/**";
  "*.byte";
  "*.native";
  ".git/**";
  "**/.DS_Store";
  "**/.*~";
]

let () =
  let files = collect "." "" in
  List.iter print_endline (apply_ignore default_rules files)
```

`Syto.filter` parses the pattern once and matches all names against it.
`is_ignored` above parses each rule on every call to `match_pattern`.
For a small fixed rule set checked against a large file list, the overhead
is negligible — rule count is bounded. If you have many rules and need to
check each name only once, run `filter` per rule and track exclusions:

```ocaml
let apply_ignore_fast rules names =
  let excluded = Hashtbl.create 64 in
  List.iter (fun pattern ->
    Syto.filter ~flags:ignore_flags ~pattern names
    |> List.iter (fun n -> Hashtbl.replace excluded n ())
  ) rules;
  List.filter (fun n -> not (Hashtbl.mem excluded n)) names
```

---

## Case-insensitive matching

`CASEFOLD` folds ASCII A–Z to a–z before comparison — on both the pattern
side and the name side.

```ocaml
(* Match image files regardless of extension case *)
let is_image name =
  List.exists
    (fun pat -> Syto.match_pattern ~flags:[`CASEFOLD] ~pattern:pat ~name)
    ["*.jpg"; "*.jpeg"; "*.png"; "*.gif"; "*.webp"]

let () =
  let files = ["photo.JPG"; "image.png"; "doc.PDF"; "icon.GIF"] in
  assert (List.filter is_image files = ["photo.JPG"; "image.png"; "icon.GIF"])
```

`CASEFOLD` combines cleanly with `PATHNAME`:

```ocaml
(* Case-insensitive match within a specific directory *)
Syto.match_pattern
  ~flags:[`PATHNAME; `CASEFOLD]
  ~pattern:"SRC/*.ML"
  ~name:"src/foo.ml";;
(* - : bool = true *)
```

`CASEFOLD` is ASCII-only. Ukrainian `А` (U+0410) and `а` (U+0430) are
distinct codepoints and remain distinct. If you need case-insensitive
matching for a specific non-ASCII script, normalize both strings before
calling syto.

---

## Unicode and Ukrainian filenames

syto decodes strings as UTF-8. `?` matches one Unicode codepoint, which may
span 1–4 bytes. Character ranges compare by codepoint value.

```ocaml
(* Ukrainian word яблуко: 6 codepoints, 12 UTF-8 bytes *)
Syto.match_pattern ~pattern:"??????" ~name:"яблуко";;
(* - : bool = true  — one ? per codepoint *)

Syto.match_pattern ~pattern:"????????????" ~name:"яблуко";;
(* - : bool = false — 12 bytes is not 12 codepoints *)

(* Cyrillic lowercase range а–я (U+0430–U+044F) *)
Syto.match_pattern ~pattern:"[а-я]*" ~name:"яблуко";;
(* - : bool = true *)

Syto.match_pattern ~pattern:"[а-я]*" ~name:"apple";;
(* - : bool = false *)
```

Ukrainian filenames use two different apostrophe characters in practice:
`'` (U+0027, ASCII) and `'` (U+2019, RIGHT SINGLE QUOTATION MARK). They
are distinct codepoints. Use `*` or `['\u2019]`-style patterns when you
need to match either:

```ocaml
(* Matches м'яч with either apostrophe variant *)
Syto.match_pattern ~pattern:"м*яч" ~name:"м'яч";;
(* - : bool = true *)
```

---

## Error handling

`match_pattern` and `filter` raise `Syto.Error` on invalid patterns.
Patterns from user input should be caught:

```ocaml
let safe_filter ~pattern names =
  match Syto.filter ~pattern names with
  | result -> Ok result
  | exception Syto.Error { kind; pattern; offset } ->
    let reason = match kind with
      | Syto.Unterminated_bracket      -> "unterminated bracket expression"
      | Syto.Invalid_range             -> "invalid range in bracket expression"
      | Syto.Unknown_class s           -> "unknown character class [:" ^ s ^ ":]"
      | Syto.Trailing_escape           -> "pattern ends with backslash"
      | Syto.Unsupported_bracket_syntax -> "collating or equivalence class not supported"
    in
    Error (Printf.sprintf "bad pattern %S (byte %d): %s" pattern offset reason)
```

`offset` is a byte offset into `pattern`, consistent with `String.sub`.
Errors are never raised because of the name string — invalid UTF-8 in a
name is handled silently (each invalid byte is treated as a single unit).

---

## Flag combinations at a glance

| Use case | Flags |
|----------|-------|
| Shell glob, exclude dotfiles | `` [`PATHNAME; `PERIOD] `` |
| gitignore-style rules | `` [`PATHNAME; `PERIOD; `GLOBSTAR] `` |
| Recursive source discovery | `` [`PATHNAME; `GLOBSTAR] `` |
| Case-insensitive file search | `` [`CASEFOLD] `` |
| Case-insensitive with path boundaries | `` [`PATHNAME; `CASEFOLD] `` |
| Match everything including dotfiles | `[]` |
| Literal pattern, no escape processing | `` [`NOESCAPE] `` |
