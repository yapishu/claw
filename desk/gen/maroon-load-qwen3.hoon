::  Load Qwen3 (Bonsai-1.7B MLX 2-bit) weights and poke the maroon agent.
::
::  Usage:
::    =payload +saloon!maroon-load-qwen3
::    :maroon &maroon-load-qwen3 payload
::
::  Reads /weights/qwen3-bonsai/jam (~538 MB). Requires 64-bit Vere —
::  32-bit's u3r_met caps single atoms below that size.
::
/-  ls=lagoon
/+  maroon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %maroon-load-qwen3
::
::  Bonsai-1.7B Qwen3 config (matches config.json of the MLX-2bit variant).
=/  cfg=model-config-qwen3:maroon
  :*  d-model=2.048
      n-heads=16
      n-kv-heads=8
      n-layers=28
      d-ff=6.144
      vocab-size=151.669
      max-seq=32.768
      head-dim=128
      rms-eps=.1e-6
      rope-theta=.1e6
      yarn-factor=.4
      yarn-orig-max-seq=8.192
      bloq=5
  ==
::
=/  path  /(scot %p p.bec)/(scot %tas q.bec)/(scot %da now)/weights/qwen3-bonsai/jam
=/  jam-res  (mule |.(.^(@ %cx path)))
?:  ?=(%| -.jam-res)
  ~&  >>>  "qwen3-bonsai.jam not found at /weights/qwen3-bonsai.jam"
  ~|  %no-weights-file
  !!
=/  jam-atom  p.jam-res
~&  >  "loaded qwen3-bonsai.jam ({<(met 3 jam-atom)>} bytes)"
[cfg jam-atom]
