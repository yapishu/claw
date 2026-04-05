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
/+  nexus, tarball, io=fiberio, loader, story-parse, tools=claw-tools, cron
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
::    returns [%text content] for normal responses
::    returns [%tools content calls] for tool-call responses
::    returns [%error message] for API errors
::
++  parse-llm-response
  |=  [status=@ud body=@t]
  ^-  ?([%text @t] [%tools @t (list [id=@t name=@t arguments=@t])] [%error @t])
  =/  jon=(unit json)  (de:json:html body)
  ?.  =(200 status)
    :-  %error
    ?~  jon  (rap 3 'HTTP ' (crip "{<status>}") ': ' (end 3^200 body) ~)
    =/  err-msg=@t
      ?~  (me u.jon)  (end 3^200 body)
      =/  err=(unit json)  (~(get by (need (me u.jon))) 'error')
      ?~  err  (end 3^200 body)
      ?~  (me u.err)  (end 3^200 body)
      (jget u.err 'message' (end 3^200 body))
    (rap 3 'API error ' (crip "{<status>}") ': ' err-msg ~)
  ?~  jon  [%error 'Failed to parse LLM response as JSON']
  =/  result
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
  ?~  result  [%error 'Failed to parse LLM response structure']
  u.result
::  +find-tagged-bots: find bots whose name appears as [%tag] in story
::
++  find-tagged-bots
  |=  [bot-names=(map @tas @t) =story:d]
  ^-  (list @tas)
  %+  murn  ~(tap by bot-names)
  |=  [id=@tas name=@t]
  ?.  %+  lien  story
      |=  =verse:d
      ?.  ?=(%inline -.verse)  %.n
      %+  lien  p.verse
      |=  =inline:d
      ?&  ?=([%tag *] inline)
          =(name p.inline)
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
::  +nest-kind: parse channel kind from cord
::
++  nest-kind
  |=  k=@t
  ^-  ?(%chat %diary %heap)
  ?+  k  %chat
    %'chat'   %chat
    %'diary'  %diary
    %'heap'   %heap
  ==
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
  ;<  ev=[tag=@tas dat=cage]  bind:m
    |=  input:fiber:nexus
    :+  ~  state
    ?~  in  [%wait ~]
    ?:  ?=(%agent -.u.in)
      ?:  ?&  =(wire.u.in /activity)
              ?=([%fact *] sign.u.in)
          ==
        [%done %activity cage.sign.u.in]
      ?:  ?&  =(wire.u.in /activity)
              ?=([%kick ~] sign.u.in)
          ==
        [%done %kick-activity *cage]
      ?:  =(wire.u.in /self-dm)
        ?:  ?=([%watch-ack *] sign.u.in)
          ::  consume and ignore watch-ack
          [%done %dm-ack *cage]
        ?:  ?=([%fact *] sign.u.in)
          [%done %self-dm cage.sign.u.in]
        ?:  ?=([%kick ~] sign.u.in)
          [%done %kick-dm *cage]
        [%skip ~]
      [%skip ~]
    ?:  ?&  ?=(%arvo -.u.in)
            =(wire.u.in /cron)
        ==
      [%done %cron *cage]
    [%skip ~]
  ::
  ?+    tag.ev  $
      %kick-activity
    ;<  ~  bind:m  (gall-watch:io /activity [our %activity] /v4)
    $
  ::
      %dm-ack
    %-  (slog leaf+"claw-grub: self-DM watch ack received" ~)
    $
  ::
      %kick-dm
    ::  only re-watch if the initial watch succeeded
    %-  (slog leaf+"claw-grub: self-DM kicked, re-subscribing" ~)
    ;<  ~  bind:m  (send-card:io [%pass /self-dm %agent [our %chat] %watch /dm/(scot %p our)])
    $
  ::
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
    ?:  =(from our)  $
    =/  text=@t  (jget event-data 'text' '')
    ?:  =('' text)  $
    ::  dedup by event id
    =/  evt-id=@t  (rap 3 event-type '/' (jget event-data 'from' '') '/' (jget event-data 'msg_id' '') ~)
    ?:  (~(has in seen-msgs) evt-id)  $
    =.  seen-msgs  (~(put in seen-msgs) evt-id)
    =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
    ::  scan bots (names + whitelists)
    ;<  bots=(map @tas bot-info)  bind:m  scan-bots
    ?~  bots  $
    ::  extract name map for matching
    =/  bots-list=(list [@tas bot-info])  ~(tap by `(map @tas bot-info)`bots)
    =/  bot-names=(map @tas @t)
      %-  ~(gas by *(map @tas @t))
      %+  turn  bots-list
      |=([id=@tas bi=bot-info] [id name.bi])
    ::  +allowed: check if ship is permitted for a bot
    =/  bots-map=(map @tas bot-info)  bots
    =/  allowed
      |=  [bot-id=@tas =ship]
      ^-  ?
      ?:  =(ship our)  %.y
      =/  bi=(unit bot-info)  (~(get by bots-map) bot-id)
      ?~  bi  %.n
      ?:  =(~ whitelist.u.bi)  %.y
      (~(has by whitelist.u.bi) ship)
    ::  find matching bots and route (with permission check)
    ?+    event-type  $
    ::
        ?(%post %reply)
      =/  story-json=json  (need (~(get by (need (me event-data))) 'story'))
      =/  =story:d  (json-to-story story-json)
      =/  tagged=(list @tas)  (find-tagged-bots bot-names story)
      =/  named=(list @tas)  ?^(tagged ~ (find-named-bots bot-names text))
      ::  filter by whitelist
      =/  match=(list @tas)
        %+  skim  (weld tagged named)
        |=(id=@tas (allowed id from))
      ?~  match  $
      %-  (slog leaf+"claw-grub: routing {(trip event-type)} to {<match>}" ~)
      =/  rem=(list @tas)  match
      |-
      ?~  rem  ^$
      ;<  ~  bind:m
        (poke:io /route (bot-road i.rem) %json !>(event-data))
      $(rem t.rem)
    ::
        ?(%dm-post %dm-reply)
      =/  named=(list @tas)  (find-named-bots bot-names text)
      =/  all-bots=(list [@tas @t])  ~(tap by `(map @tas @t)`bot-names)
      ?~  all-bots  $
      =/  bot-id=@tas
        ?^(named i.named -.i.all-bots)
      ::  check whitelist for DMs
      ?.  (allowed bot-id from)
        %-  (slog leaf+"claw-grub: {(scow %p from)} not whitelisted for {(trip bot-id)}" ~)
        $
      %-  (slog leaf+"claw-grub: routing {(trip event-type)} to {(trip bot-id)}" ~)
      ;<  ~  bind:m
        (poke:io /route (bot-road bot-id) %json !>(event-data))
      $
    ==
  ::
      %self-dm
    ::  parse raw writ fact from %chat: [whom id [%add memo time]]
    =/  dm-result=(unit [from=@p text=@t msg-time=@da])
      %-  mole  |.
      =/  noun  +.q.dat.ev
      ?>  ?=([* * [%add *]] noun)
      =/  msg-time=@da  ;;(@da +.-.+.noun)
      =/  memo-noun  -.+.+.+.noun
      =/  content-noun  -.memo-noun
      =/  author-noun  -.+.memo-noun
      ::  skip bot-authored messages (cell = bot-meta, atom = human)
      ?>  ?@(author-noun %.y !!)
      =/  from=ship  ;;(@p author-noun)
      =/  text=@t  (story-to-text:story-parse ;;(story:d content-noun))
      [from text msg-time]
    ?~  dm-result  $
    =/  from=@p  from.u.dm-result
    =/  text=@t  text.u.dm-result
    =/  msg-time=@da  msg-time.u.dm-result
    ?:  =('' text)  $
    ::  dedup
    =/  evt-id=@t  (rap 3 'dmw/' (scot %p from) '/' (scot %da msg-time) ~)
    ?:  (~(has in seen-msgs) evt-id)  $
    =.  seen-msgs  (~(put in seen-msgs) evt-id)
    =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
    %-  (slog leaf+"claw-grub: dm-watch from {(scow %p from)}: {(trip (end 3^40 text))}" ~)
    ::  route to bot
    ;<  bots-dm=(map @tas bot-info)  bind:m  scan-bots
    =/  bot-names-dm=(map @tas @t)
      %-  ~(gas by *(map @tas @t))
      %+  turn  ~(tap by `(map @tas bot-info)`bots-dm)
      |=([id=@tas bi=bot-info] [id name.bi])
    =/  named=(list @tas)  (find-named-bots bot-names-dm text)
    ::  self-DM: only route if bot is explicitly named (prevents feedback loop)
    ?~  named  $
    =/  bot-id=@tas  i.named
    =/  dm-event=json
      %-  pairs:enjs:format
      :~  ['from' s+(scot %p from)]
          ['text' s+text]
          ['msg_id' s+(scot %da msg-time)]
      ==
    %-  (slog leaf+"claw-grub: dm-watch routing to {(trip bot-id)}" ~)
    ;<  ~  bind:m
      (poke:io /route (bot-road bot-id) %json !>(dm-event))
    $
  ::
      %cron
    ::  cron tick: scan all bots for due cron jobs, fire them, re-arm timer
    ;<  now=@da  bind:m  get-time:io
    ;<  bots-for-cron=(map @tas bot-info)  bind:m  scan-bots
    =/  bot-list=(list [@tas bot-info])  ~(tap by `(map @tas bot-info)`bots-for-cron)
    |-
    ?~  bot-list
      ::  re-arm timer for next minute
      ;<  ~  bind:m  (send-card:io [%pass /cron %arvo %b %wait (add now ~m1)])
      ^$
    =/  [bot-id=@tas bi=bot-info]  i.bot-list
    ::  read bot config for cron jobs
    ;<  cfg-seen=seen:nexus  bind:m
      (peek:io /cron-cfg/[bot-id] (cord-to-road:tarball (crip "./bots/{(trip bot-id)}/config.json")) `%json)
    ?.  ?=([%& %file *] cfg-seen)
      $(bot-list t.bot-list)
    =/  cfg=json  !<(json q.cage.p.cfg-seen)
    ?.  ?=([%o *] cfg)
      $(bot-list t.bot-list)
    =/  cron-json=(unit json)  (~(get by p.cfg) 'cron')
    ?~  cron-json
      $(bot-list t.bot-list)
    ?.  ?=([%a *] u.cron-json)
      $(bot-list t.bot-list)
    ::  check each cron job
    =/  jobs=(list json)  p.u.cron-json
    |-
    ?~  jobs  ^$(bot-list t.bot-list)
    =/  job=json  i.jobs
    ?.  ?=([%o *] job)  $(jobs t.jobs)
    =/  schedule=@t  (jget job 'schedule' '')
    =/  prompt=@t  (jget job 'prompt' '')
    ?:  |(=('' schedule) =('' prompt))  $(jobs t.jobs)
    ::  check if this job should fire now (within the last minute)
    =/  check-time=@da  (sub now ~m1)
    =/  next-fire=(unit @da)  (next-cron-fire:cron schedule check-time)
    ?~  next-fire  $(jobs t.jobs)
    ?.  (lte u.next-fire now)  $(jobs t.jobs)
    ::  fire! poke the bot with a cron prompt
    %-  (slog leaf+"claw-grub: cron firing for bot '{(trip bot-id)}': {(trip (end 3^40 prompt))}" ~)
    =/  cron-event=json
      %-  pairs:enjs:format
      :~  ['from' s+(scot %p our)]
          ['text' s+prompt]
          ['msg_id' s+(scot %da now)]
          ['is_cron' b+%.y]
      ==
    ;<  ~  bind:m
      (poke:io /cron (bot-road bot-id) %json !>(cron-event))
    $(jobs t.jobs)
  ==
::
++  bot-road
  |=  bot-id=@tas
  ^-  road:tarball
  [%& %& /bots/[bot-id] %'main.sig']
::
::  bot-info: name + whitelist for routing decisions
::
+$  bot-info  [name=@t whitelist=(map @p @t)]
::
++  scan-bots
  =/  m  (fiber:fiber:nexus ,(map @tas bot-info))
  ^-  form:m
  ::  read registry for bot IDs
  ;<  reg-seen=seen:nexus  bind:m
    (peek:io /reg (cord-to-road:tarball './bots-registry.json') `%json)
  ?.  ?=([%& %file *] reg-seen)  (pure:m ~)
  =/  reg=json  !<(json q.cage.p.reg-seen)
  ?.  ?=([%o *] reg)  (pure:m ~)
  =/  bot-ids=(list [@tas @t])
    %+  murn  ~(tap by p.reg)
    |=  [id=@t val=json]
    ?.  ?=([%s *] val)  ~
    ?:  =('' p.val)  ~
    `[(crip (trip id)) p.val]
  ::  read each bot's config for whitelist
  =|  out=(map @tas bot-info)
  =/  remaining=(list [@tas @t])  bot-ids
  |-
  ?~  remaining  (pure:m out)
  =/  [id=@tas name=@t]  i.remaining
  ;<  cfg-seen=seen:nexus  bind:m
    (peek:io /bot-cfg/[id] (cord-to-road:tarball (crip "./bots/{(trip id)}/config.json")) `%json)
  =/  wl=(map @p @t)
    ?.  ?=([%& %file *] cfg-seen)  ~
    =/  cfg=json  !<(json q.cage.p.cfg-seen)
    ?.  ?=([%o *] cfg)  ~
    =/  wl-json=(unit json)  (~(get by p.cfg) 'whitelist')
    ?~  wl-json  ~
    ?.  ?=([%o *] u.wl-json)  ~
    %-  ~(gas by *(map @p @t))
    %+  murn  ~(tap by p.u.wl-json)
    |=  [k=@t v=json]
    =/  ship=(unit @p)  (slaw %p k)
    ?~  ship  ~
    ?.  ?=([%s *] v)  ~
    `[u.ship p.v]
  =.  out  (~(put by out) id [name wl])
  $(remaining t.remaining)
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
  ::  read bot config + global config
  ;<  cfg-seen=seen:nexus  bind:m
    (peek:io /cfg (cord-to-road:tarball './config.json') `%json)
  =/  bot-cfg=json
    ?.  ?=([%& %file *] cfg-seen)  (need (de:json:html '{}'))
    !<(json q.cage.p.cfg-seen)
  ;<  global-seen=seen:nexus  bind:m
    (peek:io /gcfg (cord-to-road:tarball '../../config.json') `%json)
  =/  global-cfg=json
    ?.  ?=([%& %file *] global-seen)  (need (de:json:html '{}'))
    !<(json q.cage.p.global-seen)
  ::  resolve effective config (bot overrides global)
  =/  bname=@t    (jget bot-cfg 'name' '')
  =/  bavatar=@t  (jget bot-cfg 'avatar' '')
  =/  bmodel=@t
    =/  bm=@t  (jget bot-cfg 'model' '')
    ?:(=('' bm) (jget global-cfg 'model' 'anthropic/claude-sonnet-4') bm)
  =/  bkey=@t
    =/  bk=@t  (jget bot-cfg 'api_key' '')
    ?:(=('' bk) (jget global-cfg 'api_key' '') bk)
  ::  extract message details
  =/  from=@p      (slav %p (jget event-data 'from' '~zod'))
  =/  text=@t      (jget event-data 'text' '')
  =/  msg-id=@t    (jget event-data 'msg_id' '')
  =/  nk=@t        (jget event-data 'nest_kind' '')
  =/  ns=@t        (jget event-data 'nest_ship' '')
  =/  nn=@t        (jget event-data 'nest_name' '')
  =/  parent-id=@t  (jget event-data 'parent_id' '')
  =/  is-dm=?      =('' nk)
  =/  is-thread=?  !=('' parent-id)
  =/  is-cron=?
    =/  cron-flag=(unit json)
      ?.  ?=([%o *] event-data)  ~
      (~(get by p.event-data) 'is_cron')
    ?~  cron-flag  %.n
    ?=([%b %.y] u.cron-flag)
  ;<  our=@p   bind:m  get-our:io
  ;<  now=@da  bind:m  get-time:io
  ::  no key → tell user
  ?:  =('' bkey)
    %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' has no API key" ~)
    ;<  ~  bind:m
      (send-reply our from is-dm is-thread nk ns nn parent-id 'Sorry, no API key configured.' bname bavatar now)
    $
  ::  build context from context files
  ;<  ctx-text=@t  bind:m  read-context-files
  ::  conversation key (namespaced per bot)
  =/  conv-key=@t
    ?:  is-dm  (rap 3 bot-id '/dm/' (scot %p from) ~)
    ?:  is-thread
      (rap 3 bot-id '/thread/' nk '/' ns '/' nn '/' parent-id ~)
    (rap 3 bot-id '/channel/' nk '/' ns '/' nn ~)
  ::  ingest user message into LCM
  ;<  ~  bind:m
    (gall-poke:io /lcm-ingest [our %lcm] %lcm-action !>(`lcm-action:lcm`[%ingest conv-key 'user' text]))
  ::  scry LCM for assembled conversation history
  =/  history=(list json)
    =/  lcm-path=path  /(scot %p our)/lcm/(scot %da now)/assemble/[conv-key]/(scot %ud 50.000)/json
    =/  ctx-json=(unit json)  (mole |.(.^(json %gx lcm-path)))
    ?~  ctx-json  ~
    ?.  ?=([%a *] u.ctx-json)  ~
    p.u.ctx-json
  ::  build system prompt with full bot identity
  =/  default-identity=@t
    (rap 3 'You are ' bname ', an AI bot running on the Urbit ship ' (scot %p our) '.' ~)
  =/  default-soul=@t
    'You are helpful, knowledgeable, and concise. You have opinions and share them when relevant. You are honest about what you don\'t know. Keep responses focused.'
  =/  default-agent=@t
    (rap 3 'You are ' bname ', a native Urbit LLM agent. Your text response is automatically routed back to wherever the message came from. You do NOT need to call any tool to reply. Just respond with text.' ~)
  =/  sys-prompt=@t
    %+  rap  3
    :~  ::  bot identity section
        '# Bot Identity\0a\0a'
        'You are '  bname  ', a bot running on the Urbit ship '  (scot %p our)  '.\0a'
        'You are NOT the ship operator - you are a bot running on their ship.\0a'
        '\0a---\0a\0a'
        ::  context files (with defaults if empty)
        ?:  =('' ctx-text)
          %+  rap  3
          :~  '# Identity\0a\0a'  default-identity
              '\0a\0a---\0a\0a# Personality\0a\0a'  default-soul
              '\0a\0a---\0a\0a# Agent\0a\0a'  default-agent
          ==
        ctx-text
        '\0a\0a---\0a\0a# System\0a\0a'
        'Ship: '  (scot %p our)  '\0a'
        'Time: '  (scot %da now)  '\0a'
        '\0a---\0a\0a# Tools\0a\0a'
        'You have tools available. ALWAYS use the appropriate tool when the user asks you to do something - '
        'do NOT pretend or hallucinate tool results. If a tool fails, report the actual error.\0a'
        'Key tools: web_search, image_search, send_dm, send_channel_message, read_channel_history, '
        'read_dm_history, list_groups, list_channels, get_contact, list_contacts, http_fetch, '
        'add_reaction, local_mcp (for Urbit system access), local_mcp_list (list MCP tools).\0a'
        'For local_mcp: call local_mcp_list first to get exact tool names, then call local_mcp with name and arguments.\0a'
        ?:  is-cron
          '\0a---\0a\0a# Automated Cron Task\0a\0aThis is an automated scheduled task. Execute the task using tools as needed. Do NOT send any text reply or confirmation — only use tools to produce output. Your text response will be discarded.\0a'
        '\0a---\0a\0a# Current Conversation\0a\0a'
        ?:  is-dm
          %+  rap  3
          :~  'You are in a DM with '  (scot %p from)  '.\0a'
              'Your text response is automatically sent as a DM reply.\0a'
              'In this conversation, messages from you appear with your bot name ('  bname  ').\0a'
              'Messages from the human appear as their ship name.\0a'
              'Only respond when someone mentions your name ('  bname  '). Ignore messages not addressed to you.'
          ==
        %+  rap  3
        :~  (scot %p from)
            ?:  is-thread
              (rap 3 ' replied in a thread in channel ' nk '/' ns '/' nn ~)
            (rap 3 ' tagged you in channel ' nk '/' ns '/' nn ~)
            '.\0aTheir message ID is: '  msg-id
            '\0aThe channel nest is: '  nk  '/'  ns  '/'  nn
            '\0aYour responses are automatically posted in '
            ?:(is-thread 'that thread.' 'that channel.')
            '\0aTo react to their message, use add_reaction with channel='
            nk  '/'  ns  '/'  nn  ' and msg_id='  msg-id
        ==
    ==
  ::  build base API messages
  =/  base-msgs=(list json)
    :-  (pairs:enjs:format ~[['role' s+'system'] ['content' s+sys-prompt]])
    %+  weld  history
    :~  (pairs:enjs:format ~[['role' s+'user'] ['content' s+text]])
    ==
  ::  resolve brave key for tools
  =/  bbrave=@t
    =/  bb=@t  (jget bot-cfg 'brave_key' '')
    ?:(=('' bb) (jget global-cfg 'brave_key' '') bb)
  ::  check if from is an owner (for owner-only tools)
  =/  is-owner=?  =(from our)  :: TODO: check whitelist for owner role
  ::  enter LLM loop (with tool execution, max 5 rounds)
  =/  extra-msgs=(list json)  ~
  =/  round=@ud  0
  |-
  ?:  (gte round 5)
    %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' hit tool loop limit" ~)
    ;<  ~  bind:m
      (send-reply our from is-dm is-thread nk ns nn parent-id 'I hit my tool iteration limit. Here is what I have so far.' bname bavatar now)
    ^$
  =/  all-msgs=json  [%a (weld base-msgs extra-msgs)]
  =/  body-cord=@t
    %-  en:json:html
    %-  pairs:enjs:format
    :~  ['model' s+bmodel]
        ['messages' all-msgs]
        ['tools' tool-defs:tools]
    ==
  %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' calling LLM round {<round>}" ~)
  =/  =request:http
    :^  %'POST'  'https://openrouter.ai/api/v1/chat/completions'
      :~  ['Content-Type' 'application/json']
          ['Authorization' (crip "Bearer {(trip bkey)}")]
      ==
    `(as-octs:mimes:html body-cord)
  ;<  ~  bind:m  (send-request:io request)
  ;<  =client-response:iris  bind:m  take-client-response:io
  ?>  ?=(%finished -.client-response)
  =/  status=@ud  status-code.response-header.client-response
  =/  response-body=@t
    ?~  full-file.client-response  ''
    q.data.u.full-file.client-response
  =/  parsed  (parse-llm-response status response-body)
  ::
  ?:  ?=([%error *] parsed)
    =/  [%error err-msg=@t]  parsed
    %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' error: {(trip err-msg)}" ~)
    ;<  ~  bind:m
      (send-reply our from is-dm is-thread nk ns nn parent-id (rap 3 'Error: ' err-msg ~) bname bavatar now)
    ^$
  ::
  ?:  ?=([%text *] parsed)
    =/  [%text reply=@t]  parsed
    ::  cron tasks: suppress text reply (tools already produced output)
    ?:  is-cron
      %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' cron complete (suppressed reply)" ~)
      ^$
    %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' replying: {(trip (end 3^80 reply))}" ~)
    ;<  ~  bind:m
      (send-reply our from is-dm is-thread nk ns nn parent-id reply bname bavatar now)
    ;<  ~  bind:m
      (gall-poke:io /lcm-ingest [our %lcm] %lcm-action !>(`lcm-action:lcm`[%ingest conv-key 'assistant' reply]))
    ^$
  ::
  ?>  ?=([%tools *] parsed)
  =/  [%tools tc-text=@t tc-calls=(list [id=@t name=@t arguments=@t])]  parsed
  %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' executing {<(lent tc-calls)>} tools" ~)
  ::  build assistant message with tool_calls for follow-up context
  =/  tc-json=(list json)
    %+  turn  tc-calls
    |=  [id=@t name=@t arguments=@t]
    %-  pairs:enjs:format
    :~  ['id' s+id]
        ['type' s+'function']
        :-  'function'
        (pairs:enjs:format ~[['name' s+name] ['arguments' s+arguments]])
    ==
  =/  asst-msg=json
    %-  pairs:enjs:format
    :~  ['role' s+'assistant']
        ['content' s+?:(=('' tc-text) '' tc-text)]
        ['tool_calls' [%a tc-json]]
    ==
  ::  execute each tool and collect results — get fresh time for scries
  ;<  nbowl=bowl:nexus  bind:m  (get-bowl:io /tool-bowl)
  ;<  fresh-now=@da  bind:m  get-time:io
  =/  =bowl:gall
    %*  .  *bowl:gall
      our  our.nbowl
      src  our.nbowl
      dap  dap.nbowl
      now  fresh-now
      byk  [our.nbowl q.byk.nbowl [%da fresh-now]]
      eny  eny.nbowl
    ==
  ;<  tool-results=(list json)  bind:m
    (exec-tools tc-calls bowl bbrave is-owner bot-id bname bavatar)
  =.  extra-msgs
    %+  weld  extra-msgs
    [asst-msg (flop tool-results)]
  $(round +(round))
::
::  +exec-tools: execute a list of tool calls, return result messages
::
++  exec-tools
  |=  $:  tc-calls=(list [id=@t name=@t arguments=@t])
          =bowl:gall
          bbrave=@t  is-owner=?  bot-id=@tas  bname=@t  bavatar=@t
      ==
  =/  m  (fiber:fiber:nexus ,(list json))
  ^-  form:m
  =/  bname-u=(unit @t)  ?:(=('' bname) ~ `bname)
  =/  bavatar-u=(unit @t)  ?:(=('' bavatar) ~ `bavatar)
  ::  process tools sequentially, accumulating result messages
  (exec-tool-list tc-calls ~ bowl bbrave is-owner bot-id bname-u bavatar-u)
::
++  exec-tool-list
  |=  $:  pending=(list [id=@t name=@t arguments=@t])
          results=(list json)
          =bowl:gall
          bbrave=@t  is-owner=?  bot-id=@tas
          bname-u=(unit @t)  bavatar-u=(unit @t)
      ==
  =/  m  (fiber:fiber:nexus ,(list json))
  ^-  form:m
  ?~  pending  (pure:m results)
  =/  [tid=@t tname=@t targs=@t]  i.pending
  =/  rest=(list [id=@t name=@t arguments=@t])  t.pending
  %-  (slog leaf+"claw-grub: executing tool '{(trip tname)}' args={(trip (end 3^80 targs))}" ~)
  ::  intercept delegate — spawn a sub-agent task
  ?:  =('delegate' tname)
    =/  mk-res  |=(c=@t (pairs:enjs:format ~[['role' s+'tool'] ['tool_call_id' s+tid] ['content' s+c]]))
    =/  args-json=(unit json)  (de:json:html targs)
    ?~  args-json
      (exec-tool-list rest [(mk-res 'error: invalid json') results] bowl bbrave is-owner bot-id bname-u bavatar-u)
    =/  task-prompt=@t  (jget u.args-json 'task' '')
    =/  report-to=@t  (jget u.args-json 'report_to' '')
    ?:  =('' task-prompt)
      (exec-tool-list rest [(mk-res 'error: task description required') results] bowl bbrave is-owner bot-id bname-u bavatar-u)
    ::  generate task id from current time
    ;<  task-now=@da  bind:m  get-time:io
    =/  task-id=@tas  (crip (scag 12 (slag 2 (trip (scot %uv (mug task-now))))))
    ::  write task config (instructions + where to report)
    =/  task-cfg=json
      %-  pairs:enjs:format
      :~  ['task' s+task-prompt]
          ['report_to' s+report-to]
          ['parent_bot' s+bot-id]
      ==
    =/  cfg-road=road:tarball  [%& %& /bots/[bot-id]/tasks/[task-id] %'config.json']
    =/  cfg-make=make:nexus  [%| %.n json+!>(task-cfg) ~]
    ;<  ~  bind:m  (make:io /task-cfg cfg-road cfg-make)
    =/  sig-road=road:tarball  [%& %& /bots/[bot-id]/tasks/[task-id] %'main.sig']
    =/  sig-make=make:nexus  [%| %.n sig+!>(~) ~]
    ;<  ~  bind:m  (make:io /task-sig sig-road sig-make)
    %-  (slog leaf+"claw-grub: spawned task '{(trip task-id)}' for bot '{(trip bot-id)}'" ~)
    (exec-tool-list rest [(mk-res (rap 3 'Delegated task to sub-agent ' task-id '. It will work independently and report back when done.' ~)) results] bowl bbrave is-owner bot-id bname-u bavatar-u)
  ::  intercept update_profile — write to tarball config
  ?:  =('update_profile' tname)
    =/  args-json=(unit json)  (de:json:html targs)
    ?~  args-json
      (exec-tool-list rest ~ bowl bbrave is-owner bot-id bname-u bavatar-u)
    ;<  cfg-seen=seen:nexus  bind:m
      (peek:io /profile-peek (cord-to-road:tarball './config.json') `%json)
    =/  cfg=json
      ?.  ?=([%& %file *] cfg-seen)  [%o ~]
      !<(json q.cage.p.cfg-seen)
    ?.  ?=([%o *] cfg)
      (exec-tool-list rest ~ bowl bbrave is-owner bot-id bname-u bavatar-u)
    =/  nick=@t  (jget u.args-json 'nickname' '')
    =/  avatar=@t  (jget u.args-json 'avatar' '')
    =/  new-cfg=json
      =/  c=(map @t json)  p.cfg
      =?  c  !=('' nick)    (~(put by c) 'name' s+nick)
      =?  c  !=('' avatar)  (~(put by c) 'avatar' s+avatar)
      [%o c]
    ;<  ~  bind:m  (over:io /profile-write (cord-to-road:tarball './config.json') json+!>(new-cfg))
    ::  also update registry if name changed
    ?:  =('' nick)
      =/  msg=@t  ?:(=('' avatar) 'no changes' 'avatar updated')
      =/  make-result  |=(content=@t (pairs:enjs:format ~[['role' s+'tool'] ['tool_call_id' s+tid] ['content' s+content]]))
      (exec-tool-list rest [(make-result msg) results] bowl bbrave is-owner bot-id bname-u bavatar-u)
    ;<  reg-seen=seen:nexus  bind:m
      (peek:io /reg-peek (cord-to-road:tarball '../../bots-registry.json') `%json)
    =/  reg=json
      ?.  ?=([%& %file *] reg-seen)  [%o ~]
      !<(json q.cage.p.reg-seen)
    ?:  ?=([%o *] reg)
      ;<  ~  bind:m  (over:io /reg-write (cord-to-road:tarball '../../bots-registry.json') json+!>([%o (~(put by p.reg) bot-id s+nick)]))
      =/  make-result  |=(content=@t (pairs:enjs:format ~[['role' s+'tool'] ['tool_call_id' s+tid] ['content' s+content]]))
      (exec-tool-list rest [(make-result (rap 3 'profile updated: name=' nick ~)) results] bowl bbrave is-owner bot-id bname-u bavatar-u)
    =/  make-result  |=(content=@t (pairs:enjs:format ~[['role' s+'tool'] ['tool_call_id' s+tid] ['content' s+content]]))
    (exec-tool-list rest [(make-result (rap 3 'profile updated: name=' nick ~)) results] bowl bbrave is-owner bot-id bname-u bavatar-u)
  ::  build tool result json message helper
  =/  make-result
    |=  content=@t
    ::  cap tool results at 6000 chars
    =/  capped=@t
      ?.  (gth (met 3 content) 6.000)  content
      (rap 3 (end 3^5.900 content) '\0a...[truncated]' ~)
    %-  (slog leaf+"claw-grub: tool '{(trip tname)}' result ({<(met 3 content)>} bytes): {(trip (end 3^120 content))}" ~)
    %-  pairs:enjs:format
    :~  ['role' s+'tool']
        ['tool_call_id' s+tid]
        ['content' s+capped]
    ==
  ::  intercept cron tools — handle via tarball config (grubbery-idiomatic)
  ::  these read/write the bot's own config.json via fiber I/O
  ?:  =('cron_list' tname)
    ;<  cfg-seen=seen:nexus  bind:m
      (peek:io /cron-peek (cord-to-road:tarball './config.json') `%json)
    =/  cfg=json
      ?.  ?=([%& %file *] cfg-seen)  [%o ~]
      !<(json q.cage.p.cfg-seen)
    =/  cron-json=json
      ?.  ?=([%o *] cfg)  [%a ~]
      (fall (~(get by p.cfg) 'cron') [%a ~])
    =/  result-text=@t  (crip (scag 4.000 (trip (en:json:html cron-json))))
    (exec-tool-list rest [(make-result result-text) results] bowl bbrave is-owner bot-id bname-u bavatar-u)
  ?:  =('cron_add' tname)
    =/  args-json=(unit json)  (de:json:html targs)
    ?~  args-json
      (exec-tool-list rest [(make-result 'error: invalid json') results] bowl bbrave is-owner bot-id bname-u bavatar-u)
    =/  sched=@t  (jget u.args-json 'schedule' '')
    =/  prompt=@t  (jget u.args-json 'prompt' '')
    ;<  cfg-seen=seen:nexus  bind:m
      (peek:io /cron-peek (cord-to-road:tarball './config.json') `%json)
    =/  cfg=json
      ?.  ?=([%& %file *] cfg-seen)  [%o ~]
      !<(json q.cage.p.cfg-seen)
    ?.  ?=([%o *] cfg)
      (exec-tool-list rest [(make-result 'error: no bot config') results] bowl bbrave is-owner bot-id bname-u bavatar-u)
    =/  cron=json  (fall (~(get by p.cfg) 'cron') [%a ~])
    ?.  ?=([%a *] cron)
      (exec-tool-list rest [(make-result 'error: invalid cron config') results] bowl bbrave is-owner bot-id bname-u bavatar-u)
    =/  new-job=json  (pairs:enjs:format ~[['schedule' s+sched] ['prompt' s+prompt]])
    =/  new-cfg=json  [%o (~(put by p.cfg) 'cron' [%a (snoc p.cron new-job)])]
    ;<  ~  bind:m  (over:io /cron-write (cord-to-road:tarball './config.json') json+!>(new-cfg))
    =/  msg=@t  (rap 3 'Scheduled cron ' sched ': ' (end 3^40 prompt) ~)
    (exec-tool-list rest [(make-result msg) results] bowl bbrave is-owner bot-id bname-u bavatar-u)
  ?:  =('cron_remove' tname)
    =/  args-json=(unit json)  (de:json:html targs)
    ?~  args-json
      (exec-tool-list rest [(make-result 'error: invalid json') results] bowl bbrave is-owner bot-id bname-u bavatar-u)
    =/  idx=@ud  (fall (rush (jget u.args-json 'id' '0') dem) 0)
    ;<  cfg-seen=seen:nexus  bind:m
      (peek:io /cron-peek (cord-to-road:tarball './config.json') `%json)
    =/  cfg=json
      ?.  ?=([%& %file *] cfg-seen)  [%o ~]
      !<(json q.cage.p.cfg-seen)
    ?.  ?=([%o *] cfg)
      (exec-tool-list rest [(make-result 'error: no bot config') results] bowl bbrave is-owner bot-id bname-u bavatar-u)
    =/  cron=json  (fall (~(get by p.cfg) 'cron') [%a ~])
    ?.  ?=([%a *] cron)
      (exec-tool-list rest [(make-result 'error: invalid cron config') results] bowl bbrave is-owner bot-id bname-u bavatar-u)
    =/  new-cron=(list json)
      =/  i=@ud  0
      =/  out=(list json)  ~
      |-
      ?~  p.cron  (flop out)
      =?  out  !=(i idx)  [i.p.cron out]
      $(p.cron t.p.cron, i +(i))
    =/  new-cfg=json  [%o (~(put by p.cfg) 'cron' [%a new-cron])]
    ;<  ~  bind:m  (over:io /cron-write (cord-to-road:tarball './config.json') json+!>(new-cfg))
    (exec-tool-list rest [(make-result 'Removed cron job') results] bowl bbrave is-owner bot-id bname-u bavatar-u)
  ::  wrap execution in mule — a crashing tool must never kill the bot
  =/  exec-result=(each tool-result:tools tang)
    (mule |.((execute-tool:tools bowl tname targs bbrave is-owner bot-id bname-u bavatar-u)))
  ?:  ?=(%| -.exec-result)
    =/  err-trace=tape
      %-  zing
      %+  turn  (scag 5 `tang`p.exec-result)
      |=(t=tank ~(ram re t))
    %-  (slog leaf+"claw-grub: tool '{(trip tname)}' crashed: {(scag 200 err-trace)}" ~)
    =/  err-msg=@t  (crip (scag 500 (weld "error: tool crashed: " err-trace)))
    (exec-tool-list rest [(make-result err-msg) results] bowl bbrave is-owner bot-id bname-u bavatar-u)
  =/  result=tool-result:tools  p.exec-result
  ?:  ?=([%sync *] result)
    ::  sync tool: send any gall cards, collect result text
    %-  (slog leaf+"claw-grub: tool '{(trip tname)}' sync, {<(lent cards.result)>} cards" ~)
    =/  sync-cards=(list card:agent:gall)  cards.result
    |-
    ?~  sync-cards
      %=  ^$
        pending  rest
        results  [(make-result result.result) results]
      ==
    ;<  ~  bind:m  (send-card:io i.sync-cards)
    $(sync-cards t.sync-cards)
  ::  async tool: execute HTTP request
  %-  (slog leaf+"claw-grub: tool '{(trip tname)}' async" ~)
  ?>  ?=([%async *] result)
  =/  async-card=card:agent:gall  card.result
  ?.  ?=([%pass * %arvo %i %request * *] async-card)
    ::  non-iris async card (e.g. khan thread) — send and wait
    ;<  ~  bind:m  (send-card:io async-card)
    ;<  =sign-arvo  bind:m
      |=  input:fiber:nexus
      :+  ~  state
      ?~  in  [%wait ~]
      ?.  ?=(%arvo -.u.in)  [%skip ~]
      [%done sign.u.in]
    =/  tool-body=@t
      ?:  ?=([%khan %arow %| *] sign-arvo)
        ::  khan thread error — include trace for the bot
        =/  err-tang=tang  p.p.sign-arvo
        =/  trace=tape
          %-  zing
          %+  turn  (scag 10 `tang`err-tang)
          |=(t=tank ~(ram re t))
        (crip (scag 2.000 (weld "error: thread failed:\0a" trace)))
      ?:  ?=([%khan %arow %& *] sign-arvo)
        ::  khan success — extract result
        =/  res-noun  q.p.p.sign-arvo
        =/  as-json=(unit @t)  (mole |.((en:json:html ;;(json res-noun))))
        ?^  as-json  (crip (scag 6.000 (trip u.as-json)))
        =/  as-cord=(unit @t)  (mole |.(;;(@t res-noun)))
        ?^  as-cord  (crip (scag 4.000 (trip u.as-cord)))
        'tool returned non-text result'
      ?:  ?=([%iris %http-response %finished *] sign-arvo)
        %-  crip  %-  (cury scag 6.000)  %-  trip
        ?~(full-file.client-response.sign-arvo 'no response' q.data.u.full-file.client-response.sign-arvo)
      'tool completed (unknown response type)'
    (exec-tool-list rest [(make-result tool-body) results] bowl bbrave is-owner bot-id bname-u bavatar-u)
  ::  iris HTTP request
  =/  ireq=request:http  +>+>+<.async-card
  ;<  ~  bind:m  (send-request:io ireq)
  ;<  =client-response:iris  bind:m  take-client-response:io
  ?>  ?=(%finished -.client-response)
  =/  tool-body=@t
    (parse-tool-response:tools tname ?~(full-file.client-response '' q.data.u.full-file.client-response))
  (exec-tool-list rest [(make-result tool-body) results] bowl bbrave is-owner bot-id bname-u bavatar-u)
::
::  +send-reply: route reply to the appropriate channel, thread, or DM
::
++  send-reply
  |=  $:  our=@p  from=@p
          is-dm=?  is-thread=?
          nk=@t  ns=@t  nn=@t  parent-id=@t
          text=@t  bname=@t  bavatar=@t  now=@da
      ==
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  get fresh timestamp for message ID
  ;<  fresh-now=@da  bind:m  get-time:io
  =/  bname-u=(unit @t)  ?:(=('' bname) ~ `bname)
  =/  bavatar-u=(unit @t)  ?:(=('' bavatar) ~ `bavatar)
  =/  =author:d  (bot-author our bname-u bavatar-u)
  =/  =story:d  (text-to-story:story-parse text)
  ?:  is-dm
    ::  DM reply
    =/  =memo:d  [content=story author=author sent=fresh-now]
    =/  =essay:c  [memo [%chat /] ~ ~]
    =/  =delta:writs:c  [%add essay ~]
    =/  =diff:writs:c  [[our fresh-now] delta]
    =/  =action:dm:c  [from diff]
    (gall-poke:io /dm-send [our %chat] %chat-dm-action-1 !>(action))
  ::  channel or thread reply
  =/  =memo:d  [content=story author=author sent=fresh-now]
  =/  kind=?(%chat %diary %heap)  (nest-kind nk)
  =/  =nest:d  [kind (slav %p ns) (crip (trip nn))]
  ?:  is-thread
    ::  thread reply
    =/  pid=@da  (slav %da parent-id)
    =/  act=a-channels:d  [%channel nest [%post [%reply pid [%add memo]]]]
    (gall-poke:io /ch-send [our %channels] %channel-action-1 !>(act))
  ::  top-level channel post
  =/  =essay:d  [memo /chat ~ ~]
  =/  act=a-channels:d  [%channel nest [%post [%add essay]]]
  (gall-poke:io /ch-send [our %channels] %channel-action-1 !>(act))
::
::  +read-context-files: read identity, soul, agent, memory from ./context/
::
++  read-context-files
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
::
::  ┌────���─────────────────────────────────────────────┐
::  │ TASK (SUB-AGENT) LOOP                            │
::  └─���──────────────────────────────��─────────────────┘
::
++  task-loop
  |=  [bot-id=@tas task-id=@tas]
  =/  m  (fiber:fiber:nexus ,~)
  ^-  form:m
  ::  read task config
  ;<  task-seen=seen:nexus  bind:m
    (peek:io /task-cfg (cord-to-road:tarball './config.json') `%json)
  =/  task-cfg=json
    ?.  ?=([%& %file *] task-seen)  [%o ~]
    !<(json q.cage.p.task-seen)
  =/  task-prompt=@t  (jget task-cfg 'task' '')
  =/  report-to=@t   (jget task-cfg 'report_to' '')
  ?:  =('' task-prompt)
    %-  (slog leaf+"claw-grub: task '{(trip task-id)}' has no prompt, exiting" ~)
    (pure:m ~)
  ::  read parent bot's config for API key, model, context
  ;<  bot-cfg-seen=seen:nexus  bind:m
    (peek:io /bot-cfg (cord-to-road:tarball '../../config.json') `%json)
  =/  bot-cfg=json
    ?.  ?=([%& %file *] bot-cfg-seen)  [%o ~]
    !<(json q.cage.p.bot-cfg-seen)
  =/  bname=@t  (jget bot-cfg 'name' '')
  =/  bavatar=@t  (jget bot-cfg 'avatar' '')
  ::  read global config
  ;<  global-seen=seen:nexus  bind:m
    (peek:io /gcfg (cord-to-road:tarball '../../../../config.json') `%json)
  =/  global-cfg=json
    ?.  ?=([%& %file *] global-seen)  [%o ~]
    !<(json q.cage.p.global-seen)
  =/  bmodel=@t
    =/  bm=@t  (jget bot-cfg 'model' '')
    ?:(=('' bm) (jget global-cfg 'model' 'anthropic/claude-sonnet-4') bm)
  =/  bkey=@t
    =/  bk=@t  (jget bot-cfg 'api_key' '')
    ?:(=('' bk) (jget global-cfg 'api_key' '') bk)
  ?:  =('' bkey)
    %-  (slog leaf+"claw-grub: task '{(trip task-id)}' no API key" ~)
    (pure:m ~)
  ;<  our=@p  bind:m  get-our:io
  ;<  now=@da  bind:m  get-time:io
  ::  read parent bot context files for background
  =/  ctx-fields=(list @tas)  ~[%identity %soul %agent]
  =|  ctx-parts=(list @t)
  |-
  ?~  ctx-fields
    ::  all context read — build prompt and call LLM
    =/  parent-ctx=@t  (join-parts (flop ctx-parts))
    =/  sys-prompt=@t
      %+  rap  3
      :~  '# Sub-Agent Task\0a\0a'
          'You are a temporary sub-agent of '  bname
          ' (bot on '  (scot %p our)  ').\0a'
          'You have been delegated a specific task. Complete it thoroughly, '
          'then provide your findings as a clear, complete response.\0a'
          'You have the same tools available as the parent bot.\0a'
          '\0a---\0a\0a'
          ?:(=('' parent-ctx) '' (rap 3 '# Parent Bot Context\0a\0a' parent-ctx '\0a\0a---\0a\0a' ~))
          '# Your Task\0a\0a'
          task-prompt
      ==
    =/  api-msgs=json
      :-  %a
      :~  (pairs:enjs:format ~[['role' s+'system'] ['content' s+sys-prompt]])
          (pairs:enjs:format ~[['role' s+'user'] ['content' s+task-prompt]])
      ==
    =/  body-cord=@t
      %-  en:json:html
      %-  pairs:enjs:format
      :~  ['model' s+bmodel]
          ['messages' api-msgs]
          ['tools' tool-defs:tools]
      ==
    %-  (slog leaf+"claw-grub: task '{(trip task-id)}' calling LLM" ~)
    =/  =request:http
      :^  %'POST'  'https://openrouter.ai/api/v1/chat/completions'
        :~  ['Content-Type' 'application/json']
            ['Authorization' (crip "Bearer {(trip bkey)}")]
        ==
      `(as-octs:mimes:html body-cord)
    ;<  ~  bind:m  (send-request:io request)
    ;<  =client-response:iris  bind:m  take-client-response:io
    ?>  ?=(%finished -.client-response)
    =/  status=@ud  status-code.response-header.client-response
    =/  response-body=@t
      ?~  full-file.client-response  ''
      q.data.u.full-file.client-response
    =/  parsed  (parse-llm-response status response-body)
    =/  result-text=@t
      ?:  ?=([%error *] parsed)
        =/  [%error err=@t]  parsed
        (rap 3 'Sub-agent error: ' err ~)
      ?:  ?=([%text *] parsed)
        =/  [%text txt=@t]  parsed
        txt
      ::  tools response — just extract text portion for now
      ?>  ?=([%tools *] parsed)
      =/  [%tools txt=@t *]  parsed
      ?:(=('' txt) 'Sub-agent completed (tool calls not supported in sub-agents yet)' txt)
    %-  (slog leaf+"claw-grub: task '{(trip task-id)}' complete: {(trip (end 3^60 result-text))}" ~)
    ::  send result as a message
    ;<  fresh-now=@da  bind:m  get-time:io
    =/  report-msg=@t
      (rap 3 '[Sub-agent report for ' bname ']\0a\0aTask: ' (end 3^100 task-prompt) '\0a\0aResult:\0a' result-text ~)
    ::  parse report_to to determine where to send
    ?:  |(=('' report-to) =((end 3^3 report-to) 'dm/'))
      ::  DM: extract ship from "dm/~ship" or default to our
      =/  target=@p
        ?:  =('' report-to)  our
        (fall (slaw %p (rsh 3^3 report-to)) our)
      (send-reply our target %.y %.n '' '' '' '' report-msg bname bavatar fresh-now)
    ::  channel: parse "channel/kind/~ship/name"
    =/  parts=(list @t)  (rash report-to (more fas (cook crip (plus ;~(pose hig low nud dot hep sig)))))
    ?.  (gte (lent parts) 4)
      (send-reply our our %.y %.n '' '' '' '' report-msg bname bavatar fresh-now)
    =/  ch-kind=@t  (snag 1 parts)
    =/  ch-ship=@t  (snag 2 parts)
    =/  ch-name=@t  (snag 3 parts)
    (send-reply our our %.n %.n ch-kind ch-ship ch-name '' report-msg bname bavatar fresh-now)
  ::  still reading context files
  =/  field=@tas  i.ctx-fields
  =/  filename=@ta  (crip "{(trip field)}.txt")
  ;<  ctx-seen=seen:nexus  bind:m
    (peek:io /task-ctx/[field] [%& %& /context filename] `%txt)
  =/  content=@t
    ?.  ?=([%& %file *] ctx-seen)  ''
    =/  wain-val=wain  !<(wain q.cage.p.ctx-seen)
    (of-wain:format wain-val)
  =?  ctx-parts  !=('' content)
    :_  ctx-parts
    (rap 3 '# ' (crip (cuss (trip field))) '\0a\0a' content ~)
  $(ctx-fields t.ctx-fields)
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
  ?+  ver
    ::  unknown version — preserve everything, don't crash
    %-  (slog leaf+"claw: unknown tarball version {<ver>}, preserving state" ~)
    [sand gain ball]
  ::
      ?(~ [~ %0])
    %+  spin:loader  [sand gain ball]
    :~  (ver-row:loader 1)
        [%fall %& [/ %'config.json'] %.n [~ %json !>(default-config)]]
        [%fall %& [/ %'bots-registry.json'] %.n [~ %json !>(default-registry)]]
        [%fall %& [/ %'main.sig'] %.n [~ %sig !>(~)]]
        [%fall %| /bots [~ ~] [~ ~] empty-dir:loader]
        [%fall %& [/bots/brap %'config.json'] %.n [~ %json !>(default-bot-config)]]
        [%fall %& [/bots/brap %'main.sig'] %.n [~ %sig !>(~)]]
        [%fall %| /bots/brap/context [~ ~] [~ ~] empty-dir:loader]
        [%fall %| /bots/brap/conversations [~ ~] [~ ~] empty-dir:loader]
        ::  grubbery subsystems (server + explorer)
        [%fall %| /'server.server' [~ ~] [~ ~] [`[~ `%server ~] ~]]
        [%fall %| /'explorer.explorer' [~ ~] [~ ~] [`[~ `%explorer ~] ~]]
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
        ::  grubbery subsystems
        [%fall %| /'server.server' [~ ~] [~ ~] [`[~ `%server ~] ~]]
        [%fall %| /'explorer.explorer' [~ ~] [~ ~] [`[~ `%explorer ~] ~]]
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
    ::  always leave-then-watch to avoid wire-not-unique on revive
    ;<  ~  bind:m  (send-card:io [%pass /activity %agent [our %activity] %leave ~])
    ;<  ~  bind:m  (gall-watch:io /activity [our %activity] /v4)
    %-  (slog leaf+"claw-grub: subscribed to activity" ~)
    ::  self-DM watch: one attempt, non-fatal (may fail on fresh ship)
    ;<  ~  bind:m  (send-card:io [%pass /self-dm %agent [our %chat] %leave ~])
    ;<  ~  bind:m  (send-card:io [%pass /self-dm %agent [our %chat] %watch /dm/(scot %p our)])
    %-  (slog leaf+"claw-grub: self-DM watch requested" ~)
    ::  cron timer
    ;<  now=@da  bind:m  get-time:io
    ;<  ~  bind:m  (send-card:io [%pass /cron %arvo %b %wait (add now ~m1)])
    %-  (slog leaf+"claw-grub: cron timer armed" ~)
    (root-loop our)
  ::
  ::  BOT PROCESS: /bots/{id}/main.sig
  ::
      [[%bots @ ~] %'main.sig']
    ;<  ~  bind:m  (rise-wait:io prod "%claw: bot process failed")
    =/  bot-id=@tas  i.t.path.rail
    %-  (slog leaf+"claw-grub: bot '{(trip bot-id)}' process starting" ~)
    (bot-loop bot-id)
  ::
  ::  TASK PROCESS: /bots/{id}/tasks/{task-id}.sig
  ::  temporary sub-agent that runs a prompt, sends results, then completes
  ::
      [[%bots @ %tasks @ ~] %'main.sig']
    =/  bot-id=@tas  i.t.path.rail
    =/  task-id=@tas  i.t.t.t.path.rail
    %-  (slog leaf+"claw-grub: task '{(trip task-id)}' starting for bot '{(trip bot-id)}'" ~)
    (task-loop bot-id task-id)
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
        config.json         Global defaults (api_key, model).
        bots-registry.json  Bot ID -> name mapping for routing.
        main.sig            Root process — activity sub, message routing.
      """
        [%bots ~]
      'Bot directory. Each subdirectory is a separate bot with its own process.'
    ==
      %|
    ?+  rail.p.mana  'File in the claw nexus.'
      [~ %'config.json']         'Global config: api_key, model defaults.'
      [~ %'bots-registry.json']  'Bot registry: maps bot-id to display name for routing.'
      [~ %'main.sig']            'Root process: activity subscription, message routing.'
    ==
  ==
--
