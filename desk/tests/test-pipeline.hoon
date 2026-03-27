::  e2e pipeline tests
/-  claw, lcm
/+  *test
=>
|%
++  lcm-key
  |=  =msg-source:claw
  ^-  @t
  ?-  -.msg-source
    %direct   'direct'
    %dm       (rap 3 'dm/' (scot %p ship.msg-source) ~)
    %channel  (rap 3 'channel/' kind.msg-source '/' (scot %p host.msg-source) '/' name.msg-source ~)
  ==
++  estimate-tokens
  |=  text=@t
  ^-  @ud
  (div (add (met 3 text) 3) 4)
++  assemble
  |=  [=conversation:lcm budget=@ud]
  ^-  (list [@t @t])
  =/  items=(list context-item:lcm)  context-items.conversation
  =/  len=@ud  (lent items)
  =/  tail-n=@ud  (min len 16)
  =/  fresh=(list context-item:lcm)  (slag (sub len tail-n) items)
  =/  before=(list context-item:lcm)  (scag (sub len tail-n) items)
  =/  fresh-msgs=(list [@t @t])
    %+  murn  fresh
    |=  ci=context-item:lcm
    ^-  (unit [@t @t])
    ?-  -.ci
        %msg
      =/  m=(unit stored-msg:lcm)  (~(get by messages.conversation) seq.ci)
      ?~  m  ~
      `[role.u.m content.u.m]
        %sum
      =/  s=(unit summary:lcm)  (~(get by summaries.conversation) id.ci)
      ?~  s  ~
      `['system' content.u.s]
    ==
  =/  fresh-tok=@ud
    %+  roll  fresh-msgs
    |=  [[r=@t c=@t] acc=@ud]
    (add acc (estimate-tokens c))
  =/  remaining=@ud  ?:((gth fresh-tok budget) 0 (sub budget fresh-tok))
  =/  prefix=(list [@t @t])  ~
  |-
  ?~  before  (weld prefix fresh-msgs)
  =/  ci  i.before
  ?.  ?=(%msg -.ci)  $(before t.before)
  =/  m=(unit stored-msg:lcm)  (~(get by messages.conversation) seq.ci)
  ?~  m  $(before t.before)
  ?:  (gth token-est.u.m remaining)
    $(before t.before)
  %=  $
    before     t.before
    remaining  (sub remaining token-est.u.m)
    prefix     (snoc prefix [role.u.m content.u.m])
  ==
++  ingest
  |=  [=conversation:lcm role=@t con=@t]
  ^-  conversation:lcm
  =/  tok=@ud  (estimate-tokens con)
  =/  =stored-msg:lcm  [next-seq.conversation role con tok ~2024.1.1]
  =.  messages.conversation
    (~(put by messages.conversation) next-seq.conversation stored-msg)
  =.  context-items.conversation
    (snoc context-items.conversation [%msg next-seq.conversation])
  =.  next-seq.conversation  +(next-seq.conversation)
  conversation
--
|%
++  test-pipeline-dm
  =/  key=@t  (lcm-key [%dm ~nes])
  =/  conv=conversation:lcm  *conversation:lcm
  =.  conv  (ingest conv 'user' 'What is Urbit?')
  =.  conv  (ingest conv 'assistant' 'A personal server.')
  =/  ctx  (assemble conv 10.000)
  =/  [a=@t b=@t]  (snag 0 ctx)
  ;:  weld
    (expect-eq !>('dm/~nes') !>(key))
    (expect-eq !>(2) !>((lent ctx)))
    (expect-eq !>('user') !>(a))
    (expect-eq !>('What is Urbit?') !>(b))
  ==
++  test-pipeline-channel
  =/  key=@t  (lcm-key [%channel %chat ~zod %general ~nes])
  =/  conv=conversation:lcm  *conversation:lcm
  =.  conv  (ingest conv 'user' 'Hey bot')
  =.  conv  (ingest conv 'assistant' 'Hello!')
  ;:  weld
    (expect-eq !>('channel/chat/~zod/general') !>(key))
    (expect-eq !>(2) !>((lent (assemble conv 10.000))))
  ==
++  test-pipeline-isolation
  =/  convs=(map @t conversation:lcm)  *(map @t conversation:lcm)
  =.  convs  (~(put by convs) (lcm-key [%dm ~nes]) (ingest *conversation:lcm 'user' 'dm'))
  =.  convs  (~(put by convs) (lcm-key [%channel %chat ~zod %general ~nes]) (ingest *conversation:lcm 'user' 'ch'))
  (expect-eq !>(2) !>(~(wyt by convs)))
++  test-pipeline-long
  =/  conv=conversation:lcm  *conversation:lcm
  =.  conv
    =/  n=@ud  0
    |-
    ?:  =(n 30)  conv
    =.  conv  (ingest conv 'user' (crip "q {(a-co:co n)}"))
    =.  conv  (ingest conv 'assistant' (crip "a {(a-co:co n)}"))
    $(n +(n))
  ;:  weld
    (expect-eq !>(60) !>(~(wyt by messages.conv)))
    (expect-eq !>(60) !>((lent (assemble conv 100.000))))
  ==
++  test-pipeline-fresh-tail
  =/  conv=conversation:lcm  *conversation:lcm
  =.  conv
    =/  n=@ud  0
    |-
    ?:  =(n 20)  conv
    =.  conv  (ingest conv 'user' (crip "m {(a-co:co n)}"))
    $(n +(n))
  =/  ctx  (assemble conv 1)
  =/  [a=@t b=@t]  (snag 15 ctx)
  ;:  weld
    (expect-eq !>(16) !>((lent ctx)))
    (expect-eq !>('m 19') !>(b))
  ==
--
