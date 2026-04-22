::  Test a single forward pass on the currently-loaded model.
::  Bypasses SSE/HTTP — runs forward directly and prints the next token.
::
::  Usage: +saloon!maroon-test-forward
::
/-  ls=lagoon
/+  *lagoon, math, saloon, maroon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %noun
::  Read the agent's loaded model via scry. We also need its config.
::  For now, just hardcode a tiny test: 4 prompt tokens through whatever's loaded.
=/  weights-jam-path
  /(scot %p p.bec)/(scot %tas q.bec)/(scot %da now)/weights/tiny-gpt2/jam
=/  jam-res  (mule |.(.^(@ %cx weights-jam-path)))
?:  ?=(%| -.jam-res)
  ~|  %need-tiny-gpt2-jam
  !!
=/  weights  (load-weights:maroon p.jam-res)
=/  cfg=model-config:maroon
  [d-model=2 n-heads=2 n-layers=2 d-ff=8 vocab-size=50.257 max-seq=1.024 bloq=5]
~&  >  'starting forward pass...'
=/  logits  (forward:mr:maroon ~[7.454 2.402 257 640] weights cfg)
~&  >  "logits shape: {<shape.meta.logits>}"
=/  next-tok  (argmax-token:mr:maroon logits)
~&  >  "next token: {<next-tok>}"
next-tok
