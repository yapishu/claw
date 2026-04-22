::  Unit test: dequant-mlx2-ray on a synthetic weight with known answer.
::
::  Construct a 1x1 uint32 ray with packed value 0x1B1B1B1B which encodes
::  the 16 int2 sequence [3, 2, 1, 0, 3, 2, 1, 0, 3, 2, 1, 0, 3, 2, 1, 0]
::  (each byte 0x1B = 0b00_01_10_11 packs [3, 2, 1, 0] LSB-first).
::
::  group-size=8, two groups across the 16 elements:
::    group 0: scale=2.0  bias=0.5    -> [6.5 4.5 2.5 0.5 6.5 4.5 2.5 0.5]
::    group 1: scale=10.0 bias=-1.0   -> [29 19 9 -1 29 19 9 -1]
::
::  Usage: +saloon!maroon-test-mlx2
::
/-  ls=lagoon
/+  *lagoon, math, saloon, maroon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %noun
=/  la  (lake %n)
::
::  Build w: shape [1 1] uint32, value 0x1b1b1b1b
=/  w-meta=meta:ls  [~[1 1] 5 %uint ~]
=/  w  (set-item:la (zeros:la w-meta) ~[0 0] 0x1b1b.1b1b)
::
::  Build scales: shape [1 2] fp32, [2.0, 10.0]
=/  s-meta=meta:ls  [~[1 2] 5 %i754 ~]
=/  scales
  =/  s0  (set-item:la (zeros:la s-meta) ~[0 0] .2)
  (set-item:la s0 ~[0 1] .10)
::
::  Build biases: shape [1 2] fp32, [0.5, -1.0]
=/  biases
  =/  b0  (set-item:la (zeros:la s-meta) ~[0 0] .0.5)
  (set-item:la b0 ~[0 1] .-1)
::
::  Dequant — new layout is [in=16, out=1]
=/  out  (dequant-mlx2-ray:maroon w scales biases 8)
~&  >  "out shape: {<shape.meta.out>}"
::
::  Read all 16 rows (input features), col 0 (only output neuron)
=/  vals
  =/  i  0
  =|  acc=(list @rs)
  |-  ^-  (list @rs)
  ?:  =(i 16)  (flop acc)
  $(i +(i), acc [`@rs`(get-item:la out ~[i 0]) acc])
~&  >  ['HN mlx2 vals' vals]
=/  expect=(list @rs)
  :~  .6.5  .4.5  .2.5  .0.5  .6.5  .4.5  .2.5  .0.5
      .29   .19   .9    .-1   .29   .19   .9    .-1
  ==
~&  >  ['expected   ' expect]
?:  =(vals expect)
  ~&  >  'PASS — mlx2 dequant matches expected'
  'PASS'
~&  >>>  'FAIL — values differ'
'FAIL'
