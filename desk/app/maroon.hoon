  ::
::::  %maroon - on-ship transformer inference agent
::
::  Holds model weights in state. HTTP endpoint at /apps/maroon/chat.
::
/-  ls=lagoon
/+  default-agent,
    dbug,
    server,
    *lagoon,
    math,
    saloon,
    maroon,
    tokenizer=gpt2-tokenizer
::
|%
+$  versioned-state
  $%  [%0 state-0]
  ==
+$  state-0
  $:  weights=(unit model-weights:maroon)
      config=(unit model-config:maroon)
      last-output=(list @ud)
      tok=(unit tokenizer-maps:tokenizer)
      gen=(unit gen-state)
      weights-qwen3=(unit model-weights-qwen3:maroon)
      config-qwen3=(unit model-config-qwen3:maroon)
  ==
::  Generation is tick-based so long CPU forwards don't exceed Vere's ~45s
::  HTTP chunk idle timeout.  Two tick modes:
::    %single       - whole forward per tick.  Used when the forward is
::                    fast enough (GPU-ready models, or any model small
::                    enough that one token fits under the timeout).
::    %block-stream - GPT-2 legacy: embed+pos on the first tick, one
::                    transformer block per subsequent tick, emit
::                    keepalive pings between ticks.  Needed when the
::                    CPU forward would exceed the timeout.
::
::  Which mode a given load uses lives in +default-tick-mode.  Anything
::  added to +forward-loaded with no stream impl defaults to %single.
+$  tick-mode  ?(%single %block-stream)
+$  gen-state
  $:  eyre-id=@ta
      tokens=(list @ud)        ::  prompt + tokens generated so far
      n-remaining=@ud
      strategy=sampling:mr:maroon
      step=@ud                  ::  for entropy mixing
      start=@da                 ::  when generation began
      last-tick=@da             ::  when the last tick event fired
      n-prompt=@ud              ::  length of the original prompt
      mode=tick-mode
      phase=?(%new %block %final)  ::  only used when mode = %block-stream
      block-idx=@ud             ::  next block to compute (mode = %block-stream)
      x=(unit tensor:maroon)    ::  intermediate activations across events
      cos=(unit tensor:maroon)  ::  RoPE cos table (qwen3 block-stream only)
      sin=(unit tensor:maroon)  ::  RoPE sin table (qwen3 block-stream only)
      text-sent=@ud             ::  bytes of decoded text emitted to client;
                                ::  tracks UTF-8 codepoint boundaries so
                                ::  multi-byte characters never arrive split.
      text-decoded=@t           ::  incrementally accumulated decoded text of
                                ::  all generated tokens so far.  Saves having
                                ::  to re-decode the full token list each step
                                ::  (O(N) → O(1) per tick).
      rope-cs=(unit [cos=tensor:maroon sin=tensor:maroon])
                                ::  precomputed rope cos/sin tables covering
                                ::  the whole generation's max seq length.
                                ::  Same atom on every tick so the VRAM cache
                                ::  hits; kernel only reads first `seq-len`
                                ::  rows each call.
      kv-session=@ud            ::  unique-per-generation session id;
                                ::  keys the VRAM-resident KV buffers
                                ::  shared by prefill + all decode steps.
      kv-max-seq=@ud            ::  max seq length allocated for KV buffers
                                ::  at prefill time — decode writes up to here.
      prefilled=?               ::  has the first forward (populating KV
                                ::  buffers) already run?  Drives prefill-vs-
                                ::  decode branching.
      api=?(%maroon %openai %poke)
                                ::  response format.  %maroon/%openai go
                                ::  through Eyre as HTTP.  %poke skips HTTP
                                ::  entirely: on done, poke the caller
                                ::  back with a %maroon-chat-resp cage.
                                ::  Used for same-ship claw→maroon calls.
      stream=?                  ::  SSE-streaming vs buffered single response
                                ::  (OpenAI `stream` param).  %.y for %maroon.
                                ::  always %.n for %poke.
      response-id=@t            ::  echoed in every OpenAI chunk as `id`
      model-name=@t             ::  echoed in every OpenAI chunk as `model`
      poke-caller=@p            ::  ship to poke back when api=%poke
      poke-req-id=@t            ::  req-id to include in response poke
      poke-meta=*               ::  opaque noun echoed back in response poke
  ==
+$  card  card:agent:gall
::
::  Build an SSE data event body from a JSON payload.
::  Format: "data: <payload>\n\n"
::
++  sse-event-data
  |=  payload=@t
  ^-  octs
  =/  body  (rap 3 ~['data: ' payload (rap 3 ~[10 10])])
  [(met 3 body) body]
::
::  SSE comment (keepalive). Clients ignore lines starting with ':'.
::  Sending one resets Vere's HTTP chunk idle timeout.
::
++  ping-verbs
  ^-  (list @t)
  :~  'Accomplishing'  'Actioning'  'Actualizing'  'Architecting'
      'Baking'  'Beaming'  'Beboppin\''  'Befuddling'  'Billowing'
      'Blanching'  'Bloviating'  'Boogieing'  'Boondoggling'  'Booping'
      'Bootstrapping'  'Brewing'  'Bunning'  'Burrowing'  'Calculating'
      'Canoodling'  'Caramelizing'  'Cascading'  'Catapulting'
      'Cerebrating'  'Channeling'  'Channelling'  'Choreographing'
      'Churning'  'Clauding'  'Coalescing'  'Cogitating'  'Combobulating'
      'Composing'  'Computing'  'Concocting'  'Considering'
      'Contemplating'  'Cooking'  'Crafting'  'Creating'  'Crunching'
      'Crystallizing'  'Cultivating'  'Deciphering'  'Deliberating'
      'Determining'  'Dilly-dallying'  'Discombobulating'  'Doing'
      'Doodling'  'Drizzling'  'Ebbing'  'Effecting'  'Elucidating'
      'Embellishing'  'Enchanting'  'Envisioning'  'Evaporating'
      'Fermenting'  'Fiddle-faddling'  'Finagling'  'Flambéing'
      'Flibbertigibbeting'  'Flowing'  'Flummoxing'  'Fluttering'
      'Forging'  'Forming'  'Frolicking'  'Frosting'  'Gallivanting'
      'Galloping'  'Garnishing'  'Generating'  'Gesticulating'
      'Germinating'  'Gitifying'  'Grooving'  'Gusting'  'Harmonizing'
      'Hashing'  'Hatching'  'Herding'  'Honking'  'Hullaballooing'
      'Hyperspacing'  'Ideating'  'Imagining'  'Improvising'
      'Incubating'  'Inferring'  'Infusing'  'Ionizing'  'Jitterbugging'
      'Julienning'  'Kneading'  'Leavening'  'Levitating'  'Lollygagging'
      'Manifesting'  'Marinating'  'Meandering'  'Metamorphosing'
      'Misting'  'Moonwalking'  'Moseying'  'Mulling'  'Mustering'
      'Musing'  'Nebulizing'  'Nesting'  'Newspapering'  'Noodling'
      'Nucleating'  'Orbiting'  'Orchestrating'  'Osmosing'
      'Perambulating'  'Percolating'  'Perusing'  'Philosophising'
      'Photosynthesizing'  'Pollinating'  'Pondering'  'Pontificating'
      'Pouncing'  'Precipitating'  'Prestidigitating'  'Processing'
      'Proofing'  'Propagating'  'Puttering'  'Puzzling'  'Quantumizing'
      'Razzle-dazzling'  'Razzmatazzing'  'Recombobulating'
      'Reticulating'  'Roosting'  'Ruminating'  'Sautéing'  'Scampering'
      'Schlepping'  'Scurrying'  'Seasoning'  'Shenaniganing'
      'Shimmying'  'Simmering'  'Skedaddling'  'Sketching'  'Slithering'
      'Smooshing'  'Sock-hopping'  'Spelunking'  'Spinning'  'Sprouting'
      'Stewing'  'Sublimating'  'Swirling'  'Swooping'  'Symbioting'
      'Synthesizing'  'Tempering'  'Thinking'  'Thundering'  'Tinkering'
      'Tomfoolering'  'Topsy-turvying'  'Transfiguring'  'Transmuting'
      'Twisting'  'Undulating'  'Unfurling'  'Unravelling'  'Vibing'
      'Waddling'  'Wandering'  'Warping'  'Whatchamacalliting'
      'Whirlpooling'  'Whirring'  'Whisking'  'Wibbling'  'Working'
      'Wrangling'  'Zesting'  'Zigzagging'
  ==
::
++  sse-event-ping
  |=  eny=@
  ^-  octs
  =/  vs  ping-verbs
  =/  verb  (snag (mod eny (lent vs)) vs)
  =/  body  (rap 3 ~[': ' verb '...' (rap 3 ~[10 10])])
  [(met 3 body) body]
::
::  Unix-epoch seconds from urbit @da — OpenAI `created` field.
::  Urbit @da counts 2^64-ticks per second from its epoch; ~1970.1.1
::  is about 291·365·2^64 ticks before that.  The difference in @da
::  units, right-shifted by 64, gives seconds.
::
++  da-to-unix
  |=  d=@da  ^-  @ud
  =/  diff  (sub d ~1970.1.1)
  (rsh [6 1] diff)
::
::  Render a Qwen3 ChatML prompt from OpenAI-style messages.
::  Produces `<|im_start|>{role}\n{content}<|im_end|>\n` per message,
::  with a trailing `<|im_start|>assistant\n` to prompt the reply.
::
++  render-qwen3-chat
  |=  msgs=(list json)
  ^-  @t
  =|  parts=(list @t)
  |-  ^-  @t
  ?~  msgs
    (rap 3 (snoc parts (rap 3 ~['<|im_start|>assistant' 10])))
  =/  role-opt=(unit @t)
    %.  i.msgs
    %-  ot:dejs-soft:format
    :~  [%role so:dejs-soft:format]
    ==
  =/  content-opt=(unit @t)
    %.  i.msgs
    %-  ot:dejs-soft:format
    :~  [%content so:dejs-soft:format]
    ==
  ?:  ?=(~ role-opt)  $(msgs t.msgs)
  =/  role=@t  u.role-opt
  =/  content=@t  ?~(content-opt '' u.content-opt)
  ::  tool-result messages are mapped into the Hermes `<tool_response>`
  ::  form so qwen3 recognises them as a reply to its tool_call.  role
  ::  becomes `user` so chatml stays valid.
  ?:  =(role 'tool')
    =/  piece=@t
      %+  rap  3
      :~  '<|im_start|>user'  10
          '<tool_response>\0a'  content  '\0a</tool_response>'
          10  '<|im_end|>'  10
      ==
    $(msgs t.msgs, parts (snoc parts piece))
  =/  piece=@t
    %+  rap  3
    :~  '<|im_start|>'  role  10
        content         '<|im_end|>'  10
    ==
  $(msgs t.msgs, parts (snoc parts piece))
::
::  OpenAI chat.completion.chunk builder.  `kind` picks the delta
::  shape (first role chunk / content chunk / final finish_reason).
::
++  openai-chunk
  |=  $:  id=@t
          model=@t
          created=@da
          kind=?(%role %content %final)
          content=@t
          finish=@t
      ==
  ^-  @t
  =/  delta-entries=(list [@t json])
    ?-  kind
      %role     ~[['role' s+'assistant']]
      %content  ~[['content' s+content]]
      %final    ~
    ==
  =/  delta=json  [%o (~(gas by *(map @t json)) delta-entries)]
  =/  choice-entries=(list [@t json])
    =/  base=(list [@t json])
      ~[['index' (numb:enjs:format 0)] ['delta' delta]]
    ?:  ?=(%final kind)
      (snoc base ['finish_reason' s+finish])
    base
  =/  choice=json  [%o (~(gas by *(map @t json)) choice-entries)]
  =/  obj=json
    :-  %o
    %-  ~(gas by *(map @t json))
    :~  ['id' s+id]
        ['object' s+'chat.completion.chunk']
        ['created' (numb:enjs:format (da-to-unix created))]
        ['model' s+model]
        ['choices' [%a ~[choice]]]
    ==
  (en:json:html obj)
::
::  Full (non-streaming) chat.completion body.
::
++  openai-completion
  |=  $:  id=@t
          model=@t
          created=@da
          content=@t
          finish=@t
          prompt-tokens=@ud
          completion-tokens=@ud
      ==
  ^-  @t
  =/  message=json
    :-  %o
    %-  ~(gas by *(map @t json))
    :~  ['role' s+'assistant']
        ['content' s+content]
    ==
  =/  choice=json
    :-  %o
    %-  ~(gas by *(map @t json))
    :~  ['index' (numb:enjs:format 0)]
        ['message' message]
        ['finish_reason' s+finish]
    ==
  =/  usage=json
    :-  %o
    %-  ~(gas by *(map @t json))
    :~  ['prompt_tokens' (numb:enjs:format prompt-tokens)]
        ['completion_tokens' (numb:enjs:format completion-tokens)]
        ['total_tokens' (numb:enjs:format (add prompt-tokens completion-tokens))]
    ==
  =/  obj=json
    :-  %o
    %-  ~(gas by *(map @t json))
    :~  ['id' s+id]
        ['object' s+'chat.completion']
        ['created' (numb:enjs:format (da-to-unix created))]
        ['model' s+model]
        ['choices' [%a ~[choice]]]
        ['usage' usage]
    ==
  (en:json:html obj)
::
::  Model dispatch.  The orchestration code (HTTP handler, gen-tick)
::  never references a specific model by name — it goes through these
::  helpers.  Adding a new model type:
::    1. add (unit ...) state fields for its weights + config
::    2. add a clause to +forward-loaded
::    3. add a clause to +default-tick-mode iff the model needs
::       block-stream (otherwise it gets %single, which works for any
::       model whose forward fits under Vere's HTTP chunk timeout).
::
::  +model-loaded: does any model have both weights and config?
::
++  model-loaded
  |=  s=state-0
  ^-  ?
  ?|  ?&(?=(^ weights-qwen3.s) ?=(^ config-qwen3.s))
      ?&(?=(^ weights.s) ?=(^ config.s))
  ==
::
::  +forward-loaded: run a whole-forward for the loaded model, returning
::  logits, or ~ if nothing is loaded.  Called by scries and by the
::  %single-mode tick.
::
++  forward-loaded
  |=  [s=state-0 tokens=(list @ud)]
  ^-  (unit tensor:maroon)
  ?:  ?&(?=(^ weights-qwen3.s) ?=(^ config-qwen3.s))
    `(forward-qwen3:mr:maroon tokens u.weights-qwen3.s u.config-qwen3.s)
  ?:  ?&(?=(^ weights.s) ?=(^ config.s))
    `(forward:mr:maroon tokens u.weights.s u.config.s)
  ~
::
::  +default-tick-mode: per-loaded-model tick strategy.  GPT-2 is the
::  only backend with a %block-stream implementation today; everything
::  else defaults to %single.
::
++  default-tick-mode
  |=  s=state-0
  ^-  tick-mode
  ::  Qwen3 on GPU runs a full forward in well under a second — faster
  ::  than ~500 ms of per-tick Gall/behn overhead times 29 ticks.  Ship
  ::  it as %single.  GPT-2 on CPU still needs %block-stream to stay
  ::  under the HTTP chunk timeout.  Picks mode per loaded model:
  ?:  ?&  ?=(^ weights.s)
          ?=(^ config.s)
          ?=(~ weights-qwen3.s)
      ==
    %block-stream
  %single
::
::  +last-utf8-boundary: largest k <= n such that text[0..k] ends at a
::  complete UTF-8 codepoint boundary.  Used to hold back partial bytes
::  of multi-byte characters (emoji etc.) until the next token delivers
::  the remaining bytes — otherwise the client receives mojibake.
::
++  last-utf8-boundary
  |=  [text=@t n=@ud]
  ^-  @ud
  ?:  =(0 n)  0
  =/  i  (dec n)
  |-  ^-  @ud
  =/  b  (cut 3 [i 1] text)
  ?:  (lth b 0x80)  n                          ::  ASCII at end: complete
  ?:  =(2 (rsh [0 6] b))                       ::  10xxxxxx continuation
    ?:  =(0 i)  0
    $(i (dec i))
  ::  leading byte b at position i — how many bytes does it start?
  =/  need
    ?:  =(6 (rsh [0 5] b))
      2
    ?:  =(14 (rsh [0 4] b))
      3
    ?:  =(30 (rsh [0 3] b))
      4
    1
  =/  have  (add 1 (sub (dec n) i))
  ?:  (gte have need)  n
  i
::
::  +auto-load-qwen3: scry qwen3 weights + tokenizer from Clay when they
::  aren't already in state, then pre-warm VRAM.  Top-level helper
::  (not an agent arm) so the agent door stays at the required 10 arms.
::
++  auto-load-qwen3
  |=  [=bowl:gall s=state-0]
  ^-  state-0
  =.  s
    ?:  ?=(^ weights-qwen3.s)  s
    =/  path=^path
      /(scot %p our.bowl)/(scot %tas q.byk.bowl)/(scot %da now.bowl)/weights/qwen3-bonsai/jam
    =/  res  (mule |.(.^(@ %cx path)))
    ?:  ?=(%| -.res)
      ~&  >>>  '%maroon: qwen3 weights missing at /weights/qwen3-bonsai/jam (run :maroon &maroon-load-qwen3 +claw!maroon-load-qwen3)'
      s
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
    =/  w  ;;(model-weights-qwen3:maroon (cue p.res))
    ~&  >  '%maroon: auto-loaded qwen3 weights'
    s(weights-qwen3 `w, config-qwen3 `cfg)
  =.  s
    ?:  ?=(^ tok.s)  s
    =/  path=^path
      /(scot %p our.bowl)/(scot %tas q.byk.bowl)/(scot %da now.bowl)/weights/qwen3-tokenizer/jam
    =/  res  (mule |.(.^(@ %cx path)))
    ?:  ?=(%| -.res)
      ~&  >>>  '%maroon: qwen3 tokenizer missing at /weights/qwen3-tokenizer/jam (run :maroon &maroon-load-tokenizer +claw!maroon-load-qwen3-tokenizer)'
      s
    =/  t  (cue-tokenizer:tokenizer p.res)
    ~&  >  '%maroon: auto-loaded qwen3 tokenizer'
    s(tok `t)
  ::  Pre-warm VRAM: uploads every weight data atom to the cache so the
  ::  first inference doesn't pay per-block upload cost.  Idempotent on
  ::  probe-hit; re-uploads cold state if the ship process restarted
  ::  while the pier kept its weights in loom memory.
  ?.  ?&(?=(^ weights-qwen3.s) ?=(^ config-qwen3.s))  s
  =/  n  (warm-weights:maroon (qwen3-weight-atoms:maroon u.weights-qwen3.s))
  ?:  =(0 n)  s
  ~&  >  "%maroon: warmed {<n>} weights into VRAM"
  s
--
::
%-  agent:dbug
=|  state-0
=*  state  -
^-  agent:gall
|_  =bowl:gall
+*  this  .
    def   ~(. (default-agent this %|) bowl)
::
++  on-init
  ^-  (quip card _this)
  ~&  >  '%maroon initialized — bound at /apps/maroon/chat + /apps/maroon/v1'
  :_  this
  :~  [%pass /eyre/connect %arvo %e %connect [~ /apps/maroon/chat] dap.bowl]
      [%pass /eyre/connect-v1 %arvo %e %connect [~ /apps/maroon/v1] dap.bowl]
  ==
::
++  on-save   !>(state)
++  on-load
  |=  old-state=vase
  ^-  (quip card _this)
  ::  always rebind on every reload so eyre keeps mapping both paths
  ::  (api + ui) to us across agent revives and vere restarts.
  =/  rebind-cards=(list card)
    :~  [%pass /eyre/connect %arvo %e %connect [~ /apps/maroon/chat] dap.bowl]
        [%pass /eyre/connect-v1 %arvo %e %connect [~ /apps/maroon/v1] dap.bowl]
    ==
  ::  1. Typed vase extract — fast path when the stored type nests under
  ::  the current one (no schema drift).
  =/  recovered=state-0
    =/  typed  (mule |.(!<(versioned-state old-state)))
    ?:  ?=(%& -.typed)
      ?-  -.p.typed
        %0  +.p.typed
      ==
    ::  2. Structural cast on the raw noun.  Handles the common case where
    ::  rebuilding /lib/*.hoon invalidates the stored vase's type reference
    ::  but the underlying noun layout is unchanged — so weights and
    ::  tokenizer don't need to be reloaded after every commit.
    =/  raw  (mule |.(;;(versioned-state q.old-state)))
    ?:  ?=(%& -.raw)
      ?-  -.p.raw
        %0
          ~&  >  '%maroon: on-load recovered state via structural cast'
          +.p.raw
      ==
    ::  3. Real schema change — reset; reload payloads below.
    ~&  >>  '%maroon: on-load could not recover state, resetting'
    *state-0
  [rebind-cards this(state (auto-load-qwen3 bowl recovered))]
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+    mark  (on-poke:def mark vase)
    ::
    ::  Handle HTTP request on /apps/maroon/chat
    ::
      %handle-http-request
    |^
    =+  !<([eyre-id=@ta req=inbound-request:eyre] vase)
    =/  rl=request-line:server  (parse-request-line:server url.request.req)
    =/  site=(list @t)  site.rl
    ::  OpenAI-compatible endpoint takes precedence over legacy match
    ::  (the /v1 path is bound separately so it can't fall through to
    ::  /chat's [%apps %maroon %chat *] guard even as a prefix).
    ?:  ?=([%apps %maroon %v1 %chat %completions ~] site)
      (handle-openai eyre-id req)
    ?.  ?=([%apps %maroon %chat *] site)
      :_  this
      (not-found eyre-id)
    ?:  =(%'GET' method.request.req)
      :_  this
      (give-help eyre-id)
    ?.  =(%'POST' method.request.req)
      :_  this
      (give-http eyre-id 405 ~[['content-type' 'text/plain']] (some (as-octs:mimes:html 'method not allowed')))
    =/  body
      ?~  body.request.req  ''
      q.u.body.request.req
    =/  parsed  (de:json:html body)
    ?~  parsed
      :_  this
      (give-http eyre-id 400 ~ (some (as-octs:mimes:html '{"error":"invalid JSON"}')))
    =/  tokens-opt=(unit (list @ud))
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  [%tokens (ar:dejs-soft:format ni:dejs-soft:format)]
      ==
    =/  prompt-opt=(unit @t)
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  [%prompt so:dejs-soft:format]
      ==
    =/  n=(unit @ud)
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  [%n ni:dejs-soft:format]
      ==
    ::  accept numbers OR strings for float params — JSON numbers lose
    ::  precision for fp32 literals, so clients often send strings.
    =/  num-or-str=$-(json (unit @ta))
      |=  j=json  ^-  (unit @ta)
      ?+  j  ~
        [%n *]  `p.j
        [%s *]  `p.j
      ==
    =/  temperature=(unit @ta)
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  [%temperature num-or-str]
      ==
    =/  top-k-opt=(unit @ud)
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  ['top_k' ni:dejs-soft:format]
      ==
    =/  top-p-opt=(unit @ta)
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  ['top_p' num-or-str]
      ==
    =/  rep-pen-opt=(unit @ta)
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  ['repetition_penalty' num-or-str]
      ==
    ?.  (model-loaded state)
      :_  this
      (give-http eyre-id 503 ~ (some (as-octs:mimes:html '{"error":"no model loaded"}')))
    ::  single-slot generator: reject overlap (see note in handle-openai).
    ?^  gen
      %-  (slog leaf+"SSE /apps/maroon/chat: busy, rejecting overlapping request" ~)
      :_  this
      (give-http eyre-id 503 ~[['retry-after' '5']] (some (as-octs:mimes:html '{"error":"busy: a generation is already in progress"}')))
    =/  tokens=(list @ud)
      ?^  tokens-opt  u.tokens-opt
      ?~  prompt-opt  ~
      ?~  tok  ~
      (encode:tokenizer u.tok u.prompt-opt)
    ?:  =(~ tokens)
      :_  this
      (give-http eyre-id 400 ~ (some (as-octs:mimes:html '{"error":"provide tokens or prompt (and load tokenizer)"}')))
    ::  max_tokens: hard upper bound.  Generation also stops early on an
    ::  EOS token (see %single handler).  Default 128 is a sensible
    ::  chat default.
    =/  n-tokens  (fall n 128)
    ::  Defaults: temp=0.7, top-p=0.9, rep-penalty=1.2, top-k disabled.
    ::  Clients can override any of them; setting top_p=1.0 disables it, etc.
    ::  slav %rs needs the `.` prefix (so '.5' parses as 5.0 but '5' bails);
    ::  normalize so JSON `5.0` and `"5.0"` both work.
    =/  to-rs
      |=  c=@ta  ^-  @rs
      =/  s=@t  ?:(=('.' (end 3 c)) c (rap 3 ~['.' c]))
      (slav %rs s)
    =/  strategy=sampling:mr:maroon
      :*  temp=?~(temperature .0.7 (to-rs u.temperature))
          top-k=(fall top-k-opt 0)
          top-p=?~(top-p-opt .0.9 (to-rs u.top-p-opt))
          rep-penalty=?~(rep-pen-opt .1.2 (to-rs u.rep-pen-opt))
      ==
    ~&  >  "SSE /apps/maroon/chat: streaming {<n-tokens>} tokens..."
    ::  Open SSE stream: send headers and the prompt as the first event
    =/  sse-headers
      ^-  (list [@t @t])
      :~  ['content-type' 'text/event-stream']
          ['cache-control' 'no-cache']
          ['x-accel-buffering' 'no']
      ==
    =/  sampling-json=json
      :-  %o
      %-  ~(gas by *(map @t json))
      :~  ['temperature' s+(scot %rs temp.strategy)]
          ['top_k' (numb:enjs:format top-k.strategy)]
          ['top_p' s+(scot %rs top-p.strategy)]
          ['repetition_penalty' s+(scot %rs rep-penalty.strategy)]
      ==
    =/  prompt-event
      =/  prompt-json=json
        :-  %o
        %-  ~(gas by *(map @t json))
        :~  ['type' s+'prompt']
            ['tokens' [%a (turn tokens numb:enjs:format)]]
            ['sampling' sampling-json]
        ==
      (sse-event-data (en:json:html prompt-json))
    =/  resp-header=response-header:http  [200 sse-headers]
    =/  cards=(list card)
      :~  [%give %fact ~[/http-response/[eyre-id]] %http-response-header !>(resp-header)]
          [%give %fact ~[/http-response/[eyre-id]] %http-response-data !>(`prompt-event)]
          [%pass /gen-tick %arvo %b %wait now.bowl]
      ==
    ::  Stash the in-progress generation, picking tick mode per model.
    ::  Session ID: fresh per generation so simultaneous chats don't
    ::  collide.  Derived from `eny` so it's unpredictable without
    ::  tying to content (which would leak across identical prompts).
    =/  seed=@  (end [0 31] (mix eny.bowl `@`now.bowl))
    =/  session-id=@ud  ?:(=(0 seed) 1 `@ud`seed)
    =/  max-seq=@ud  (add (lent tokens) n-tokens)
    =/  new-gen=gen-state
      :*  eyre-id  tokens  n-tokens  strategy  0
          now.bowl  now.bowl  (lent tokens)
          (default-tick-mode state)
          %new  0  ~  ~  ~  0
          ''                   ::  text-decoded: starts empty
          ~                    ::  rope-cs: lazy-compute on first tick
          session-id           ::  kv-session
          max-seq              ::  kv-max-seq
          |                    ::  prefilled: false until first forward
          %maroon              ::  api: legacy format
          &                    ::  stream: always SSE for legacy
          ''                   ::  response-id: unused for %maroon
          ''                   ::  model-name: unused for %maroon
          ~zod                 ::  poke-caller: unused for HTTP
          ''                   ::  poke-req-id: unused for HTTP
          0                    ::  poke-meta: unused for HTTP
      ==
    [cards this(gen `new-gen)]
    ::
    ++  give-http
      |=  [eyre-id=@ta status=@ud headers=(list [@t @t]) body=(unit octs)]
      ^-  (list card)
      %+  give-simple-payload:app:server  eyre-id
      [[status headers] body]
    ::
    ++  give-json
      |=  [eyre-id=@ta jon=json]
      ^-  (list card)
      %+  give-simple-payload:app:server  eyre-id
      (json-response:gen:server jon)
    ::
    ++  not-found
      |=  eyre-id=@ta
      ^-  (list card)
      (give-http eyre-id 404 ~[['content-type' 'text/plain']] (some (as-octs:mimes:html 'not found')))
    ::
    ++  give-help
      |=  eyre-id=@ta
      ^-  (list card)
      =/  msg  'POST JSON {"tokens":[...], "n":N, "temperature":T?} to this endpoint'
      (give-http eyre-id 200 ~[['content-type' 'text/plain']] (some (as-octs:mimes:html msg)))
    ::
    ::  POST /apps/maroon/v1/chat/completions — OpenAI-compatible chat.
    ::
    ++  handle-openai
      |=  [eyre-id=@ta req=inbound-request:eyre]
      ^-  (quip card _this)
      ?.  =(%'POST' method.request.req)
        :_  this
        (give-http eyre-id 405 ~[['content-type' 'text/plain']] (some (as-octs:mimes:html 'method not allowed')))
      =/  body  ?~(body.request.req '' q.u.body.request.req)
      =/  parsed=(unit json)  (de:json:html body)
      ?~  parsed
        :_  this
        (give-http eyre-id 400 ~[['content-type' 'application/json']] (some (as-octs:mimes:html '{"error":"invalid JSON"}')))
      =/  msgs-opt=(unit (list json))
        %.  u.parsed
        %-  ot:dejs-soft:format
        :~  [%messages (ar:dejs-soft:format |=(j=json `(unit json)`(some j)))]
        ==
      ?~  msgs-opt
        :_  this
        (give-http eyre-id 400 ~[['content-type' 'application/json']] (some (as-octs:mimes:html '{"error":"messages required"}')))
      =/  stream-opt=(unit ?)
        %.  u.parsed
        %-  ot:dejs-soft:format
        :~  [%stream bo:dejs-soft:format]
        ==
      =/  model-opt=(unit @t)
        %.  u.parsed
        %-  ot:dejs-soft:format
        :~  [%model so:dejs-soft:format]
        ==
      =/  max-tokens-opt=(unit @ud)
        %.  u.parsed
        %-  ot:dejs-soft:format
        :~  ['max_tokens' ni:dejs-soft:format]
        ==
      =/  num-or-str=$-(json (unit @ta))
        |=  j=json  ^-  (unit @ta)
        ?+  j  ~
          [%n *]  `p.j
          [%s *]  `p.j
        ==
      =/  temperature=(unit @ta)
        %.  u.parsed
        %-  ot:dejs-soft:format
        :~  [%temperature num-or-str]
        ==
      =/  top-p-opt=(unit @ta)
        %.  u.parsed
        %-  ot:dejs-soft:format
        :~  ['top_p' num-or-str]
        ==
      ?.  (model-loaded state)
        :_  this
        (give-http eyre-id 503 ~[['content-type' 'application/json']] (some (as-octs:mimes:html '{"error":"no model loaded"}')))
      ?~  tok
        :_  this
        (give-http eyre-id 503 ~[['content-type' 'application/json']] (some (as-octs:mimes:html '{"error":"no tokenizer loaded"}')))
      ::  single-slot generator: reject overlap so two requests don't
      ::  clobber `gen` and spawn duplicate /gen-tick behns.
      ?^  gen
        %-  (slog leaf+"/v1/chat/completions: busy, rejecting overlapping request" ~)
        :_  this
        (give-http eyre-id 503 ~[['content-type' 'application/json'] ['retry-after' '5']] (some (as-octs:mimes:html '{"error":"busy: a generation is already in progress"}')))
      =/  prompt-text=@t  (render-qwen3-chat u.msgs-opt)
      =/  tokens=(list @ud)  (encode:tokenizer u.tok prompt-text)
      ?:  =(~ tokens)
        :_  this
        (give-http eyre-id 400 ~[['content-type' 'application/json']] (some (as-octs:mimes:html '{"error":"empty prompt after tokenization"}')))
      =/  n-tokens=@ud  (fall max-tokens-opt 128)
      =/  to-rs
        |=  c=@ta  ^-  @rs
        =/  s=@t  ?:(=('.' (end 3 c)) c (rap 3 ~['.' c]))
        (slav %rs s)
      =/  strategy=sampling:mr:maroon
        :*  temp=?~(temperature .0.7 (to-rs u.temperature))
            top-k=0
            top-p=?~(top-p-opt .0.9 (to-rs u.top-p-opt))
            rep-penalty=.1.2
        ==
      =/  stream=?  (fall stream-opt |)
      =/  model-name=@t  (fall model-opt 'qwen3')
      =/  response-id=@t  'chatcmpl-session'
      ~&  >  "/v1/chat/completions: {<(lent tokens)>} prompt tokens, max {<n-tokens>}, stream={<stream>}"
      =/  seed=@  (end [0 31] (mix eny.bowl `@`now.bowl))
      =/  session-id=@ud  ?:(=(0 seed) 1 `@ud`seed)
      =/  max-seq=@ud  (add (lent tokens) n-tokens)
      =/  initial-cards=(list card)
        ?.  stream
          :~  [%pass /gen-tick %arvo %b %wait now.bowl]
          ==
        =/  sse-headers=(list [@t @t])
          :~  ['content-type' 'text/event-stream']
              ['cache-control' 'no-cache']
              ['x-accel-buffering' 'no']
              ['access-control-allow-origin' '*']
          ==
        =/  resp-header=response-header:http  [200 sse-headers]
        =/  role-chunk
          (openai-chunk response-id model-name now.bowl %role '' '')
        :~  [%give %fact ~[/http-response/[eyre-id]] %http-response-header !>(resp-header)]
            [%give %fact ~[/http-response/[eyre-id]] %http-response-data !>(`(sse-event-data role-chunk))]
            [%pass /gen-tick %arvo %b %wait now.bowl]
        ==
      =/  new-gen=gen-state
        :*  eyre-id  tokens  n-tokens  strategy  0
            now.bowl  now.bowl  (lent tokens)
            (default-tick-mode state)
            %new  0  ~  ~  ~  0
            ''                   ::  text-decoded
            ~                    ::  rope-cs
            session-id           ::  kv-session
            max-seq              ::  kv-max-seq
            |                    ::  prefilled
            %openai              ::  api
            stream               ::  stream
            response-id
            model-name
            ~zod                 ::  poke-caller: unused for HTTP
            ''                   ::  poke-req-id: unused for HTTP
            0                    ::  poke-meta: unused for HTTP
        ==
      [initial-cards this(gen `new-gen)]
    --
    ::
    ::  Direct same-ship chat request (no HTTP).  Caller (typically
    ::  %claw) pokes us with a %maroon-chat-req cage; we generate via
    ::  the existing %single tick path and poke back with a
    ::  %maroon-chat-resp cage when done.  Body is identical to the
    ::  OpenAI /v1/chat/completions request body.
    ::
      %maroon-chat-req
    =+  !<([req-id=@t meta=* body=@t] vase)
    ::  compose an error-response poke back to the caller; we use it
    ::  any time we can't start generation
    =/  err-poke
      |=  [status=@ud msg=@t]
      ^-  card
      =/  err-json=json
        :-  %o
        (~(gas by *(map @t json)) ~[['error' s+msg]])
      =/  body-cord=@t  (en:json:html err-json)
      :*  %pass  /maroon-resp/[req-id]
          %agent  [src.bowl %claw]  %poke
          %maroon-chat-resp  !>([req-id meta status body-cord])
      ==
    ?.  (model-loaded state)
      :_  this
      ~[(err-poke 503 'no model loaded')]
    ?~  tok
      :_  this
      ~[(err-poke 503 'no tokenizer loaded')]
    ?^  gen
      %-  (slog leaf+"%maroon-chat-req: busy, rejecting overlapping request" ~)
      :_  this
      ~[(err-poke 503 'busy: a generation is already in progress')]
    =/  parsed=(unit json)  (de:json:html body)
    ?~  parsed
      :_  this
      ~[(err-poke 400 'invalid JSON')]
    =/  msgs-opt=(unit (list json))
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  [%messages (ar:dejs-soft:format |=(j=json `(unit json)`(some j)))]
      ==
    ?~  msgs-opt
      :_  this
      ~[(err-poke 400 'messages required')]
    =/  model-opt=(unit @t)
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  [%model so:dejs-soft:format]  ==
    =/  max-tokens-opt=(unit @ud)
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  ['max_tokens' ni:dejs-soft:format]  ==
    =/  num-or-str=$-(json (unit @ta))
      |=  j=json  ^-  (unit @ta)
      ?+  j  ~
        [%n *]  `p.j
        [%s *]  `p.j
      ==
    =/  temperature=(unit @ta)
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  [%temperature num-or-str]  ==
    =/  top-p-opt=(unit @ta)
      %.  u.parsed
      %-  ot:dejs-soft:format
      :~  ['top_p' num-or-str]  ==
    =/  prompt-text=@t  (render-qwen3-chat u.msgs-opt)
    =/  tokens=(list @ud)  (encode:tokenizer u.tok prompt-text)
    ?:  =(~ tokens)
      :_  this
      ~[(err-poke 400 'empty prompt after tokenization')]
    =/  n-tokens=@ud  (fall max-tokens-opt 128)
    =/  to-rs
      |=  c=@ta  ^-  @rs
      =/  s=@t  ?:(=('.' (end 3 c)) c (rap 3 ~['.' c]))
      (slav %rs s)
    =/  strategy=sampling:mr:maroon
      :*  temp=?~(temperature .0.7 (to-rs u.temperature))
          top-k=0
          top-p=?~(top-p-opt .0.9 (to-rs u.top-p-opt))
          rep-penalty=.1.2
      ==
    =/  model-name=@t  (fall model-opt 'qwen3')
    =/  response-id=@t  'chatcmpl-session'
    ~&  >  "%maroon-chat-req: {<(lent tokens)>} prompt tokens, max {<n-tokens>}"
    =/  seed=@  (end [0 31] (mix eny.bowl `@`now.bowl))
    =/  session-id=@ud  ?:(=(0 seed) 1 `@ud`seed)
    =/  max-seq=@ud  (add (lent tokens) n-tokens)
    =/  new-gen=gen-state
      :*  ''                   ::  eyre-id: unused for %poke
          tokens  n-tokens  strategy  0
          now.bowl  now.bowl  (lent tokens)
          (default-tick-mode state)
          %new  0  ~  ~  ~  0
          ''                   ::  text-decoded
          ~                    ::  rope-cs
          session-id
          max-seq
          |                    ::  prefilled
          %poke                ::  api: direct poke response
          |                    ::  stream: always buffered for %poke
          response-id
          model-name
          src.bowl             ::  poke-caller
          req-id               ::  poke-req-id
          meta                 ::  poke-meta (echoed back)
      ==
    :_  this(gen `new-gen)
    ~[[%pass /gen-tick %arvo %b %wait now.bowl]]
    ::
      %maroon-load
    =/  payload  !<([model-config:maroon @] vase)
    =/  cfg  -.payload
    =/  jammed  +.payload
    ~&  >  "loading model: d={<d-model.cfg>} heads={<n-heads.cfg>} layers={<n-layers.cfg>} vocab={<vocab-size.cfg>}"
    =/  w  (load-weights:maroon jammed)
    ~&  >  '%maroon model loaded successfully'
    `this(weights `w, config `cfg)
    ::
    ::  Load Qwen3 weights (mlx2-quantized). Payload is [qwen3-cfg jam-atom].
    ::  Weights are cued off the jam atom and stored in state.
    ::
      %maroon-load-qwen3
    =/  payload  !<([model-config-qwen3:maroon @] vase)
    =/  cfg  -.payload
    =/  jammed  +.payload
    ~&  >  "loading qwen3: d={<d-model.cfg>} heads={<n-heads.cfg>} kv-heads={<n-kv-heads.cfg>} layers={<n-layers.cfg>} vocab={<vocab-size.cfg>}"
    =/  w  ;;(model-weights-qwen3:maroon (cue jammed))
    ~&  >  '%maroon qwen3 model loaded successfully'
    =/  n  (warm-weights:maroon (qwen3-weight-atoms:maroon w))
    ?.  (gth n 0)  `this(weights-qwen3 `w, config-qwen3 `cfg)
    ~&  >  "%maroon: warmed {<n>} weights into VRAM"
    `this(weights-qwen3 `w, config-qwen3 `cfg)
    ::
    ::  Load tokenizer from jammed atom (vocab + merges + byte maps)
    ::
      %maroon-load-tokenizer
    =/  jammed  !<(@ vase)
    ~&  >  "loading tokenizer..."
    =/  t  (cue-tokenizer:tokenizer jammed)
    ~&  >  '%maroon tokenizer loaded successfully'
    `this(tok `t)
    ::
      %maroon-infer
    =/  tokens  !<((list @ud) vase)
    ?~  weights
      ~&  >>>  'no model loaded'
      `this
    ?~  config
      `this
    ~&  >  "running inference on {<(lent tokens)>} tokens..."
    =/  logits  (forward:mr:maroon tokens u.weights u.config)
    =/  next-token  (argmax-token:mr:maroon logits)
    ~&  >  "next token: {<next-token>}"
    `this(last-output ~[next-token])
    ::
      %maroon-generate
    =/  req  !<([prompt=(list @ud) n=@ud strategy=sampling:mr:maroon] vase)
    ?~  weights
      ~&  >>>  'no model loaded'
      `this
    ?~  config
      `this
    ~&  >  "generating {<n.req>} tokens from prompt of {<(lent prompt.req)>}..."
    =/  out
      %:  generate:mr:maroon
        prompt.req  n.req
        u.weights  u.config  strategy.req
        eny.bowl
      ==
    ~&  >  "generated: {<out>}"
    `this(last-output out)
  ==
::
++  on-watch
  |=  =path
  ^-  (quip card _this)
  ?+    path  (on-watch:def path)
    [%http-response *]  `this
  ==
++  on-leave  on-leave:def
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  ?+    path  (on-peek:def path)
    [%x %status ~]       ``noun+!>(?~(weights %no-model %model-loaded))
    [%x %config ~]       ?~(config ~ ``noun+!>(u.config))
    [%x %last-output ~]  ``noun+!>(last-output)
    ::  /x/tok-stats — sizes of tokenizer maps (debug)
      [%x %tok-stats ~]
    ?~  tok  ~
    =/  stats=[vocab=@ud inv=@ud merges=@ud bytemap=@ud ibm=@ud]
      :*  ~(wyt by vocab.u.tok)
          ~(wyt by inverse-vocab.u.tok)
          ~(wyt by merges.u.tok)
          ~(wyt by byte-map.u.tok)
          ~(wyt by inverse-byte-map.u.tok)
      ==
    ``noun+!>(stats)
    ::  /x/tok-get-vocab/KEY  — debug: lookup in vocab (given as @ud atom)
      [%x %tok-get-vocab @ ~]
    ?~  tok  ~
    ``noun+!>((~(get by vocab.u.tok) (@t (slav %ud i.t.t.path))))
    ::  /x/tok-get-inv/ID  — debug: look up ID in inverse-vocab
      [%x %tok-get-inv @ ~]
    ?~  tok  ~
    ``noun+!>((~(get by inverse-vocab.u.tok) (slav %ud i.t.t.path)))
    ::  /x/wo-bias-shape — inspect first block's wo.b shape (debug)
      [%x %wo-bias-shape ~]
    ?~  weights  ~
    =/  blks  blocks.u.weights
    ?~  blks  ~
    ``noun+!>(`(list @)`shape.meta.b.wo.i.blks)
    ::  /x/wo-w-tag — inspect first block's wo.w tag (%fp or %q8)
      [%x %wo-w-tag ~]
    ?~  weights  ~
    =/  blks  blocks.u.weights
    ?~  blks  ~
    ``noun+!>(-.w.wo.i.blks)
    ::  /x/decode/~[id1 id2 ...] — decode token IDs to text (for debugging)
      [%x %decode *]
    ?~  tok  ~
    =/  ids=(list @ud)
      %+  turn  t.t.path
      |=  n=@ta
      (slav %ud n)
    ``noun+!>((decode:tokenizer u.tok ids))
    ::  /x/encode/~['text'] — encode text to token IDs (for debugging)
      [%x %encode @ ~]
    ?~  tok  ~
    ``noun+!>((encode:tokenizer u.tok (@t i.t.t.path)))
    ::  /x/test-transpose-mlx2/noun
    ::    Dequant block-0 q-proj, then transpose, return first 8 fp32 vals
    ::    of row 0 of the TRANSPOSED matrix. Isolates whether transpose works
    ::    on a dequanted tensor.
      [%x %test-transpose-mlx2 ~]
    =/  jres  (mule |.(.^(@ %cx /(scot %p our.bowl)/(scot %tas q.byk.bowl)/(scot %da now.bowl)/weights/qwen3-bonsai/jam)))
    ?:  ?=(%| -.jres)  ~
    =/  ws  ;;(model-weights-qwen3:maroon (cue p.jres))
    =/  blk0   (snag 0 blocks.ws)
    =/  qproj  q-proj.blk0
    ?>  ?=([%mlx2 *] qproj)
    =/  fp  (dequant-mlx2-ray:maroon wq.qproj scales.qproj biases.qproj group-size.qproj)
    =/  fp-t  fp   :: dequant now produces [in, out] = transposed by construction
    =/  vals=(list @rs)
      :~  `@rs`(get-item:la fp-t ~[0 0])
          `@rs`(get-item:la fp-t ~[0 1])
          `@rs`(get-item:la fp-t ~[0 2])
          `@rs`(get-item:la fp-t ~[0 3])
          `@rs`(get-item:la fp-t ~[0 4])
          `@rs`(get-item:la fp-t ~[0 5])
          `@rs`(get-item:la fp-t ~[0 6])
          `@rs`(get-item:la fp-t ~[0 7])
      ==
    ``noun+!>(vals)
    ::  /x/test-dequant-mlx2/noun
    ::    Reads /weights/qwen3-bonsai/jam, cues, pulls block 0 q-proj (which
    ::    is an mlx2-packed weight), dequants it, returns first 8 fp32 values
    ::    of row 0 as a (list @rs).
    ::    Compare against numpy reference (saloon/tools/dequant_q_proj.py):
    ::      [-0.02282715 -0.02282715 -0.02282715 0 0.02282715 -0.02282715 0 0]
    ::    Exists here so click threads can validate dequant correctness on
    ::    real weights without /+ importing maroon. Remove when validated.
    ::  /x/test-dequant-raw/N/noun — dequant q-proj, return all of:
    ::    - shape of output meta
    ::    - cut 5 [N 1] data
    ::    - get-item [0, N]
    ::    - data's met 3 (byte count)
    ::  to cross-check get-item vs direct cut.
      [%x %test-dequant-raw @ ~]
    =/  jres  (mule |.(.^(@ %cx /(scot %p our.bowl)/(scot %tas q.byk.bowl)/(scot %da now.bowl)/weights/qwen3-bonsai/jam)))
    ?:  ?=(%| -.jres)  ~
    =/  ws  ;;(model-weights-qwen3:maroon (cue p.jres))
    =/  blk0   (snag 0 blocks.ws)
    =/  qproj  q-proj.blk0
    ?.  ?=(%mlx2 -.qproj)  ~
    =/  deq  (dequant-mlx2-ray:maroon wq.qproj scales.qproj biases.qproj group-size.qproj)
    =/  n  (slav %ud i.t.t.path)
    ``noun+!>(`@ux`(get-item:la deq ~[0 n]))
    ::
    ::  /x/test-raw-word/N/noun — return w-data word at linear offset N
    ::  (diagnostic for jet vs hoon layout verification)
      [%x %test-raw-word @ ~]
    =/  jres  (mule |.(.^(@ %cx /(scot %p our.bowl)/(scot %tas q.byk.bowl)/(scot %da now.bowl)/weights/qwen3-bonsai/jam)))
    ?:  ?=(%| -.jres)  ~
    =/  ws  ;;(model-weights-qwen3:maroon (cue p.jres))
    =/  blk0   (snag 0 blocks.ws)
    =/  qproj  q-proj.blk0
    ?>  ?=([%mlx2 *] qproj)
    =/  n  (slav %ud i.t.t.path)
    ``noun+!>(`@ux`(cut 5 [n 1] data.wq.qproj))
    ::
      [%x %test-dequant-mlx2 ~]
    =/  jres  (mule |.(.^(@ %cx /(scot %p our.bowl)/(scot %tas q.byk.bowl)/(scot %da now.bowl)/weights/qwen3-bonsai/jam)))
    ?:  ?=(%| -.jres)  ~
    =/  ws  ;;(model-weights-qwen3:maroon (cue p.jres))
    =/  blk0   (snag 0 blocks.ws)
    =/  qproj  q-proj.blk0
    ?>  ?=([%mlx2 *] qproj)
    =/  fp  (dequant-mlx2-ray:maroon wq.qproj scales.qproj biases.qproj group-size.qproj)
    =/  vals=(list @rs)
      :~  `@rs`(get-item:la fp ~[0 0])
          `@rs`(get-item:la fp ~[0 1])
          `@rs`(get-item:la fp ~[0 2])
          `@rs`(get-item:la fp ~[0 3])
          `@rs`(get-item:la fp ~[0 4])
          `@rs`(get-item:la fp ~[0 5])
          `@rs`(get-item:la fp ~[0 6])
          `@rs`(get-item:la fp ~[0 7])
      ==
    ``noun+!>(vals)
    ::  /x/qwen3-say/<prompt>/noun — end-to-end inference with decoded output.
    ::    Encodes <prompt> via the loaded tokenizer, runs forward-qwen3 on the
    ::    loaded qwen3 weights, returns [next-id=@ud next-text=@t]. Requires
    ::    prior pokes: %maroon-load-qwen3 and %maroon-load-tokenizer.
      [%x %qwen3-say @ ~]
    ?~  weights-qwen3
      ~&  >>>  'no qwen3 weights loaded — poke %maroon-load-qwen3 first'
      ~
    ?~  config-qwen3  ~
    ?~  tok
      ~&  >>>  'no tokenizer loaded — poke %maroon-load-tokenizer first'
      ~
    =/  prompt=@t  (@t i.t.t.path)
    =/  ids=(list @ud)  (encode:tokenizer u.tok prompt)
    =/  logits  (forward-qwen3:mr:maroon ids u.weights-qwen3 u.config-qwen3)
    =/  next-id  (argmax-token:mr:maroon logits)
    =/  next-text=@t  (decode:tokenizer u.tok ~[next-id])
    ``noun+!>([next-id next-text])
    ::
    ::  /x/forward-qwen3/<id1>/<id2>/.../noun
    ::    Reads /weights/qwen3-bonsai/jam, cues to model-weights-qwen3,
    ::    runs forward on the supplied token IDs, returns next argmax token.
    ::    Bonsai-1.7B config is hardcoded; this is for testing, not production.
    ::    Exists here so click threads (which can't /+ import maroon) can drive
    ::    the forward-qwen3 path; remove when an inference scry surface lands.
      [%x %forward-qwen3 *]
    =/  ids=(list @ud)
      %+  turn  t.t.path
      |=  n=@ta
      (slav %ud n)
    =/  jres  (mule |.(.^(@ %cx /(scot %p our.bowl)/(scot %tas q.byk.bowl)/(scot %da now.bowl)/weights/qwen3-bonsai/jam)))
    ?:  ?=(%| -.jres)  ~
    =/  ws  ;;(model-weights-qwen3:maroon (cue p.jres))
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
    =/  logits  (forward-qwen3:mr:maroon ids ws cfg)
    ``noun+!>((argmax-token:mr:maroon logits))
  ==
::
++  on-agent  on-agent:def
++  on-arvo
  |=  [=wire =sign-arvo]
  ^-  (quip card _this)
  ?+    wire  (on-arvo:def wire sign-arvo)
      [%eyre %connect ~]       `this
      [%eyre %connect-v1 ~]    `this
      [%gen-tick ~]
    ?~  gen  `this
    =/  g  u.gen
    =/  la  (lake %n)
    =/  seq-len  (lent tokens.g)
    =/  ping-card=card
      :*  %give  %fact  ~[/http-response/[eyre-id.g]]
          %http-response-data  !>(`(sse-event-ping (mix eny.bowl step.g)))
      ==
    =/  tick-card=card  [%pass /gen-tick %arvo %b %wait now.bowl]
    ?-    mode.g
        ::  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        ::  Single-shot: one tick = one token.  Model-agnostic.
        ::  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        %single
      ::  Qwen3 with KV cache: prefill on first tick, decode thereafter.
      ::  On cache miss (e.g. LRU-evicted), fall back to a fresh prefill
      ::  that re-populates cache under curr-seq-hash.
      ::  Qwen3: precompute rope cos/sin once per generation at max
      ::  seq length so every tick reuses the same atom.
      =/  rope-cs=(unit [cos=tensor:maroon sin=tensor:maroon])
        ?:  ?&(?=(^ weights-qwen3) ?=(^ config-qwen3))
          ?^  rope-cs.g  rope-cs.g
          =/  max-seq  (add n-prompt.g n-remaining.g)
          =/  cs=[cos=tensor:maroon sin=tensor:maroon]
            (precompute-rope-cs-qwen3:maroon max-seq u.config-qwen3)
          `cs
        ~
      =/  logits-u=(unit tensor:maroon)
        ?:  ?&(?=(^ weights-qwen3) ?=(^ config-qwen3) ?=(^ rope-cs))
          ?.  prefilled.g
            =/  x-emb=tensor:maroon
              (embed-tied-mlx2:maroon tokens.g tok-emb.u.weights-qwen3 u.config-qwen3)
            =/  x-all=tensor:maroon
              %:  run-blocks-qwen3:maroon
                x-emb  blocks.u.weights-qwen3  u.config-qwen3
                cos.u.rope-cs  sin.u.rope-cs
                kv-session.g  kv-max-seq.g
              ==
            ::  Extract the last row from the [S, D] activation as a
            ::  [1, D] tensor directly from the data atom.  Hoon's
            ::  get-row iterates set-item D times, which invokes ++sew
            ::  per element; some vere / pier combos misdispatch sew
            ::  and crash, so we cut raw bytes and feed the jetted
            ::  single-row path instead.
            =/  d-model=@ud  d-model.u.config-qwen3
            =/  last-idx     (dec (lent tokens.g))
            =/  row-bytes    (mul d-model 4)
            =/  last-raw=@
              (cut 3 [(mul last-idx row-bytes) row-bytes] data.x-all)
            =/  last-data=@  (mix last-raw (lsh [3 row-bytes] 1))
            =/  last-row=tensor:maroon
              :-  `meta:ls`[~[1 d-model] 5 %i754 ~]
              last-data
            =/  rn=tensor:maroon
              %:  rms-norm-row:maroon
                last-row  ln-f.u.weights-qwen3  rms-eps.u.config-qwen3
              ==
            =/  l=tensor:maroon
              (logits-tied-mlx2:mr:maroon rn tok-emb.u.weights-qwen3 u.config-qwen3)
            `l
          ::  Decode: one new position into the persistent KV buffers.
          ::  Inlined to bypass the Hoon get-row in forward-qwen3-final-row
          ::  (same ++sew crash path as prefill).
          =/  seq-len     (lent tokens.g)
          =/  last-tok    (rear tokens.g)
          =/  position    (dec seq-len)
          =/  x-single
            (embed-tied-mlx2:maroon ~[last-tok] tok-emb.u.weights-qwen3 u.config-qwen3)
          =/  new-x-opt=(unit tensor:maroon)
            %:  run-decode-qwen3:maroon
              x-single
              blocks.u.weights-qwen3
              u.config-qwen3
              cos.u.rope-cs  sin.u.rope-cs
              position
              kv-session.g
            ==
          ?^  new-x-opt
            ::  x-new is [1, D]; rms-norm + logits on it.
            =/  rn-d=tensor:maroon
              %:  rms-norm-row:maroon
                u.new-x-opt  ln-f.u.weights-qwen3  rms-eps.u.config-qwen3
              ==
            `(logits-tied-mlx2:mr:maroon rn-d tok-emb.u.weights-qwen3 u.config-qwen3)
          ::  KV miss — run embed + blocks, then last-row projection.
          =/  x-emb2=tensor:maroon
            (embed-tied-mlx2:maroon tokens.g tok-emb.u.weights-qwen3 u.config-qwen3)
          =/  x-all2=tensor:maroon
            %:  run-blocks-qwen3:maroon
              x-emb2  blocks.u.weights-qwen3  u.config-qwen3
              cos.u.rope-cs  sin.u.rope-cs
              kv-session.g  kv-max-seq.g
            ==
          =/  d-model2=@ud  d-model.u.config-qwen3
          =/  last-idx2     (dec (lent tokens.g))
          =/  row-bytes2    (mul d-model2 4)
          =/  last-raw2=@
            (cut 3 [(mul last-idx2 row-bytes2) row-bytes2] data.x-all2)
          =/  last-data2=@  (mix last-raw2 (lsh [3 row-bytes2] 1))
          =/  last-row2=tensor:maroon
            :-  `meta:ls`[~[1 d-model2] 5 %i754 ~]
            last-data2
          =/  rn2=tensor:maroon
            %:  rms-norm-row:maroon
              last-row2  ln-f.u.weights-qwen3  rms-eps.u.config-qwen3
            ==
          =/  l=tensor:maroon
            (logits-tied-mlx2:mr:maroon rn2 tok-emb.u.weights-qwen3 u.config-qwen3)
          `l
        (forward-loaded state tokens.g)
      ?~  logits-u  `this(gen ~)
      =/  next-tok
        (sample-token:mr:maroon u.logits-u strategy.g tokens.g (mix eny.bowl step.g))
      =/  new-tokens  (snoc tokens.g next-tok)
      ::  Emit the text delta that ends at a complete UTF-8 codepoint
      ::  boundary.  Incremental: decode only the new token's bytes and
      ::  append to the running buffer — O(1) per step instead of re-
      ::  decoding the entire gen list.
      =/  gen-so-far  (slag n-prompt.g new-tokens)
      =/  new-bytes  ?~(tok '' (decode:tokenizer u.tok ~[next-tok]))
      =/  full-text=@t  (cat 3 text-decoded.g new-bytes)
      =/  full-bytes  (met 3 full-text)
      =/  safe-end   (last-utf8-boundary full-text full-bytes)
      =/  delta-len
        ?:  (gth safe-end text-sent.g)  (sub safe-end text-sent.g)
        0
      =/  text-chunk=@t  (cut 3 [text-sent.g delta-len] full-text)
      =/  total=@dr  (sub now.bowl start.g)
      ::  Per-tick wire emission, format-aware.  Buffered OpenAI emits
      ::  nothing until done; streaming OpenAI emits a delta chunk.
      =/  per-tick-cards=(list card)
        ?-    api.g
            %maroon
          =/  chunk-json=json
            :-  %o
            %-  ~(gas by *(map @t json))
            :~  ['type' s+'token']  ['id' (numb:enjs:format next-tok)]
                ['text' s+text-chunk]
            ==
          :~  :*  %give  %fact  ~[/http-response/[eyre-id.g]]
                  %http-response-data
                  !>(`(sse-event-data (en:json:html chunk-json)))
              ==
          ==
        ::
            %openai
          ?.  stream.g  ~
          ?:  =(0 delta-len)  ~
          =/  chunk-text=@t
            %:  openai-chunk
              response-id.g  model-name.g  now.bowl  %content  text-chunk  ''
            ==
          :~  :*  %give  %fact  ~[/http-response/[eyre-id.g]]
                  %http-response-data
                  !>(`(sse-event-data chunk-text))
              ==
          ==
        ::
            %poke  ~  ::  poke path is always buffered — nothing per-tick
        ==
      =/  remaining   (dec n-remaining.g)
      ::  Stop early on EOS.  Qwen3 emits 151.645 (<|im_end|>) at end of
      ::  turn and 151.643 (<|endoftext|>) at true EOS; anything else is
      ::  model-specific, so only these two are hard-coded.  max_tokens
      ::  still caps the upper bound.
      =/  eos=?
        ?|  =(151.645 next-tok)
            =(151.643 next-tok)
        ==
      ?:  ?|(=(0 remaining) eos)
        =/  tokens-gen  (lent gen-so-far)
        =/  ms-unit      (div ~s1 1.000)
        =/  ms           (div total ms-unit)
        =/  rate-x10     ?:(=(0 ms) 0 (div (mul tokens-gen 10.000) ms))
        ~&  >  "done: {<tokens-gen>} tokens in {<total>} ({<(div rate-x10 10)>}.{<(mod rate-x10 10)>} tok/s)"
        =/  finish-reason=@t  ?:(eos 'stop' 'length')
        =/  done-cards=(list card)
          ?-    api.g
              %maroon
            =/  done-json=json
              [%o (~(gas by *(map @t json)) ~[['type' s+'done']])]
            =/  done-card=card
              :*  %give  %fact  ~[/http-response/[eyre-id.g]]
                  %http-response-data
                  !>(`(sse-event-data (en:json:html done-json)))
              ==
            =/  kick-card=card  [%give %kick ~[/http-response/[eyre-id.g]] ~]
            ~[done-card kick-card]
          ::
              %openai
            ?:  stream.g
              =/  final-chunk=@t
                %:  openai-chunk
                  response-id.g  model-name.g  now.bowl  %final  ''  finish-reason
                ==
              =/  final-card=card
                :*  %give  %fact  ~[/http-response/[eyre-id.g]]
                    %http-response-data
                    !>(`(sse-event-data final-chunk))
                ==
              ::  OpenAI convention: stream terminator is the literal
              ::  `data: [DONE]` line.  Emit it as a plain SSE event.
              =/  done-marker=card
                :*  %give  %fact  ~[/http-response/[eyre-id.g]]
                    %http-response-data
                    !>(`(sse-event-data '[DONE]'))
                ==
              =/  kick-card=card  [%give %kick ~[/http-response/[eyre-id.g]] ~]
              ~[final-card done-marker kick-card]
            ::  Buffered: emit one full JSON response via Eyre's
            ::  simple-payload path (no prior headers have been sent).
            =/  completion-body=@t
              %:  openai-completion
                response-id.g  model-name.g  now.bowl
                full-text  finish-reason
                n-prompt.g  (lent gen-so-far)
              ==
            %+  give-simple-payload:app:server  eyre-id.g
            :-  :-  200
                :~  ['content-type' 'application/json']
                    ['access-control-allow-origin' '*']
                ==
            (some (as-octs:mimes:html completion-body))
          ::
              %poke
            ::  Direct-poke path: no HTTP.  Send a single poke back to
            ::  the original caller with the full completion body and
            ::  the echoed-meta so the caller can route the response.
            =/  completion-body=@t
              %:  openai-completion
                response-id.g  model-name.g  now.bowl
                full-text  finish-reason
                n-prompt.g  (lent gen-so-far)
              ==
            ~&  >  [%maroon-poke-back caller=poke-caller.g req-id=poke-req-id.g body-len=(met 3 completion-body)]
            :~  :*  %pass  /maroon-resp/[poke-req-id.g]
                    %agent  [poke-caller.g %claw]  %poke
                    %maroon-chat-resp
                    !>([poke-req-id.g poke-meta.g 200 completion-body])
                ==
            ==
          ==
        :_  this(gen ~, last-output new-tokens)
        (weld per-tick-cards done-cards)
      =/  new-g=gen-state
        %=    g
            tokens         new-tokens
            n-remaining    remaining
            step           +(step.g)
            last-tick      now.bowl
            text-sent      safe-end
            text-decoded   full-text
            rope-cs        rope-cs
            prefilled      &
        ==
      :_  this(gen `new-g)
      (weld per-tick-cards ~[tick-card])
    ::
        ::  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        ::  Block-stream: embed on the first tick, one transformer block
        ::  per subsequent tick, final+sample on the last.  Keepalive
        ::  pings fire between every tick so the HTTP chunk stream stays
        ::  alive even under slow CPU forwards.  Each phase dispatches
        ::  per-model by inspecting which weights are loaded.
        ::  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        %block-stream
      ?-    phase.g
          %new
        ::  Qwen3: embed + precompute RoPE cos/sin.
        ?:  ?&(?=(^ weights-qwen3) ?=(^ config-qwen3))
          =/  ws   u.weights-qwen3
          =/  cfg  u.config-qwen3
          =/  emb  (forward-qwen3-embed:mr:maroon tokens.g ws cfg)
          :_  this(gen `g(phase %block, block-idx 0, x `x.emb, cos `cos.emb, sin `sin.emb, last-tick now.bowl))
          ~[ping-card tick-card]
        ::  GPT-2: embed + positional embeddings.
        ?~  weights  `this
        ?~  config   `this
        =/  w  u.weights
        =/  c  u.config
        =/  x0  (embed:mr:maroon tokens.g tok-emb.w bloq.c)
        =/  d-model  (snag 1 shape.meta.x0)
        =/  pos=tensor:maroon
          =/  init  (zeros:la [~[seq-len d-model] bloq.c %i754 ~])
          =/  i  0
          |-  ^-  tensor:maroon
          ?:  =(i seq-len)  init
          =/  row  (get-row:la pos-emb.w ~[i])
          $(i +(i), init (set-row:la init ~[i] row))
        =/  x1  (add:la x0 pos)
        :_  this(gen `g(phase %block, block-idx 0, x `x1, last-tick now.bowl))
        ~[ping-card tick-card]
      ::
          %block
        ?~  x.g  `this
        ::  Qwen3
        ?:  ?&(?=(^ weights-qwen3) ?=(^ config-qwen3))
          ?~  cos.g  `this
          ?~  sin.g  `this
          =/  ws   u.weights-qwen3
          =/  cfg  u.config-qwen3
          =/  blk  (snag block-idx.g blocks.ws)
          =/  x-next
            (run-block-qwen3:maroon u.x.g blk cfg u.cos.g u.sin.g)
          =/  next-idx  +(block-idx.g)
          =/  n-layers  (lent blocks.ws)
          =/  next-phase=?(%new %block %final)
            ?:  =(next-idx n-layers)  %final
            %block
          :_  this(gen `g(phase next-phase, block-idx next-idx, x `x-next, last-tick now.bowl))
          ~[ping-card tick-card]
        ::  GPT-2
        ?~  weights  `this
        ?~  config   `this
        =/  w  u.weights
        =/  c  u.config
        =/  blk  (snag block-idx.g blocks.w)
        =/  x-next  (transformer-block:mr:maroon u.x.g blk n-heads.c)
        =/  next-idx  +(block-idx.g)
        =/  n-layers  (lent blocks.w)
        =/  next-phase=?(%new %block %final)
          ?:  =(next-idx n-layers)  %final
          %block
        :_  this(gen `g(phase next-phase, block-idx next-idx, x `x-next, last-tick now.bowl))
        ~[ping-card tick-card]
      ::
          %final
        ?~  x.g  `this
        ::  Compute logits per model.
        =/  logits=tensor:maroon
          ?:  ?&(?=(^ weights-qwen3) ?=(^ config-qwen3))
            (forward-qwen3-final:mr:maroon u.x.g tokens.g u.weights-qwen3 u.config-qwen3)
          ?~  weights  !!
          ?~  config   !!
          =/  w  u.weights
          =/  c  u.config
          =/  x-norm  (layer-norm-2d:mr:maroon u.x.g ln-f-g.w ln-f-b.w)
          =/  last-row  (get-row:la x-norm ~[(dec seq-len)])
          =/  bias-zeros  (zeros:la [~[1 vocab-size.c] bloq.c %i754 ~])
          (linear:mr:maroon last-row [[%fp out-proj.w] bias-zeros])
        =/  next-tok
          (sample-token:mr:maroon logits strategy.g tokens.g (mix eny.bowl step.g))
        =/  text-chunk=@t  ?~(tok '' (decode:tokenizer u.tok ~[next-tok]))
        =/  total=@dr  (sub now.bowl start.g)
        =/  token-card=card
          =/  chunk-json=json
            :-  %o
            %-  ~(gas by *(map @t json))
            :~  ['type' s+'token']  ['id' (numb:enjs:format next-tok)]
                ['text' s+text-chunk]
            ==
          :*  %give  %fact  ~[/http-response/[eyre-id.g]]
              %http-response-data
              !>(`(sse-event-data (en:json:html chunk-json)))
          ==
        =/  new-tokens  (snoc tokens.g next-tok)
        =/  remaining   (dec n-remaining.g)
        ?:  =(0 remaining)
          =/  gen-toks  (slag n-prompt.g new-tokens)
          =/  full-text=@t  ?~(tok '' (decode:tokenizer u.tok gen-toks))
          =/  tokens-gen  (lent gen-toks)
          =/  ms-unit     (div ~s1 1.000)
          =/  ms          (div total ms-unit)
          =/  rate-x10    ?:(=(0 ms) 0 (div (mul tokens-gen 10.000) ms))
          ~&  >  "done: {<tokens-gen>} tokens in {<total>} ({<(div rate-x10 10)>}.{<(mod rate-x10 10)>} tok/s)"
          =/  done-card=card
            =/  done-json=json  [%o (~(gas by *(map @t json)) ~[['type' s+'done']])]
            :*  %give  %fact  ~[/http-response/[eyre-id.g]]
                %http-response-data
                !>(`(sse-event-data (en:json:html done-json)))
            ==
          =/  kick-card=card  [%give %kick ~[/http-response/[eyre-id.g]] ~]
          :_  this(gen ~, last-output new-tokens)
          ~[token-card done-card kick-card]
        :_  this(gen `g(tokens new-tokens, n-remaining remaining, step +(step.g), last-tick now.bowl, phase %new, block-idx 0, x ~, cos ~, sin ~))
        ~[token-card tick-card]
      ==
    ==
  ==
++  on-fail   on-fail:def
--
