::  Benchmark whether ANY math jets are active.
::  eml is ~40 ops in pure Hoon per call, ~1ns jetted.
::  100K calls: Hoon ~5-10s, jetted ~milliseconds.
::
/-  ls=lagoon
/+  *lagoon, math, saloon, maroon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %noun
=/  rs  ~(. rs:math [%n .1e-5])
::  single call, to verify eml works at all
~&  >  'single eml call...'
=/  single  (eml:rs .0.5 .1)
~&  >  "single eml returned: {<single>}"
::  small batch
=/  n  1.000
~&  >  "starting eml benchmark, n={<n>}..."
=/  total=@rs  .0
=/  i  0
|-  ^-  @rs
?:  =(i n)
  ~&  >  "eml done. total={<total>}"
  total
=/  r  (eml:rs .0.5 .1)
$(i +(i), total (add:rs total r))
