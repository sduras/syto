let invalid_byte b = 0x110000 + Char.code b

let read s i =
  let d = String.get_utf_8_uchar s i in
  if Uchar.utf_decode_is_valid d
  then Uchar.to_int (Uchar.utf_decode_uchar d), i + Uchar.utf_decode_length d
  else invalid_byte s.[i], i + 1

let decode s =
  let n   = String.length s in
  let buf = Array.make n 0 in
  let src = ref 0
  and dst = ref 0 in
  while !src < n do
    let cp, next = read s !src in
    buf.(!dst) <- cp;
    src := next;
    incr dst
  done;
  Array.sub buf 0 !dst
