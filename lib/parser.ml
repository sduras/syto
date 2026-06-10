open Token

exception Parse_error of { kind : Token.error_kind; offset : int }

let slash_cp  = Char.code '/'
let star_cp   = Char.code '*'
let qmark_cp  = Char.code '?'
let lbrack_cp = Char.code '['
let rbrack_cp = Char.code ']'
let bslash_cp = Char.code '\\'
let bang_cp   = Char.code '!'
let caret_cp  = Char.code '^'
let dash_cp   = Char.code '-'
let colon_cp  = Char.code ':'
let dot_cp    = Char.code '.'
let eq_cp     = Char.code '='

let valid_classes = [
  "alpha"; "digit"; "alnum"; "upper"; "lower"; "space";
  "blank"; "punct"; "print"; "graph"; "cntrl"; "xdigit" ]

let parse_bracket pat start =
  let n   = String.length pat in
  let i   = ref (start + 1) in
  let err k = raise (Parse_error { kind = k; offset = start }) in

  let negated =
    if !i < n && (Char.code pat.[!i] = bang_cp || Char.code pat.[!i] = caret_cp)
    then (incr i; true)
    else false
  in

  let items       = ref [] in
  let first       = ref true  in
  let after_range = ref false in
  let fin         = ref false in

  let process_char cp was_first prev_after_range =
    let is_trailing_dash =
      cp = dash_cp
      && (!i >= n || Char.code pat.[!i] = rbrack_cp)
    in
    if (was_first && cp = dash_cp) || is_trailing_dash then
      items := Char cp :: !items
    else if prev_after_range && cp = dash_cp then
      err Invalid_range
    else if !i < n
         && Char.code pat.[!i] = dash_cp
         && !i + 1 < n
         && Char.code pat.[!i + 1] <> rbrack_cp
    then begin
      incr i;
      let cp_end, next = Utf8.read pat !i in
      i := next;
      if cp > cp_end then err Invalid_range;
      items := Range (cp, cp_end) :: !items;
      after_range := true
    end else
      items := Char cp :: !items
  in

  while not !fin do
    if !i >= n then err Unterminated_bracket;
    let b = Char.code pat.[!i] in

    if b = rbrack_cp && not !first then begin
      incr i; fin := true

    end else begin
      let was_first       = !first in
      let prev_after_range = !after_range in
      first       := false;
      after_range := false;

      if b = lbrack_cp && !i + 1 < n then begin
        let b2 = Char.code pat.[!i + 1] in
        if b2 = colon_cp then begin
          i := !i + 2;
          let j = ref !i in
          while !j < n && Char.code pat.[!j] <> colon_cp do incr j done;
          if !j + 1 >= n || Char.code pat.[!j + 1] <> rbrack_cp then
            err Unterminated_bracket;
          let name = String.sub pat !i (!j - !i) in
          (if not (List.mem name valid_classes) then err (Unknown_class name));
          i := !j + 2;
          items := Class name :: !items
        end else if b2 = dot_cp || b2 = eq_cp then
          err Unsupported_bracket_syntax
        else begin
          let cp, next = Utf8.read pat !i in
          i := next;
          process_char cp was_first prev_after_range
        end

      end else begin
        let cp, next = Utf8.read pat !i in
        i := next;
        process_char cp was_first prev_after_range
      end
    end
  done;

  Bracket { negated; items = List.rev !items }, !i

let[@warning "-32"] parse ~noescape ~globstar pat =
  let n   = String.length pat in
  let buf = Array.make (n + 1) Question in
  let t   = ref 0 in
  let i   = ref 0 in
  let emit tok = buf.(!t) <- tok; incr t in

  while !i < n do
    let b = Char.code pat.[!i] in

    if b = bslash_cp && not noescape then begin
      if !i + 1 >= n then
        raise (Parse_error { kind = Trailing_escape; offset = !i });
      let cp, next = Utf8.read pat (!i + 1) in
      emit (Literal cp);
      i := next

    end else if b = star_cp then begin
      let double = !i + 1 < n && Char.code pat.[!i + 1] = star_cp in
      if double && globstar then begin
        let at_start   = !t = 0 in
        let prev_slash = not at_start && buf.(!t - 1) = Literal slash_cp in
        let after      = !i + 2 in
        let next_boundary = after >= n || Char.code pat.[after] = slash_cp in
        if (at_start || prev_slash) && next_boundary
        then emit Globstar
        else emit Star;
        i := !i + 2
      end else begin
        emit Star;
        i := !i + (if double then 2 else 1)
      end

    end else if b = qmark_cp then begin
      emit Question;
      i := !i + 1

    end else if b = lbrack_cp then begin
      let tok, next = parse_bracket pat !i in
      emit tok;
      i := next

    end else begin
      let cp, next = Utf8.read pat !i in
      emit (Literal cp);
      i := next
    end
  done;

  Array.sub buf 0 !t
