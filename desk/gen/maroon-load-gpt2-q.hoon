::  Load INT8-quantized GPT-2 small from /weights/gpt2-q.jam.
::
::  Generate with:
::    python3 weights_to_noun.py --model gpt2 --quantize --output gpt2-q.jam
::
::  WARNING: ~379MB file. Will stress your loom; if your ship dies, increase
::  --loom (e.g. --loom 35 for 32GB).
::
/-  ls=lagoon
/+  *lagoon, math, saloon, maroon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %maroon-load
::
::  GPT-2 small config
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
=/  path  /(scot %p p.bec)/(scot %tas q.bec)/(scot %da now)/weights/gpt2-q/jam
=/  jam-res  (mule |.(.^(@ %cx path)))
?:  ?=(%| -.jam-res)
  ~&  >>>  'gpt2-q.jam not found'
  ~|  %no-weights-file
  !!
~&  >  "loaded gpt2-q.jam ({<(met 3 p.jam-res)>} bytes)"
[cfg p.jam-res]
