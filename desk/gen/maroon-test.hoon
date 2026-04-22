::  Generate tiny test weights and run inference via %maroon agent
::
/-  ls=lagoon
/+  *lagoon,
    math,
    saloon,
    maroon
::
:-  %say
|=  [[* eny=@uv *] ~ ~]
:-  %noun
::  build tiny model: d=4, heads=1, layers=1, vocab=8, seq=4
=/  la  (lake %n)
=/  mk  |=([s=(list @) b=@] (ones:la [s b %i754 ~]))
=/  mk-lin
  |=  [[di=@ do=@] b=@]
  ^-  linear-weights:maroon
  [[%fp (mk ~[di do] b)] (mk ~[1 do] b)]
::
=/  cfg=model-config:maroon
  [d-model=4 n-heads=1 n-layers=1 d-ff=8 vocab-size=8 max-seq=4 bloq=5]
::
=/  wq  (mk-lin [4 4] 5)
=/  wk  (mk-lin [4 4] 5)
=/  wv  (mk-lin [4 4] 5)
=/  wo  (mk-lin [4 4] 5)
=/  ln-g  (mk ~[4] 5)
=/  ln-b  (zeros:la [~[4] 5 %i754 ~])
=/  ff1  (mk-lin [4 8] 5)
=/  ff2  (mk-lin [8 4] 5)
=/  blk=block-weights:maroon
  [wq wk wv wo ln-g ln-b ln-g ln-b ff1 ff2]
=/  weights=model-weights:maroon
  :*  tok-emb=(mk ~[8 4] 5)
      pos-emb=(mk ~[4 4] 5)
      blocks=~[blk]
      ln-f-g=ln-g
      ln-f-b=ln-b
      out-proj=(mk ~[4 8] 5)
  ==
::
~&  >  "running forward pass on tokens [0 1 2]..."
=/  logits  (forward:mr:maroon ~[0 1 2] weights cfg)
=/  next  (argmax-token:mr:maroon logits)
~&  >  "logits shape: {<shape.meta.logits>}"
~&  >  "next token: {<next>}"
next
