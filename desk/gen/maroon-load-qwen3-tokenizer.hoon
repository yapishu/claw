::  Load Qwen3 BBPE tokenizer from /weights/qwen3-tokenizer.jam.
::
::  Generate with:
::    gguf2jam --arch tokenizer <hf-tokenizer.json> -o qwen3-tokenizer.jam
::  Put into your pier at saloon/weights/qwen3-tokenizer.jam then |commit.
::
::  Pokes %maroon with %maroon-load-tokenizer (same mark as gpt2; the on-poke
::  handler just calls cue-tokenizer:tokenizer which is BBPE-generic).
::
::  Special tokens (<|im_start|>, <|im_end|>, <think>, etc.) are recognized
::  as single token IDs — gguf2jam extracts them from `added_tokens` and
::  the Hoon encoder splits on them before BPE.  Chat templates work.
::
::  Known minor gap: our pre-tokenize regex is GPT-2's, not Qwen3's.  For
::  plain English text they agree on almost every boundary; for some
::  unicode and contractions the splits may differ, producing slightly
::  different (but still valid) token sequences than HF.  Decode is
::  unaffected; generation quality is basically unchanged.
::
:-  %say
|=  [[now=@da eny=@uv bec=beak] ~ ~]
:-  %maroon-load-tokenizer
::
=/  path  /(scot %p p.bec)/(scot %tas q.bec)/(scot %da now)/weights/qwen3-tokenizer/jam
=/  jam-res  (mule |.(.^(@ %cx path)))
?:  ?=(%| -.jam-res)
  ~&  >>>  'tokenizer not found at /weights/qwen3-tokenizer.jam'
  ~&  >>>  'generate with: gguf2jam --arch tokenizer <hf-tokenizer.json> -o qwen3-tokenizer.jam'
  ~|  %no-tokenizer-file
  !!
~&  >  "loaded qwen3-tokenizer.jam ({<(met 3 p.jam-res)>} bytes)"
p.jam-res
