::  Load INT8-quantized sshleifer/tiny-gpt2 weights.
::
::  Generate with:
::    python3 weights_to_noun.py --model sshleifer/tiny-gpt2 \
::      --quantize --output tiny-gpt2-q.jam
::  Put into your pier at saloon/weights/tiny-gpt2-q.jam and |commit.
::
/-  ls=lagoon
/+  *lagoon,
    math,
    saloon,
    maroon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %maroon-load
::
=/  cfg=model-config:maroon
  :*  d-model=2
      n-heads=2
      n-layers=2
      d-ff=8
      vocab-size=50.257
      max-seq=1.024
      bloq=5
  ==
::
=/  path  /(scot %p p.bec)/(scot %tas q.bec)/(scot %da now)/weights/tiny-gpt2-q/jam
=/  jam-res  (mule |.(.^(@ %cx path)))
?:  ?=(%| -.jam-res)
  ~|  %no-quantized-weights-file
  !!
=/  jam-atom  p.jam-res
~&  >  "loaded tiny-gpt2-q.jam ({<(met 3 jam-atom)>} bytes)"
[cfg jam-atom]
