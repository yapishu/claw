::  claw: minimal llm agent harness with groups dm integration
::
::  sends prompts to openrouter with full structured context.
::  watches %chat for dms from whitelisted ships, processes
::  them through the llm, and responds via dm.
::
/-  claw
/-  c=chat
/-  d=channels
/-  a=activity
/-  lcm
/-  ct=contacts
/+  dbug, default-agent, server, tools=claw-tools
/+  *story-parse, *cron
|%
+$  card  card:agent:gall
+$  versioned-state  $%(state-0:claw state-1:claw state-2:claw state-3:claw state-4:claw state-5:claw state-6:claw state-7:claw state-8:claw state-9:claw state-10:claw state-11:claw state-12:claw state-13:claw state-14:claw)
::
++  build-prompt
  |=  [=bowl:gall context=(map @tas @t) owner-ts=@da]
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
      "Time: {(scow %da now.bowl)}\0a"
      ?:  =(0 owner-ts)
        "Owner last seen: never"
      "Owner last seen: {(scow %da owner-ts)}"
    ==
  ?~  parts  ''
  =/  out=@t  i.parts
  =/  rem=(list @t)  t.parts
  |-
  ?~  rem  out
  $(rem t.rem, out (rap 3 out '\0a\0a---\0a\0a' i.rem ~))
::
::  +build-bot-prompt: system prompt with bot self-awareness
::
++  build-bot-prompt
  |=  [=bowl:gall bot-id=@tas cfg=bot-config:claw bots=(map @tas bot-config:claw) owner-ts=@da]
  ^-  @t
  =/  base=@t  (build-prompt bowl context.cfg owner-ts)
  =/  my-name=@t  (fall bot-name.cfg (scot %tas bot-id))
  ::  build sibling bots list
  =/  siblings=(list @t)
    %+  murn  ~(tap by bots)
    |=  [id=@tas c=bot-config:claw]
    ?:  =(id bot-id)  ~
    ?~  bot-name.c  ~
    `(rap 3 u.bot-name.c ' (' (scot %tas id) ')' ~)
  =/  sibling-str=@t
    ?~  siblings  'none'
    =/  out=@t  i.siblings
    =/  rest=(list @t)  t.siblings
    |-
    ?~  rest  out
    $(rest t.rest, out (rap 3 out ', ' i.rest ~))
  =/  identity=@t
    %-  crip
    ;:  weld
      "# Bot Identity\0a\0a"
      "You are {(trip my-name)}, a bot sub-identity running on the Urbit ship {(scow %p our.bowl)}.\0a"
      "Your bot-id is {(trip (scot %tas bot-id))}.\0a"
      "Other bots on this ship: {(trip sibling-str)}.\0a"
      "IMPORTANT: Do not respond to messages from other bots on this ship. "
      "If you see a message authored by another bot (shown with a Bot badge), ignore it.\0a"
      "You are NOT the ship operator — you are a bot running on their ship."
    ==
  (rap 3 identity '\0a\0a---\0a\0a' base ~)
::
::  +estimate-tokens: rough token count for a message list
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
::  +assemble-context: build message list from summaries + fresh tail
::
++  make-llm-request
  |=  $:  =bowl:gall  api-key=@t  model=@t  sys-prompt=@t
          key=@t  =wire
          extra-msgs=(list json)
          pending-msg=(unit msg:claw)
      ==
  ^-  card
  ::  scry lcm for assembled context
  =/  budget=@ud  (model-budget model)
  =/  trimmed=(list msg:claw)
    =/  ctx  (lcm-context bowl key budget)
    ::  append pending msg if set (not yet ingested into lcm)
    ?~  pending-msg  ctx
    (snoc ctx u.pending-msg)
  =/  api-msgs=json
    :-  %a
    %+  weld
      %+  turn  [['system' sys-prompt] trimmed]
      |=  =msg:claw
      %-  pairs:enjs:format
      :~  ['role' s+role.msg]
          ['content' s+content.msg]
      ==
    extra-msgs
  =/  body=json
    %-  pairs:enjs:format
    :~  ['model' s+model]
        ['messages' api-msgs]
        ['tools' tool-defs:tools]
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
::  +parse-llm-response: parse openrouter response, detecting tool calls
::
::    returns [%text content] for normal responses
::    returns [%tools assistant-msg tool-calls] for tool call responses
::    where tool-calls is (list [id=@t name=@t arguments=@t])
::
::  +bot-author: build author field, using bot-meta when configured
::
++  bot-author
  |=  [=bowl:gall bname=(unit @t) bavatar=(unit @t)]
  ^-  author:d
  ?~  bname  our.bowl
  [ship=our.bowl nickname=bname avatar=bavatar]
::
::  +send-dm-card: build a card to send a dm to a ship
::
::
::  +lcm-key: convert msg-source to lcm conversation key
::
++  lcm-key
  |=  =msg-source:claw
  ^-  @t
  ?-  -.msg-source
    %direct     'direct'
    %dm         (rap 3 'dm/' (scot %p ship.msg-source) ~)
    %dm-thread  (rap 3 'dm/' (scot %p ship.msg-source) ~)
    %channel    (rap 3 'channel/' kind.msg-source '/' (scot %p host.msg-source) '/' name.msg-source ~)
    %thread     (rap 3 'thread/' kind.msg-source '/' (scot %p host.msg-source) '/' name.msg-source '/' (scot %da parent-id.msg-source) ~)
  ==
::
::  +lcm-ingest: build a card to ingest a message into lcm
::
++  lcm-ingest
  |=  [=bowl:gall key=@t role=@t content=@t]
  ^-  card
  [%pass /lcm-ingest %agent [our.bowl %lcm] %poke %lcm-action !>(`lcm-action:lcm`[%ingest key role content])]
::
::  +lcm-sync-config: sync api key and model to lcm
::
++  lcm-sync-config
  |=  [=bowl:gall api-key=@t model=@t]
  ^-  card
  [%pass /lcm-config %agent [our.bowl %lcm] %poke %lcm-action !>(`lcm-action:lcm`[%set-config [api-key model 75 16 20.000 1.200 2.000 8 4 0]])]
::
::  +lcm-context: scry lcm for assembled context
::
++  lcm-context
  |=  [=bowl:gall key=@t budget=@ud]
  ^-  (list msg:claw)
  =/  result=(each (list msg:claw) tang)
    %-  mule  |.
    =/  j=json
      .^(json %gx /(scot %p our.bowl)/lcm/(scot %da now.bowl)/assemble/[key]/(scot %ud budget)/json)
    ?.  ?=([%a *] j)  ~
    %+  turn  p.j
    |=  item=json
    ^-  msg:claw
    ?.  ?=([%o *] item)  ['system' '']
    =/  m=(map @t json)  p.item
    =/  role=@t
      =/  r  (~(get by m) 'role')
      ?~  r  'system'
      ?.  ?=([%s *] u.r)  'system'
      p.u.r
    =/  con=@t
      =/  c  (~(get by m) 'content')
      ?~  c  ''
      ?.  ?=([%s *] u.c)  ''
      p.u.c
    [role con]
  ?:(?=(%| -.result) ~ p.result)
::  +get-bot: look up bot config, crash if missing
++  get-bot
  |=  [bots=(map @tas bot-config:claw) id=@tas]
  ^-  bot-config:claw
  (~(got by bots) id)
::
::  +bot-api-key: resolve effective api key (per-bot override or global)
++  bot-api-key
  |=  [cfg=bot-config:claw global=@t]
  ^-  @t
  (fall api-key.cfg global)
::
::  +bot-model: resolve effective model
++  bot-model
  |=  [cfg=bot-config:claw global=@t]
  ^-  @t
  (fall model.cfg global)
::
::  +bot-brave-key: resolve effective brave key
++  bot-brave-key
  |=  [cfg=bot-config:claw global=@t]
  ^-  @t
  (fall brave-key.cfg global)
::
::  +effective-lcm-key: namespace lcm key by bot-id
::    default bot keeps legacy unprefixed keys for backward compat
++  effective-lcm-key
  |=  [bot-id=@tas =msg-source:claw]
  ^-  @t
  ?:  =(bot-id %default)  (lcm-key msg-source)
  (rap 3 bot-id '/' (lcm-key msg-source) ~)
::
::  +find-tagged-bots: find all bots whose name appears as [%tag] in story
++  find-tagged-bots
  |=  [bots=(map @tas bot-config:claw) =story:d]
  ^-  (list @tas)
  %+  murn  ~(tap by bots)
  |=  [id=@tas cfg=bot-config:claw]
  ?~  bot-name.cfg  ~
  ?.  (has-bot-tag bot-name.cfg story)  ~
  `id
::
::  +find-named-bots: find all bots whose name appears in text (for DMs)
++  find-named-bots
  |=  [bots=(map @tas bot-config:claw) text=@t]
  ^-  (list @tas)
  %+  murn  ~(tap by bots)
  |=  [id=@tas cfg=bot-config:claw]
  ?~  bot-name.cfg  ~
  =/  nick=tape  (cass (trip u.bot-name.cfg))
  ?~  nick  ~
  ?.  !=(~ (find nick (cass (trip text))))  ~
  `id
::
++  send-dm-card
  |=  [=bowl:gall to=ship text=@t bname=(unit @t) bavatar=(unit @t)]
  ^-  card
  =/  dm-story=story:d  (text-to-story text)
  =/  dm-memo=memo:d  [content=dm-story author=(bot-author bowl bname bavatar) sent=now.bowl]
  =/  dm-essay=essay:c  [dm-memo [%chat /] ~ ~]
  =/  dm-delta=delta:writs:c  [%add dm-essay ~]
  =/  dm-diff=diff:writs:c  [[our.bowl now.bowl] dm-delta]
  =/  dm-act=action:dm:c  [to dm-diff]
  [%pass /dm-send/(scot %p to) %agent [our.bowl %chat] %poke %chat-dm-action-1 !>(dm-act)]
::
::  +src-ship: extract ship from msg-source
::
++  src-ship
  |=  =msg-source:claw
  ^-  ship
  ?-  -.msg-source
    %dm         ship.msg-source
    %dm-thread  ship.msg-source
    %channel    ship.msg-source
    %thread     ship.msg-source
    %direct     *ship
  ==
::
::  +get-nickname: scry %contacts for a ship's nickname
::
++  get-nickname
  |=  [=bowl:gall who=ship]
  ^-  @t
  ::  contacts scry crashes on some ships (on-peek returns ~ for
  ::  unknown contacts, causing an arvo-level crash mule can't catch).
  ::  TODO: subscribe to %contacts and cache nicknames instead.
  ''
::
::  +has-own-nickname: check if text contains bot's own nickname
::    case-insensitive word check
::
++  has-own-nickname
  |=  [bname=(unit @t) text=@t]
  ^-  ?
  ?~  bname  %.n
  =/  nick=tape  (cass (trip u.bname))
  ?~  nick  %.n
  !=(~ (find nick (cass (trip text))))
::
::  +has-bot-tag: check if story content has a [%tag p=botname]
::
++  has-bot-tag
  |=  [bname=(unit @t) =story:d]
  ^-  ?
  ?~  bname  %.n
  =/  nick=@t  u.bname
  %+  lien  story
  |=  =verse:d
  ?.  ?=(%inline -.verse)  %.n
  %+  lien  p.verse
  |=  =inline:d
  ?&  ?=([%tag *] inline)
      =(nick p.inline)
  ==
::
::  +send-reply-card: send a response based on message source
::
++  send-reply-card
  |=  [=bowl:gall =msg-source:claw text=@t bname=(unit @t) bavatar=(unit @t)]
  ^-  card
  ?-  -.msg-source
      %direct  [%pass /noop %arvo %b %wait (add now.bowl ~s1)]
      %dm      (send-dm-card bowl ship.msg-source text bname bavatar)
      %dm-thread
    ::  DM thread replies: send as regular DM for now
    ::  (activity message-key IDs don't reliably match chat writ IDs)
    (send-dm-card bowl ship.msg-source text bname bavatar)
      %channel
    ::  post in channel as top-level message
    =/  ch-story=story:d  (text-to-story text)
    =/  ch-memo=memo:d  [content=ch-story author=(bot-author bowl bname bavatar) sent=now.bowl]
    =/  ch-essay=essay:d  [ch-memo /chat ~ ~]
    =/  =nest:d  [kind.msg-source host.msg-source name.msg-source]
    =/  act=a-channels:d  [%channel nest [%post [%add ch-essay]]]
    [%pass /ch-send %agent [our.bowl %channels] %poke %channel-action-1 !>(act)]
      %thread
    ::  post as reply in a thread
    =/  th-story=story:d  (text-to-story text)
    =/  th-memo=memo:d  [content=th-story author=(bot-author bowl bname bavatar) sent=now.bowl]
    =/  =nest:d  [kind.msg-source host.msg-source name.msg-source]
    =/  act=a-channels:d  [%channel nest [%post [%reply parent-id.msg-source [%add th-memo]]]]
    [%pass /ch-send %agent [our.bowl %channels] %poke %channel-action-1 !>(act)]
  ==
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
  ::  check for tool_calls
  =/  tc=(unit json)  (~(get by msg-map) 'tool_calls')
  ?~  tc
    ::  normal text response
    =/  content=json  (need (~(get by msg-map) 'content'))
    ?.  ?=([%s *] content)  !!
    [%text p.content]
  ::  tool call response - also grab content text if present
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
::
::  helper: extract object map from json
++  me
  |=  =json
  ^-  (unit (map @t ^json))
  ?.  ?=([%o *] json)  ~
  `p.json
::
::
++  slash-help-text
  ^-  @t
  %-  crip
  ;:  weld
    "Available commands:\0a"
    "/model - show current model\0a"
    "/model <name> - set model (owner only)\0a"
    "/clear - clear conversation history\0a"
    "/status - show agent status\0a"
    "/approve ~ship - approve a pending ship (owner only)\0a"
    "/deny ~ship - deny a pending ship (owner only)\0a"
    "/pending - list pending approval requests (owner only)\0a"
    "/botname <name> - set bot display name (owner only)\0a"
    "/botavatar <url> - set bot avatar URL (owner only)\0a"
    "/help - show this help\0a"
    "\0aAvailable tools:\0a"
    "web_search, image_search, upload_image, send_dm,\0a"
    "send_channel_message, add_reaction, remove_reaction,\0a"
    "get_contact, list_groups, list_channels,\0a"
    "read_channel_history, http_fetch, update_profile,\0a"
    "join_group, leave_group, local_mcp, local_mcp_list,\0a"
    "cron_add, cron_list, cron_remove"
  ==
::
++  handle-slash
  |=  $:  =bowl:gall  text=@t  from=ship  =msg-source:claw
          mod=@t  pend=?  api=@t  last-err=@t
          wl=(map ship ship-role:claw)  ctx=(map @tas @t)
          pa=(map ship @t)  owner-ts=@da
          bname=(unit @t)  bavatar=(unit @t)
      ==
  ^-  (unit (list card))
  ::  trim both leading and trailing whitespace
  =/  txt=tape
    =/  raw=tape  (trip text)
    (flop (trim-ws (flop (trim-ws raw))))
  ?~  txt  ~
  ?.  =(i.txt '/')  ~
  =/  cmd=@t  (crip txt)
  ?:  =(cmd '/help')
    `[(send-reply-card bowl msg-source slash-help-text bname bavatar)]~
  ::  /model or /model <name>
  ?:  =(cmd '/model')
    =/  ctx-win=@t  (fall (~(get by ctx) %model-context-window) 'unknown')
    =/  info=@t
      %-  crip
      ;:  weld
        "Model: {(trip mod)}\0a"
        "Context window: {(trip ctx-win)} tokens"
      ==
    `[(send-reply-card bowl msg-source info bname bavatar)]~
  ?:  &((gte (met 3 cmd) 8) =((end [3 7] cmd) '/model '))
    =/  new-model=@t  (crip (trim-ws (trip (rsh [3 7] cmd))))
    ?:  =('' new-model)
      `[(send-reply-card bowl msg-source (rap 3 'Model: ' mod ~) bname bavatar)]~
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can change the model.' bname bavatar)]~
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Model set to: ' new-model ~) bname bavatar)
        [%pass /slash-model %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%set-model new-model])]
    ==
  ?:  =(cmd '/clear')
    =/  key=@t  (lcm-key msg-source)
    %-  some
    :~  (send-reply-card bowl msg-source 'Conversation cleared.' bname bavatar)
        [%pass /lcm-clear %agent [our.bowl %lcm] %poke %lcm-action !>(`lcm-action:lcm`[%clear key])]
    ==
  ?:  =(cmd '/status')
    =/  owner-ago=@t
      ?:  =(0 owner-ts)  'never'
      =/  diff=@dr  (sub now.bowl owner-ts)
      =/  mins=@ud  (div diff ~m1)
      ?:  (lth mins 60)
        (rap 3 (scot %ud mins) 'm ago' ~)
      =/  hrs=@ud  (div mins 60)
      ?:  (lth hrs 24)
        (rap 3 (scot %ud hrs) 'h ago' ~)
      (rap 3 (scot %ud (div hrs 24)) 'd ago' ~)
    =/  status=@t
      %-  crip
      ;:  weld
        "Model: {(trip mod)}\0a"
        "Pending: {?:(pend "yes" "no")}\0a"
        "Ships: {(a-co:co ~(wyt by wl))}\0a"
        "Pending approvals: {(a-co:co ~(wyt by pa))}\0a"
        "Owner last seen: {(trip owner-ago)}\0a"
        "Error: {?:(=('' last-err) "none" (trip (end 3^100 last-err)))}"
      ==
    `[(send-reply-card bowl msg-source status bname bavatar)]~
  ::  /open <channel> - set channel to allow all (owner only)
  ?:  &((gte (met 3 cmd) 7) =((end [3 6] cmd) '/open '))
    =/  ch=@t  (crip (trim-ws (trip (rsh [3 6] cmd))))
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can manage channel permissions.' bname bavatar)]~
    ::  poke self to update channel-perms
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Channel ' ch ' set to open.' ~) bname bavatar)
        [%pass /slash-perm %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%set-channel-perm ch %open])]
    ==
  ::  /restrict <channel> - set channel to whitelist-only (owner only)
  ?:  &((gte (met 3 cmd) 11) =((end [3 10] cmd) '/restrict '))
    =/  ch=@t  (crip (trim-ws (trip (rsh [3 10] cmd))))
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can manage channel permissions.' bname bavatar)]~
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Channel ' ch ' set to whitelist-only.' ~) bname bavatar)
        [%pass /slash-perm %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%set-channel-perm ch %whitelist])]
    ==
  ::  /approve ~ship - approve a pending ship (owner only)
  ?:  &((gte (met 3 cmd) 10) =((end [3 9] cmd) '/approve '))
    =/  ship-str=@t  (crip (trim-ws (trip (rsh [3 9] cmd))))
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can approve ships.' bname bavatar)]~
    =/  parsed=(unit ship)  (slaw %p ship-str)
    ?~  parsed
      `[(send-reply-card bowl msg-source 'Invalid ship name.' bname bavatar)]~
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Approved ' ship-str ' and added to whitelist.' ~) bname bavatar)
        [%pass /slash-approve %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%approve u.parsed])]
    ==
  ::  /deny ~ship - deny a pending ship (owner only)
  ?:  &((gte (met 3 cmd) 7) =((end [3 6] cmd) '/deny '))
    =/  ship-str=@t  (crip (trim-ws (trip (rsh [3 6] cmd))))
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can deny ships.' bname bavatar)]~
    =/  parsed=(unit ship)  (slaw %p ship-str)
    ?~  parsed
      `[(send-reply-card bowl msg-source 'Invalid ship name.' bname bavatar)]~
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Denied ' ship-str '.' ~) bname bavatar)
        [%pass /slash-deny %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%deny u.parsed])]
    ==
  ::  /pending - list pending approval requests (owner only)
  ?:  =(cmd '/pending')
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can view pending approvals.' bname bavatar)]~
    ?:  =(~ pa)
      `[(send-reply-card bowl msg-source 'No pending approval requests.' bname bavatar)]~
    =/  lines=(list @t)
      %+  turn  ~(tap by pa)
      |=  [s=ship reason=@t]
      (rap 3 '- ' (scot %p s) ': ' reason ~)
    =/  body=@t
      %+  roll  lines
      |=  [line=@t acc=@t]
      ?:(=('' acc) line (rap 3 acc '\0a' line ~))
    `[(send-reply-card bowl msg-source (rap 3 'Pending approvals:\0a' body ~) bname bavatar)]~
  ::  /botname <name> - set bot display name (owner only)
  ?:  &((gte (met 3 cmd) 10) =((end [3 9] cmd) '/botname '))
    =/  new-name=@t  (crip (trim-ws (trip (rsh [3 9] cmd))))
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can set bot name.' bname bavatar)]~
    =/  name-unit=(unit @t)  ?:(=('' new-name) ~ `new-name)
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Bot name set to: ' ?~(name-unit 'none (disabled)' u.name-unit) ~) bname bavatar)
        [%pass /slash-botname %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%set-bot-name name-unit])]
    ==
  ::  /botavatar <url> - set bot avatar URL (owner only)
  ?:  &((gte (met 3 cmd) 12) =((end [3 11] cmd) '/botavatar '))
    =/  new-avatar=@t  (crip (trim-ws (trip (rsh [3 11] cmd))))
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can set bot avatar.' bname bavatar)]~
    =/  avatar-unit=(unit @t)  ?:(=('' new-avatar) ~ `new-avatar)
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Bot avatar set to: ' ?~(avatar-unit 'none' u.avatar-unit) ~) bname bavatar)
        [%pass /slash-botavatar %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%set-bot-avatar avatar-unit])]
    ==
  ~
--
::
%-  agent:dbug
=|  state-14:claw
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
          "across sessions. You are connected to the Urbit network\0a"
          "and receive direct messages from whitelisted ships.\0a"
          "\0a"
          "IMPORTANT: Your text response is automatically routed\0a"
          "back to wherever the message came from - DM or channel.\0a"
          "You do NOT need to call any tool to reply. Just respond.\0a"
          "\0a"
          "The system prompt includes message IDs and channel info\0a"
          "for the current conversation. Use these IDs with tools\0a"
          "like add_reaction. DO NOT ask for IDs you already have.\0a"
          "\0a"
          "TOOLS: web_search, image_search, upload_image,\0a"
          "send_dm, send_channel_message (both support image_url),\0a"
          "add_reaction, remove_reaction, block_ship, unblock_ship,\0a"
          "get_contact, list_groups, list_channels,\0a"
          "read_channel_history, http_fetch, update_profile,\0a"
          "join_group, leave_group.\0a"
          "\0a"
          "MEMORY TOOLS (for recalling compacted history):\0a"
          "- search_history: search ALL conversations for a keyword/topic.\0a"
          "  Returns matching snippets with summary IDs.\0a"
          "- describe_summary: get full content and metadata for a summary ID.\0a"
          "  Use after search_history to read compressed context.\0a"
          "- list_conversations: see all conversation keys and sizes.\0a"
          "Escalation: search_history first, then describe_summary for details.\0a"
          "\0a"
          "SCHEDULED TASKS (cron):\0a"
          "- cron_add: schedule a recurring prompt (owner only).\0a"
          "  Uses cron expressions: min hour dom month dow.\0a"
          "  Examples: '*/30 * * * *' (every 30min), '0 9 * * *' (daily 9am).\0a"
          "- cron_list: list all scheduled tasks.\0a"
          "- cron_remove: remove a task by ID (owner only).\0a"
          "\0a"
          "When asked to find/send images, ALWAYS:\0a"
          "1. Call image_search with a descriptive query\0a"
          "2. Pick the best image URL from the results\0a"
          "3. Call send_dm with ship=<requester> and image_url=<url>\0a"
          "4. Respond confirming what you sent."
        ==
    ==
  =/  default-cfg=bot-config:claw  [~ ~ ~ ~ ~ default-ctx ~ ~ ~ 0]
  :_  this(model 'anthropic/claude-sonnet-4', pending %.n, bots (~(put by *(map @tas bot-config:claw)) %default default-cfg), default-bot %default)
  :~  [%pass /eyre/connect %arvo %e %connect [`/apps/claw/api dap.bowl]]
      ::  subscribe to activity for mentions and group invites
      [%pass /activity %agent [our.bowl %activity] %watch /v4]
      ::  subscribe to self-DM for bot interaction with owner
      ::  use v3 path to get bot-meta author in responses
      [%pass /dm-watch/(scot %p our.bowl) %agent [our.bowl %chat] %watch /dm/(scot %p our.bowl)]
  ==
::
++  on-save  !>(state)
::
++  on-load
  |=  =vase
  ^-  (quip card _this)
  =/  old  !<(versioned-state vase)
  ::  state-14 already current - skip migration
  ?:  ?=(%14 -.old)
    =/  new=state-14:claw  old
    =/  def-cfg=bot-config:claw  (get-bot bots.new %default)
    =/  sub-cards=(list card)
      :~  [%pass /activity %agent [our.bowl %activity] %leave ~]
          [%pass /activity %agent [our.bowl %activity] %watch /v4]
      ==
    =/  dm-cards=(list card)
      :-  [%pass /dm-watch/(scot %p our.bowl) %agent [our.bowl %chat] %leave ~]
      :-  [%pass /dm-watch/(scot %p our.bowl) %agent [our.bowl %chat] %watch /dm/(scot %p our.bowl)]
      %+  murn  ~(tap by whitelist.def-cfg)
      |=  [s=ship r=ship-role:claw]
      ?:  =(s our.bowl)  ~
      `[%pass /dm-watch/(scot %p s) %agent [our.bowl %chat] %watch /dm/(scot %p s)]
    =/  cron-cards=(list card)
      %+  murn  ~(tap by cron-jobs.def-cfg)
      |=  [cid=@ud job=cron-job:claw]
      ?.  active.job  ~
      =/  nxt=(unit @da)  (next-cron-fire schedule.job now.bowl)
      ?~  nxt  ~
      `[%pass /cron/(scot %ud cid)/(scot %ud version.job) %arvo %b %wait u.nxt]
    :_  this(state new)
    :(weld sub-cards dm-cards cron-cards)
  ::  first migrate everything to state-13
  =/  mid=state-13:claw
    ?-  -.old
        %13  old
        %12
      [%13 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old channel-perms.old participated.old seen-msgs.old bot-counts.old pending-approvals.old owner-last-msg.old cron-jobs.old next-cron-id.old msg-queue.old ~ ~]
        %11
      [%13 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old channel-perms.old participated.old seen-msgs.old bot-counts.old pending-approvals.old owner-last-msg.old cron-jobs.old next-cron-id.old ~ ~ ~]
        %10
      [%13 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old channel-perms.old participated.old seen-msgs.old bot-counts.old pending-approvals.old owner-last-msg.old ~ 0 ~ ~ ~]
        %9
      [%13 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old channel-perms.old participated.old seen-msgs.old bot-counts.old pending-approvals.old owner-last-msg.old ~ 0 ~ ~ ~]
        %8
      [%13 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old channel-perms.old participated.old seen-msgs.old ~ ~ *@da ~ 0 ~ ~ ~]
        %7
      [%13 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old channel-perms.old ~ ~ ~ ~ *@da ~ 0 ~ ~ ~]
        %6
      [%13 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old ~ ~ ~ ~ ~ *@da ~ 0 ~ ~ ~]
        %5
      [%13 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~ ~ ~]
        %4
      [%13 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~ ~ ~]
        %3
      [%13 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~ ~ ~]
        %2
      [%13 api-key.old '' model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~ ~ ~]
        %1
      [%13 api-key.old '' model.old pending.old last-error.old context.old ~ ~ ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~ ~ ~]
        %0
      =/  ctx=(map @tas @t)  *(map @tas @t)
      =?  ctx  !=('' system-prompt.old)
        (~(put by ctx) %agent system-prompt.old)
      [%13 api-key.old '' model.old pending.old last-error.old ctx ~ ~ ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~ ~ ~]
    ==
  ::  now migrate state-13 to state-14
  =/  new=state-14:claw
    =/  cfg=bot-config:claw
      :*  bot-name.mid  bot-avatar.mid
          ~  ~  ~
          context.mid  whitelist.mid
          channel-perms.mid  cron-jobs.mid
          next-cron-id.mid
      ==
    :*  %14
        api-key.mid  brave-key.mid  model.mid
        pending.mid  last-error.mid
        seen-msgs.mid  pending-approvals.mid
        owner-last-msg.mid  msg-queue.mid
        ::  bots
        (~(put by *(map @tas bot-config:claw)) %default cfg)
        %default
        ::  dm-pending: wrap each ship with %default
        %-  ~(gas in *(set [@tas ship]))
        (turn ~(tap in dm-pending.mid) |=(s=ship [%default s]))
        ::  pending-src: wrap each key with %default
        %-  ~(gas by *(map [@tas ship] msg-source:claw))
        (turn ~(tap by pending-src.mid) |=([s=ship src=msg-source:claw] [[%default s] src]))
        ::  participated: put under %default
        (~(put by *(map @tas (set @t))) %default participated.mid)
        ::  bot-counts: wrap each key with %default
        %-  ~(gas by *(map [@tas @t] @ud))
        (turn ~(tap by bot-counts.mid) |=([k=@t v=@ud] [[%default k] v]))
        ::  tool-loops: migrate tool-loop
        ?~  tool-loop.mid  *(map @tas tool-pending:claw)
        (~(put by *(map @tas tool-pending:claw)) %default u.tool-loop.mid)
    ==
  ::  re-establish subscriptions on every load
  =/  sub-cards=(list card)
    :~  [%pass /activity %agent [our.bowl %activity] %leave ~]
        [%pass /activity %agent [our.bowl %activity] %watch /v4]
    ==
  ::  re-subscribe to DMs for all whitelisted ships + self-DM
  =/  def-cfg=bot-config:claw  (get-bot bots.new %default)
  =/  dm-cards=(list card)
    ::  leave then re-subscribe to self-DM (v3 for bot-meta)
    :-  [%pass /dm-watch/(scot %p our.bowl) %agent [our.bowl %chat] %leave ~]
    :-  [%pass /dm-watch/(scot %p our.bowl) %agent [our.bowl %chat] %watch /dm/(scot %p our.bowl)]
    ::  regular DM watches, skip our.bowl (handled above)
    %+  murn  ~(tap by whitelist.def-cfg)
    |=  [s=ship r=ship-role:claw]
    ?:  =(s our.bowl)  ~
    `[%pass /dm-watch/(scot %p s) %agent [our.bowl %chat] %watch /dm/(scot %p s)]
  ::  sync config to lcm when migrating from older state
  =/  migrate-cards=(list card)
    ?.  ?|  =(-.old %6)
            =(-.old %9)
            =(-.old %10)
            =(-.old %11)
            =(-.old %12)
            =(-.old %13)
        ==
      :~  (lcm-sync-config bowl api-key.new model.new)
      ==
    ~
  ::  re-arm all active cron timers
  =/  cron-cards=(list card)
    %+  murn  ~(tap by cron-jobs.def-cfg)
    |=  [cid=@ud job=cron-job:claw]
    ?.  active.job  ~
    =/  nxt=(unit @da)  (next-cron-fire schedule.job now.bowl)
    ?~  nxt  ~
    `[%pass /cron/(scot %ud cid)/(scot %ud version.job) %arvo %b %wait u.nxt]
  :_  this(state new)
  :(weld sub-cards dm-cards migrate-cards cron-cards)
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+  mark
    (on-poke:def mark vase)
  ::
      %handle-http-request
    =+  !<([rid=@ta =inbound-request:eyre] vase)
    =/  req  inbound-request
    ?>  authenticated.req
    =/  rl  (parse-request-line:server url.request.req)
    =/  site=(list @t)  site.rl
    ::  strip /apps/claw/api prefix
    =/  api-path=(list @t)
      ^-  (list @t)
      ?.  ?=([@ @ @ *] site)  ~
      ?.  &(=('apps' i.site) =('claw' i.t.site) =('api' i.t.t.site))  ~
      t.t.t.site
    =/  cors-headers=(list [key=@t value=@t])
      :~  ['content-type' 'application/json']
          ['access-control-allow-origin' '*']
      ==
    ::  POST /action: handle separately so state changes persist
    ::
    ?:  ?=([%action ~] api-path)
      ?.  ?=(%'POST' method.request.req)
        :_  this
        (give-simple-payload:app:server rid [[405 ~] `(as-octs:mimes:html '"method not allowed"')])
      ?~  body.request.req
        :_  this
        (give-simple-payload:app:server rid [[400 ~] `(as-octs:mimes:html '"no body"')])
      =/  jon=(unit json)  (de:json:html q.u.body.request.req)
      ?~  jon
        :_  this
        (give-simple-payload:app:server rid [[400 ~] `(as-octs:mimes:html '"invalid json"')])
      =/  act=(unit action:claw)
        %-  mole  |.
        =,  dejs:format
        =/  typ=@t  ((ot ~[action+so]) u.jon)
        ?+  typ  !!
            %'set-key'
          ^-  action:claw  [%set-key `@t`((ot ~[key+so]) u.jon)]
            %'set-model'
          ^-  action:claw  [%set-model `@t`((ot ~[model+so]) u.jon)]
            %'set-brave-key'
          ^-  action:claw  [%set-brave-key `@t`((ot ~[key+so]) u.jon)]
            %'set-context'
          ^-  action:claw
          =/  [f=@tas c=@t]  ((ot ~[field+(se %tas) content+so]) u.jon)
          [%set-context f c]
            %'del-context'
          ^-  action:claw  [%del-context `@tas`((ot ~[field+(se %tas)]) u.jon)]
            %'add-ship'
          ^-  action:claw
          =/  [s=@p r=@t]  ((ot ~[ship+(se %p) role+so]) u.jon)
          [%add-ship s ?:(=('owner' r) %owner %allowed)]
            %'del-ship'
          ^-  action:claw  [%del-ship `@p`((ot ~[ship+(se %p)]) u.jon)]
            %'clear'
          ^-  action:claw  [%clear ~]
            %'prompt'
          ^-  action:claw  [%prompt `@t`((ot ~[content+so]) u.jon)]
            %'approve'
          ^-  action:claw  [%approve `@p`((ot ~[ship+(se %p)]) u.jon)]
            %'deny'
          ^-  action:claw  [%deny `@p`((ot ~[ship+(se %p)]) u.jon)]
            %'cron-add'
          ^-  action:claw
          =/  [s=@t p=@t]
            ((ot ~[schedule+so prompt+so]) u.jon)
          [%cron-add s p]
            %'cron-remove'
          ^-  action:claw  [%cron-remove `@ud`((ot ~[['cron-id' ni]]) u.jon)]
            %'set-bot-name'
          ^-  action:claw
          =/  n=@t  ((ot ~[name+so]) u.jon)
          ?:  =('' n)  [%set-bot-name ~]
          [%set-bot-name `n]
            %'set-bot-avatar'
          ^-  action:claw
          =/  a=@t  ((ot ~[avatar+so]) u.jon)
          ?:  =('' a)  [%set-bot-avatar ~]
          [%set-bot-avatar `a]
          ::  bot management
            %'add-bot'
          ^-  action:claw  [%add-bot `@tas`((ot ~[id+(se %tas)]) u.jon)]
            %'del-bot'
          ^-  action:claw  [%del-bot `@tas`((ot ~[id+(se %tas)]) u.jon)]
            %'set-default-bot'
          ^-  action:claw  [%set-default-bot `@tas`((ot ~[id+(se %tas)]) u.jon)]
          ::  per-bot config
            %'bot-set-name'
          ^-  action:claw
          =/  [id=@tas n=@t]  ((ot ~[id+(se %tas) name+so]) u.jon)
          [%bot-set-name id ?:(=('' n) ~ `n)]
            %'bot-set-avatar'
          ^-  action:claw
          =/  [id=@tas a=@t]  ((ot ~[id+(se %tas) avatar+so]) u.jon)
          [%bot-set-avatar id ?:(=('' a) ~ `a)]
            %'bot-set-model'
          ^-  action:claw
          =/  [id=@tas m=@t]  ((ot ~[id+(se %tas) model+so]) u.jon)
          [%bot-set-model id ?:(=('' m) ~ `m)]
            %'bot-set-key'
          ^-  action:claw
          =/  [id=@tas k=@t]  ((ot ~[id+(se %tas) key+so]) u.jon)
          [%bot-set-key id ?:(=('' k) ~ `k)]
            %'bot-set-brave-key'
          ^-  action:claw
          =/  [id=@tas k=@t]  ((ot ~[id+(se %tas) key+so]) u.jon)
          [%bot-set-brave-key id ?:(=('' k) ~ `k)]
            %'bot-set-context'
          ^-  action:claw
          =/  [id=@tas f=@tas c=@t]  ((ot ~[id+(se %tas) field+(se %tas) content+so]) u.jon)
          [%bot-set-context id f c]
            %'bot-del-context'
          ^-  action:claw
          =/  [id=@tas f=@tas]  ((ot ~[id+(se %tas) field+(se %tas)]) u.jon)
          [%bot-del-context id f]
            %'bot-add-ship'
          ^-  action:claw
          =/  [id=@tas s=@p r=@t]  ((ot ~[id+(se %tas) ship+(se %p) role+so]) u.jon)
          [%bot-add-ship id s ?:(=('owner' r) %owner %allowed)]
            %'bot-del-ship'
          ^-  action:claw
          =/  [id=@tas s=@p]  ((ot ~[id+(se %tas) ship+(se %p)]) u.jon)
          [%bot-del-ship id s]
            %'bot-set-channel-perm'
          ^-  action:claw
          =/  [id=@tas ch=@t p=@t]  ((ot ~[id+(se %tas) channel+so perm+so]) u.jon)
          [%bot-set-channel-perm id ch ?:(=('open' p) %open %whitelist)]
            %'bot-cron-add'
          ^-  action:claw
          =/  [id=@tas s=@t p=@t]  ((ot ~[id+(se %tas) schedule+so prompt+so]) u.jon)
          [%bot-cron-add id s p]
            %'bot-cron-remove'
          ^-  action:claw
          =/  [id=@tas cid=@ud]  ((ot ~[id+(se %tas) ['cron-id' ni]]) u.jon)
          [%bot-cron-remove id cid]
        ==
      ?~  act
        :_  this
        (give-simple-payload:app:server rid [[400 cors-headers] `(as-octs:mimes:html '"bad action"')])
      ::  execute via on-poke and keep state changes
      =/  res=(each (quip card _this) tang)
        %-  mule  |.
        (on-poke %claw-action !>(u.act))
      ?:  ?=(%| -.res)
        :_  this
        (give-simple-payload:app:server rid [[500 cors-headers] `(as-octs:mimes:html '"action failed"')])
      =/  http-cards  (give-simple-payload:app:server rid [[200 cors-headers] `(as-octs:mimes:html '"ok"')])
      [(weld -.p.res http-cards) +.p.res]
    ::  read-only endpoints
    ::
    =;  =simple-payload:http
      :_  this
      (give-simple-payload:app:server rid simple-payload)
    ?+  api-path  [[404 ~] `(as-octs:mimes:html '"not found"')]
    ::
        [%bots ~]
      =/  j=json
        %-  pairs:enjs:format
        :~  ['default' s+(scot %tas default-bot)]
            :-  'bots'
            %-  pairs:enjs:format
            %+  turn  ~(tap by bots)
            |=  [id=@tas cfg=bot-config:claw]
            :-  (scot %tas id)
            %-  pairs:enjs:format
            :~  ['name' s+(fall bot-name.cfg '')]
                ['avatar' s+(fall bot-avatar.cfg '')]
                ['model' s+(fall model.cfg '')]
            ==
        ==
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
        [%bot @ %config ~]
      =/  bid=@tas  (slav %tas i.t.api-path)
      ?.  (~(has by bots) bid)
        [[404 ~] `(as-octs:mimes:html '"bot not found"')]
      =/  cfg=bot-config:claw  (get-bot bots bid)
      =/  j=json
        %-  pairs:enjs:format
        :~  ['name' s+(fall bot-name.cfg '')]
            ['avatar' s+(fall bot-avatar.cfg '')]
            ['model' s+(fall model.cfg model)]
            ['api-key' s+(fall api-key.cfg api-key)]
            ['brave-key' s+(fall brave-key.cfg brave-key)]
            :-  'whitelist'
            %-  pairs:enjs:format
            %+  turn  ~(tap by whitelist.cfg)
            |=  [s=ship r=ship-role:claw]
            [(scot %p s) s+?:(=(r %owner) 'owner' 'allowed')]
            :-  'context-keys'
            a+(turn ~(tap in ~(key by context.cfg)) |=(k=@tas s+(scot %tas k)))
        ==
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
        [%config ~]
      =/  cfg=bot-config:claw  (get-bot bots default-bot)
      =/  j=json
        %-  pairs:enjs:format
        :~  ['model' s+model]
            ['pending' b+pending]
            ['last-error' s+last-error]
            ['api-key' s+api-key]
            ['brave-key' s+brave-key]
            :-  'whitelist'
            %-  pairs:enjs:format
            %+  turn  ~(tap by whitelist.cfg)
            |=  [s=ship r=ship-role:claw]
            [(scot %p s) s+?:(=(r %owner) 'owner' 'allowed')]
            :-  'context-keys'
            a+(turn ~(tap in ~(key by context.cfg)) |=(k=@tas s+(scot %tas k)))
            :-  'pending-approvals'
            %-  pairs:enjs:format
            %+  turn  ~(tap by pending-approvals)
            |=  [s=ship reason=@t]
            [(scot %p s) s+reason]
            ['bot-name' s+(fall bot-name.cfg '')]
            ['bot-avatar' s+(fall bot-avatar.cfg '')]
        ==
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
        [%context ~]
      =/  cfg=bot-config:claw  (get-bot bots default-bot)
      =/  j=json
        %-  pairs:enjs:format
        %+  turn  ~(tap by context.cfg)
        |=  [k=@tas v=@t]
        [(scot %tas k) s+v]
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
        [%context @ ~]
      =/  cfg=bot-config:claw  (get-bot bots default-bot)
      =/  field=@tas  i.t.api-path
      =/  val=(unit @t)  (~(get by context.cfg) field)
      =/  j=json  ?~(val ~ s+u.val)
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
        [%history ~]
      =/  j=json
        (fall (mole |.(.^(json %gx /(scot %p our.bowl)/lcm/(scot %da now.bowl)/assemble/'direct'/(scot %ud 999.999)/json))) a+~)
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
        [%dm-history @ ~]
      =/  who=ship  (slav %p i.t.api-path)
      =/  key=@t  (rap 3 'dm/' (scot %p who) ~)
      =/  j=json
        (fall (mole |.(.^(json %gx /(scot %p our.bowl)/lcm/(scot %da now.bowl)/assemble/[key]/(scot %ud 999.999)/json))) a+~)
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
        [%prompt ~]
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html s+(build-bot-prompt bowl default-bot (get-bot bots default-bot) bots owner-last-msg)))]
    ::
        [%cron-jobs ~]
      =/  cfg=bot-config:claw  (get-bot bots default-bot)
      =/  j=json
        :-  %a
        %+  turn  ~(tap by cron-jobs.cfg)
        |=  [cid=@ud job=cron-job:claw]
        %-  pairs:enjs:format
        :~  ['id' (numb:enjs:format id.job)]
            ['schedule' s+schedule.job]
            ['prompt' s+prompt.job]
            ['active' b+active.job]
            ['version' (numb:enjs:format version.job)]
            ['created' s+(scot %da created.job)]
        ==
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
        [%channel-perms ~]
      =/  cfg=bot-config:claw  (get-bot bots default-bot)
      =/  j=json
        %-  pairs:enjs:format
        %+  turn  ~(tap by channel-perms.cfg)
        |=  [ch=@t perm=channel-perm:claw]
        [ch s+?:(=(perm %open) 'open' 'whitelist')]
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
    ==
  ::
      %claw-action
  ?>  =(src our):bowl
  =/  act=action:claw  !<(action:claw vase)
  ?-  -.act
      %set-key
    %-  (slog leaf+"claw: api key set" ~)
    :_  this(api-key key.act)
    :~  (lcm-sync-config bowl key.act model)
    ==
  ::
      %set-model
    ?:  =('' model.act)
      %-  (slog leaf+"claw: ignoring empty model" ~)
      `this
    %-  (slog leaf+"claw: model set to {(trip model.act)}" ~)
    ::  fetch model info from OpenRouter to get context window
    :_  this(model model.act)
    =/  sync-card=card  (lcm-sync-config bowl api-key model.act)
    ::  fetch model list from OpenRouter if we have an api key
    ?:  =('' api-key)  [sync-card]~
    =/  hed=(list [key=@t value=@t])
      :~  ['Authorization' (crip "Bearer {(trip api-key)}")]
      ==
    :~  sync-card
        [%pass /model-info/(scot %da now.bowl) %arvo %i %request [%'GET' 'https://openrouter.ai/api/v1/models' hed ~] *outbound-config:iris]
    ==
  ::
      %set-brave-key
    %-  (slog leaf+"claw: brave api key set" ~)
    `this(brave-key key.act)
  ::
      %set-context
    %-  (slog leaf+"claw: context '{(trip field.act)}' set" ~)
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =.  bots  (~(put by bots) default-bot cfg(context (~(put by context.cfg) field.act content.act)))
    `this
  ::
      %append-context
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =/  existing=@t  (fall (~(get by context.cfg) field.act) '')
    =/  new=@t
      ?:  =('' existing)  content.act
      (rap 3 existing '\0a' content.act ~)
    %-  (slog leaf+"claw: context '{(trip field.act)}' appended" ~)
    =.  bots  (~(put by bots) default-bot cfg(context (~(put by context.cfg) field.act new)))
    `this
  ::
      %del-context
    %-  (slog leaf+"claw: context '{(trip field.act)}' deleted" ~)
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =.  bots  (~(put by bots) default-bot cfg(context (~(del by context.cfg) field.act)))
    `this
  ::
      %clear
    %-  (slog leaf+"claw: cleared (history + stuck state)" ~)
    =.  tool-loops  ~
    =.  dm-pending  ~
    =.  pending  %.n
    :_  this(pending %.n)
    :~  [%pass /lcm-clear %agent [our.bowl %lcm] %poke %lcm-action !>(`lcm-action:lcm`[%clear 'direct'])]
    ==
  ::
      %add-ship
    %-  (slog leaf+"claw: added {(scow %p ship.act)} as {(trip ?:(=(%owner role.act) 'owner' 'allowed'))}" ~)
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =.  bots  (~(put by bots) default-bot cfg(whitelist (~(put by whitelist.cfg) ship.act role.act)))
    :_  this
    ::  skip DM watch for our own ship (handled by self-DM v3 sub)
    ?:  =(ship.act our.bowl)
      :~  [%pass /dm-rsvp/(scot %p ship.act) %agent [our.bowl %chat] %poke %chat-dm-rsvp !>([ship.act %.y])]
      ==
    :~  [%pass /dm-rsvp/(scot %p ship.act) %agent [our.bowl %chat] %poke %chat-dm-rsvp !>([ship.act %.y])]
        ::  leave first to avoid duplicate wire error
        [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %leave ~]
        [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %watch /dm/(scot %p ship.act)]
    ==
  ::
      %del-ship
    %-  (slog leaf+"claw: removed {(scow %p ship.act)}" ~)
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =.  bots  (~(put by bots) default-bot cfg(whitelist (~(del by whitelist.cfg) ship.act)))
    ::  dm-history managed by lcm
    =.  dm-pending  (~(del in dm-pending) [default-bot ship.act])
    :_  this
    :~  [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %leave ~]
    ==
  ::
      %set-channel-perm
    %-  (slog leaf+"claw: channel '{(trip channel.act)}' set to {<perm.act>}" ~)
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =.  bots  (~(put by bots) default-bot cfg(channel-perms (~(put by channel-perms.cfg) channel.act perm.act)))
    `this
  ::
      %approve
    %-  (slog leaf+"claw: approved {(scow %p ship.act)}" ~)
    =.  pending-approvals  (~(del by pending-approvals) ship.act)
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =.  bots  (~(put by bots) default-bot cfg(whitelist (~(put by whitelist.cfg) ship.act %allowed)))
    :_  this
    ::  skip DM watch for our own ship (handled by self-DM v3 sub)
    ?:  =(ship.act our.bowl)
      :~  (send-dm-card bowl ship.act 'Your access has been approved. You can now talk to me!' bot-name.cfg bot-avatar.cfg)
      ==
    :~  [%pass /dm-rsvp/(scot %p ship.act) %agent [our.bowl %chat] %poke %chat-dm-rsvp !>([ship.act %.y])]
        [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %leave ~]
        [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %watch /dm/(scot %p ship.act)]
        (send-dm-card bowl ship.act 'Your access has been approved. You can now talk to me!' bot-name.cfg bot-avatar.cfg)
    ==
  ::
      %deny
    %-  (slog leaf+"claw: denied {(scow %p ship.act)}" ~)
    `this(pending-approvals (~(del by pending-approvals) ship.act))
  ::
      %cron-add
    %-  (slog leaf+"claw: cron-add schedule='{(trip schedule.act)}'" ~)
    =/  nxt=(unit @da)  (next-cron-fire schedule.act now.bowl)
    ?~  nxt
      %-  (slog leaf+"claw: cron-add failed - invalid schedule or no match in next year" ~)
      `this
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =/  cid=@ud  next-cron-id.cfg
    =/  job=cron-job:claw  [cid schedule.act prompt.act %.y 0 now.bowl]
    =.  bots  (~(put by bots) default-bot cfg(cron-jobs (~(put by cron-jobs.cfg) cid job), next-cron-id +(cid)))
    :_  this
    :~  [%pass /cron/(scot %ud cid)/(scot %ud 0) %arvo %b %wait u.nxt]
    ==
  ::
      %cron-remove
    %-  (slog leaf+"claw: cron-remove {(a-co:co cron-id.act)}" ~)
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =.  bots  (~(put by bots) default-bot cfg(cron-jobs (~(del by cron-jobs.cfg) cron-id.act)))
    `this
  ::
      %set-bot-name
    %-  (slog leaf+"claw: bot name set to {<name.act>}" ~)
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =.  bots  (~(put by bots) default-bot cfg(bot-name name.act))
    `this
  ::
      %set-bot-avatar
    %-  (slog leaf+"claw: bot avatar set to {<avatar.act>}" ~)
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =.  bots  (~(put by bots) default-bot cfg(bot-avatar avatar.act))
    `this
  ::
      %prompt
    ?:  pending  ~|(%claw-busy !!)
    ?:  =('' api-key)  ~|(%claw-no-api-key !!)
    =/  new-msg=msg:claw  ['user' content.act]
    =.  pending  %.y
    =/  sys-prompt=@t  (build-bot-prompt bowl default-bot (get-bot bots default-bot) bots owner-last-msg)
    %-  (slog leaf+"claw: sending prompt..." ~)
    :_  this
    :~  (lcm-ingest bowl 'direct' 'user' content.act)
        (make-llm-request bowl api-key model sys-prompt 'direct' /query ~ `new-msg)
    ==
  ::
  ::  bot management actions
  ::
      %add-bot
    %-  (slog leaf+"claw: add-bot {(trip id.act)}" ~)
    ?:  (~(has by bots) id.act)
      ~|(%claw-bot-exists !!)
    ::  auto-generate bot name: "<ship>'s bot #N"
    =/  bot-num=@ud  ~(wyt by bots)
    =/  auto-name=@t  (crip "{(scow %p our.bowl)}'s bot #{(a-co:co +(bot-num))}")
    ::  check name uniqueness
    =/  names-taken=(set @t)
      %-  ~(gas in *(set @t))
      %+  murn  ~(val by bots)
      |=(c=bot-config:claw bot-name.c)
    =?  auto-name  (~(has in names-taken) auto-name)
      (crip "{(trip auto-name)}-{(trip (scot %tas id.act))}")
    =/  cfg=bot-config:claw  [`auto-name ~ ~ ~ ~ ~ ~ ~ ~ 0]
    =.  bots  (~(put by bots) id.act cfg)
    %-  (slog leaf+"claw: bot {(trip id.act)} created with name '{(trip auto-name)}'" ~)
    `this
  ::
      %del-bot
    %-  (slog leaf+"claw: del-bot {(trip id.act)}" ~)
    ?:  =(id.act default-bot)
      ~|(%claw-cannot-delete-default !!)
    =.  bots  (~(del by bots) id.act)
    `this
  ::
      %set-default-bot
    %-  (slog leaf+"claw: set-default-bot {(trip id.act)}" ~)
    ?.  (~(has by bots) id.act)
      ~|(%claw-bot-not-found !!)
    `this(default-bot id.act)
  ::
      %bot-set-name
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    ::  validate: name required, at least one letter
    ?~  name.act  ~|(%claw-bot-name-required !!)
    ?:  =('' u.name.act)  ~|(%claw-bot-name-empty !!)
    ::  check uniqueness across bots
    =/  names-taken=(set @t)
      %-  ~(gas in *(set @t))
      %+  murn  ~(tap by bots)
      |=  [bid=@tas c=bot-config:claw]
      ?:  =(bid id.act)  ~
      bot-name.c
    ?:  (~(has in names-taken) u.name.act)  ~|(%claw-bot-name-duplicate !!)
    %-  (slog leaf+"claw: bot {(trip id.act)} name set to '{(trip u.name.act)}'" ~)
    =.  bots  (~(put by bots) id.act cfg(bot-name name.act))
    `this
  ::
      %bot-set-avatar
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =.  bots  (~(put by bots) id.act cfg(bot-avatar avatar.act))
    `this
  ::
      %bot-set-model
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =.  bots  (~(put by bots) id.act cfg(model model.act))
    `this
  ::
      %bot-set-key
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =.  bots  (~(put by bots) id.act cfg(api-key key.act))
    `this
  ::
      %bot-set-brave-key
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =.  bots  (~(put by bots) id.act cfg(brave-key key.act))
    `this
  ::
      %bot-set-context
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =.  bots  (~(put by bots) id.act cfg(context (~(put by context.cfg) field.act content.act)))
    `this
  ::
      %bot-append-context
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =/  existing=@t  (fall (~(get by context.cfg) field.act) '')
    =/  new=@t
      ?:  =('' existing)  content.act
      (rap 3 existing '\0a' content.act ~)
    =.  bots  (~(put by bots) id.act cfg(context (~(put by context.cfg) field.act new)))
    `this
  ::
      %bot-del-context
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =.  bots  (~(put by bots) id.act cfg(context (~(del by context.cfg) field.act)))
    `this
  ::
      %bot-add-ship
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =.  bots  (~(put by bots) id.act cfg(whitelist (~(put by whitelist.cfg) ship.act role.act)))
    `this
  ::
      %bot-del-ship
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =.  bots  (~(put by bots) id.act cfg(whitelist (~(del by whitelist.cfg) ship.act)))
    `this
  ::
      %bot-set-channel-perm
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =.  bots  (~(put by bots) id.act cfg(channel-perms (~(put by channel-perms.cfg) channel.act perm.act)))
    `this
  ::
      %bot-cron-add
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =/  nxt=(unit @da)  (next-cron-fire schedule.act now.bowl)
    ?~  nxt  `this
    =/  cid=@ud  next-cron-id.cfg
    =/  job=cron-job:claw  [cid schedule.act prompt.act %.y 0 now.bowl]
    =.  bots  (~(put by bots) id.act cfg(cron-jobs (~(put by cron-jobs.cfg) cid job), next-cron-id +(cid)))
    :_  this
    :~  [%pass /cron/(scot %ud cid)/(scot %ud 0) %arvo %b %wait u.nxt]
    ==
  ::
      %bot-cron-remove
    =/  cfg=bot-config:claw  (get-bot bots id.act)
    =.  bots  (~(put by bots) id.act cfg(cron-jobs (~(del by cron-jobs.cfg) cron-id.act)))
    `this
  ==
  ==
::
++  on-watch
  |=  =path
  ^-  (quip card _this)
  ?+  path  (on-watch:def path)
      [%updates ~]  ?>  =(src our):bowl  `this
      [%http-response *]  `this
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
      (fall (mole |.(.^(json %gx /(scot %p our.bowl)/lcm/(scot %da now.bowl)/assemble/'direct'/(scot %ud 999.999)/json))) a+~)
    ``json+!>(j)
      [%x %last ~]
    ``json+!>(s+'use /history for conversation data')
      [%x %config ~]
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =/  j=json
      %-  pairs:enjs:format
      :~  ['model' s+model]  ['pending' b+pending]  ['last-error' s+last-error]
          ['api-key' s+api-key]
          ['brave-key' s+brave-key]
          :-  'whitelist'
          %-  pairs:enjs:format
          %+  turn  ~(tap by whitelist.cfg)
          |=  [s=ship r=ship-role:claw]
          [(scot %p s) s+?:(=(r %owner) 'owner' 'allowed')]
          :-  'pending-approvals'
          %-  pairs:enjs:format
          %+  turn  ~(tap by pending-approvals)
          |=  [s=ship reason=@t]
          [(scot %p s) s+reason]
          ['bot-name' s+(fall bot-name.cfg '')]
          ['bot-avatar' s+(fall bot-avatar.cfg '')]
      ==
    ``json+!>(j)
      [%x %context @ ~]
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =/  field=@tas  (slav %tas i.t.t.path)
    =/  val=(unit @t)  (~(get by context.cfg) field)
    ?~  val  ``json+!>(~)
    ``json+!>(s+u.val)
      [%x %context ~]
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    %-  some  %-  some
    json+!>((pairs:enjs:format (turn ~(tap by context.cfg) |=([k=@tas v=@t] [(scot %tas k) s+v]))))
      [%x %prompt ~]
    ``json+!>(s+(build-bot-prompt bowl default-bot (get-bot bots default-bot) bots owner-last-msg))
      [%x %cron-jobs ~]
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =/  j=json
      :-  %a
      %+  turn  ~(tap by cron-jobs.cfg)
      |=  [cid=@ud job=cron-job:claw]
      %-  pairs:enjs:format
      :~  ['id' (numb:enjs:format id.job)]
          ['schedule' s+schedule.job]
          ['prompt' s+prompt.job]
          ['active' b+active.job]
          ['version' (numb:enjs:format version.job)]
          ['created' s+(scot %da created.job)]
      ==
    ``json+!>(j)
      [%x %dm-history @ ~]
    =/  who=ship  (slav %p i.t.t.path)
    =/  key=@t  (rap 3 'dm/' (scot %p who) ~)
    =/  j=json
      (fall (mole |.(.^(json %gx /(scot %p our.bowl)/lcm/(scot %da now.bowl)/assemble/[key]/(scot %ud 999.999)/json))) a+~)
    ``json+!>(j)
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
      ::  re-subscribe: use v3 for self-DM, unversioned for others
      ?:  =(who our.bowl)
        :~  [%pass /dm-watch/(scot %p who) %agent [our.bowl %chat] %watch /dm/(scot %p who)]
        ==
      :~  [%pass /dm-watch/(scot %p who) %agent [our.bowl %chat] %watch /dm/(scot %p who)]
      ==
        %fact
      ::  extract the response from the vase
      ::  the fact is a writ-response: [whom id response-delta]
      ::
      =/  noun  +.q.cage.sign
      ?.  ?=([* * [%add *]] noun)  `this
      =/  response-delta  +.+.noun
      ::  extract message-id time from noun: [whom [id delta]]
      ::  id = [ship time], so time = +.-.+.noun
      =/  msg-time=@da  ;;(@da +.-.+.noun)
      ::  [%add memo time] where memo = [content author sent]
      =/  memo-noun  -.+.response-delta
      =/  content-noun  -.memo-noun
      =/  author-noun  -.+.memo-noun
      =/  from=ship
        ?@  author-noun  ;;(@p author-noun)
        ;;(@p -.author-noun)
      ::  regular DM: skip messages from our own ship
      ?:  &(!=(who our.bowl) =(from our.bowl))  `this
      ::  self-DM: skip messages we sent (matched by message-id time)
      =/  self-key=@t  (rap 3 'sds/' (scot %da msg-time) ~)
      ?:  &(=(who our.bowl) (~(has in seen-msgs) self-key))
        =.  seen-msgs  (~(del in seen-msgs) self-key)
        `this
      ::  check whitelist (self-DM owner is always allowed)
      =/  cfg=bot-config:claw  (get-bot bots default-bot)
      ?.  |(=(who our.bowl) (~(has by whitelist.cfg) from))
        %-  (slog leaf+"claw: ignoring dm from {(scow %p from)}" ~)
        `this
      ::  extract text from story content
      =/  text=@t  (story-to-text ;;(story:d content-noun))
      ?:  =('' text)  `this
      ::  dedup: use message-id time
      =/  evt-id=@t  (rap 3 'dmw/' (scot %p from) '/' (scot %da msg-time) ~)
      ?:  (~(has in seen-msgs) evt-id)  `this
      =.  seen-msgs  (~(put in seen-msgs) evt-id)
      =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
      ::  owner heartbeat tracking
      =/  dmw-role=(unit ship-role:claw)  (~(get by whitelist.cfg) from)
      =?  owner-last-msg  &(?=(^ dmw-role) =(u.dmw-role %owner))
        now.bowl
      ::  bot rate limiting: reset count (human DM received)
      =/  dmw-rl-key=@t  (rap 3 'dm/' (scot %p from) ~)
      =.  bot-counts  (~(put by bot-counts) [default-bot dmw-rl-key] 0)
      %-  (slog leaf+"claw: dm from {(scow %p from)}: {(trip text)}" ~)
      ::  check for slash commands
      =/  src=msg-source:claw  [%dm from]
      =/  slash-result  (handle-slash bowl text from src model pending api-key last-error whitelist.cfg context.cfg pending-approvals owner-last-msg bot-name.cfg bot-avatar.cfg)
      ?^  slash-result  [u.slash-result this]
      ::  send to llm, history managed by lcm
      =.  dm-pending  (~(put in dm-pending) [default-bot from])
      ?:  =('' api-key)
        =.  dm-pending  (~(del in dm-pending) [default-bot from])
        :_  this
        :~  (send-dm-card bowl from 'Sorry, I don\'t have an API key configured yet. My owner needs to set one up.' bot-name.cfg bot-avatar.cfg)
        ==
      =/  base-prompt=@t  (build-bot-prompt bowl default-bot cfg bots owner-last-msg)
      =/  sys-prompt=@t
        ?:  =(who our.bowl)
          ::  self-DM: owner is talking directly to the bot
          (rap 3 base-prompt '\0a\0a---\0a\0a# Current Conversation\0a\0aYour owner is talking to you directly via self-DM. Respond naturally. Your responses will appear in the same DM conversation.' ~)
        ::  regular DM: inject sender context
        =/  nick=@t  (get-nickname bowl from)
        =/  nick-str=@t
          ?:(=('' nick) '' (rap 3 ' (nickname: ' nick ')' ~))
        (rap 3 base-prompt '\0a\0a---\0a\0a# Current Conversation\0a\0aYou are in a DM conversation with ' (scot %p from) nick-str '. When they ask you to send them something, use ship=' (scot %p from) ' in the send_dm tool.' ~)
      =/  eff-lcm-key=@t  (effective-lcm-key default-bot src)
      :_  this
      :~  (lcm-ingest bowl eff-lcm-key 'user' text)
          (make-llm-request bowl api-key model sys-prompt eff-lcm-key /dm-query/(scot %tas default-bot)/(scot %p from)/(scot %da now.bowl) ~ `['user' text])
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
  ::
  ::  activity stream: mentions, group invites
  ::
      [%activity ~]
    ?+  -.sign  `this
        %watch-ack
      ?~  p.sign
        %-  (slog leaf+"claw: subscribed to activity" ~)
        `this
      %-  (slog leaf+"claw: activity subscription failed" ~)
      `this
        %kick
      :_  this
      :~  [%pass /activity %agent [our.bowl %activity] %watch /v4]
      ==
        %fact
      ::  use typed extraction via !< with activity types
      =/  result=(unit (quip card _this))
        %-  mole  |.
        =/  upd=update:a  !<(update:a q.cage.sign)
        ?.  ?=(%add -.upd)  `this
        =/  incoming=incoming-event:a  -.event.upd
        %-  (slog leaf+"claw: activity event {<-.incoming>}" ~)
        ?+  -.incoming  `this
      ::
          %group-invite
        =/  from=ship  ship.incoming
        =/  cfg=bot-config:claw  (get-bot bots default-bot)
        ?.  (~(has by whitelist.cfg) from)
          %-  (slog leaf+"claw: ignoring group invite from {(scow %p from)}" ~)
          `this
        %-  (slog leaf+"claw: accepting group invite from {(scow %p from)}" ~)
        :_  this
        :~  [%pass /group-join %agent [our.bowl %groups] %poke %group-join !>([group.incoming %.y])]
        ==
      ::
          %post
        =/  from=ship  p.id.key.incoming
        ?:  =(from our.bowl)  `this
        ::  find ALL bots tagged in this message
        =/  tagged=(list @tas)  (find-tagged-bots bots content.incoming)
        ?~  tagged  `this
        =/  text=@t  (story-to-text content.incoming)
        ?:  =('' text)  `this
        ::  dedup
        =/  evt-id=@t  (rap 3 'post/' (scot %p from) '/' (scot %da q.id.key.incoming) ~)
        ?:  (~(has in seen-msgs) evt-id)  `this
        =.  seen-msgs  (~(put in seen-msgs) evt-id)
        =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
        =/  =nest:d  channel.incoming
        =/  ch-key=@t  (rap 3 kind.nest '/' (scot %p ship.nest) '/' name.nest ~)
        =/  src=msg-source:claw  [%channel kind.nest ship.nest name.nest from]
        =/  msg-id=@t  (scot %da q.id.key.incoming)
        =/  ch-str=@t  ch-key
        %-  (slog leaf+"claw: mention from {(scow %p from)} in {(trip ch-str)}: {(trip text)}" ~)
        ::  fire each tagged bot independently
        =/  all-cards=(list card)  ~
        =/  remaining=(list @tas)  tagged
        |-
        ?~  remaining  [all-cards this]
        =/  bot-id=@tas  i.remaining
        =/  cfg=bot-config:claw  (get-bot bots bot-id)
        ::  check THIS bot's permissions
        =/  ch-perm=(unit channel-perm:claw)  (~(get by channel-perms.cfg) ch-key)
        ?.  ?|  (~(has by whitelist.cfg) from)
                &(?=(^ ch-perm) =(u.ch-perm %open))
            ==
          ::  approval workflow for this bot
          ?:  (~(has by pending-approvals) from)
            $(remaining t.remaining)
          =.  pending-approvals  (~(put by pending-approvals) from (rap 3 'bot-tagged in ' ch-key ~))
          =/  owner-cards=(list card)
            %+  murn  ~(tap by whitelist.cfg)
            |=  [s=ship r=ship-role:claw]
            ?.  =(r %owner)  ~
            `(send-dm-card bowl s (rap 3 'Access request from ' (scot %p from) ': bot-tagged in ' ch-key ~) bot-name.cfg bot-avatar.cfg)
          =.  all-cards  (weld all-cards owner-cards)
          $(remaining t.remaining)
        ::  rate limiting per bot
        =/  ch-bot-count=@ud  (~(gut by bot-counts) [bot-id ch-key] 0)
        ?:  (gth ch-bot-count 3)
          %-  (slog leaf+"claw: {(trip bot-id)} rate limited in {(trip ch-key)}" ~)
          $(remaining t.remaining)
        ::  track state for this bot
        =/  bot-part=(set @t)  (~(gut by participated) bot-id ~)
        =.  participated  (~(put by participated) bot-id (~(put in bot-part) ch-key))
        =.  pending-src  (~(put by pending-src) [bot-id from] src)
        =.  dm-pending  (~(put in dm-pending) [bot-id from])
        ::  resolve effective config
        =/  eff-key=@t  (bot-api-key cfg api-key)
        =/  eff-model=@t  (bot-model cfg model)
        ?:  =('' eff-key)
          =.  dm-pending  (~(del in dm-pending) [bot-id from])
          =.  all-cards  (snoc all-cards (send-reply-card bowl src 'Sorry, no API key configured.' bot-name.cfg bot-avatar.cfg))
          $(remaining t.remaining)
        =/  base-prompt=@t  (build-bot-prompt bowl bot-id cfg bots owner-last-msg)
        =/  nick=@t  (get-nickname bowl from)
        =/  nick-str=@t
          ?:(=('' nick) '' (rap 3 ' (nickname: ' nick ')' ~))
        =/  sys-prompt=@t
          %+  rap  3
          :~  base-prompt
              '\0a\0a---\0a\0a# Current Conversation\0a\0a'
              (scot %p from)  nick-str
              ' tagged you in channel '  ch-str
              '.\0aTheir message ID is: '  msg-id
              '\0aThe channel nest is: '  ch-str
              '\0aYour responses are automatically posted in that channel.'
              '\0aTo react to their message, use add_reaction with channel='
              ch-str  ' and msg_id='  msg-id
          ==
        =/  eff-lcm-key=@t  (effective-lcm-key bot-id src)
        =.  all-cards
          %+  weld  all-cards
          :~  (lcm-ingest bowl eff-lcm-key 'user' text)
              (make-llm-request bowl eff-key eff-model sys-prompt eff-lcm-key /dm-query/(scot %tas bot-id)/(scot %p from)/(scot %da now.bowl) ~ `['user' text])
          ==
        $(remaining t.remaining)
      ::
          %dm-post
        =/  from=ship  p.id.key.incoming
        ?:  =(from our.bowl)  `this
        ::  find bot by name in DM text, fall back to default
        =/  dm-text-raw=@t  (story-to-text content.incoming)
        =/  named=(list @tas)  (find-named-bots bots dm-text-raw)
        =/  bot-id=@tas  ?~(named default-bot i.named)
        =/  cfg=bot-config:claw  (get-bot bots bot-id)
        ?.  (~(has by whitelist.cfg) from)
          ::  approval workflow: notify owner of DM from unknown ship
          =/  dm-text=@t  (story-to-text content.incoming)
          ?:  =('' dm-text)  `this
          ?:  (~(has by pending-approvals) from)  `this
          %-  (slog leaf+"claw: access request via DM from {(scow %p from)}" ~)
          =/  reason=@t  (rap 3 'DM: ' (end 3^100 dm-text) ~)
          =.  pending-approvals  (~(put by pending-approvals) from reason)
          =/  owner-cards=(list card)
            %+  murn  ~(tap by whitelist.cfg)
            |=  [s=ship r=ship-role:claw]
            ?.  =(r %owner)  ~
            `(send-dm-card bowl s (rap 3 'Access request from ' (scot %p from) ': ' reason '\0a\0aUse /approve ' (scot %p from) ' or /deny ' (scot %p from) ~) bot-name.cfg bot-avatar.cfg)
          [owner-cards this]
        =/  text=@t  (story-to-text content.incoming)
        ?:  =('' text)  `this
        =/  evt-id=@t  (rap 3 'dmp/' (scot %p from) '/' (scot %da q.id.key.incoming) ~)
        ?:  (~(has in seen-msgs) evt-id)  `this
        =.  seen-msgs  (~(put in seen-msgs) evt-id)
        =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
        =/  dmp-role=(unit ship-role:claw)  (~(get by whitelist.cfg) from)
        =?  owner-last-msg  &(?=(^ dmp-role) =(u.dmp-role %owner))
          now.bowl
        =/  dmp-rl-key=@t  (rap 3 'dm/' (scot %p from) ~)
        =.  bot-counts  (~(put by bot-counts) [bot-id dmp-rl-key] 0)
        %-  (slog leaf+"claw: dm-post from {(scow %p from)} → bot {(trip bot-id)}: {(trip text)}" ~)
        =/  src=msg-source:claw  [%dm from]
        =/  slash-result  (handle-slash bowl text from src model pending api-key last-error whitelist.cfg context.cfg pending-approvals owner-last-msg bot-name.cfg bot-avatar.cfg)
        ?^  slash-result  [u.slash-result this]
        =.  dm-pending  (~(put in dm-pending) [bot-id from])
        =/  eff-key=@t  (bot-api-key cfg api-key)
        ?:  =('' eff-key)
          =.  dm-pending  (~(del in dm-pending) [bot-id from])
          :_  this
          :~  (send-dm-card bowl from 'Sorry, no API key configured.' bot-name.cfg bot-avatar.cfg)
          ==
        =/  eff-model=@t  (bot-model cfg model)
        =/  msg-id=@t  (scot %da q.id.key.incoming)
        =/  base-prompt=@t  (build-bot-prompt bowl default-bot cfg bots owner-last-msg)
        =/  nick=@t  (get-nickname bowl from)
        =/  nick-str=@t
          ?:(=('' nick) '' (rap 3 ' (nickname: ' nick ')' ~))
        =/  sys-prompt=@t
          %+  rap  3
          :~  base-prompt
              '\0a\0a---\0a\0a# Current Conversation\0a\0aYou are in a DM with '
              (scot %p from)
              nick-str
              '.\0aTheir message ID is: '
              msg-id
              '\0aYour text response is automatically sent as a DM reply.'
          ==
        =/  eff-lcm-key=@t  (effective-lcm-key bot-id src)
        :_  this
        :~  (lcm-ingest bowl eff-lcm-key 'user' text)
            (make-llm-request bowl eff-key eff-model sys-prompt eff-lcm-key /dm-query/(scot %tas bot-id)/(scot %p from)/(scot %da now.bowl) ~ `['user' text])
        ==
      ::
          %dm-reply
        =/  from=ship  p.id.key.incoming
        ?:  =(from our.bowl)  `this
        ::  route to bot by name in text, or default
        =/  reply-text=@t  (story-to-text content.incoming)
        =/  named=(list @tas)  (find-named-bots bots reply-text)
        =/  bot-id=@tas  ?~(named default-bot i.named)
        =/  cfg=bot-config:claw  (get-bot bots bot-id)
        ?.  (~(has by whitelist.cfg) from)  `this
        =/  text=@t  reply-text
        ?:  =('' text)  `this
        =/  pid=[p=@p q=@da]  [p.id.parent.incoming q.id.parent.incoming]
        =/  evt-id=@t  (rap 3 'dmr/' (scot %p from) '/' (scot %da q.id.key.incoming) ~)
        ?:  (~(has in seen-msgs) evt-id)  `this
        =.  seen-msgs  (~(put in seen-msgs) evt-id)
        =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
        =/  dmr-role=(unit ship-role:claw)  (~(get by whitelist.cfg) from)
        =?  owner-last-msg  &(?=(^ dmr-role) =(u.dmr-role %owner))
          now.bowl
        %-  (slog leaf+"claw: dm-reply from {(scow %p from)} → bot {(trip bot-id)} parent={<pid>}: {(trip text)}" ~)
        =/  src=msg-source:claw  [%dm-thread from pid]
        =/  slash-result  (handle-slash bowl text from src model pending api-key last-error whitelist.cfg context.cfg pending-approvals owner-last-msg bot-name.cfg bot-avatar.cfg)
        ?^  slash-result  [u.slash-result this]
        =.  dm-pending  (~(put in dm-pending) [bot-id from])
        =/  eff-key=@t  (bot-api-key cfg api-key)
        ?:  =('' eff-key)
          =.  dm-pending  (~(del in dm-pending) [bot-id from])
          :_  this
          :~  (send-dm-card bowl from 'Sorry, no API key configured.' bot-name.cfg bot-avatar.cfg)
          ==
        =/  eff-model=@t  (bot-model cfg model)
        =/  base-prompt=@t  (build-bot-prompt bowl default-bot cfg bots owner-last-msg)
        =/  nick=@t  (get-nickname bowl from)
        =/  nick-str=@t
          ?:(=('' nick) '' (rap 3 ' (nickname: ' nick ')' ~))
        =/  sys-prompt=@t
          %+  rap  3
          :~  base-prompt
              '\0a\0a---\0a\0a# Current Conversation\0a\0aYou are in a DM thread with '
              (scot %p from)
              nick-str
              '.\0aYour response will be posted in the same thread.'
          ==
        =/  eff-lcm-key=@t  (effective-lcm-key bot-id src)
        =.  pending-src  (~(put by pending-src) [bot-id from] src)
        :_  this
        :~  (lcm-ingest bowl eff-lcm-key 'user' text)
            (make-llm-request bowl eff-key eff-model sys-prompt eff-lcm-key /dm-query/(scot %tas bot-id)/(scot %p from)/(scot %da now.bowl) ~ `['user' text])
        ==
      ::
          %reply
        =/  parent-author=ship  p.id.parent.incoming
        =/  from=ship  p.id.key.incoming
        ?:  =(from our.bowl)  `this
        =/  =nest:d  channel.incoming
        =/  ch-key=@t  (rap 3 kind.nest '/' (scot %p ship.nest) '/' name.nest ~)
        =/  text=@t  (story-to-text content.incoming)
        ?:  =('' text)  `this
        =/  parent-time=@da  q.id.parent.incoming
        =/  thread-key=@t  (rap 3 'thread/' kind.nest '/' (scot %p ship.nest) '/' name.nest '/' (scot %da parent-time) ~)
        ::  dedup
        =/  evt-id=@t  (rap 3 'rpl/' (scot %p from) '/' (scot %da q.id.key.incoming) ~)
        ?:  (~(has in seen-msgs) evt-id)  `this
        =.  seen-msgs  (~(put in seen-msgs) evt-id)
        =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
        =/  src=msg-source:claw  [%thread kind.nest ship.nest name.nest parent-time from]
        ::  find bots that should respond: tagged, parent authored by bot, or participated
        =/  tagged=(list @tas)  (find-tagged-bots bots content.incoming)
        =/  extra-bots=(list @tas)
          %+  murn  ~(tap by bots)
          |=  [id=@tas cfg=bot-config:claw]
          =/  bot-part=(set @t)  (~(gut by participated) id ~)
          ?:  (~(has in bot-part) thread-key)  `id
          ?:  =(parent-author our.bowl)  `id
          ~
        =/  responding-set=(set @tas)
          (~(gas in *(set @tas)) (weld tagged extra-bots))
        =/  responding=(list @tas)  ~(tap in responding-set)
        ?~  responding  `this
        %-  (slog leaf+"claw: reply from {(scow %p from)} in thread {(trip (scot %p ship.nest))}/{(trip name.nest)}" ~)
        ::  fire each responding bot
        =/  all-cards=(list card)  ~
        =/  rsp-remaining=(list @tas)  responding
        |-
        ?~  rsp-remaining  [all-cards this]
        =/  bot-id=@tas  i.rsp-remaining
        =/  cfg=bot-config:claw  (get-bot bots bot-id)
        =/  ch-perm=(unit channel-perm:claw)  (~(get by channel-perms.cfg) ch-key)
        ?.  ?|  (~(has by whitelist.cfg) from)
                &(?=(^ ch-perm) =(u.ch-perm %open))
            ==
          $(rsp-remaining t.rsp-remaining)
        =/  thr-bot-count=@ud  (~(gut by bot-counts) [bot-id thread-key] 0)
        ?:  (gth thr-bot-count 3)
          $(rsp-remaining t.rsp-remaining)
        =/  bot-part=(set @t)  (~(gut by participated) bot-id ~)
        =.  participated  (~(put by participated) bot-id (~(put in bot-part) thread-key))
        =.  pending-src  (~(put by pending-src) [bot-id from] src)
        =.  dm-pending  (~(put in dm-pending) [bot-id from])
        =/  eff-key=@t  (bot-api-key cfg api-key)
        =/  eff-model=@t  (bot-model cfg model)
        ?:  =('' eff-key)
          =.  dm-pending  (~(del in dm-pending) [bot-id from])
          =.  all-cards  (snoc all-cards (send-reply-card bowl src 'Sorry, no API key configured.' bot-name.cfg bot-avatar.cfg))
          $(rsp-remaining t.rsp-remaining)
        =/  base-prompt=@t  (build-bot-prompt bowl bot-id cfg bots owner-last-msg)
        =/  nick=@t  (get-nickname bowl from)
        =/  nick-str=@t
          ?:(=('' nick) '' (rap 3 ' (nickname: ' nick ')' ~))
        =/  sys-prompt=@t
          %+  rap  3
          :~  base-prompt
              '\0a\0a---\0a\0a# Current Conversation\0a\0a'
              (scot %p from)  nick-str
              ' replied in a thread in channel '  ch-key
              '.\0aYour response will be posted in the same thread.'
          ==
        =/  eff-lcm-key=@t  (effective-lcm-key bot-id src)
        =.  all-cards
          %+  weld  all-cards
          :~  (lcm-ingest bowl eff-lcm-key 'user' text)
              (make-llm-request bowl eff-key eff-model sys-prompt eff-lcm-key /dm-query/(scot %tas bot-id)/(scot %p from)/(scot %da now.bowl) ~ `['user' text])
          ==
        $(rsp-remaining t.rsp-remaining)
      ==
      ?~  result
        %-  (slog leaf+"claw: activity parse failed (mole caught)" ~)
        `this
      u.result
    ==
  ::
      [%ch-send ~]
    ?+  -.sign  `this
        %poke-ack
      ?~  p.sign
        %-  (slog leaf+"claw: channel post sent" ~)
        `this
      %-  (slog leaf+"claw: channel post FAILED" ~)
      %-  (slog u.p.sign)
      `this
    ==
      [%group-join ~]
    ?+  -.sign  `this
        %poke-ack
      ?~  p.sign
        %-  (slog leaf+"claw: joined group" ~)
        `this
      %-  (slog leaf+"claw: group join failed" ~)
      `this
    ==
      [%slash-model ~]
    ?+  -.sign  `this
        %poke-ack  `this
    ==
      [%slash-perm ~]
    ?+  -.sign  `this
        %poke-ack  `this
    ==
      [%slash-approve ~]
    ?+  -.sign  `this
        %poke-ack  `this
    ==
      [%slash-deny ~]
    ?+  -.sign  `this
        %poke-ack  `this
    ==
  ==
::
++  on-arvo
  |=  [=wire sign=sign-arvo]
  ^-  (quip card _this)
  |^
  ?+  wire  (on-arvo:def wire sign)
  ::
      [%eyre %connect ~]
    `this
  ::
  ::  cron timer fired
  ::
      [%cron @ @ ~]
    ?.  ?=([%behn %wake *] sign)  `this
    =/  raw-id=@t  i.t.wire
    =/  raw-ver=@t  i.t.t.wire
    =/  cid=(unit @ud)  (slaw %ud raw-id)
    =/  ver=(unit @ud)  (slaw %ud raw-ver)
    ?~  cid  `this
    ?~  ver  `this
    =/  cfg=bot-config:claw  (get-bot bots default-bot)
    =/  job=(unit cron-job:claw)  (~(get by cron-jobs.cfg) u.cid)
    ?~  job  `this
    ::  ignore stale fires
    ?.  &(active.u.job =(u.ver version.u.job))  `this
    %-  (slog leaf+"claw: cron fire schedule='{(trip schedule.u.job)}'" ~)
    ::  process the prompt through the LLM
    ?:  =('' api-key)  `this
    =/  sys-prompt=@t  (build-bot-prompt bowl default-bot cfg bots owner-last-msg)
    ::  bump version and reschedule
    =/  next-ver=@ud  +(version.u.job)
    =.  bots  (~(put by bots) default-bot cfg(cron-jobs (~(put by cron-jobs.cfg) u.cid u.job(version next-ver))))
    ::  compute next fire time from cron schedule
    =/  nxt=(unit @da)  (next-cron-fire schedule.u.job now.bowl)
    ::  fire LLM request and re-arm timer
    :_  this
    =/  cards=(list card)
      :~  (lcm-ingest bowl 'direct' 'system' (rap 3 '[Scheduled: ' schedule.u.job '] ' prompt.u.job ~))
          (make-llm-request bowl api-key model sys-prompt 'direct' /cron-query ~ `['system' prompt.u.job])
      ==
    ?~  nxt  cards
    :_  cards
    [%pass /cron/(scot %ud u.cid)/(scot %ud next-ver) %arvo %b %wait u.nxt]
  ::
      [%cron-query ~]
    (handle-llm-response sign [%direct ~] ~)
  ::
  ::  model info response from OpenRouter
  ::
      [%model-info *]
    ?.  ?=([%iris %http-response *] sign)  `this
    =/  resp=client-response:iris  client-response.sign
    ?.  ?=(%finished -.resp)  `this
    ?.  =(200 status-code.response-header.resp)
      %-  (slog leaf+"claw: model info fetch failed" ~)
      `this
    ?~  full-file.resp  `this
    =/  body=@t  q.data.u.full-file.resp
    =/  jon=(unit json)  (de:json:html body)
    ?~  jon
      %-  (slog leaf+"claw: model info parse failed" ~)
      `this
    ::  search data array for our model
    =/  ctx-len=(unit @ud)
      %-  mole  |.
      =/  data=json  (~(got by (need (me u.jon))) 'data')
      ?.  ?=([%a *] data)  !!
      =/  items  p.data
      |-
      ?~  items  !!
      =/  item=(map @t json)  (need (me i.items))
      =/  mid=@t  (so:dejs:format (~(got by item) 'id'))
      ?.  =(mid model)  $(items t.items)
      (ni:dejs:format (~(got by item) 'context_length'))
    ?~  ctx-len
      %-  (slog leaf+"claw: model '{(trip model)}' not found in OpenRouter" ~)
      `this
    %-  (slog leaf+"claw: context window for {(trip model)}: {(a-co:co u.ctx-len)}" ~)
    =/  mi-cfg=bot-config:claw  (get-bot bots default-bot)
    =.  bots  (~(put by bots) default-bot mi-cfg(context (~(put by context.mi-cfg) %model-context-window (crip (a-co:co u.ctx-len)))))
    :_  this
    :~  [%pass /lcm-config %agent [our.bowl %lcm] %poke %lcm-action !>(`lcm-action:lcm`[%set-config [api-key model 75 16 20.000 1.200 2.000 8 4 u.ctx-len]])]
    ==
  ::
  ::  compaction response
  ::
  ::
      [%tool-http %local-mcp *]
    ?.  ?=([%khan %arow *] sign)  `this
    =/  tool-loop=(unit tool-pending:claw)  (~(get by tool-loops) default-bot)
    ?~  tool-loop
      %-  (slog leaf+"claw: khan response but no pending loop" ~)
      `this
    =/  tl=tool-pending:claw  u.tool-loop
    =/  tc-id=@t
      =/  found  (skim pending.tl |=([id=@t n=@t a=@t] =(n 'local_mcp')))
      ?~(found 'unknown' id.i.found)
    =/  result=@t
      ?:  ?=(%| -.p.sign)
        'error: MCP tool execution failed'
      ::  extract text from the result vase
      =/  res-noun  q.p.p.sign
      ::  try JSON first, then cord, then just describe it
      =/  as-json=(unit @t)  (mole |.((en:json:html ;;(json res-noun))))
      ?^  as-json  (crip (scag 6.000 (trip u.as-json)))
      =/  as-cord=(unit @t)  (mole |.(;;(@t res-noun)))
      ?^  as-cord  (crip (scag 4.000 (trip u.as-cord)))
      'MCP tool returned a result (non-text)'
    %-  (slog leaf+"claw: mcp tool done" ~)
    (finish-tool tl tc-id result)
  ::
      [%query ~]
    (handle-llm-response sign [%direct ~] ~)
  ::
      [%query-tools *]
    (handle-llm-response sign [%direct ~] ~)
  ::
      [%dm-query @ @ *]
    =/  bot-id=@tas  (slav %tas i.t.wire)
    =/  who=ship  (slav %p i.t.t.wire)
    =/  src=msg-source:claw  (fall (~(get by pending-src) [bot-id who]) [%dm who])
    (handle-llm-response sign src `who)
  ::
      [%dm-query-tools @ @ *]
    =/  bot-id=@tas  (slav %tas i.t.wire)
    =/  who=ship  (slav %p i.t.t.wire)
    =/  src=msg-source:claw  (fall (~(get by pending-src) [bot-id who]) [%dm who])
    (handle-llm-response sign src `who)
  ::
      [%tool @ ~]  `this  ::  tool poke-acks
  ::
  ::  async tool http response
  ::
      [%tool-http @ *]
    ?.  ?=([%iris %http-response *] sign)  `this
    =/  resp=client-response:iris  client-response.sign
    ?.  ?=(%finished -.resp)  `this
    =/  tool-loop=(unit tool-pending:claw)  (~(get by tool-loops) default-bot)
    ?~  tool-loop
      %-  (slog leaf+"claw: tool-http but no pending loop" ~)
      `this
    =/  tl=tool-pending:claw  u.tool-loop
    =/  tool-name=@t  i.t.wire
    ::  +finish-tool: complete a tool with result and continue loop
    ::  this ensures errors never leave the bot stuck
    ::
    ::  handle upload_image phase 1: image fetched, now PUT to S3
    ?:  =('upload_image' tool-name)
      =/  tc-id=@t
        =/  found  (skim pending.tl |=([id=@t n=@t a=@t] =(n 'upload_image')))
        ?~(found 'unknown' id.i.found)
      ?.  =(200 status-code.response-header.resp)
        %-  (slog leaf+"claw: image fetch failed {<status-code.response-header.resp>}" ~)
        (finish-tool tl tc-id 'error: could not fetch image from that URL')
      ?~  full-file.resp
        (finish-tool tl tc-id 'error: empty image response')
      ::  extract content-type
      =/  ct=@t
        =/  ct-hdr  (skim headers.response-header.resp |=([k=@t v=@t] =(k 'content-type')))
        ?~(ct-hdr 'image/jpeg' value.i.ct-hdr)
      ::  sign and fire S3 PUT
      =/  s3-result  (make-s3-put:tools bowl data.u.full-file.resp ct)
      ?~  s3-result
        %-  (slog leaf+"claw: s3 signing failed" ~)
        (finish-tool tl tc-id 'error: S3 credentials not configured')
      ::  fire S3 PUT - phase 2, store URL for later
      =.  tool-loops  (~(put by tool-loops) default-bot tl(follow-msgs (snoc follow-msgs.tl s+url.u.s3-result)))
      :_  this
      [card.u.s3-result]~
    ::
    ::  handle upload_put phase 2: S3 PUT completed
    ?:  =('upload_put' tool-name)
      =/  tc-id=@t
        =/  found  (skim pending.tl |=([id=@t n=@t a=@t] =(n 'upload_image')))
        ?~(found 'unknown' id.i.found)
      =/  s3-ok=?  (lth status-code.response-header.resp 300)
      %-  (slog leaf+"claw: s3 put status={<status-code.response-header.resp>}" ~)
      ?.  s3-ok
        =/  err-body=@t  ?~(full-file.resp '' (crip (scag 200 (trip q.data.u.full-file.resp))))
        %-  (slog leaf+"claw: s3 error: {(trip err-body)}" ~)
        (finish-tool tl tc-id 'error: S3 upload failed')
      ::  get stored URL from follow-msgs (last entry is s+url from phase 1)
      =/  stored-url=@t
        =/  last  (rear follow-msgs.tl)
        ?:  ?=([%s *] last)  p.last
        'upload complete'
      ::  remove stored URL marker from follow-msgs
      =.  follow-msgs.tl  (snip follow-msgs.tl)
      %-  (slog leaf+"claw: s3 uploaded: {(trip stored-url)}" ~)
      (finish-tool tl tc-id stored-url)
    ::
    %-  (slog leaf+"claw: tool-http status={<status-code.response-header.resp>}" ~)
    =/  raw-body=@t
      ?~  full-file.resp  ''
      q.data.u.full-file.resp
    %-  (slog leaf+"claw: tool-http body[0:200]={<(crip (scag 200 (trip raw-body)))>}" ~)
    =/  body=@t
      ?~  full-file.resp  'error: empty response'
      ?.  =(200 status-code.response-header.resp)
        ::  include error body so LLM and logs can see what went wrong
        (rap 3 'error: http ' (scot %ud status-code.response-header.resp) ' - ' (crip (scag 500 (trip raw-body))) ~)
      raw-body
    =/  result=@t  (parse-tool-response:tools tool-name body)
    %-  (slog leaf+"claw: tool {(trip tool-name)} done" ~)
    ::  take the first pending tool (we execute sequentially)
    =/  tc-id=@t
      ?~  pending.tl  'unknown'
      id.i.pending.tl
    =/  new-fmsgs=(list json)  (snoc follow-msgs.tl (tool-result-json tc-id result))
    =/  rest=(list [id=@t name=@t arguments=@t])
      ^-  (list [@t @t @t])
      ?~  pending.tl  ~
      t.pending.tl
    ::  if more pending, fire next
    =/  th-cfg=bot-config:claw  (get-bot bots default-bot)
    ?^  rest
      =/  next  i.rest
      =/  tl-owner=?
        ?:  =(-.msg-source.tl %direct)  %.y
        =/  r=(unit ship-role:claw)  (~(get by whitelist.th-cfg) (src-ship msg-source.tl))
        &(?=(^ r) =(u.r %owner))
      =/  res=tool-result:tools
        =/  r=(each tool-result:tools tang)
          (mule |.((execute-tool:tools bowl name.next arguments.next brave-key tl-owner default-bot bot-name.th-cfg bot-avatar.th-cfg)))
        ?:(?=(%| -.r) [%sync ~ 'error: tool crashed'] p.r)
      ?.  ?=(%async -.res)
        =.  tool-loops  (~(put by tool-loops) default-bot [msg-source.tl conv-key.tl (snoc new-fmsgs (tool-result-json id.next 'done')) t.rest])
        `this
      =.  tool-loops  (~(put by tool-loops) default-bot [msg-source.tl conv-key.tl new-fmsgs t.rest])
      :_  this  [card.res]~
    ::  all done - fire llm follow-up
    =/  sys-prompt=@t  (build-bot-prompt bowl default-bot th-cfg bots owner-last-msg)
    =/  follow-wire=path
      ?:  =(-.msg-source.tl %direct)  /query-tools/(scot %da now.bowl)
      /dm-query-tools/(scot %p (src-ship msg-source.tl))/(scot %da now.bowl)
    :_  this(tool-loops (~(del by tool-loops) default-bot))
    :~  (make-llm-request bowl api-key model sys-prompt conv-key.tl follow-wire new-fmsgs ~)
    ==
  ==
::
::  +finish-tool: complete a tool call with result and continue the loop
::    ensures errors never leave the bot stuck
::
++  finish-tool
  |=  [tl=tool-pending:claw tc-id=@t result=@t]
  ^-  (quip card _this)
  =/  ft-cfg=bot-config:claw  (get-bot bots default-bot)
  =/  new-fmsgs=(list json)  (snoc follow-msgs.tl (tool-result-json tc-id result))
  ::  remove the completed tool (first in pending)
  =/  rest=(list [id=@t name=@t arguments=@t])
    ^-  (list [@t @t @t])
    ?~(pending.tl ~ t.pending.tl)
  ?^  rest
    ::  more pending tools - execute next
    =/  next  i.rest
    =/  tl-owner=?
      ?:  =(-.msg-source.tl %direct)  %.y
      =/  r=(unit ship-role:claw)  (~(get by whitelist.ft-cfg) (src-ship msg-source.tl))
      &(?=(^ r) =(u.r %owner))
    =/  res=tool-result:tools
      =/  r=(each tool-result:tools tang)
        (mule |.((execute-tool:tools bowl name.next arguments.next brave-key tl-owner default-bot bot-name.ft-cfg bot-avatar.ft-cfg)))
      ?:(?=(%| -.r) [%sync ~ 'error: tool crashed'] p.r)
    ?.  ?=(%async -.res)
      ::  sync - add result and recurse
      $(tl [msg-source.tl conv-key.tl (snoc new-fmsgs (tool-result-json id.next 'done')) t.rest])
    ::  keep 'next' as first in pending so khan handler finds its ID
    =.  tool-loops  (~(put by tool-loops) default-bot [msg-source.tl conv-key.tl new-fmsgs rest])
    :_  this  [card.res]~
  ::  all done - fire LLM follow-up
  =/  sys-prompt=@t  (build-bot-prompt bowl default-bot ft-cfg bots owner-last-msg)
  =/  follow-wire=path
    ?:  =(-.msg-source.tl %direct)  /query-tools/(scot %da now.bowl)
    /dm-query-tools/(scot %p (src-ship msg-source.tl))/(scot %da now.bowl)
  :_  this(tool-loops (~(del by tool-loops) default-bot))
  :~  (make-llm-request bowl api-key model sys-prompt conv-key.tl follow-wire new-fmsgs ~)
  ==
::
++  tool-result-json
  |=  [id=@t content=@t]
  ^-  json
  %-  pairs:enjs:format
  :~  ['role' s+'tool']
      ['tool_call_id' s+id]
      ['content' s+content]
  ==
::  +handle-llm-response: shared handler for llm responses
::    handles both text and tool-call responses
::
++  handle-llm-response
  |=  $:  sign=sign-arvo
          source=msg-source:claw
          dm-who=(unit ship)
      ==
  ^-  (quip card _this)
  =/  hlr-cfg=bot-config:claw  (get-bot bots default-bot)
  ?.  ?=([%iris %http-response *] sign)  `this
  =/  resp=client-response:iris  client-response.sign
  ?.  ?=(%finished -.resp)  `this
  =/  code=@ud  status-code.response-header.resp
  ::  error handling
  ?.  =(200 code)
    =/  err=@t  ?~(full-file.resp 'http error' q.data.u.full-file.resp)
    %-  (slog leaf+"claw error [{(a-co:co code)}]" ~)
    =.  last-error  err
    =?  pending  =(-.source %direct)  %.n
    =?  dm-pending  !=(-.source %direct)  (~(del in dm-pending) [default-bot (src-ship source)])
    ::  self-DM: record sent timestamp so returning fact is skipped
    =?  seen-msgs  &(!=(-.source %direct) =((src-ship source) our.bowl))
      (~(put in seen-msgs) (rap 3 'sds/' (scot %da now.bowl) ~))
    :_  this
    ?:  =(-.source %direct)
      :~  [%give %fact ~[/updates] %claw-update !>(`update:claw`[%error err])]  ==
    :~  (send-reply-card bowl source 'Sorry, I hit an error talking to the LLM provider.' bot-name.hlr-cfg bot-avatar.hlr-cfg)  ==
  ?~  full-file.resp
    =?  pending  =(-.source %direct)  %.n
    =?  dm-pending  !=(-.source %direct)  (~(del in dm-pending) [default-bot (src-ship source)])
    `this
  =/  body=@t  q.data.u.full-file.resp
  =/  is-owner=?
    ?:  =(-.source %direct)  %.y
    =/  who=ship  (src-ship source)
    =/  role=(unit ship-role:claw)  (~(get by whitelist.hlr-cfg) who)
    &(?=(^ role) =(u.role %owner))
  =/  parsed  (parse-llm-response body)
  ?~  parsed
    %-  (slog leaf+"claw error: parse failed" ~)
    =.  last-error  body
    =?  pending  =(-.source %direct)  %.n
    =?  dm-pending  !=(-.source %direct)  (~(del in dm-pending) [default-bot (src-ship source)])
    :_  this
    ?:  =(-.source %direct)  ~
    :~  (send-reply-card bowl source 'Sorry, I had trouble understanding the response from my LLM provider.' bot-name.hlr-cfg bot-avatar.hlr-cfg)  ==
  ::
  ?-  -.u.parsed
  ::
  ::  text response - deliver to user
  ::
      %text
    =/  content=@t  content.u.parsed
    =.  last-error  ''
    ?:  =(-.source %direct)
      =.  pending  %.n
      %-  (slog leaf+"< {(trip content)}" ~)
      :_  this
      :~  [%give %fact ~[/updates] %claw-update !>(`update:claw`[%response ['assistant' content]])]
          (lcm-ingest bowl 'direct' 'assistant' content)
      ==
    ::  non-direct response - send back to source
    %-  (slog leaf+"claw: response routing via {<-.source>}" ~)
    =/  who=ship
      ?-  -.source
        %dm         ship.source
        %dm-thread  ship.source
        %channel    ship.source
        %thread     ship.source
        %direct     our.bowl
      ==
    ::  assistant response ingested into lcm via card below
    =?  dm-pending  (~(has in dm-pending) [default-bot who])  (~(del in dm-pending) [default-bot who])
    =.  pending-src  (~(del by pending-src) [default-bot who])
    ::  track participated: mark channel/thread so we respond to follow-ups
    =/  hlr-part=(set @t)  (~(gut by participated) default-bot ~)
    =.  participated
      ?+  -.source  participated
        %channel  (~(put by participated) default-bot (~(put in hlr-part) (rap 3 kind.source '/' (scot %p host.source) '/' name.source ~)))
        %thread   (~(put by participated) default-bot (~(put in hlr-part) (lcm-key source)))
      ==
    ::  bot rate limiting: increment count for this conversation key
    =/  resp-rl-key=@t  (lcm-key source)
    =/  cur-bot-count=@ud  (~(gut by bot-counts) [default-bot resp-rl-key] 0)
    =.  bot-counts  (~(put by bot-counts) [default-bot resp-rl-key] +(cur-bot-count))
    %-  (slog leaf+"claw reply to {(scow %p who)} via {<-.source>}: {(trip (end 3^80 content))}" ~)
    ::  self-DM: record sent timestamp so returning fact is skipped
    =?  seen-msgs  =(who our.bowl)
      (~(put in seen-msgs) (rap 3 'sds/' (scot %da now.bowl) ~))
    =/  response-cards=(list card)
      :~  (send-reply-card bowl source content bot-name.hlr-cfg bot-avatar.hlr-cfg)
          [%give %fact ~[/updates] %claw-update !>(`update:claw`[%dm-response who ['assistant' content]])]
          (lcm-ingest bowl (lcm-key source) 'assistant' content)
      ==
    :_  this
    response-cards
  ::
  ::  tool call response - execute tools and loop back
  ::
      %tools
    %-  (slog leaf+"claw: executing {<(lent calls.u.parsed)>} tool call(s)" ~)
    ::  process tool calls: sync ones immediately, async ones queued
    =/  tool-cards=(list card)  ~
    ::  rebuild assistant message from parsed calls for clean round-trip
    =/  assistant-msg=json
      %-  pairs:enjs:format
      :~  ['role' s+'assistant']
          ['content' ?:(=('' content.u.parsed) ~ s+content.u.parsed)]
          :-  'tool_calls'
          :-  %a
          %+  turn  calls.u.parsed
          |=  [id=@t name=@t arguments=@t]
          %-  pairs:enjs:format
          :~  ['id' s+id]
              ['type' s+'function']
              :-  'function'
              %-  pairs:enjs:format
              :~  ['name' s+name]
                  ['arguments' s+arguments]
              ==
          ==
      ==
    =/  follow-msgs=(list json)  [assistant-msg]~
    =/  async-pending=(list [id=@t name=@t arguments=@t])  ~
    =/  remaining  calls.u.parsed
    |-
    ?~  remaining
      ::  if async tools pending, store state and fire first one
      ?^  async-pending
        =/  first  i.async-pending
        %-  (slog leaf+"claw: async tool {(trip name.first)}" ~)
        =/  res=tool-result:tools
          =/  r=(each tool-result:tools tang)
            (mule |.((execute-tool:tools bowl name.first arguments.first brave-key is-owner default-bot bot-name.hlr-cfg bot-avatar.hlr-cfg)))
          ?:(?=(%| -.r) [%sync ~ 'error: tool crashed'] p.r)
        ?.  ?=(%async -.res)
          ::  shouldn't happen, but handle gracefully
          $(async-pending t.async-pending, follow-msgs (snoc follow-msgs (tool-result-json id.first 'unexpected sync')))
        =.  tool-loops
          (~(put by tool-loops) default-bot [source (lcm-key source) follow-msgs async-pending])
        :_  this
        (weld (flop tool-cards) [card.res]~)
      ::  all sync - fire llm follow-up immediately
      =/  sys-prompt=@t  (build-bot-prompt bowl default-bot hlr-cfg bots owner-last-msg)
      =/  follow-wire=path
        ?:  =(-.source %direct)  /query-tools
        /dm-query-tools/(scot %p (src-ship source))
      :_  this
      %+  weld  (flop tool-cards)
      :~  (make-llm-request bowl api-key model sys-prompt (lcm-key source) follow-wire follow-msgs ~)
      ==
    ::  execute this tool
    =/  tc  i.remaining
    %-  (slog leaf+"claw: tool {(trip name.tc)}" ~)
    =/  res=tool-result:tools
      =/  r=(each tool-result:tools tang)
        (mule |.((execute-tool:tools bowl name.tc arguments.tc brave-key is-owner default-bot bot-name.hlr-cfg bot-avatar.hlr-cfg)))
      ?:(?=(%| -.r) [%sync ~ 'error: tool crashed'] p.r)
    ?:  ?=(%async -.res)
      ::  queue async tool for later
      %=  $
        remaining     t.remaining
        async-pending  (snoc async-pending tc)
      ==
    ::  sync tool - execute now
    %=  $
      remaining    t.remaining
      tool-cards   (weld cards.res tool-cards)
      follow-msgs  (snoc follow-msgs (tool-result-json id.tc result.res))
    ==
  ==
  --
::
++  on-fail  on-fail:def
--
