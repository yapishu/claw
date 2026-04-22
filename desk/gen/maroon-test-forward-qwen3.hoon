::  Run a single Qwen3 forward pass on hardcoded prompt tokens; print argmax
::  and first-5 of intermediate layer outputs for diff against verify_qwen3.py.
::
::  Usage: +saloon!maroon-test-forward-qwen3
::
::  Reference (numpy on Bonsai-1.7B for tokens [1124 1234 1345 1456]):
::    embed last-row first5: [.0.030273 .0.030273 .0 .0 .0.030273]
::    after final-LN first5: [.-0.7293 .0.0074 .-0.4668 .-0.0083 .0.5680]
::    argmax token: 81
::
/-  ls=lagoon
/+  *lagoon, math, saloon, maroon
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %noun
=/  pat=path  /(scot %p p.bec)/(scot %tas q.bec)/(scot %da now)/weights/qwen3-bonsai/jam
=/  jam-res  (mule |.(.^(@ %cx pat)))
?:  ?=(%| -.jam-res)  ~|(%need-qwen3-bonsai-jam !!)
~&  >  "loaded jam ({<(met 3 p.jam-res)>} bytes), cueing..."
=/  weights  ;;(model-weights-qwen3:maroon (cue p.jam-res))
~&  >  'cue done'
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
=/  tokens=(list @ud)  ~[1.124 1.234 1.345 1.456]
~&  >  ['running forward on tokens' tokens]
=/  logits  (forward-qwen3:mr:maroon tokens weights cfg)
=/  argmax  (argmax-token:mr:maroon logits)
~&  >  ['HN argmax token' argmax]
~&  >  '(numpy reference says: 81)'
argmax
