/-  lcm
/+  *test
=>
|%
++  estimate-tokens
  |=  text=@t
  ^-  @ud
  (div (add (met 3 text) 3) 4)
++  make-msg
  |=  [seq=@ud role=@t con=@t]
  ^-  stored-msg:lcm
  [seq role con (estimate-tokens con) ~2024.1.1]
++  make-conv
  |=  msgs=(list stored-msg:lcm)
  ^-  conversation:lcm
  :*  (malt (turn msgs |=(m=stored-msg:lcm [seq.m m])))
      *(map @ud summary:lcm)
      (turn msgs |=(m=stored-msg:lcm [%msg seq.m]))
      (lent msgs)
      0
  ==
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
++  select-leaf-chunk
  |=  [=conversation:lcm max-tokens=@ud fresh-tail-n=@ud]
  ^-  (list @ud)
  =/  items  context-items.conversation
  =/  len  (lent items)
  =/  cutoff  (sub len (min len fresh-tail-n))
  =/  eligible  (scag cutoff items)
  =/  collected=(list @ud)  ~
  =/  tok=@ud  0
  |-
  ?~  eligible  (flop collected)
  ?.  ?=(%msg -.i.eligible)  $(eligible t.eligible)
  =/  m=(unit stored-msg:lcm)  (~(get by messages.conversation) seq.i.eligible)
  ?~  m  $(eligible t.eligible)
  ?:  (gth (add tok token-est.u.m) max-tokens)
    ?~  collected
      (flop [seq.i.eligible collected])
    (flop collected)
  %=  $
    eligible   t.eligible
    tok        (add tok token-est.u.m)
    collected  [seq.i.eligible collected]
  ==
--
|%
++  test-tokens
  (expect-eq !>(0) !>((context-tokens (make-conv ~))))
++  test-assemble
  (expect-eq !>(~) !>((assemble (make-conv ~) 1.000)))
++  test-chunk
  (expect-eq !>(~) !>((select-leaf-chunk (make-conv ~) 1.000 16)))
++  test-twenty
  =/  msgs=(list stored-msg:lcm)
    %+  turn  (gulf 0 19)
    |=  n=@ud
    (make-msg n 'user' (crip "m {(a-co:co n)}"))
  (expect-eq !>(20) !>((lent (assemble (make-conv msgs) 100.000))))
++  test-estimate-empty
  (expect-eq !>(0) !>((estimate-tokens '')))
++  test-estimate-short
  (expect-eq !>(2) !>((estimate-tokens 'hello')))
++  test-assemble-order
  =/  conv  (make-conv ~[(make-msg 0 'user' 'first') (make-msg 1 'assistant' 'second')])
  =/  r  (assemble conv 10.000)
  =/  [a=@t b=@t]  (snag 0 r)
  =/  [c=@t d=@t]  (snag 1 r)
  ;:  weld
    (expect-eq !>('first') !>(b))
    (expect-eq !>('second') !>(d))
  ==
++  test-assemble-tight
  =/  msgs=(list stored-msg:lcm)
    %+  turn  (gulf 0 19)
    |=  n=@ud
    (make-msg n 'user' (crip "m {(a-co:co n)}"))
  (expect-eq !>(16) !>((lent (assemble (make-conv msgs) 5))))
++  test-chunk-few
  =/  conv  (make-conv ~[(make-msg 0 'user' 'a') (make-msg 1 'user' 'b')])
  (expect-eq !>(~) !>((select-leaf-chunk conv 1.000 16)))
++  test-chunk-eligible
  =/  msgs=(list stored-msg:lcm)
    %+  turn  (gulf 0 19)
    |=  n=@ud
    (make-msg n 'user' (crip "m {(a-co:co n)}"))
  (expect-eq !>(~[0 1 2 3]) !>((select-leaf-chunk (make-conv msgs) 1.000 16)))
--
