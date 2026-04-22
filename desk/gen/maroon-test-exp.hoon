::  Sanity-test +exp:rs:math — prints bit patterns for a range of inputs.
::
::  Usage: +saloon!maroon-test-exp
::
/+  math
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %noun
=/  rs  ~(. rs:math [%n .1e-5])
=/  cases=(list @rs)
  :~  .0
      .1
      .-1
      .2
      .0.5
      .-0.5
      .10
      .-10
      .0.1
  ==
=/  out
  %+  turn  cases
  |=  x=@rs
  =/  y  (exp:rs x)
  ~&  >  ['exp' x '=' y 'bits' `@ux`y]
  [x y]
out
