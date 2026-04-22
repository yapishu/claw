::  Verify lagoon's `sub` jet computes `a - b` (not `b - a`).
::
::  Construct two scalar fp32 rays a=5.0 and b=2.0 (shape [1]),
::  then check `(sub a b)` first element. Should be 3.0 (.3),
::  not -3.0 (.-3).
::
::  Run with: +saloon!maroon-test-sub
::
/-  ls=lagoon
/+  *lagoon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %noun
=/  la  (lake %n)
=/  meta=meta:ls  [~[1] 5 %i754 ~]
::  build a=[5.0] and b=[2.0] as 1-element fp32 rays
=/  a-ray=ray:ls  (fill:la meta .5)
=/  b-ray=ray:ls  (fill:la meta .2)
::  result of (sub a b) should be [3.0]
=/  diff  (sub:la a-ray b-ray)
=/  v  `@rs`(get-item:la diff ~[0])
~&  >  ['(sub [5.0] [2.0]) first elem' v]
~&  >  ?:  =(v .3)  'PASS — sub jet gives a - b'
        ?:  =(v .-3)  'FAIL — sub jet gives b - a (BUG)'
        'FAIL — unexpected value'
diff
