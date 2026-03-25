::  claw: minimal llm agent harness with groups dm integration
::
::  sends prompts to openrouter with full structured context.
::  watches %chat for dms from whitelisted ships, processes
::  them through the llm, and responds via dm.
::
/-  claw
/-  c=chat
/-  d=channels
/+  dbug, default-agent
|%
+$  card  card:agent:gall
+$  versioned-state  $%(state-0:claw state-1:claw state-2:claw)
::
++  build-prompt
  |=  [=bowl:gall context=(map @tas @t)]
  ^-  @t
  =/  sections=(list [@t @tas])
    :~  ['Identity' %identity]
        ['Personality & Behavior' %soul]
        ['Agent' %agent]
        ['User Profile' %user]
        ['Memory' %memory]
    ==
  =/  parts=(list @t)
    %+  murn  sections
    |=  [header=@t field=@tas]
    =/  val=(unit @t)  (~(get by context) field)
    ?~  val  ~
    ?:  =('' u.val)  ~
    `(crip "# {(trip header)}\0a\0a{(trip u.val)}")
  =/  standard=(set @tas)
    (silt `(list @tas)`~[%identity %soul %agent %user %memory])
  =/  extras=(list [@tas @t])
    %+  murn  ~(tap by context)
    |=  [k=@tas v=@t]
    ?:  (~(has in standard) k)  ~
    ?:  =('' v)  ~
    `[k v]
  =.  parts
    %+  weld  parts
    %+  turn  extras
    |=  [k=@tas v=@t]
    (crip "# {(trip k)}\0a\0a{(trip v)}")
  =.  parts
    %+  snoc  parts
    %-  crip
    ;:  weld
      "# System\0a\0a"
      "Ship: {(scow %p our.bowl)}\0a"
      "Time: {(scow %da now.bowl)}"
    ==
  ?~  parts  ''
  =/  out=@t  i.parts
  =/  rem=(list @t)  t.parts
  |-
  ?~  rem  out
  $(rem t.rem, out (rap 3 out '\0a\0a---\0a\0a' i.rem ~))
::
::  +story-to-text: extract plain text from a story
::
++  story-to-text
  |=  =story:d
  ^-  @t
  =/  parts=(list @t)
    %+  murn  story
    |=  =verse:d
    ?.  ?=([%inline *] verse)  ~
    =/  text=@t  (inlines-to-text p.verse)
    ?:  =('' text)  ~
    `text
  ?~  parts  ''
  =/  out=@t  i.parts
  =/  rem=(list @t)  t.parts
  |-
  ?~  rem  out
  $(rem t.rem, out (rap 3 out '\0a' i.rem ~))
::
++  inlines-to-text
  |=  ils=(list inline:d)
  ^-  @t
  ?~  ils  ''
  =/  this=@t
    ?@  i.ils  i.ils
    ?+  -.i.ils  ''
      %bold         $(ils p.i.ils)
      %italics      $(ils p.i.ils)
      %strike       $(ils p.i.ils)
      %blockquote   $(ils p.i.ils)
      %inline-code  p.i.ils
      %code         p.i.ils
      %break        '\0a'
    ==
  =/  rest=@t  $(ils t.ils)
  ?:  =('' this)  rest
  ?:  =('' rest)  this
  (rap 3 this rest ~)
::
++  make-llm-request
  |=  [=bowl:gall api-key=@t model=@t sys-prompt=@t msgs=(list msg:claw) =wire]
  ^-  card
  =/  api-msgs=(list msg:claw)
    [['system' sys-prompt] msgs]
  =/  msgs-json=json
    :-  %a
    %+  turn  api-msgs
    |=  =msg:claw
    %-  pairs:enjs:format
    :~  ['role' s+role.msg]
        ['content' s+content.msg]
    ==
  =/  body=json
    %-  pairs:enjs:format
    :~  ['model' s+model]
        ['messages' msgs-json]
    ==
  =/  body-cord=@t  (en:json:html body)
  =/  hed=(list [key=@t value=@t])
    :~  ['Content-Type' 'application/json']
        ['Authorization' (crip "Bearer {(trip api-key)}")]
    ==
  =/  req=request:http
    [%'POST' 'https://openrouter.ai/api/v1/chat/completions' hed `(as-octs:mimes:html body-cord)]
  [%pass wire %arvo %i %request req *outbound-config:iris]
::
++  parse-llm-response
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
=|  state-2:claw
=*  state  -
^-  agent:gall
|_  =bowl:gall
+*  this  .
    def   ~(. (default-agent this %|) bowl)
::
++  on-init
  ^-  (quip card _this)
  %-  (slog leaf+"claw: initialized" ~)
  =/  default-ctx=(map @tas @t)
    %-  ~(gas by *(map @tas @t))
    :~  :-  %identity
        %-  crip
        ;:  weld
          "You are an AI assistant running natively on the Urbit network.\0a"
          "You are a sovereign computing entity on a personal server.\0a"
          "Your responses and data live on your owner's ship, not on any\0a"
          "external infrastructure."
        ==
    ::
        :-  %soul
        %-  crip
        ;:  weld
          "You are helpful, knowledgeable, and concise.\0a"
          "You have opinions and share them when relevant.\0a"
          "You are honest about what you don't know.\0a"
          "Keep responses focused. Avoid unnecessary verbosity.\0a"
          "When asked about yourself, you know you run on Urbit\0a"
          "and can describe your capabilities accurately."
        ==
    ::
        :-  %agent
        %-  crip
        ;:  weld
          "You are claw, a native Urbit LLM agent.\0a"
          "You communicate via the OpenRouter API.\0a"
          "You maintain conversation history and structured context\0a"
          "across sessions. Your context includes identity, personality,\0a"
          "user profile, and memory files that persist on your ship.\0a"
          "You can accumulate knowledge in your memory over time.\0a"
          "You are connected to the Urbit network and can receive\0a"
          "direct messages from whitelisted ships."
        ==
    ==
  `this(model 'anthropic/claude-sonnet-4', pending %.n, context default-ctx)
::
++  on-save  !>(state)
::
++  on-load
  |=  =vase
  ^-  (quip card _this)
  =/  old  !<(versioned-state vase)
  ?-  -.old
      %2  `this(state old)
      %1
    `this(state [%2 api-key.old model.old history.old pending.old last-error.old context.old ~ ~ ~])
      %0
    =/  ctx=(map @tas @t)  *(map @tas @t)
    =?  ctx  !=('' system-prompt.old)
      (~(put by ctx) %agent system-prompt.old)
    `this(state [%2 api-key.old model.old history.old pending.old last-error.old ctx ~ ~ ~])
  ==
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?>  =(src our):bowl
  ?.  ?=(%claw-action mark)
    (on-poke:def mark vase)
  =/  act=action:claw  !<(action:claw vase)
  ?-  -.act
      %set-key
    %-  (slog leaf+"claw: api key set" ~)
    `this(api-key key.act)
  ::
      %set-model
    %-  (slog leaf+"claw: model set to {(trip model.act)}" ~)
    `this(model model.act)
  ::
      %set-context
    %-  (slog leaf+"claw: context '{(trip field.act)}' set" ~)
    `this(context (~(put by context) field.act content.act))
  ::
      %append-context
    =/  existing=@t  (fall (~(get by context) field.act) '')
    =/  new=@t
      ?:  =('' existing)  content.act
      (rap 3 existing '\0a' content.act ~)
    %-  (slog leaf+"claw: context '{(trip field.act)}' appended" ~)
    `this(context (~(put by context) field.act new))
  ::
      %del-context
    %-  (slog leaf+"claw: context '{(trip field.act)}' deleted" ~)
    `this(context (~(del by context) field.act))
  ::
      %clear
    %-  (slog leaf+"claw: history cleared" ~)
    `this(history ~, pending %.n)
  ::
      %add-ship
    %-  (slog leaf+"claw: added {(scow %p ship.act)} as {(trip ?:(=(%owner role.act) 'owner' 'allowed'))}" ~)
    =.  whitelist  (~(put by whitelist) ship.act role.act)
    :_  this
    :~  [%pass /dm-rsvp/(scot %p ship.act) %agent [our.bowl %chat] %poke %chat-dm-rsvp !>([ship.act %.y])]
        [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %watch /dm/(scot %p ship.act)]
    ==
  ::
      %del-ship
    %-  (slog leaf+"claw: removed {(scow %p ship.act)}" ~)
    =.  whitelist  (~(del by whitelist) ship.act)
    =.  dm-history  (~(del by dm-history) ship.act)
    =.  dm-pending  (~(del in dm-pending) ship.act)
    :_  this
    :~  [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %leave ~]
    ==
  ::
      %prompt
    ?:  pending  ~|(%claw-busy !!)
    ?:  =('' api-key)  ~|(%claw-no-api-key !!)
    =/  new-msg=msg:claw  ['user' content.act]
    =.  history  (snoc history new-msg)
    =.  pending  %.y
    =/  sys-prompt=@t  (build-prompt bowl context)
    %-  (slog leaf+"claw: sending prompt..." ~)
    :_  this
    :~  (make-llm-request bowl api-key model sys-prompt history /query)
    ==
  ==
::
++  on-watch
  |=  =path
  ^-  (quip card _this)
  ?+  path  (on-watch:def path)
      [%updates ~]  ?>  =(src our):bowl  `this
  ==
::
++  on-leave  on-leave:def
::
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  ?+  path  ~
      [%x %history ~]
    =/  j=json
      :-  %a
      %+  turn  history
      |=  =msg:claw
      %-  pairs:enjs:format
      :~  ['role' s+role.msg]  ['content' s+content.msg]  ==
    ``json+!>(j)
      [%x %last ~]
    ?~  history  ``json+!>(s+'no messages yet')
    =/  lst=msg:claw  (rear history)
    ``json+!>((pairs:enjs:format ~[['role' s+role.lst] ['content' s+content.lst]]))
      [%x %config ~]
    =/  j=json
      %-  pairs:enjs:format
      :~  ['model' s+model]  ['pending' b+pending]  ['last-error' s+last-error]
          :-  'whitelist'
          %-  pairs:enjs:format
          %+  turn  ~(tap by whitelist)
          |=  [s=ship r=ship-role:claw]
          [(scot %p s) s+?:(=(r %owner) 'owner' 'allowed')]
      ==
    ``json+!>(j)
      [%x %context @ ~]
    =/  field=@tas  (slav %tas i.t.t.path)
    =/  val=(unit @t)  (~(get by context) field)
    ?~  val  ``json+!>(~)
    ``json+!>(s+u.val)
      [%x %context ~]
    %-  some  %-  some
    json+!>((pairs:enjs:format (turn ~(tap by context) |=([k=@tas v=@t] [(scot %tas k) s+v]))))
      [%x %prompt ~]
    ``json+!>(s+(build-prompt bowl context))
      [%x %dm-history @ ~]
    =/  who=ship  (slav %p i.t.t.path)
    =/  hist=(list msg:claw)  (fall (~(get by dm-history) who) ~)
    ``json+!>(a+(turn hist |=(=msg:claw (pairs:enjs:format ~[['role' s+role.msg] ['content' s+content.msg]]))))
  ==
::
++  on-agent
  |=  [=wire =sign:agent:gall]
  ^-  (quip card _this)
  ?+  wire  (on-agent:def wire sign)
      [%dm-watch @ ~]
    =/  who=ship  (slav %p i.t.wire)
    ?+  -.sign  `this
        %watch-ack
      ?~  p.sign
        %-  (slog leaf+"claw: watching dms from {(scow %p who)}" ~)
        `this
      %-  (slog leaf+"claw: dm watch failed for {(scow %p who)}" ~)
      `this
        %kick
      :_  this
      :~  [%pass /dm-watch/(scot %p who) %agent [our.bowl %chat] %watch /dm/(scot %p who)]
      ==
        %fact
      ::  extract the response from the vase
      ::  the fact is a writ-response: [whom id response-delta]
      ::
      =/  noun  +.q.cage.sign
      ?.  ?=([* * [%add *]] noun)  `this
      =/  response-delta  +.+.noun
      ::  [%add memo time] where memo = [content author sent]
      =/  memo-noun  -.+.response-delta
      =/  content-noun  -.memo-noun
      =/  from=ship  ;;(@p -.+.memo-noun)
      ::  skip our own messages
      ?:  =(from our.bowl)  `this
      ::  check whitelist
      ?.  (~(has by whitelist) from)
        %-  (slog leaf+"claw: ignoring dm from {(scow %p from)}" ~)
        `this
      ::  skip if already processing
      ?:  (~(has in dm-pending) from)  `this
      ::  extract text from story content
      =/  text=@t  (story-to-text ;;(story:d content-noun))
      ?:  =('' text)  `this
      %-  (slog leaf+"claw: dm from {(scow %p from)}: {(trip text)}" ~)
      ::  add to history and send to llm
      =/  hist=(list msg:claw)  (fall (~(get by dm-history) from) ~)
      =.  hist  (snoc hist ['user' text])
      =.  dm-history  (~(put by dm-history) from hist)
      =.  dm-pending  (~(put in dm-pending) from)
      ?:  =('' api-key)
        %-  (slog leaf+"claw: no api key, cannot respond" ~)
        =.  dm-pending  (~(del in dm-pending) from)
        `this
      =/  sys-prompt=@t  (build-prompt bowl context)
      :_  this
      :~  (make-llm-request bowl api-key model sys-prompt hist /dm-query/(scot %p from))
      ==
    ==
  ::
      [%dm-rsvp @ ~]
    ?+  -.sign  `this
        %poke-ack
      ?~  p.sign  `this
      %-  (slog leaf+"claw: dm rsvp failed" ~)
      `this
    ==
  ::
      [%dm-send @ ~]
    ?+  -.sign  `this
        %poke-ack
      ?~  p.sign
        %-  (slog leaf+"claw: dm sent to {(trip i.t.wire)}" ~)
        `this
      %-  (slog leaf+"claw: dm send failed to {(trip i.t.wire)}" ~)
      `this
    ==
  ==
::
++  on-arvo
  |=  [=wire sign=sign-arvo]
  ^-  (quip card _this)
  ?+  wire  (on-arvo:def wire sign)
  ::
      [%query ~]
    ?.  ?=([%iris %http-response *] sign)  `this
    =/  resp=client-response:iris  client-response.sign
    ?.  ?=(%finished -.resp)  `this
    =/  code=@ud  status-code.response-header.resp
    ?.  =(200 code)
      =/  err=@t  ?~(full-file.resp 'http error' q.data.u.full-file.resp)
      %-  (slog leaf+"claw error [{(a-co:co code)}]" ~)
      =.  pending  %.n
      =.  last-error  err
      :_  this
      :~  [%give %fact ~[/updates] %claw-update !>(`update:claw`[%error err])]  ==
    ?~  full-file.resp
      =.  pending  %.n
      =.  last-error  'empty response'
      :_  this
      :~  [%give %fact ~[/updates] %claw-update !>(`update:claw`[%error 'empty response'])]  ==
    =/  parsed=(unit @t)  (parse-llm-response q.data.u.full-file.resp)
    ?~  parsed
      =.  pending  %.n
      =.  last-error  q.data.u.full-file.resp
      :_  this
      :~  [%give %fact ~[/updates] %claw-update !>(`update:claw`[%error 'parse error'])]  ==
    =/  content=@t  u.parsed
    =.  history  (snoc history ['assistant' content])
    =.  pending  %.n
    =.  last-error  ''
    %-  (slog leaf+"< {(trip content)}" ~)
    :_  this
    :~  [%give %fact ~[/updates] %claw-update !>(`update:claw`[%response ['assistant' content]])]  ==
  ::
      [%dm-query @ ~]
    =/  who=ship  (slav %p i.t.wire)
    ?.  ?=([%iris %http-response *] sign)  `this
    =/  resp=client-response:iris  client-response.sign
    ?.  ?=(%finished -.resp)  `this
    =.  dm-pending  (~(del in dm-pending) who)
    =/  code=@ud  status-code.response-header.resp
    ?.  =(200 code)
      =/  err=@t  ?~(full-file.resp 'http error' q.data.u.full-file.resp)
      %-  (slog leaf+"claw dm error [{(a-co:co code)}]" ~)
      =.  last-error  err
      `this
    ?~  full-file.resp  `this
    =/  parsed=(unit @t)  (parse-llm-response q.data.u.full-file.resp)
    ?~  parsed
      %-  (slog leaf+"claw dm error: parse failed" ~)
      =.  last-error  q.data.u.full-file.resp
      `this
    =/  content=@t  u.parsed
    ::  save to dm history
    =/  hist=(list msg:claw)  (fall (~(get by dm-history) who) ~)
    =.  dm-history  (~(put by dm-history) who (snoc hist ['assistant' content]))
    %-  (slog leaf+"claw dm to {(scow %p who)}: {(trip content)}" ~)
    ::  send dm via %chat
    =/  dm-story=story:d  ~[[%inline `(list inline:d)`~[content]]]
    =/  dm-memo=memo:d  [content=dm-story author=our.bowl sent=now.bowl]
    =/  dm-essay=essay:c  [dm-memo [%chat /] ~ ~]
    =/  dm-delta=delta:writs:c  [%add dm-essay ~]
    =/  dm-diff=diff:writs:c  [[our.bowl now.bowl] dm-delta]
    =/  dm-act=action:dm:c  [who dm-diff]
    :_  this
    :~  [%pass /dm-send/(scot %p who) %agent [our.bowl %chat] %poke %chat-dm-action-1 !>(dm-act)]
        [%give %fact ~[/updates] %claw-update !>(`update:claw`[%dm-response who ['assistant' content]])]
    ==
  ==
::
++  on-fail  on-fail:def
--
