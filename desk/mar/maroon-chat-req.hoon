::  maroon-chat-req: direct (non-HTTP) chat request from claw to maroon.
::    req-id — opaque id for response correlation
::    meta   — opaque noun echoed back in the response poke; claw uses
::             it to reconstruct the msg-source without needing per-
::             request state in maroon
::    body   — OpenAI chat.completions JSON (same shape as the HTTP body)
::
|_  req=[req-id=@t meta=* body=@t]
++  grab
  |%
  ++  noun  [req-id=@t meta=* body=@t]
  --
++  grow
  |%
  ++  noun  req
  --
++  grad  %noun
--
