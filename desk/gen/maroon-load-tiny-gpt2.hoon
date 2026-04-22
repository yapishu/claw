::  Load sshleifer/tiny-gpt2 weights from /weights/tiny-gpt2.jam.
::  Small enough to actually work on-ship (~800KB).
::
::  Setup:
::    python3 weights_to_noun.py --model sshleifer/tiny-gpt2 --output tiny-gpt2.jam
::    cp tiny-gpt2.jam ~/.urbit/<ship>/<desk>/weights/tiny-gpt2.jam
::    |commit %saloon
::    +saloon!maroon-load-tiny-gpt2
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
::  sshleifer/tiny-gpt2 config — same arch as GPT-2, tiny dims
=/  cfg=model-config:maroon
  :*  d-model=2
      n-heads=2
      n-layers=2
      d-ff=8          ::  4 * d-model by HF convention
      vocab-size=50.257
      max-seq=1.024
      bloq=5
  ==
::
=/  path  /(scot %p p.bec)/(scot %tas q.bec)/(scot %da now)/weights/tiny-gpt2/jam
=/  jam-res  (mule |.(.^(@ %cx path)))
?:  ?=(%| -.jam-res)
  ~&  >>>  'tiny-gpt2.jam not found at /weights/tiny-gpt2.jam'
  ~&  >>>  'generate with: python3 tools/weights_to_noun.py --model sshleifer/tiny-gpt2 --output tiny-gpt2.jam'
  ~&  >>>  'then copy into your pier at saloon/weights/tiny-gpt2.jam and commit'
  ~|  %no-weights-file
  !!
=/  jam-atom  p.jam-res
~&  >  "loaded tiny-gpt2.jam ({<(met 3 jam-atom)>} bytes)"
[cfg jam-atom]
