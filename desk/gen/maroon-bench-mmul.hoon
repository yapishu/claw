::  Time a 768x768 fp32 matmul. If lagoon's mmul jet dispatches this is
::  near-instant. If pure-Hoon fallback (jet hash mismatch, missing chum,
::  etc.) it'll take many seconds.
::
::  Usage: +saloon!maroon-bench-mmul
::
/-  ls=lagoon
/+  *lagoon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %noun
=/  la  (lake %n)
=/  meta=meta:ls  [~[768 768] 5 %i754 ~]
=/  m  (ones:la meta)
~&  >  'starting 768x768 mmul...'
=/  start  now
=/  out  (mmul:la m m)
~&  >  ['done. first elem' `@rs`(get-item:la out ~[0 0])]
out
