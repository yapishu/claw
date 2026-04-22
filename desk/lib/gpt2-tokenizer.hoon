  ::
::::  /lib/tokenizer — GPT-2 BPE tokenizer
::
::  Encode text -> token IDs, decode IDs -> text.
::  Load from a jammed noun produced by tokenizer_to_noun.py.
::
|%
::  Tree: balanced binary tree emitted by the Python exporter.
::    empty = 0
::    node  = [[k v] [left right]]  where left/right are trees or 0
::    leaf  = [[k v] 0]
::  In-order traversal yields the original list.
+$  tree
  $@  @               ::  0 (empty)
  $:  item=[k=* v=*]
      rest=tree-rest
  ==
+$  tree-rest
  $@  @               ::  0 (leaf)
  [l=tree r=tree]     ::  inner node
::
+$  tokenizer
  $:  vocab=tree              ::  @t -> @ud  (BPE string -> ID)
      inverse-vocab=tree      ::  @ud -> @t
      merges=tree              ::  [@t @t] -> @ud  (pair -> rank)
      byte-map=tree            ::  @ (byte) -> @t (unicode char)
      inverse-byte-map=tree    ::  @t -> @ (byte)
      specials=tree            ::  @t -> @ud  (literal string -> special-token ID)
  ==
::
::  Walk a tree and return all items as a list of cells.
::  Works for any item type — caller does the casting.
::
++  tree-items
  |=  t=tree
  ^-  (list [* *])
  =|  out=(list [* *])
  |-  ^-  (list [* *])
  ?@  t  out
  =.  out  [item.t out]
  ?@  rest.t  out
  ::  recurse into left subtree, accumulating; then right
  =.  out  $(t l.rest.t)
  $(t r.rest.t)
::
::  Build an atom-keyed map from a tree.
::
++  tree-to-map-at
  |=  t=tree
  ^-  (map @ @)
  =/  items  (tree-items t)
  =|  m=(map @ @)
  |-
  ?~  items  m
  $(items t.items, m (~(put by m) ;;(@ -.i.items) ;;(@ +.i.items)))
::
::  Build a map keyed by a pair of atoms from a tree.
::
++  pair-tree-to-map
  |=  t=tree
  ^-  (map [@ @] @)
  =/  items  (tree-items t)
  =|  m=(map [@ @] @)
  |-
  ?~  items  m
  $(items t.items, m (~(put by m) ;;([@ @] -.i.items) ;;(@ +.i.items)))
::
::  Tokenizer with maps — created from a tokenizer tree by +build-maps
::
+$  tokenizer-maps
  $:  vocab=(map @t @ud)
      inverse-vocab=(map @ud @t)
      merges=(map [@t @t] @ud)
      byte-map=(map @ @t)
      inverse-byte-map=(map @t @)
      specials=(map @t @ud)
  ==
::
++  build-maps
  |=  t=tokenizer
  ^-  tokenizer-maps
  :*  `(map @t @ud)`(tree-to-map-at vocab.t)
      `(map @ud @t)`(tree-to-map-at inverse-vocab.t)
      `(map [@t @t] @ud)`(pair-tree-to-map merges.t)
      `(map @ @t)`(tree-to-map-at byte-map.t)
      `(map @t @)`(tree-to-map-at inverse-byte-map.t)
      `(map @t @ud)`(tree-to-map-at specials.t)
  ==
::
::  +cue-tokenizer: load and build maps from a jammed atom.
::
++  cue-tokenizer
  |=  jammed=@
  ^-  tokenizer-maps
  (build-maps ;;(tokenizer (cue jammed)))
::
::  ======== ENCODE ========
::
::  +byte-encode: convert a cord into a list of unicode chars via byte-map.
::  Each byte in the UTF-8 representation is mapped to a printable Unicode
::  character per GPT-2's bytes_to_unicode().
::
++  byte-encode
  |=  [t=tokenizer-maps s=@t]
  ^-  @t
  =/  bytes  (rip 3 s)
  =/  chars
    %+  turn  bytes
    |=  b=@
    (fall (~(get by byte-map.t) b) (tape-as-cord ~[(@c b)]))
  (rap 3 chars)
::
::  +tape-as-cord: (list @c) -> @t  (UTF-8 concatenation)
::
++  tape-as-cord
  |=  cs=(list @)
  ^-  @t
  (rap 3 cs)
::
::  +is-letter: GPT-2's pre-tokenizer splits on \p{L}+ (Unicode letters).
::  We handle ASCII letters + all non-ASCII bytes. Non-ASCII bytes are
::  UTF-8 continuation or leading bytes — always part of some Unicode
::  scalar. Treating them as letters means multi-byte sequences stay
::  intact within a word run, which matches GPT-2's regex for letter
::  scripts (Latin, Greek, Cyrillic, CJK, etc). This is NOT perfect: e.g.
::  a multi-byte symbol like a bullet point would also be treated as a
::  letter, which would differ from reference tokenization on text
::  containing such symbols.
++  is-letter
  |=  c=@
  ^-  ?
  ?|  &((gte c 'A') (lte c 'Z'))
      &((gte c 'a') (lte c 'z'))
      (gte c 0x80)
  ==
::  +is-digit: ASCII digit [0-9]
::  (Unicode \p{N} also includes Arabic-Indic, Devanagari, etc. digits;
::  those are rare in practice. A byte >= 0x80 goes to the letter path.)
++  is-digit
  |=  c=@
  ^-  ?
  &((gte c '0') (lte c '9'))
::  +is-space: whitespace
++  is-space
  |=  c=@
  ^-  ?
  |(=(c ' ') =(c 9) =(c 10) =(c 13))
::
::  +pre-tokenize: GPT-2 regex pre-tokenizer (approximate).
::    's|'t|'re|'ve|'m|'ll|'d  — contractions
::    | ?[A-Za-z]+              — word with optional leading space
::    | ?[0-9]+                 — number with optional leading space
::    | ?[non-alphanumeric]+    — other chars (punctuation etc.)
::    | \s+(?!\S)               — trailing whitespace
::    | \s+                     — remaining whitespace
::
++  pre-tokenize
  |=  s=@t
  ^-  (list @t)
  =/  chars=(list @)  (rip 3 s)
  =|  out=(list @t)
  |-  ^-  (list @t)
  ?~  chars  (flop out)
  =/  c  i.chars
  ::  Try contraction: apostrophe (39)
  ?:  =(c 39)
    =/  rest  t.chars
    ?~  rest  $(chars ~, out [(rap 3 ~[39]) out])
    ::  's(115), 't(116), 'm(109), 'd(100) — single-char contraction
    ?:  |(=(i.rest 115) =(i.rest 116) =(i.rest 109) =(i.rest 100))
      =/  tok  (rap 3 ~[39 i.rest])
      $(chars t.rest, out [tok out])
    ::  're, 've, 'll — two-char contraction; rest has ≥ 1 char (checked above)
    ?~  t.rest
      =/  [new-chars=(list @) piece=@t]  (consume-punct chars)
      $(chars new-chars, out [piece out])
    =/  a  i.rest
    =/  b  i.t.rest
    ?:  ?|  &(=(a 114) =(b 101))  ::  re
            &(=(a 118) =(b 101))  ::  ve
            &(=(a 108) =(b 108))  ::  ll
        ==
      =/  tok  (rap 3 ~[39 a b])
      $(chars t.t.rest, out [tok out])
    ::  lone apostrophe — fall through as punct
    =/  [new-chars=(list @) piece=@t]  (consume-punct chars)
    $(chars new-chars, out [piece out])
  ::  Optional leading space
  =/  has-space  =(c ' ')
  =/  start-chars  ?:(has-space t.chars chars)
  ?~  start-chars  (flop [(rap 3 ~[c]) out])
  =/  next  i.start-chars
  ::  Letter run (with optional leading space)
  ?:  (is-letter next)
    =/  [new-chars=(list @) piece=@t]  (consume-run chars has-space is-letter)
    $(chars new-chars, out [piece out])
  ::  Digit run
  ?:  (is-digit next)
    =/  [new-chars=(list @) piece=@t]  (consume-run chars has-space is-digit)
    $(chars new-chars, out [piece out])
  ::  If we consumed a space but next is whitespace, emit as whitespace run
  ?:  has-space
    ?:  (is-space next)
      =/  [new-chars=(list @) piece=@t]  (consume-run-no-lead chars is-space)
      $(chars new-chars, out [piece out])
    ::  space + non-letter/digit punct: run of punct with leading space
    =/  [new-chars=(list @) piece=@t]  (consume-run chars %.y |=(x=@ &(!(is-space x) !(is-letter x) !(is-digit x))))
    $(chars new-chars, out [piece out])
  ::  No leading space
  ?:  (is-space c)
    =/  [new-chars=(list @) piece=@t]  (consume-run-no-lead chars is-space)
    $(chars new-chars, out [piece out])
  ::  Non-alphanumeric (punctuation)
  =/  [new-chars=(list @) piece=@t]  (consume-punct chars)
    $(chars new-chars, out [piece out])
::
::  consume-run: consume characters matching `ok` starting from chars.
::  If lead=yes, the first char is consumed unconditionally (it's the leading space).
::
++  consume-run
  |=  [chars=(list @) lead=? ok=$-(@ ?)]
  ^-  [(list @) @t]
  =/  buf=(list @)
    ?:  lead
      ?~  chars  ~
      ~[i.chars]
    ~
  =.  chars
    ?:  lead
      ?~  chars  ~
      t.chars
    chars
  |-  ^-  [(list @) @t]
  ?~  chars  [~ (rap 3 (flop buf))]
  ?.  (ok i.chars)  [chars (rap 3 (flop buf))]
  $(chars t.chars, buf [i.chars buf])
::
++  consume-run-no-lead
  |=  [chars=(list @) ok=$-(@ ?)]
  ^-  [(list @) @t]
  (consume-run chars %.n ok)
::
++  consume-punct
  |=  chars=(list @)
  ^-  [(list @) @t]
  ::  eat one char, then any non-alphanumeric-non-space chars
  ?~  chars  [~ '']
  =/  first-char  i.chars
  =/  buf=(list @)  ~[first-char]
  =/  rest=(list @)  t.chars
  |-  ^-  [(list @) @t]
  ?~  rest  [~ (rap 3 (flop buf))]
  ?:  |((is-letter i.rest) (is-digit i.rest) (is-space i.rest))
    [rest (rap 3 (flop buf))]
  $(rest t.rest, buf [i.rest buf])
::
::  +get-pairs: adjacent pairs from a list of BPE symbols.
::
++  get-pairs
  |=  syms=(list @t)
  ^-  (list [@t @t])
  =|  out=(list [@t @t])
  ?~  syms  ~
  ?~  t.syms  ~
  =/  a  i.syms
  =/  b  i.t.syms
  =.  out  [[a b] out]
  |-
  ?~  t.t.syms  (flop out)
  $(syms t.syms, out [[i.t.syms i.t.t.syms] out])
::
::  +bpe-merge: apply BPE merges until no more valid merges.
::  Input: list of single-character symbols.
::  Output: list of merged symbols.
::
++  bpe-merge
  |=  [t=tokenizer-maps syms=(list @t)]
  ^-  (list @t)
  |-  ^-  (list @t)
  =/  pairs=(list [@t @t])  (get-pairs syms)
  ?~  pairs  syms
  ::  find best (lowest-rank) pair
  =/  best=(unit [pair=[@t @t] rank=@ud])  ~
  =/  ps=(list [@t @t])  pairs
  =.  best
    |-  ^-  (unit [[@t @t] @ud])
    ?~  ps  best
    =/  r  (~(get by merges.t) i.ps)
    ?~  r  $(ps t.ps)
    ?~  best
      $(ps t.ps, best `[i.ps u.r])
    ?:  (lth u.r rank.u.best)
      $(ps t.ps, best `[i.ps u.r])
    $(ps t.ps)
  ?~  best  syms
  ::  apply this merge throughout syms
  =/  target  pair.u.best
  =/  merged=@t  (cat 3 -.target +.target)
  =/  new-syms=(list @t)
    =|  out=(list @t)
    =/  xs  syms
    |-  ^-  (list @t)
    ?~  xs  (flop out)
    ?~  t.xs  (flop [i.xs out])
    ?:  ?&(=(i.xs -.target) =(i.t.xs +.target))
      $(xs t.t.xs, out [merged out])
    $(xs t.xs, out [i.xs out])
  $(syms new-syms)
::
::  +chars-of: split a byte-encoded @t into UTF-8 character atoms.
::  GPT-2's BPE operates on characters (codepoints), not bytes.
::  In the byte-encoded form (post bytes_to_unicode), each character is
::  either a single ASCII byte (< 0x80) or a 2-byte UTF-8 sequence
::  (U+00A0..U+013F, which the byte map produces).
::
++  chars-of
  |=  s=@t
  ^-  (list @t)
  =/  bs  (rip 3 s)
  =|  out=(list @t)
  |-  ^-  (list @t)
  ?~  bs  (flop out)
  =/  b  i.bs
  ?:  (lth b 0x80)  ::  ASCII: 1 byte per char
    $(bs t.bs, out [`@t`b out])
  ::  multi-byte UTF-8 lead: for GPT-2 byte-map only 2-byte sequences occur
  ?~  t.bs  (flop [`@t`b out])
  =/  b2  i.t.bs
  ::  represent the 2-byte char as an atom (little-endian bytes)
  =/  ch  `@t`(add b (lsh [3 1] b2))
  $(bs t.t.bs, out [ch out])
::
::  +encode: text -> list of token IDs.
::    First splits the input on any literal string that appears in
::    `specials` (e.g. "<|im_start|>", "<|im_end|>", "<think>") and
::    emits that token ID directly.  The remaining plain segments go
::    through the normal byte-level-BPE path.
::
++  encode
  |=  [t=tokenizer-maps text=@t]
  ^-  (list @ud)
  ?:  =(0 ~(wyt by specials.t))
    (bpe-encode t text)
  (encode-split t text)
::
::  Recursive split on the earliest special occurrence.
::
++  encode-split
  |=  [t=tokenizer-maps text=@t]
  ^-  (list @ud)
  =/  hit  (find-first-special t text)
  ?~  hit
    (bpe-encode t text)
  =/  pre-len  offset.u.hit
  =/  after-start  (add offset.u.hit slen.u.hit)
  =/  text-len  (met 3 text)
  =/  after-len  (sub text-len after-start)
  =/  before-ids
    ?:  =(0 pre-len)  ~
    (bpe-encode t (cut 3 [0 pre-len] text))
  =/  after-ids
    ?:  =(0 after-len)  ~
    $(text (cut 3 [after-start after-len] text))
  (weld before-ids [id.u.hit after-ids])
::
::  Earliest-position / longest-match scan for any known special string.
::
++  find-first-special
  |=  [t=tokenizer-maps text=@t]
  ^-  (unit [offset=@ud slen=@ud id=@ud])
  =/  text-len  (met 3 text)
  =|  best=(unit [offset=@ud slen=@ud id=@ud])
  =/  specs  ~(tap by specials.t)
  |-  ^-  (unit [offset=@ud slen=@ud id=@ud])
  ?~  specs  best
  =/  spec-s  -.i.specs
  =/  spec-id  +.i.specs
  =/  spec-len  (met 3 spec-s)
  =/  found
    ?:  |(=(0 spec-len) (gth spec-len text-len))  ~
    (find-substr text spec-s text-len spec-len)
  =.  best
    ?~  found  best
    ?~  best  `[u.found spec-len spec-id]
    ?:  (lth u.found offset.u.best)  `[u.found spec-len spec-id]
    ?:  &(=(u.found offset.u.best) (gth spec-len slen.u.best))
      `[u.found spec-len spec-id]
    best
  $(specs t.specs)
::
::  Naive substring search.  Returns ~ if not found.
::
++  find-substr
  |=  [text=@t pat=@t text-len=@ud pat-len=@ud]
  ^-  (unit @ud)
  =/  last-start  (sub text-len pat-len)
  =/  i  0
  |-
  ?:  (gth i last-start)  ~
  =/  sub  (cut 3 [i pat-len] text)
  ?:  =(sub pat)  `i
  $(i +(i))
::
::  Core byte-level BPE encode: what used to be +encode.
::
++  bpe-encode
  |=  [t=tokenizer-maps text=@t]
  ^-  (list @ud)
  ?:  =(0 (met 3 text))  ~
  =/  words  (pre-tokenize text)
  =|  out=(list @ud)
  =/  ws  words
  =.  out
    |-  ^-  (list @ud)
    ?~  ws  out
    =/  bytes-word  (byte-encode t i.ws)
    =/  syms  (bpe-merge t (chars-of bytes-word))
    =/  ids
      %+  turn  syms
      |=  s=@t
      (fall (~(get by vocab.t) s) 0)
    $(ws t.ws, out (weld out ids))
  out
::
::  ======== DECODE ========
::
::  +decode: list of token IDs -> text
::
++  decode
  |=  [t=tokenizer-maps ids=(list @ud)]
  ^-  @t
  ::  look up each ID, concat
  =/  strs
    %+  turn  ids
    |=  id=@ud
    (fall (~(get by inverse-vocab.t) id) '')
  =/  joined  (rap 3 strs)
  ::  reverse byte-level encoding: replace each unicode char with its byte
  (byte-decode t joined)
::
::  +byte-decode: reverse byte-level encoding.
::
++  byte-decode
  |=  [t=tokenizer-maps s=@t]
  ^-  @t
  ::  split s into chars, look up each in inverse-byte-map, join as bytes
  ::  (we treat chars as variable-width UTF-8; for byte-map chars are
  ::  1-2 bytes; this is approximate)
  =/  len  (met 3 s)
  =|  bytes=(list @)
  =/  i  0
  |-  ^-  @t
  ?:  (gte i len)  (rap 3 (flop bytes))
  ::  try 2-byte char first (for unicode-mapped bytes)
  =/  c2=@t  (cut 3 [i 2] s)
  =/  found  (~(get by inverse-byte-map.t) c2)
  ?^  found
    $(i (add i 2), bytes [u.found bytes])
  ::  try 1-byte
  =/  c1=@t  (cut 3 [i 1] s)
  =/  found1  (~(get by inverse-byte-map.t) c1)
  ?^  found1
    $(i +(i), bytes [u.found1 bytes])
  ::  fallback: pass through the byte
  $(i +(i), bytes [(cut 3 [i 1] s) bytes])
--
