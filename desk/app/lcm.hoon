::  lcm: lossless context management agent
::
::  stores conversations, builds DAG summaries via LLM,
::  assembles token-budgeted context for claw.
::
/-  lcm
/+  default-agent, dbug
|%
+$  card  card:agent:gall
+$  versioned-state  state-0:lcm
::
++  estimate-tokens
  |=  text=@t
  ^-  @ud
  (div (add (met 3 text) 3) 4)
::
++  model-budget
  |=  mod=@t
  ^-  @ud
  =/  m=tape  (cass (trip mod))
  ?:  !=(~ (find "claude" m))  150.000
  ?:  !=(~ (find "gpt-4" m))   100.000
  ?:  !=(~ (find "gemini" m))  800.000
  50.000
::
::  +context-tokens: total tokens in active context
::
++  context-tokens
  |=  =conversation:lcm
  ^-  @ud
  %+  roll  context-items.conversation
  |=  [ci=context-item:lcm acc=@ud]
  ?-  -.ci
      %msg
    =/  m=(unit stored-msg:lcm)  (~(get by messages.conversation) seq.ci)
    ?~  m  acc
    (add acc token-est.u.m)
      %sum
    =/  s=(unit summary:lcm)  (~(get by summaries.conversation) id.ci)
    ?~  s  acc
    (add acc token-est.u.s)
  ==
::
::  +assemble: build context from summaries + fresh tail within budget
::
++  assemble
  |=  [=conversation:lcm budget=@ud]
  ^-  (list [role=@t content=@t])
  =/  items=(list context-item:lcm)  context-items.conversation
  =/  len=@ud  (lent items)
  =/  tail-n=@ud  (min len 16)  ::  TODO: use config
  =/  fresh=(list context-item:lcm)  (slag (sub len tail-n) items)
  =/  before=(list context-item:lcm)  (scag (sub len tail-n) items)
  ::  resolve fresh tail (always included)
  =/  fresh-msgs=(list [role=@t content=@t])
    %+  murn  fresh
    |=  ci=context-item:lcm
    ^-  (unit [role=@t content=@t])
    ?-  -.ci
        %msg
      =/  m=(unit stored-msg:lcm)  (~(get by messages.conversation) seq.ci)
      ?~  m  ~
      `[role.u.m content.u.m]
        %sum
      =/  s=(unit summary:lcm)  (~(get by summaries.conversation) id.ci)
      ?~  s  ~
      `['system' (rap 3 '[Context summary, depth ' (scot %ud depth.u.s) ']\0a' content.u.s ~)]
    ==
  =/  fresh-tok=@ud
    %+  roll  fresh-msgs
    |=  [[r=@t c=@t] acc=@ud]
    (add acc (estimate-tokens c))
  =/  remaining=@ud  ?:((gth fresh-tok budget) 0 (sub budget fresh-tok))
  ::  fill remaining budget from oldest items
  =/  prefix=(list [role=@t content=@t])  ~
  |-
  ?~  before  (weld prefix fresh-msgs)
  =/  ci  i.before
  =/  resolved=(unit [role=@t content=@t tok=@ud])
    ?-  -.ci
        %msg
      =/  m=(unit stored-msg:lcm)  (~(get by messages.conversation) seq.ci)
      ?~  m  ~
      `[role.u.m content.u.m token-est.u.m]
        %sum
      =/  s=(unit summary:lcm)  (~(get by summaries.conversation) id.ci)
      ?~  s  ~
      =/  txt=@t  (rap 3 '[Context summary, depth ' (scot %ud depth.u.s) ']\0a' content.u.s ~)
      `['system' txt token-est.u.s]
    ==
  ?~  resolved  $(before t.before)
  ?:  (gth tok.u.resolved remaining)
    ::  skip items that don't fit, try next
    $(before t.before)
  %=  $
    before     t.before
    remaining  (sub remaining tok.u.resolved)
    prefix     (snoc prefix [-.u.resolved +<.u.resolved])
  ==
::
::  +select-leaf-chunk: pick oldest raw msgs outside fresh tail for compaction
::
++  select-leaf-chunk
  |=  [=conversation:lcm max-tokens=@ud fresh-tail-n=@ud]
  ^-  (list @ud)
  =/  items  context-items.conversation
  =/  len  (lent items)
  =/  cutoff  (sub len (min len fresh-tail-n))
  =/  eligible  (scag cutoff items)
  ::  collect raw message seqs until we hit max-tokens
  =/  collected=(list @ud)  ~
  =/  tok=@ud  0
  |-
  ?~  eligible  (flop collected)
  ?.  ?=(%msg -.i.eligible)  $(eligible t.eligible)
  =/  m=(unit stored-msg:lcm)  (~(get by messages.conversation) seq.i.eligible)
  ?~  m  $(eligible t.eligible)
  ?:  (gth (add tok token-est.u.m) max-tokens)
    ?~  collected  ::  always take at least one
      (flop [seq.i.eligible collected])
    (flop collected)
  %=  $
    eligible   t.eligible
    tok        (add tok token-est.u.m)
    collected  [seq.i.eligible collected]
  ==
::
::  +make-compact-request: build LLM summarization request
::
++  make-compact-request
  |=  [=bowl:gall cfg=lcm-config:lcm msgs=(list stored-msg:lcm) depth=@ud =wire]
  ^-  card
  =/  sys=@t
    ?+  depth
      'You are a context compaction engine. Compress the following summaries into a higher-level memory node. Keep durable context: key decisions, current state, active constraints, lessons learned. Brief timeline with dates. End with: "Expand for details about: <what was compressed>". Plain text only.'
        %0
      'You are a context compaction engine. Compress the following conversation segment. Preserve: key facts, decisions, user preferences, file operations, action items, names/identifiers. Drop: repetition, filler, resolved states. Track file operations as "Files: path (action)". End with: "Expand for details about: <what was compressed>". Plain text only.'
        %1
      'You are a context compaction engine. Compact these summaries into a single memory node. Preserve: decisions with rationale, superseded decisions, completed tasks with outcomes, in-progress items, blockers, specific references. Drop: unchanged context, dead ends, resolved states. Include timeline with timestamps. End with: "Expand for details about: <what was compressed>". Plain text only.'
    ==
  =/  target=@ud
    ?:  =(0 depth)  leaf-target-tokens.cfg
    condense-target-tokens.cfg
  =/  msg-text=@t
    %-  crip
    %-  zing
    %+  turn  msgs
    |=  m=stored-msg:lcm
    "{(trip role.m)}: {(trip content.m)}\0a"
  =/  full-sys=@t
    (rap 3 sys '\0aTarget: about ' (scot %ud target) ' tokens.' ~)
  =/  api-msgs=json
    :-  %a
    :~  (pairs:enjs:format ~[['role' s+'system'] ['content' s+full-sys]])
        (pairs:enjs:format ~[['role' s+'user'] ['content' s+msg-text]])
    ==
  =/  body=json
    (pairs:enjs:format ~[['model' s+model.cfg] ['messages' api-msgs]])
  =/  body-cord=@t  (en:json:html body)
  =/  hed=(list [key=@t value=@t])
    :~  ['Content-Type' 'application/json']
        ['Authorization' (crip "Bearer {(trip api-key.cfg)}")]
    ==
  [%pass wire %arvo %i %request [%'POST' 'https://openrouter.ai/api/v1/chat/completions' hed `(as-octs:mimes:html body-cord)] *outbound-config:iris]
::
::  +parse-response: extract text from OpenRouter response
::
++  parse-response
  |=  body=@t
  ^-  (unit @t)
  =/  jon=(unit json)  (de:json:html body)
  ?~  jon  ~
  %-  mole  |.
  ^-  @t
  =,  dejs:format
  =/  choices=(list @t)
    %.  u.jon
    (ot ~[choices+(ar (ot ~[message+(ot ~[content+so])]))])
  ?~  choices  !!
  i.choices
--
::
%-  agent:dbug
=|  state-0:lcm
=*  state  -
^-  agent:gall
|_  =bowl:gall
+*  this  .
    def   ~(. (default-agent this %|) bowl)
::
++  on-init
  ^-  (quip card _this)
  %-  (slog leaf+"lcm: initialized" ~)
  =/  default-cfg=lcm-config:lcm
    :*  ''  'anthropic/claude-sonnet-4'
        75  16  20.000  1.200  2.000  8  4
    ==
  `this(lcm-config default-cfg)
::
++  on-save  !>(state)
::
++  on-load
  |=  =vase
  ^-  (quip card _this)
  =/  old  !<(versioned-state vase)
  ?-  -.old
    %0  `this(state old)
  ==
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?>  =(src our):bowl
  ?.  ?=(%lcm-action mark)
    (on-poke:def mark vase)
  =/  act=lcm-action:lcm  !<(lcm-action:lcm vase)
  ?-  -.act
  ::
      %set-config
    %-  (slog leaf+"lcm: config updated" ~)
    `this(lcm-config lcm-config.act)
  ::
      %clear
    %-  (slog leaf+"lcm: cleared {(trip key.act)}" ~)
    `this(conversations (~(del by conversations) key.act))
  ::
      %ingest
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key.act) *conversation:lcm)
    =/  tok=@ud  (estimate-tokens content.act)
    =/  =stored-msg:lcm
      [next-seq.conv role.act content.act tok now.bowl]
    =.  messages.conv  (~(put by messages.conv) next-seq.conv stored-msg)
    =.  context-items.conv  (snoc context-items.conv [%msg next-seq.conv])
    =.  next-seq.conv  +(next-seq.conv)
    =.  conversations  (~(put by conversations) key.act conv)
    ::  check compaction trigger
    =/  total-tok=@ud  (context-tokens conv)
    =/  budget=@ud  (model-budget model.lcm-config)
    =/  threshold=@ud  (div (mul budget context-threshold.lcm-config) 100)
    ::  count raw msgs outside fresh tail
    =/  items-len=@ud  (lent context-items.conv)
    =/  tail-n=@ud  (min items-len fresh-tail.lcm-config)
    =/  eligible=(list context-item:lcm)  (scag (sub items-len tail-n) context-items.conv)
    =/  raw-count=@ud
      %+  roll  eligible
      |=  [ci=context-item:lcm acc=@ud]
      ?:(?=(%msg -.ci) +(acc) acc)
    ?.  &(?=([%idle ~] compact-state) (gth total-tok threshold) (gte raw-count leaf-min-fanout.lcm-config) !=('' api-key.lcm-config))
      `this
    ::  trigger leaf compaction
    =/  chunk=(list @ud)
      (select-leaf-chunk conv leaf-chunk-tokens.lcm-config fresh-tail.lcm-config)
    ?:  (lth (lent chunk) 3)  `this
    =/  chunk-msgs=(list stored-msg:lcm)
      %+  murn  chunk
      |=(seq=@ud (~(get by messages.conv) seq))
    %-  (slog leaf+"lcm: compacting {(a-co:co (lent chunk))} messages for {(trip key.act)}" ~)
    :_  this(compact-state [%running key.act])
    :~  (make-compact-request bowl lcm-config chunk-msgs 0 /compact/[key.act])
    ==
  ::
      %compact
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key.act) *conversation:lcm)
    ?.  ?=([%idle ~] compact-state)
      %-  (slog leaf+"lcm: compaction already running" ~)
      `this
    =/  chunk=(list @ud)
      (select-leaf-chunk conv leaf-chunk-tokens.lcm-config fresh-tail.lcm-config)
    ?:  (lth (lent chunk) 3)
      %-  (slog leaf+"lcm: not enough messages to compact" ~)
      `this
    =/  chunk-msgs=(list stored-msg:lcm)
      %+  murn  chunk
      |=(seq=@ud (~(get by messages.conv) seq))
    %-  (slog leaf+"lcm: manually compacting {(a-co:co (lent chunk))} messages" ~)
    :_  this(compact-state [%running key.act])
    :~  (make-compact-request bowl lcm-config chunk-msgs 0 /compact/[key.act])
    ==
  ==
::
++  on-watch
  |=  =path
  ^-  (quip card _this)
  (on-watch:def path)
::
++  on-leave  on-leave:def
::
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  ?+  path  ~
  ::
  ::  assemble context for a conversation within token budget
  ::
      [%x %assemble @ @ ~]
    =/  key=@t  i.t.t.path
    =/  budget=@ud  (slav %ud i.t.t.t.path)
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key) *conversation:lcm)
    =/  msgs=(list [role=@t content=@t])
      (assemble conv budget)
    =/  j=json
      :-  %a
      %+  turn  msgs
      |=  [role=@t content=@t]
      (pairs:enjs:format ~[['role' s+role] ['content' s+content]])
    ``json+!>(j)
  ::
  ::  search messages and summaries
  ::
      [%x %grep @ @ ~]
    =/  key=@t  i.t.t.path
    =/  query=@t  i.t.t.t.path
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key) *conversation:lcm)
    =/  q=tape  (cass (trip query))
    ::  search summaries
    =/  sum-hits=(list json)
      %+  murn  ~(val by summaries.conv)
      |=  s=summary:lcm
      ?.  !=(~ (find q (cass (trip content.s))))  ~
      %-  some
      %-  pairs:enjs:format
      :~  ['type' s+'summary']
          ['id' (numb:enjs:format id.s)]
          ['depth' (numb:enjs:format depth.s)]
          ['content' s+(crip (scag 500 (trip content.s)))]
      ==
    ::  search messages
    =/  msg-hits=(list json)
      %+  murn  ~(val by messages.conv)
      |=  m=stored-msg:lcm
      ?.  !=(~ (find q (cass (trip content.m))))  ~
      %-  some
      %-  pairs:enjs:format
      :~  ['type' s+'message']
          ['seq' (numb:enjs:format seq.m)]
          ['role' s+role.m]
          ['content' s+(crip (scag 300 (trip content.m)))]
      ==
    ``json+!>(a+(weld sum-hits msg-hits))
  ::
  ::  describe a summary
  ::
      [%x %describe @ @ ~]
    =/  key=@t  i.t.t.path
    =/  sid=@ud  (slav %ud i.t.t.t.path)
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key) *conversation:lcm)
    =/  s=(unit summary:lcm)  (~(get by summaries.conv) sid)
    ?~  s  ``json+!>(~)
    =/  j=json
      %-  pairs:enjs:format
      :~  ['id' (numb:enjs:format id.u.s)]
          ['kind' s+?:(=(%leaf kind.u.s) 'leaf' 'condensed')]
          ['depth' (numb:enjs:format depth.u.s)]
          ['content' s+content.u.s]
          ['token-est' (numb:enjs:format token-est.u.s)]
          ['source-msgs' a+(turn ~(tap in source-msgs.u.s) |=(n=@ud (numb:enjs:format n)))]
          ['parent-sums' a+(turn ~(tap in parent-sums.u.s) |=(n=@ud (numb:enjs:format n)))]
          ['earliest' s+(scot %da earliest.u.s)]
          ['latest' s+(scot %da latest.u.s)]
      ==
    ``json+!>(j)
  ::
  ::  conversation stats
  ::
      [%x %stats @ ~]
    =/  key=@t  i.t.t.path
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key) *conversation:lcm)
    =/  j=json
      %-  pairs:enjs:format
      :~  ['messages' (numb:enjs:format ~(wyt by messages.conv))]
          ['summaries' (numb:enjs:format ~(wyt by summaries.conv))]
          ['context-items' (numb:enjs:format (lent context-items.conv))]
          ['total-tokens' (numb:enjs:format (context-tokens conv))]
      ==
    ``json+!>(j)
  ::
  ::  list conversations
  ::
      [%x %conversations ~]
    =/  j=json
      :-  %a
      %+  turn  ~(tap by conversations)
      |=  [key=@t conv=conversation:lcm]
      %-  pairs:enjs:format
      :~  ['key' s+key]
          ['messages' (numb:enjs:format ~(wyt by messages.conv))]
          ['summaries' (numb:enjs:format ~(wyt by summaries.conv))]
      ==
    ``json+!>(j)
  ==
::
++  on-agent  on-agent:def
::
++  on-arvo
  |=  [=wire sign=sign-arvo]
  ^-  (quip card _this)
  ?+  wire  (on-arvo:def wire sign)
  ::
      [%compact @ ~]
    =/  key=@t  i.t.wire
    ?.  ?=([%iris %http-response *] sign)
      =.  compact-state  [%idle ~]
      `this
    =/  resp=client-response:iris  client-response.sign
    ?.  ?=(%finished -.resp)
      =.  compact-state  [%idle ~]
      `this
    ?.  =(200 status-code.response-header.resp)
      %-  (slog leaf+"lcm: compaction LLM call failed, will retry" ~)
      =.  compact-state  [%idle ~]
      `this
    ?~  full-file.resp
      =.  compact-state  [%idle ~]
      `this
    =/  parsed=(unit @t)  (parse-response q.data.u.full-file.resp)
    ?~  parsed
      %-  (slog leaf+"lcm: could not parse compaction response" ~)
      =.  compact-state  [%idle ~]
      `this
    =/  summary-text=@t  u.parsed
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key) *conversation:lcm)
    ::  find which seqs were in the chunk (raw msgs in context-items
    ::  before fresh tail that were selected)
    =/  chunk=(list @ud)
      (select-leaf-chunk conv leaf-chunk-tokens.lcm-config fresh-tail.lcm-config)
    =/  chunk-set=(set @ud)  (silt chunk)
    ::  get time range from compacted messages
    =/  earliest=@da  now.bowl
    =/  latest=@da  *@da
    =.  earliest
      %+  roll  chunk
      |=  [seq=@ud acc=@da]
      =/  m=(unit stored-msg:lcm)  (~(get by messages.conv) seq)
      ?~  m  acc
      ?:((lth created.u.m acc) created.u.m acc)
    =.  latest
      %+  roll  chunk
      |=  [seq=@ud acc=@da]
      =/  m=(unit stored-msg:lcm)  (~(get by messages.conv) seq)
      ?~  m  acc
      ?:((gth created.u.m acc) created.u.m acc)
    ::  create summary
    =/  sid=@ud  next-sum.conv
    =/  =summary:lcm
      :*  sid  %leaf  0
          summary-text  (estimate-tokens summary-text)
          chunk-set  ~
          earliest  latest  now.bowl
      ==
    =.  summaries.conv  (~(put by summaries.conv) sid summary)
    =.  next-sum.conv  +(sid)
    ::  replace compacted items in context-items with summary ref
    =/  new-items=(list context-item:lcm)
      =/  inserted=?  %.n
      %+  murn  context-items.conv
      |=  ci=context-item:lcm
      ^-  (unit context-item:lcm)
      ?.  ?=(%msg -.ci)  `ci
      ?.  (~(has in chunk-set) seq.ci)  `ci
      ::  replace first compacted msg with summary, skip rest
      ?.  inserted
        =.  inserted  %.y
        `[%sum sid]
      ~
    =.  context-items.conv  new-items
    =.  conversations  (~(put by conversations) key conv)
    =.  compact-state  [%idle ~]
    %-  (slog leaf+"lcm: created summary {(a-co:co sid)} ({(a-co:co (lent chunk))} msgs → {(a-co:co (estimate-tokens summary-text))} tokens)" ~)
    `this
  ==
::
++  on-fail  on-fail:def
--
