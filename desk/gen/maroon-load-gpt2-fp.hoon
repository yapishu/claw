::  Load FP32 GPT-2 small from /weights/gpt2-fp.jam.
::
/-  ls=lagoon
/+  *lagoon, math, saloon, maroon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %maroon-load
::
=/  cfg=model-config:maroon
  :*  d-model=768
      n-heads=12
      n-layers=12
      d-ff=3.072
      vocab-size=50.257
      max-seq=1.024
      bloq=5
  ==
::
=/  path  /(scot %p p.bec)/(scot %tas q.bec)/(scot %da now)/weights/gpt2-fp/jam
=/  jam-res  (mule |.(.^(@ %cx path)))
?:  ?=(%| -.jam-res)
  ~&  >>>  'gpt2-fp.jam not found'
  ~|  %no-weights-file
  !!
~&  >  "loaded gpt2-fp.jam ({<(met 3 p.jam-res)>} bytes)"
[cfg p.jam-res]
