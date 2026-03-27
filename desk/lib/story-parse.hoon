::  story-parse: reusable markdown/story parsing library
::
::  pure functions for converting between plaintext/markdown
::  and urbit story structures. no agent dependencies.
::
/-  d=channels
|%
::
::  +story-to-text: extract plain text from a story
::    handles both inline and block verses (code, citations, headers)
::
++  story-to-text
  |=  =story:d
  ^-  @t
  =/  parts=(list @t)
    %+  murn  story
    |=  =verse:d
    ?:  ?=([%inline *] verse)
      =/  text=@t  (inlines-to-text p.verse)
      ?:  =('' text)  ~
      `text
    ::  block verse handling
    =/  blk  p.verse
    ?+  -.blk  ~
      %code  `(rap 3 '```' lang.blk '\0a' code.blk '\0a```' ~)
      %header  `(inlines-to-text q.blk)
      %rule  `'---'
      %cite  `'[citation]'
      %image
        ?:  =('' alt.blk)
          `(rap 3 '[Image: ' src.blk ']' ~)
        `(rap 3 '[Image: ' alt.blk ' - ' src.blk ']' ~)
      %link  `(rap 3 '[Link: ' url.blk ']' ~)
    ==
  ?~  parts  ''
  =/  out=@t  i.parts
  =/  rem=(list @t)  t.parts
  |-
  ?~  rem  out
  $(rem t.rem, out (rap 3 out '\0a' i.rem ~))
::
++  inlines-to-text
  |=  ils=(list inline:d)
  ^-  @t
  ?~  ils  ''
  =/  this=@t
    ?@  i.ils  i.ils
    ?+  -.i.ils  ''
      %bold         $(ils p.i.ils)
      %italics      $(ils p.i.ils)
      %strike       $(ils p.i.ils)
      %blockquote   $(ils p.i.ils)
      %inline-code  p.i.ils
      %code         p.i.ils
      %ship         (scot %p p.i.ils)
      %link         (rap 3 q.i.ils ' (' p.i.ils ')' ~)
      %break        '\0a'
    ==
  =/  rest=@t  $(ils t.ils)
  ?:  =('' this)  rest
  ?:  =('' rest)  this
  (rap 3 this rest ~)
::
::  +text-to-story: split on double-newlines into paragraph verses
::    handles headers (#) and blockquotes (>) as special verse types
::
++  text-to-story
  |=  text=@t
  ^-  story:d
  =/  paragraphs=(list @t)  (split-paragraphs text)
  =/  verses=(list verse:d)  ~
  |-
  ?~  paragraphs  (flop verses)
  =/  para=tape  (trip i.paragraphs)
  ::  header: # through ######
  ?:  ?&(?=(^ para) =(i.para '#'))
    =/  lvl=@ud  1
    =/  rest=tape  t.para
    |-
    ?~  rest
      ^$(paragraphs t.paragraphs)
    ?:  &(=(i.rest '#') (lth lvl 6))
      $(rest t.rest, lvl +(lvl))
    ::  skip the space after #
    =/  hrest=tape  ?:(=(i.rest ' ') t.rest rest)
    =/  htxt=@t  (crip hrest)
    =/  ils=(list inline:d)  (parse-inlines htxt)
    ?~  ils
      ^$(paragraphs t.paragraphs)
    =/  tag=?(%h1 %h2 %h3 %h4 %h5 %h6)
      ?:  =(1 lvl)  %h1
      ?:  =(2 lvl)  %h2
      ?:  =(3 lvl)  %h3
      ?:  =(4 lvl)  %h4
      ?:  =(5 lvl)  %h5
      %h6
    ^$(paragraphs t.paragraphs, verses [[%block [%header tag ils]] verses])
  ::  blockquote: > text
  ?:  ?&(?=(^ para) =(i.para '>'))
    =/  rest=tape  t.para
    =?  rest  &(?=(^ rest) =(i.rest ' '))  t.rest
    =/  qtxt=@t  (crip rest)
    =/  ils=(list inline:d)  (parse-inlines qtxt)
    ?~  ils
      $(paragraphs t.paragraphs)
    $(paragraphs t.paragraphs, verses [[%inline `(list inline:d)`~[`inline:d`[%blockquote ils]]] verses])
  ::  regular paragraph
  =/  ils=(list inline:d)  (parse-inlines i.paragraphs)
  ?~  ils  $(paragraphs t.paragraphs)
  $(paragraphs t.paragraphs, verses [[%inline ils] verses])
::
::  +split-paragraphs: split text on double-newlines
::
++  split-paragraphs
  |=  text=@t
  ^-  (list @t)
  =/  chars=tape  (trip text)
  =/  out=(list @t)  ~
  =/  buf=tape  ~
  |-
  ?~  chars
    ?~  buf  (flop out)
    (flop [(crip (flop buf)) out])
  ?:  ?&(=(i.chars 10) ?=(^ t.chars) =(i.t.chars 10))
    ::  double newline: emit paragraph, skip both newlines
    =/  rest=tape  t.t.chars
    ::  skip any additional newlines
    |-
    ?~  rest  ^$(chars ~)
    ?.  =(i.rest 10)
      ?~  buf  ^$(chars rest)
      ^$(chars rest, out [(crip (flop buf)) out], buf ~)
    $(rest t.rest)
  $(chars t.chars, buf [i.chars buf])
::
::  +text-to-inlines: wrapper for parse-inlines
::
++  text-to-inlines
  |=  text=@t
  ^-  (list inline:d)
  (parse-inlines text)
::
::  +flush-buf: flush text buffer into inline list
::
++  flush-buf
  |=  [buf=tape out=(list inline:d)]
  ^-  (list inline:d)
  ?~  buf  out
  [`inline:d`(crip (flop buf)) out]
::
::  +try-delimited: try to match text between delimiters
::    returns (unit [matched=tape rest=tape]) or ~ if no closing delimiter
::
++  try-delimited
  |=  [delim=tape chars=tape]
  ^-  (unit [tape tape])
  =/  dlen=@ud  (lent delim)
  =/  collected=tape  ~
  =/  rest=tape  chars
  |-
  ?~  rest  ~
  ::  check if rest starts with delimiter
  =/  prefix=tape  (scag dlen `(list @)`rest)
  ?:  =(prefix delim)
    `[(flop collected) (slag dlen `(list @)`rest)]
  $(rest t.rest, collected [i.rest collected])
::
::  +try-ship: try to parse a ship mention starting after ~
::
++  try-ship
  |=  chars=tape
  ^-  (unit [@p tape])
  =/  ship-buf=tape  ~
  =/  rest=tape  chars
  |-
  ?~  rest
    ::  end of string, try to parse
    ?:  (lth (lent ship-buf) 3)  ~
    =/  sname=@t  (crip (weld "~" (flop ship-buf)))
    (bind (slaw %p sname) |=(p=@p [p ~]))
  =/  c=@tD  i.rest
  ?:  ?|  =(c '-')
          ?&((gte c 'a') (lte c 'z'))
          ?&((gte c '0') (lte c '9'))
      ==
    $(rest t.rest, ship-buf [c ship-buf])
  ::  non-ship char, try to parse what we have
  ?:  (lth (lent ship-buf) 3)  ~
  =/  sname=@t  (crip (weld "~" (flop ship-buf)))
  =/  parsed=(unit @p)  (slaw %p sname)
  ?~  parsed  ~
  `[u.parsed rest]
::
::  +parse-inlines: parse text into inlines with markdown support
::    handles: ~ship mentions, `inline-code`, **bold**, *italic*, ~~strike~~, \n breaks
::
++  parse-inlines
  |=  text=@t
  ^-  (list inline:d)
  =/  chars=tape  (trip text)
  =/  out=(list inline:d)  ~
  =/  buf=tape  ~
  |-  ^-  (list inline:d)
  ?~  chars
    (flop (flush-buf buf out))
  ::  newline -> break
  ?:  =(i.chars 10)
    =/  flushed  (flush-buf buf out)
    $(chars t.chars, buf ~, out [`inline:d`[%break ~] flushed])
  ::  strikethrough: ~~...~~ (before ship check)
  ?:  ?=([%'~' %'~' *] chars)
    =/  result  (try-delimited "~~" t.t.chars)
    ?~  result
      $(chars t.chars, buf [i.chars buf])
    =/  flushed  (flush-buf buf out)
    =/  inner=@t  (crip -.u.result)
    $(chars +.u.result, buf ~, out [`inline:d`[%strike `(list inline:d)`~[`inline:d`inner]] flushed])
  ::  ship mention: ~
  ?:  =(i.chars '~')
    =/  result  (try-ship t.chars)
    ?~  result
      $(chars t.chars, buf ['~' buf])
    =/  flushed  (flush-buf buf out)
    $(chars +.u.result, buf ~, out [`inline:d`[%ship -.u.result] flushed])
  ::  inline code: `...`
  ?:  =(i.chars '`')
    =/  result  (try-delimited "`" t.chars)
    ?~  result
      $(chars t.chars, buf ['`' buf])
    =/  flushed  (flush-buf buf out)
    =/  code-text=@t  (crip -.u.result)
    $(chars +.u.result, buf ~, out [`inline:d`[%inline-code code-text] flushed])
  ::  bold: **...**
  ?:  ?=([%'*' %'*' *] chars)
    =/  result  (try-delimited "**" t.t.chars)
    ?~  result
      $(chars t.chars, buf [i.chars buf])
    =/  flushed  (flush-buf buf out)
    =/  inner=@t  (crip -.u.result)
    $(chars +.u.result, buf ~, out [`inline:d`[%bold `(list inline:d)`~[`inline:d`inner]] flushed])
  ::  italic: *...* (single asterisk, not **)
  ?:  =(i.chars '*')
    =/  result  (try-delimited "*" t.chars)
    ?~  result
      $(chars t.chars, buf ['*' buf])
    =/  flushed  (flush-buf buf out)
    =/  inner=@t  (crip -.u.result)
    $(chars +.u.result, buf ~, out [`inline:d`[%italics `(list inline:d)`~[`inline:d`inner]] flushed])
  ::  default: accumulate
  $(chars t.chars, buf [i.chars buf])
::
++  trim-ws
  |=  t=tape
  ^-  tape
  ?~  t  ~
  ?:  |(=(i.t ' ') =(i.t 10) =(i.t 13))  $(t t.t)
  t
--
