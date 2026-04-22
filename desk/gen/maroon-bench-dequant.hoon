::  Benchmark dequant-q8-ray.
::  If the jet is working, this completes in milliseconds; pure Hoon takes
::  many seconds for the 10K-element input.
::
::  Usage: +saloon!maroon-bench-dequant
::
/-  ls=lagoon
/+  *lagoon, math, saloon, maroon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %noun
=/  la  (lake %n)
::  build a fake int8 ray with 10000 elements (shape [100 100])
=/  n  10.000
=/  bytes=(list @)  (reap n 5)  ::  value 5 (int8 = 5)
=/  r=ray:ls
  =/  meta=meta:ls  [~[100 100] 3 %uint ~]
  =/  zero-ray  (zeros:la meta)
  =/  data  (con data.zero-ray (rep 3 bytes))
  [meta data]
~&  >  'calling dequant-q8-ray...'
=/  fp-ray  (dequant-q8-ray:maroon r .0.01)
~&  >  "output shape: {<shape.meta.fp-ray>}"
~&  >  "output bloq: {<bloq.meta.fp-ray>}"
~&  >  "output kind: {<kind.meta.fp-ray>}"
::  Check a few values — 5 * 0.01 = 0.05
=/  first-val  (get-item:la fp-ray ~[0 0])
~&  >  "first element (should be @rs 0.05): 0x{<first-val>}"
fp-ray
