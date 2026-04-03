::  claw nexus: multi-bot LLM agent harness
::
::  root process: subscribes to activity + DMs, routes messages to bot processes
::  bot process: receives messages, calls LLM, sends replies
::
/-  a=activity
/-  d=channels
/-  c=chat
/-  claw
/-  lcm
/+  nexus, tarball, io=fiberio, loader, story-parse
!:
^-  nexus:nexus
=>
|%
::  +jget: get json string value from object, with default
::
++  jget
  |=  [j=json key=@t def=@t]
  ^-  @t
  ?.  ?=([%o *] j)  def
  =/  v=(unit json)  (~(get by p.j) key)
  ?~  v  def
  ?.  ?=([%s *] u.v)  def
  p.u.v
::  +me: extract json object map
::
++  me
  |=  =json
  ^-  (unit (map @t ^json))
  ?.  ?=([%o *] json)  ~
  `p.json
::  +parse-llm-response: parse openrouter response
::
++  parse-llm-response
  |=  body=@t
  ^-  (unit ?([%text content=@t] [%tools content=@t calls=(list [id=@t name=@t arguments=@t])]))
  =/  jon=(unit json)  (de:json:html body)
  ?~  jon  ~
  %-  mole  |.
  =/  choices=json  (need (~(get by (need (me u.jon))) 'choices'))
  ?.  ?=([%a [* *]] choices)  !!
  =/  choice=json  i.p.choices
  =/  msg=json  (need (~(get by (need (me choice))) 'message'))
  =/  msg-map=(map @t json)  (need (me msg))
  =/  tc=(unit json)  (~(get by msg-map) 'tool_calls')
  ?~  tc
    =/  content=json  (need (~(get by msg-map) 'content'))
    ?.  ?=([%s *] content)  !!
    [%text p.content]
  ?.  ?=([%a *] u.tc)  !!
  =/  tc-content=@t
    =/  ct=(unit json)  (~(get by msg-map) 'content')
    ?~  ct  ''
    ?:  ?=([%s *] u.ct)  p.u.ct
    ''
  =/  calls=(list [id=@t name=@t arguments=@t])
    %+  turn  p.u.tc
    |=  tc-item=json
    =/  tcm=(map @t json)  (need (me tc-item))
    =/  fn=json  (need (~(get by tcm) 'function'))
    =/  fnm=(map @t json)  (need (me fn))
    :+  (so:dejs:format (need (~(get by tcm) 'id')))
      (so:dejs:format (need (~(get by fnm) 'name')))
    (so:dejs:format (need (~(get by fnm) 'arguments')))
  [%tools tc-content calls]
::  +find-tagged-bots: find bots whose name appears as [%tag] in story
::
++  find-tagged-bots
  |=  [bot-names=(map @tas @t) =story:d]
  ^-  (list @tas)
  %+  murn  ~(tap by bot-names)
  |=  [id=@tas name=@t]
  =/  nick=@t  name
  ?.  %+  lien  story
      |=  =verse:d
      ?.  ?=(%inline -.verse)  %.n
      %+  lien  p.verse
      |=  =inline:d
      ?&  ?=([%tag *] inline)
          =(nick p.inline)
      ==
    ~
  `id
::  +find-named-bots: find bots by nickname substring in text
::
++  find-named-bots
  |=  [bot-names=(map @tas @t) text=@t]
  ^-  (list @tas)
  %+  murn  ~(tap by bot-names)
  |=  [id=@tas name=@t]
  =/  nick=tape  (cass (trip name))
  ?~  nick  ~
  ?.  !=(~ (find nick (cass (trip text))))  ~
  `id
::  +bot-author: build author field using bot-meta when configured
::
++  bot-author
  |=  [our=ship bname=(unit @t) bavatar=(unit @t)]
  ^-  author:d
  ?~  bname  our
  [ship=our nickname=bname avatar=bavatar]
::
::  ┌──────────────────────────────────────────────────┐
::  │ ROOT LOOP                                        │
::  └──────────────────────────────────────────────────┘
::
++  root-loop
  |=  our=@p
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =|  seen-msgs=(set @t)
  |-
  ::  multiplex: accept either activity facts or DM watch facts
  ;<  ev=[tag=@tas dat=cage]  bind:m
    |=  input:fiber:nexus
    :+  ~  state
    ?~  in  [%wait ~]
    ?.  ?=(%agent -.u.in)  [%skip ~]
    ?:  ?&  =(wire.u.in /activity)
            ?=([%fact *] sign.u.in)
        ==
      [%done %activity cage.sign.u.in]
    ?:  ?&  =(wire.u.in /activity)
            ?=([%kick ~] sign.u.in)
        ==
      [%done %kick-activity *cage]
    ?:  ?&  =(wire.u.in /self-dm)
            ?=([%fact *] sign.u.in)
        ==
      [%done %self-dm cage.sign.u.in]
    ?:  ?&  =(wire.u.in /self-dm)
            ?=([%kick ~] sign.u.in)
        ==
      [%done %kick-dm *cage]
    [%skip ~]
  ::
  ?+    tag.ev  $
  ::
  ::  resubscribe on kick
      %kick-activity
    ;<  ~  bind:m  (gall-watch:io /activity [our %activity] /v4)
    $
  ::
      %kick-dm
    ;<  ~  bind:m  (gall-watch:io /self-dm [our %chat] /dm/(scot %p our))
    $
  ::
  ::  handle activity event
      %activity
    =/  result=(unit [event-type=@tas event-data=json])
      %-  mole  |.
      =/  upd=update:a  !<(update:a q.dat.ev)
      ?>  ?=(%add -.upd)
      =/  incoming=incoming-event:a  -.event.upd
      ?+  -.incoming  !!
      ::
          %post
        =/  from=ship  p.id.key.incoming
        =/  text=@t  (story-to-text:story-parse content.incoming)
        =/  =nest:d  channel.incoming
        :-  %post
        %-  pairs:enjs:format
        :~  ['from' s+(scot %p from)]
            ['text' s+text]
            ['msg_id' s+(scot %da q.id.key.incoming)]
            ['nest_kind' s+kind.nest]
            ['nest_ship' s+(scot %p ship.nest)]
            ['nest_name' s+name.nest]
            ['story' (story-to-json content.incoming)]
        ==
      ::
          %dm-post
        =/  from=ship  p.id.key.incoming
        =/  text=@t  (story-to-text:story-parse content.incoming)
        :-  %dm-post
        %-  pairs:enjs:format
        :~  ['from' s+(scot %p from)]
            ['text' s+text]
            ['msg_id' s+(scot %da q.id.key.incoming)]
        ==
      ::
          %reply
        =/  from=ship  p.id.key.incoming
        =/  text=@t  (story-to-text:story-parse content.incoming)
        =/  =nest:d  channel.incoming
        :-  %reply
        %-  pairs:enjs:format
        :~  ['from' s+(scot %p from)]
            ['text' s+text]
            ['msg_id' s+(scot %da q.id.key.incoming)]
            ['parent_id' s+(scot %da q.id.parent.incoming)]
            ['parent_author' s+(scot %p p.id.parent.incoming)]
            ['nest_kind' s+kind.nest]
            ['nest_ship' s+(scot %p ship.nest)]
            ['nest_name' s+name.nest]
            ['story' (story-to-json content.incoming)]
        ==
      ::
          %dm-reply
        =/  from=ship  p.id.key.incoming
        =/  text=@t  (story-to-text:story-parse content.incoming)
        :-  %dm-reply
        %-  pairs:enjs:format
        :~  ['from' s+(scot %p from)]
            ['text' s+text]
            ['msg_id' s+(scot %da q.id.key.incoming)]
            ['parent_id' s+(scot %da q.id.parent.incoming)]
            ['parent_author' s+(scot %p p.id.parent.incoming)]
        ==
      ==
    ?~  result  $
    =/  [event-type=@tas event-data=json]  u.result
    =/  from=@p  (slav %p (jget event-data 'from' '~zod'))
    ::  ignore our own messages
    ?:  =(from our)  $
    =/  text=@t  (jget event-data 'text' '')
    ?:  =('' text)  $
    ::  dedup
    =/  evt-id=@t  (rap 3 event-type '/' (jget event-data 'from' '') '/' (jget event-data 'msg_id' '') ~)
    ?:  (~(has in seen-msgs) evt-id)  $
    =.  seen-msgs  (~(put in seen-msgs) evt-id)
    =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
    ::  scan bots directory for bot configs
    ;<  bot-names=(map @tas @t)  bind:m  scan-bot-names
    ?~  bot-names  $
    ::  route based on event type
    ?+    event-type  $
        %post
      =/  story-json=json  (need (~(get by (need (me event-data))) 'story'))
      =/  =story:d  (json-to-story story-json)
      =/  tagged=(list @tas)  (find-tagged-bots bot-names story)
      =/  named=(list @tas)  ?^(tagged ~ (find-named-bots bot-names text))
      =/  match=(list @tas)  (weld tagged named)
      ?~  match  $
      %-  (slog leaf+"claw-grub: routing post to {<match>}" ~)
      =/  rem=(list @tas)  match
      |-
      ?~  rem  ^$
      ;<  ~  bind:m
        (poke:io /route (bot-road i.rem) %json !>(event-data))
      $(rem t.rem)
    ::
        %reply
      =/  story-json=json  (need (~(get by (need (me event-data))) 'story'))
      =/  =story:d  (json-to-story story-json)
      =/  tagged=(list @tas)  (find-tagged-bots bot-names story)
      =/  named=(list @tas)  ?^(tagged ~ (find-named-bots bot-names text))
      =/  match=(list @tas)  (weld tagged named)
      ?~  match  $
      %-  (slog leaf+"claw-grub: routing reply to {<match>}" ~)
      =/  rem=(list @tas)  match
      |-
      ?~  rem  ^$
      ;<  ~  bind:m
        (poke:io /route (bot-road i.rem) %json !>(event-data))
      $(rem t.rem)
    ::
        %dm-post
      =/  named=(list @tas)  (find-named-bots bot-names text)
      ?~  named  $
      =/  bot-id=@tas  i.named
      %-  (slog leaf+"claw-grub: routing dm to {(trip bot-id)}" ~)
      ;<  ~  bind:m
        (poke:io /route (bot-road bot-id) %json !>(event-data))
      $
    ::
        %dm-reply
      =/  named=(list @tas)  (find-named-bots bot-names text)
      ?~  named  $
      =/  bot-id=@tas  i.named
      ;<  ~  bind:m
        (poke:io /route (bot-road bot-id) %json !>(event-data))
      $
    ==
  ::
      %self-dm
    $  :: TODO: handle self-dm watch facts
  ==
::
++  bot-road
  |=  bot-id=@tas
  ^-  road:tarball
  [%& %& /bots/[bot-id] %'main.sig']
::
++  scan-bot-names
  =/  m  (fiber:fiber:nexus ,(map @tas @t))
  ^-  form:m
  ::  read bot registry from /bots-registry.json
  ;<  reg-seen=seen:nexus  bind:m
    (peek:io /reg (cord-to-road:tarball './bots-registry.json') `%json)
  ?.  ?=([%& %file *] reg-seen)  (pure:m ~)
  =/  reg=json  !<(json q.cage.p.reg-seen)
  ?.  ?=([%o *] reg)  (pure:m ~)
  ::  registry is {bot-id: name, ...}
  %-  pure:m
  %-  ~(gas by *(map @tas @t))
  %+  murn  ~(tap by p.reg)
  |=  [id=@t val=json]
  ?.  ?=([%s *] val)  ~
  ?:  =('' p.val)  ~
  `[(crip (trip id)) p.val]
::
++  story-to-json
  |=  =story:d
  ^-  json
  :-  %a
  %+  turn  story
  |=  =verse:d
  ?:  ?=(%inline -.verse)
    %-  pairs:enjs:format
    :~  ['type' s+'inline']
        :-  'inlines'
        :-  %a
        %+  turn  p.verse
        |=  =inline:d
        ?@  inline  s+inline
        ?+  -.inline  s+''
          %tag   (pairs:enjs:format ~[['type' s+'tag'] ['p' s+p.inline]])
          %ship  (pairs:enjs:format ~[['type' s+'ship'] ['p' s+(scot %p p.inline)]])
        ==
    ==
  (pairs:enjs:format ~[['type' s+'block']])
::
++  json-to-story
  |=  j=json
  ^-  story:d
  ?.  ?=([%a *] j)  ~
  %+  turn  p.j
  |=  item=json
  ^-  verse:d
  ?.  ?=([%o *] item)  [%inline ~]
  =/  typ=(unit json)  (~(get by p.item) 'type')
  ?.  ?=([~ %s %'inline'] typ)  [%inline ~]
  =/  ils-json=(unit json)  (~(get by p.item) 'inlines')
  ?.  ?=([~ %a *] ils-json)  [%inline ~]
  :-  %inline
  ^-  (list inline:d)
  %+  turn  p.u.ils-json
  |=  il=json
  ^-  inline:d
  ?:  ?=([%s *] il)  p.il
  ?.  ?=([%o *] il)  ''
  =/  il-type=(unit json)  (~(get by p.il) 'type')
  ?+  il-type  ''
    [~ %s %'tag']   [%tag (jget il 'p' '')]
    [~ %s %'ship']  [%ship (slav %p (jget il 'p' '~zod'))]
  ==
::
::  ┌──────────────────────────────────────────────────┐
::  │ BOT LOOP                                         │
::  └──────────────────────────────────────────────────┘
::
++  bot-loop
  |=  bot-id=@tas
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  |-
  ;<  =cage  bind:m  take-poke:io
  ?.  ?=(%json p.cage)  $
  =/  event-data=json  !<(json q.cage)
  ::  read our bot config
  ;<  cfg-seen=seen:nexus  bind:m
    (peek:io /cfg (cord-to-road:tarball './config.json') `%json)
  =/  bot-cfg=json
    ?.  ?=([%& %file *] cfg-seen)  (need (de:json:html '{}'))
    !<(json q.cage.p.cfg-seen)
  ::  read global config from parent
  ;<  global-seen=seen:nexus  bind:m
    (peek:io /gcfg (cord-to-road:tarball '../../config.json') `%json)
  =/  global-cfg=json
    ?.  ?=([%& %file *] global-seen)  (need (de:json:html '{}'))
    !<(json q.cage.p.global-seen)
  ::  resolve effective config
  =/  bname=@t   (jget bot-cfg 'name' '')
  =/  bavatar=@t  (jget bot-cfg 'avatar' '')
  =/  bmodel=@t
    =/  m  (jget bot-cfg 'model' '')
    ?:(=('' m) (jget global-cfg 'model' 'anthropic/claude-sonnet-4') m)
  =/  bkey=@t
    =/  k  (jget bot-cfg 'api_key' '')
    ?:(=('' k) (jget global-cfg 'api_key' '') k)
  ?:  =('' bkey)
    %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' has no API key" ~)
    $
  ::  extract message details
  =/  from=@p  (slav %p (jget event-data 'from' '~zod'))
  =/  text=@t  (jget event-data 'text' '')
  =/  msg-id=@t  (jget event-data 'msg_id' '')
  =/  nest-kind=@t  (jget event-data 'nest_kind' '')
  =/  nest-ship=@t  (jget event-data 'nest_ship' '')
  =/  nest-name=@t  (jget event-data 'nest_name' '')
  =/  is-dm=?  =('' nest-kind)
  ::  build context from context files
  ;<  ctx-text=@t  bind:m  (read-context-files bot-id)
  ;<  our=@p  bind:m  get-our:io
  ;<  now=@da  bind:m  get-time:io
  =/  conv-key=@t
    ?:  is-dm  (rap 3 bot-id '/dm/' (scot %p from) ~)
    (rap 3 bot-id '/channel/' nest-kind '/' nest-ship '/' nest-name ~)
  ::  ingest user message into LCM
  ;<  ~  bind:m
    (gall-poke:io /lcm-ingest [our %lcm] %lcm-action !>(`lcm-action:lcm`[%ingest conv-key 'user' text]))
  ::  scry LCM for assembled context
  =/  lcm-path=path  /(scot %p our)/lcm/(scot %da now)/assemble/[conv-key]/(scot %ud 50.000)/json
  =/  history=(list json)
    =/  ctx-json=(unit json)  (mole |.(.^(json %gx lcm-path)))
    ?~  ctx-json  ~
    ?.  ?=([%a *] u.ctx-json)  ~
    p.u.ctx-json
  ::  build system prompt
  =/  sys-prompt=@t
    %+  rap  3
    :~  ctx-text
        '\0a\0a---\0a\0a# Current Conversation\0a\0a'
        ?:  is-dm
          (rap 3 'You are in a DM with ' (scot %p from) '. Your text response is automatically sent as a DM reply.' ~)
        %+  rap  3
        :~  (scot %p from)
            ' tagged you in channel '
            nest-kind  '/'  nest-ship  '/'  nest-name
            '.\0aTheir message ID is: '  msg-id
            '\0aYour responses are automatically posted in that channel.'
        ==
    ==
  ::  build API messages
  =/  api-msgs=json
    :-  %a
    :-  (pairs:enjs:format ~[['role' s+'system'] ['content' s+sys-prompt]])
    %+  weld  history
    :~  (pairs:enjs:format ~[['role' s+'user'] ['content' s+text]])
    ==
  =/  body=json
    %-  pairs:enjs:format
    :~  ['model' s+bmodel]
        ['messages' api-msgs]
    ==
  =/  body-cord=@t  (en:json:html body)
  %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' calling LLM ({(trip bmodel)})" ~)
  =/  =request:http
    :^  %'POST'  'https://openrouter.ai/api/v1/chat/completions'
      :~  ['Content-Type' 'application/json']
          ['Authorization' (crip "Bearer {(trip bkey)}")]
      ==
    `(as-octs:mimes:html body-cord)
  ;<  response=@t  bind:m  (fetch:io request)
  =/  parsed=(unit ?([%text @t] [%tools @t (list [id=@t name=@t arguments=@t])]))
    (parse-llm-response response)
  ?~  parsed
    %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' LLM parse error" ~)
    $
  ?:  ?=([%tools *] u.parsed)
    %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' got tool calls (not yet implemented)" ~)
    =/  tc-text=@t  +<.u.parsed
    ?:  =('' tc-text)  $
    ;<  ~  bind:m
      (send-reply our from is-dm nest-kind nest-ship nest-name tc-text bname bavatar now)
    ;<  ~  bind:m
      (gall-poke:io /lcm-ingest [our %lcm] %lcm-action !>(`lcm-action:lcm`[%ingest conv-key 'assistant' tc-text]))
    $
  ?>  ?=([%text *] u.parsed)
  =/  reply=@t  +<.u.parsed
  %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' replying: {(trip (end 3^80 reply))}" ~)
  ;<  ~  bind:m
    (send-reply our from is-dm nest-kind nest-ship nest-name reply bname bavatar now)
  ;<  ~  bind:m
    (gall-poke:io /lcm-ingest [our %lcm] %lcm-action !>(`lcm-action:lcm`[%ingest conv-key 'assistant' reply]))
  $
::
++  send-reply
  |=  [our=@p from=@p is-dm=? nest-kind=@t nest-ship=@t nest-name=@t text=@t bname=@t bavatar=@t now=@da]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  =/  bname-u=(unit @t)  ?:(=('' bname) ~ `bname)
  =/  bavatar-u=(unit @t)  ?:(=('' bavatar) ~ `bavatar)
  ?:  is-dm
    =/  dm-story=story:d  (text-to-story:story-parse text)
    =/  dm-memo=memo:d  [content=dm-story author=(bot-author our bname-u bavatar-u) sent=now]
    =/  dm-essay=essay:c  [dm-memo [%chat /] ~ ~]
    =/  dm-delta=delta:writs:c  [%add dm-essay ~]
    =/  dm-diff=diff:writs:c  [[our now] dm-delta]
    =/  dm-act=action:dm:c  [from dm-diff]
    (gall-poke:io /dm-send [our %chat] %chat-dm-action-1 !>(dm-act))
  =/  ch-story=story:d  (text-to-story:story-parse text)
  =/  ch-memo=memo:d  [content=ch-story author=(bot-author our bname-u bavatar-u) sent=now]
  =/  ch-essay=essay:d  [ch-memo /chat ~ ~]
  =/  kind=?(%chat %diary %heap)
    =/  k=@tas  (crip (trip nest-kind))
    ?+  k  %chat
      %chat   %chat
      %diary  %diary
      %heap   %heap
    ==
  =/  =nest:d  [kind (slav %p nest-ship) (crip (trip nest-name))]
  =/  act=a-channels:d  [%channel nest [%post [%add ch-essay]]]
  (gall-poke:io /ch-send [our %channels] %channel-action-1 !>(act))
::
++  read-context-files
  |=  bot-id=@tas
  =/  m  (fiber:fiber:nexus ,@t)
  ^-  form:m
  =|  parts=(list @t)
  =/  fields=(list @tas)  ~[%identity %soul %agent %memory]
  |-
  ?~  fields  (pure:m (join-parts (flop parts)))
  =/  field=@tas  i.fields
  =/  filename=@ta  (crip "{(trip field)}.txt")
  ;<  ctx-seen=seen:nexus  bind:m
    (peek:io /ctx/[field] [%& %& /context filename] `%txt)
  =/  content=@t
    ?.  ?=([%& %file *] ctx-seen)  ''
    =/  wain-val=wain  !<(wain q.cage.p.ctx-seen)
    (of-wain:format wain-val)
  =?  parts  !=('' content)
    :_  parts
    (rap 3 '# ' (crip (cuss (trip field))) '\0a\0a' content ~)
  $(fields t.fields)
::
++  join-parts
  |=  parts=(list @t)
  ^-  @t
  ?~  parts  ''
  =/  out=@t  i.parts
  =/  rem=(list @t)  t.parts
  |-
  ?~  rem  out
  $(rem t.rem, out (rap 3 out '\0a\0a' i.rem ~))
--
::
|%
++  on-load
  |=  [=sand:nexus =gain:nexus =ball:tarball]
  ^-  [sand:nexus gain:nexus ball:tarball]
  =/  =ver:loader  (get-ver:loader ball)
  =/  default-config=json
    %-  pairs:enjs:format
    :~  ['api_key' s+'']
        ['model' s+'anthropic/claude-sonnet-4']
    ==
  =/  default-bot-config=json
    %-  pairs:enjs:format
    :~  ['name' s+'brap']
        ['avatar' s+'']
        ['model' s+'']
        ['api_key' s+'']
        ['brave_key' s+'']
    ==
  =/  default-registry=json
    (pairs:enjs:format ~[['brap' s+'brap']])
  ?+  ver  !!
      ?(~ [~ %0])
    %+  spin:loader  [sand gain ball]
    :~  (ver-row:loader 1)
        [%fall %& [/ %'config.json'] %.n [~ %json !>(default-config)]]
        [%fall %& [/ %'bots-registry.json'] %.n [~ %json !>(default-registry)]]
        [%fall %& [/ %'main.sig'] %.n [~ %sig !>(~)]]
        [%fall %| /bots [~ ~] [~ ~] empty-dir:loader]
        ::  bot: brap (default test bot)
        [%fall %& [/bots/brap %'config.json'] %.n [~ %json !>(default-bot-config)]]
        [%fall %& [/bots/brap %'main.sig'] %.n [~ %sig !>(~)]]
        [%fall %| /bots/brap/context [~ ~] [~ ~] empty-dir:loader]
        [%fall %| /bots/brap/conversations [~ ~] [~ ~] empty-dir:loader]
        ::  system internals
        [%fall %| /sys/daises [~ ~] [~ ~] empty-dir:loader]
        [%fall %| /sys/nexuses [~ ~] [~ ~] empty-dir:loader]
        [%fall %| /sys/tubes [~ ~] [~ ~] empty-dir:loader]
        [%fall %| /sys/clay [~ ~] [~ ~] empty-dir:loader]
        [%fall %| /sys/dill [~ ~] [~ ~] empty-dir:loader]
        [%fall %| /sys/jael [~ ~] [~ ~] empty-dir:loader]
    ==
  ::
      [~ %1]
    ::  v1 — add brap bot if missing
    %+  spin:loader  [sand gain ball]
    :~  (ver-row:loader 1)
        [%stay %& [/ %'config.json']]
        [%stay %& [/ %'bots-registry.json']]
        [%stay %& [/ %'main.sig']]
        [%stay %| /bots]
        [%fall %& [/bots/brap %'config.json'] %.n [~ %json !>(default-bot-config)]]
        [%fall %& [/bots/brap %'main.sig'] %.n [~ %sig !>(~)]]
        [%fall %| /bots/brap/context [~ ~] [~ ~] empty-dir:loader]
        [%fall %| /bots/brap/conversations [~ ~] [~ ~] empty-dir:loader]
        ::  system internals
        [%stay %| /sys/daises]
        [%stay %| /sys/nexuses]
        [%stay %| /sys/tubes]
        [%stay %| /sys/clay]
        [%stay %| /sys/dill]
        [%stay %| /sys/jael]
    ==
  ==
::
++  on-file
  |=  [=rail:tarball mak=mark]
  ^-  spool:fiber:nexus
  |=  =prod:fiber:nexus
  =/  m  (fiber:fiber:nexus ,~)
  ^-  process:fiber:nexus
  ?+    rail  stay:m
  ::
  ::  ROOT PROCESS: /main.sig
  ::
      [~ %'main.sig']
    ;<  ~  bind:m  (rise-wait:io prod "%claw: root process failed")
    %-  (slog leaf+"claw-grub: root process starting" ~)
    ;<  our=@p  bind:m  get-our:io
    ::  only subscribe on fresh start, not on reload/rise
    ?.  ?=(%rise -.prod)
      ;<  ~  bind:m  (gall-watch:io /activity [our %activity] /v4)
      %-  (slog leaf+"claw-grub: subscribed to activity" ~)
      ;<  ~  bind:m  (gall-watch:io /self-dm [our %chat] /dm/(scot %p our))
      %-  (slog leaf+"claw-grub: watching self-DMs" ~)
      (root-loop our)
    %-  (slog leaf+"claw-grub: restarted (keeping existing subs)" ~)
    (root-loop our)
  ::
  ::  BOT PROCESS: /bots/{id}/main.sig
  ::
      [[%bots @ ~] %'main.sig']
    ;<  ~  bind:m  (rise-wait:io prod "%claw: bot process failed")
    =/  bot-id=@tas  i.t.path.rail
    %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' process starting" ~)
    (bot-loop bot-id)
  ==
::
++  on-manu
  |=  =mana:nexus
  ^-  @t
  ?-    -.mana
      %&
    ?+  p.mana  'Subdirectory of the claw nexus.'
        ~
      %-  crip
      """
      CLAW — Multi-bot LLM agent harness

      The root nexus manages bot processes and routes messages from
      Tlon activity and DM subscriptions to the appropriate bot.

      DIRECTORIES:
        bots/       Bot directories. Each bot has config, context,
                    conversations, and its own process.
        sys/        System internals (daises, tubes, nexuses).

      FILES:
        config.json   Global defaults (api_key, model).
        main.sig      Root process — activity sub, message routing.
      """
        [%bots ~]
      'Bot directory. Each subdirectory is a separate bot with its own process.'
    ==
      %|
    ?+  rail.p.mana  'File in the claw nexus.'
      [~ %'config.json']  'Global config: api_key, model defaults.'
      [~ %'main.sig']     'Root process: activity subscription, message routing.'
    ==
  ==
--
