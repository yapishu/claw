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
/+  nexus, tarball, io=fiberio, loader, story-parse, tools=claw-tools
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
      %kick-activity
    ;<  ~  bind:m  (gall-watch:io /activity [our %activity] /v4)
    $
  ::
      %kick-dm
    ;<  ~  bind:m  (gall-watch:io /self-dm [our %chat] /dm/(scot %p our))
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
    $  :: TODO
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
  ::  build system prompt
  =/  sys-prompt=@t
    %+  rap  3
    :~  ctx-text
        '\0a\0a---\0a\0a# Current Conversation\0a\0a'
        ?:  is-dm
          (rap 3 'You are in a DM with ' (scot %p from) '. Your text response is automatically sent as a DM reply.' ~)
        %+  rap  3
        :~  (scot %p from)
            ?:  is-thread
              (rap 3 ' replied in a thread in channel ' nk '/' ns '/' nn ~)
            (rap 3 ' tagged you in channel ' nk '/' ns '/' nn ~)
            '.\0aTheir message ID is: '  msg-id
            '\0aYour responses are automatically posted in '
            ?:(is-thread 'that thread.' 'that channel.')
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
        ?:(=('' tc-text) ['content' ~] ['content' s+tc-text])
        ['tool_calls' [%a tc-json]]
    ==
  ::  execute each tool and collect results
  ;<  nbowl=bowl:nexus  bind:m  (get-bowl:io /bowl)
  =/  =bowl:gall
    %*  .  *bowl:gall
      our  our.nbowl
      src  our.nbowl
      dap  dap.nbowl
      now  now.nbowl
      byk  byk.nbowl
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
  %-  (slog leaf+"claw-grub: tool '{(trip tname)}'" ~)
  =/  result=tool-result:tools
    (execute-tool:tools bowl tname targs bbrave is-owner bot-id bname-u bavatar-u)
  ::  build tool result json message
  =/  make-result
    |=  content=@t
    %-  pairs:enjs:format
    :~  ['role' s+'tool']
        ['tool_call_id' s+tid]
        ['content' s+content]
    ==
  ?:  ?=([%sync *] result)
    ::  sync tool: send any gall cards, collect result text
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
      %-  crip  %-  (cury scag 6.000)  %-  trip
      ?+  sign-arvo  'tool completed'
        [%iris %http-response %finished *]
          ?~  full-file.client-response.sign-arvo  'no response'
          q.data.u.full-file.client-response.sign-arvo
      ==
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
  =/  bname-u=(unit @t)  ?:(=('' bname) ~ `bname)
  =/  bavatar-u=(unit @t)  ?:(=('' bavatar) ~ `bavatar)
  =/  =author:d  (bot-author our bname-u bavatar-u)
  =/  =story:d  (text-to-story:story-parse text)
  ?:  is-dm
    ::  DM reply
    =/  =memo:d  [content=story author=author sent=now]
    =/  =essay:c  [memo [%chat /] ~ ~]
    =/  =delta:writs:c  [%add essay ~]
    =/  =diff:writs:c  [[our now] delta]
    =/  =action:dm:c  [from diff]
    (gall-poke:io /dm-send [our %chat] %chat-dm-action-1 !>(action))
  ::  channel or thread reply
  =/  =memo:d  [content=story author=author sent=now]
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
