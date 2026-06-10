## 0.1.0 (2026-06-09)

Initial release.

- POSIX fnmatch(3) pattern matching: `match_pattern` and `filter`
- Flags: `Pathname`, `Noescape`, `Period` (POSIX); `Casefold`, `Globstar` (extensions)
- UTF-8 codepoint-aware: `?` matches one Unicode codepoint; ranges operate on codepoints
- `Casefold` is ASCII-only (A–Z); bracket range validation uses raw (unfolded) endpoints
- `Globstar` recognises `**` only at path-component boundaries; trailing `**` requires at least one name component
- Structured error type: `Error of { kind; pattern; offset }`
- `Unsupported_bracket_syntax` for collating elements and equivalence classes
- 376 tests passing (361 canonical vectors + 15 property tests)
- No dependencies beyond OCaml stdlib and alcotest (test only)
