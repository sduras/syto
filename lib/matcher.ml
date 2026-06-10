open Token

let dot_cp   = Char.code '.'
let slash_cp = Char.code '/'

let fold_cp cp = if cp >= 65 && cp <= 90 then cp + 32 else cp

let in_class casefold name cp =
  let c = if casefold then fold_cp cp else cp in
  match name with
  | "alpha"  -> (c >= 97 && c <= 122) || (not casefold && c >= 65 && c <= 90)
  | "digit"  -> c >= 48 && c <= 57
  | "alnum"  -> (c >= 97 && c <= 122)
             || (not casefold && c >= 65 && c <= 90)
             || (c >= 48 && c <= 57)
  | "upper"  -> if casefold then c >= 97 && c <= 122 else c >= 65 && c <= 90
  | "lower"  -> c >= 97 && c <= 122
  | "space"  -> c = 32 || c = 9 || c = 10 || c = 13 || c = 12 || c = 11
  | "blank"  -> c = 32 || c = 9
  | "punct"  -> (c >= 33 && c <= 47) || (c >= 58 && c <= 64)
             || (c >= 91 && c <= 96) || (c >= 123 && c <= 126)
  | "print"  -> c >= 32 && c <= 126
  | "graph"  -> c >= 33 && c <= 126
  | "cntrl"  -> c <= 31 || c = 127
  | "xdigit" -> (c >= 48 && c <= 57) || (c >= 97 && c <= 102)
             || (not casefold && c >= 65 && c <= 70)
  | _        -> false

let bracket_matches casefold negated items cp =
  let c = if casefold then fold_cp cp else cp in
  let hit = List.exists (function
    | Char pat_c ->
      (if casefold then fold_cp pat_c else pat_c) = c
    | Range (lo, hi) ->
      let lo' = if casefold then fold_cp lo else lo in
      let hi' = if casefold then fold_cp hi else hi in
      lo' <= c && c <= hi'
    | Class name ->
      in_class casefold name cp
  ) items in
  if negated then not hit else hit

let token_matches casefold tok cp =
  match tok with
  | Literal pat_cp ->
    (if casefold then fold_cp pat_cp = fold_cp cp else pat_cp = cp)
  | Question -> true
  | Bracket { negated; items } ->
    bracket_matches casefold negated items cp
  | Star | Globstar -> assert false

let rec match_flat casefold period_start tokens name =
  let m = Array.length tokens in
  let n = Array.length name   in
  if period_start && n > 0 && name.(0) = dot_cp then
    if m = 0 then false
    else (match tokens.(0) with
      | Literal cp when cp = dot_cp ->
        match_flat casefold false
          (Array.sub tokens 1 (m - 1))
          (Array.sub name   1 (n - 1))
      | _ -> false)
  else begin
    let prev = Array.make (n + 1) false in
    let curr = Array.make (n + 1) false in
    prev.(0) <- true;
    for i = 1 to m do
      Array.fill curr 0 (n + 1) false;
      (match tokens.(i - 1) with
      | Star ->
        curr.(0) <- prev.(0);
        for j = 1 to n do
          curr.(j) <- prev.(j) || curr.(j - 1)
        done
      | tok ->
        for j = 1 to n do
          if prev.(j - 1) then
            curr.(j) <- token_matches casefold tok name.(j - 1)
        done);
      Array.blit curr 0 prev 0 (n + 1)
    done;
    prev.(n)
  end

type component =
  | Pattern          of token array
  | Globstar
  | Trailing_globstar


let is_globstar_token_comp comp =
  Array.length comp = 1 && comp.(0) = Token.Globstar

let split_into_components tokens =
  let n = Array.length tokens in
  let acc = ref [] and start = ref 0 in
  for i = 0 to n - 1 do
    if tokens.(i) = Literal slash_cp then begin
      acc := Array.sub tokens !start (i - !start) :: !acc;
      start := i + 1
    end
  done;
  acc := Array.sub tokens !start (n - !start) :: !acc;
  let raw = Array.of_list (List.rev !acc) in
  let p = Array.length raw in
  Array.init p (fun i ->
    if is_globstar_token_comp raw.(i) then
      if i = p - 1 then Trailing_globstar else Globstar
    else Pattern raw.(i))

let split_name name =
  let n = Array.length name in
  let acc = ref [] and start = ref 0 in
  for i = 0 to n - 1 do
    if name.(i) = slash_cp then begin
      acc := Array.sub name !start (i - !start) :: !acc;
      start := i + 1
    end
  done;
  acc := Array.sub name !start (n - !start) :: !acc;
  Array.of_list (List.rev !acc)

let match_components casefold period components name_comps =
  let p = Array.length components in
  let q = Array.length name_comps  in
  let prev = Array.make (q + 1) false in
  let curr = Array.make (q + 1) false in
  prev.(0) <- true;
  for i = 1 to p do
    Array.fill curr 0 (q + 1) false;
    (match components.(i - 1) with
    | Globstar ->
      curr.(0) <- prev.(0);
      for j = 1 to q do
        curr.(j) <- prev.(j) || curr.(j - 1)
      done
    | Trailing_globstar ->
      for j = 1 to q do
        curr.(j) <- prev.(j - 1) || curr.(j - 1)
      done
    | Pattern pat ->
      for j = 1 to q do
        if prev.(j - 1) then
          curr.(j) <- match_flat casefold period pat name_comps.(j - 1)
      done);
    Array.blit curr 0 prev 0 (q + 1)
  done;
  prev.(q)

let match_ flags tokens name_str =
  let name     = Utf8.decode name_str in
  let casefold = List.mem `CASEFOLD flags in
  let pathname = List.mem `PATHNAME flags in
  let period   = List.mem `PERIOD   flags in
  let globstar = List.mem `GLOBSTAR flags in
  if pathname then
    match_components casefold period
      (split_into_components tokens)
      (split_name name)
  else begin
    let tokens' =
      if globstar
      then Array.map (fun t -> if t = Token.Globstar then Token.Star else t) tokens
      else tokens
    in
    match_flat casefold period tokens' name
  end
