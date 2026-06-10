(lang dune 3.0)

(name syto)

(generate_opam_files true)

(source
 (uri "git+https://codeberg.org/duras/syto.git"))

(license ISC)

(authors "Sergiy Duras <sergiy@duras.org>")

(maintainers "Sergiy Duras <sergiy@duras.org>")

(package
 (name syto)
 (synopsis "POSIX fnmatch(3) filename pattern matching")
 (description
  "Dependency-free OCaml library implementing POSIX fnmatch(3) filename \
   pattern matching. Supports PATHNAME, NOESCAPE, PERIOD flags and \
   CASEFOLD, GLOBSTAR extensions. UTF-8 codepoint-aware.")
 (homepage "https://codeberg.org/duras/syto")
 (bug_reports "https://codeberg.org/duras/syto/issues")
 (depends
  (ocaml    (>= 4.14))
  (alcotest (and :with-test (>= 1.7)))))
