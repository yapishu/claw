::  Test what saloon's `(roll shape ^mul)` actually returns.
::  If it's 0, that's a bug — n-elements in layer-norm would be 0,
::  causing div-by-zero. If it's the correct product, the bug is elsewhere.
::
/+  *lagoon, math, saloon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %noun
=/  shape=(list @)  ~[768]
=/  shape2=(list @)  ~[5 768]
=/  r1  (roll shape ^mul)
=/  r2  (roll shape2 ^mul)
=/  r3  (roll shape mul)
=/  r4  (roll shape2 mul)
~&  >  ['(roll ~[768] ^mul)' r1]
~&  >  ['(roll ~[5 768] ^mul)' r2]
~&  >  ['(roll ~[768] mul)' r3]
~&  >  ['(roll ~[5 768] mul)' r4]
~
