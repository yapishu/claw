::  Load GPT-2 weights from a jam file and poke the maroon agent.
::
::  Usage: +saloon!maroon-load-gpt2 '/some/path/to/gpt2.jam'
::
::  The jam file must be produced by saloon/tools/weights_to_noun.py.
::  It's not distributed with the desk because it's ~650MB — users retrieve
::  it manually. Put it under /weights/gpt2.jam (or pass a custom path).
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
::  GPT-2 small config — matches weights_to_noun.py output for 'gpt2' model
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
::  Try to read the jam file from Clay; gracefully error if missing
=/  path  /(scot %p p.bec)/(scot %tas q.bec)/(scot %da now)/weights/gpt2/jam
=/  jam-res  (mule |.(.^(@ %cx path)))
?:  ?=(%| -.jam-res)
  ~&  >>>  "gpt2.jam not found at /weights/gpt2.jam"
  ~&  >>>  "to load: download from https://huggingface.co/gpt2 and convert with"
  ~&  >>>  "  python3 tools/weights_to_noun.py --model gpt2 --output gpt2.jam"
  ~&  >>>  "then copy gpt2.jam into your pier's %saloon desk at /weights/gpt2.jam"
  ~|  %no-weights-file
  !!
=/  jam-atom  p.jam-res
~&  >  "loaded gpt2.jam ({<(met 3 jam-atom)>} bytes)"
[cfg jam-atom]
