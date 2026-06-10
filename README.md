# syto

POSIX fnmatch(3) filename pattern matching for OCaml.

## Installation

```
opam install syto
```

Minimum OCaml version: 4.14.

## Examples

All examples run in utop after `#require "syto";;`.

### Literal and wildcard

```ocaml
Syto.match_pattern ~pattern:"*.ml" ~name:"foo.ml";;
(* - : bool = true *)

Syto.filter ~pattern:"*.ml" ["foo.ml"; "bar.txt"; "baz.ml"];;
(* - : string list = ["foo.ml"; "baz.ml"] *)
```

### PATHNAME — slashes are path boundaries

`*` and `?` do not cross `/` when `PATHNAME` is set.

```ocaml
(* Without PATHNAME: * matches anything including / *)
Syto.match_pattern ~pattern:"*.ml" ~name:"src/foo.ml";;
(* - : bool = true *)

(* With PATHNAME: * stops at / *)
Syto.match_pattern ~flags:[`PATHNAME] ~pattern:"*.ml" ~name:"src/foo.ml";;
(* - : bool = false *)

Syto.match_pattern ~flags:[`PATHNAME] ~pattern:"src/*.ml" ~name:"src/foo.ml";;
(* - : bool = true *)
```

### PERIOD — dotfiles require an explicit dot

With `PERIOD`, a name component beginning with `.` is matched only by a
pattern with a literal `.` at that position. Wildcards do not match it.

```ocaml
Syto.match_pattern ~flags:[`PERIOD] ~pattern:"*" ~name:".gitignore";;
(* - : bool = false *)

Syto.match_pattern ~flags:[`PERIOD] ~pattern:".*" ~name:".gitignore";;
(* - : bool = true *)

(* PERIOD applies after each / when PATHNAME is also set *)
Syto.match_pattern ~flags:[`PATHNAME; `PERIOD]
  ~pattern:"src/*" ~name:"src/.hidden";;
(* - : bool = false *)
```

### CASEFOLD — case-insensitive matching (ASCII)

```ocaml
Syto.match_pattern ~flags:[`CASEFOLD] ~pattern:"*.ML" ~name:"foo.ml";;
(* - : bool = true *)

Syto.filter ~flags:[`CASEFOLD] ~pattern:"readme*"
  ["README.md"; "readme.txt"; "notes.md"];;
(* - : string list = ["README.md"; "readme.txt"] *)
```

### GLOBSTAR — recursive path matching

With `PATHNAME` and `GLOBSTAR`, `**` matches zero or more path components.

```ocaml
let flags = [`PATHNAME; `GLOBSTAR];;

Syto.match_pattern ~flags ~pattern:"src/**/*.ml" ~name:"src/lib/foo.ml";;
(* - : bool = true *)

Syto.match_pattern ~flags ~pattern:"src/**/*.ml" ~name:"src/foo.ml";;
(* - : bool = true  — ** matches zero components *)

Syto.match_pattern ~flags ~pattern:"a/**" ~name:"a";;
(* - : bool = false — trailing ** requires at least one boundary *)

Syto.filter ~flags ~pattern:"**/*.ml"
  ["src/a.ml"; "src/lib/b.ml"; "other.txt"];;
(* - : string list = ["src/a.ml"; "src/lib/b.ml"] *)
```

## Flags

| Flag | POSIX? | Effect |
|------|--------|--------|
| `` `PATHNAME `` | yes | `*` and `?` do not match `/`; bracket expressions do not match `/` |
| `` `NOESCAPE `` | yes | `\` is a literal character, not an escape |
| `` `PERIOD `` | yes | a leading `.` requires an explicit `.` in the pattern |
| `` `CASEFOLD `` | no (GNU) | ASCII A–Z folded to a–z before comparison |
| `` `GLOBSTAR `` | no (bash) | `**` as a complete path component matches zero or more components |

Flags may be combined freely. `GLOBSTAR` without `PATHNAME` makes `**`
behave identically to `*`.

## filter vs match_pattern

`Syto.filter ~pattern names` and
`List.filter (fun n -> Syto.match_pattern ~pattern ~name:n) names`
produce the same result. Use `filter` when applying one pattern to many
names; it parses the pattern once. Use `match_pattern` for one-off checks
or when testing multiple patterns against one name.

## POSIX deviations

- Matching operates on UTF-8 codepoints, not locale-dependent bytes.
  `?` matches one Unicode codepoint.
- Collating elements `[.ch.]` and equivalence classes `[=a=]` raise `Error`.
- `[a-b-c]` raises `Error`; POSIX parses it as range `a-b` plus literal `-c`.
- `CASEFOLD` folds ASCII A–Z only. Cyrillic and other non-ASCII letters
  are compared by codepoint value.
- `GLOBSTAR` is a non-POSIX extension (common in bash and gitignore).

## Documentation

Extended examples and integration patterns: [`docs/guide.md`](docs/guide.md).

API reference: `dune build @doc` or the opam package documentation.

## License

ISC. See [LICENSE](LICENSE).
