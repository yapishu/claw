::  maroon-chat-resp: direct (non-HTTP) chat response from maroon to claw.
::    req-id — echoes the request's req-id
::    meta   — echoes the request's opaque meta
::    status — 200 on success, 4xx/5xx on failure
::    body   — OpenAI chat.completion JSON (success) or error text
::
|_  resp=[req-id=@t meta=* status=@ud body=@t]
++  grab
  |%
  ++  noun  [req-id=@t meta=* status=@ud body=@t]
  --
++  grow
  |%
  ++  noun  resp
  --
++  grad  %noun
--
