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
|%
+$  card  card:agent:gall
+$  versioned-state  $%(state-0:claw state-1:claw state-2:claw state-3:claw state-4:claw state-5:claw state-6:claw)
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
::  +send-dm-card: build a card to send a dm to a ship
::
::
::  +lcm-key: convert msg-source to lcm conversation key
::
++  lcm-key
  |=  =msg-source:claw
  ^-  @t
  ?-  -.msg-source
    %direct   'direct'
    %dm       (rap 3 'dm/' (scot %p ship.msg-source) ~)
    %channel  (rap 3 'channel/' kind.msg-source '/' (scot %p host.msg-source) '/' name.msg-source ~)
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
++  send-dm-card
  |=  [=bowl:gall to=ship text=@t]
  ^-  card
  =/  dm-story=story:d  ~[[%inline `(list inline:d)`~[text]]]
  =/  dm-memo=memo:d  [content=dm-story author=our.bowl sent=now.bowl]
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
    %dm       ship.msg-source
    %channel  ship.msg-source
    %direct   *ship
  ==
::
::  +get-nickname: scry %contacts for a ship's nickname
::
++  get-nickname
  |=  [=bowl:gall who=ship]
  ^-  @t
  =/  result=(each @t tang)
    %-  mule  |.
    =/  con=contact:ct
      .^(contact:ct %gx /(scot %p our.bowl)/contacts/(scot %da now.bowl)/v1/contact/(scot %p who)/contact-1)
    =/  nick=(unit value:ct)  (~(get by con) %nickname)
    ?~  nick  ''
    ?.  ?=([%text *] u.nick)  ''
    p.u.nick
  ?:(?=(%| -.result) '' p.result)
::
::  +send-reply-card: send a response based on message source
::
++  send-reply-card
  |=  [=bowl:gall =msg-source:claw text=@t]
  ^-  card
  ?-  -.msg-source
      %direct  [%pass /noop %arvo %b %wait (add now.bowl ~s1)]
      %dm      (send-dm-card bowl ship.msg-source text)
      %channel
    ::  post reply in channel using proper types
    =/  ch-story=story:d  ~[[%inline `(list inline:d)`~[text]]]
    =/  ch-memo=memo:d  [content=ch-story author=our.bowl sent=now.bowl]
    =/  ch-essay=essay:d  [ch-memo /chat ~ ~]
    =/  =nest:d  [kind.msg-source host.msg-source name.msg-source]
    =/  act=a-channels:d  [%channel nest [%post [%add ch-essay]]]
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
++  slash-help-text
  ^-  @t
  %-  crip
  ;:  weld
    "Available commands:\0a"
    "/model - show current model\0a"
    "/model <name> - set model (owner only)\0a"
    "/clear - clear conversation history\0a"
    "/status - show agent status\0a"
    "/help - show this help\0a"
    "\0aAvailable tools:\0a"
    "web_search, image_search, upload_image, send_dm,\0a"
    "send_channel_message, add_reaction, remove_reaction,\0a"
    "get_contact, list_groups, list_channels,\0a"
    "read_channel_history, http_fetch, update_profile,\0a"
    "join_group, leave_group, local_mcp, local_mcp_list"
  ==
::
++  handle-slash
  |=  $:  =bowl:gall  text=@t  from=ship  =msg-source:claw
          mod=@t  pend=?  api=@t  last-err=@t
          wl=(map ship ship-role:claw)
      ==
  ^-  (unit (list card))
  =/  txt=tape  (trip text)
  ?~  txt  ~
  ?.  =(i.txt '/')  ~
  ?:  =(txt "/help")
    `[(send-reply-card bowl msg-source slash-help-text)]~
  ?:  =(txt "/model")
    `[(send-reply-card bowl msg-source (rap 3 'Model: ' mod ~))]~
  ?:  &((gte (met 3 text) 8) =((end [3 7] text) '/model '))
      =/  new-model=@t  (rsh [3 7] text)
      =/  is-owner=?
        =/  role=(unit ship-role:claw)  (~(get by wl) from)
        &(?=(^ role) =(u.role %owner))
      ?.  is-owner
        `[(send-reply-card bowl msg-source 'Only owners can change the model.')]~
      %-  some
      :~  (send-reply-card bowl msg-source (rap 3 'Model set to: ' new-model ~))
          [%pass /slash-model %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%set-model new-model])]
      ==
  ?:  =(txt "/clear")
    =/  key=@t  (lcm-key msg-source)
    %-  some
    :~  (send-reply-card bowl msg-source 'Conversation cleared.')
        [%pass /lcm-clear %agent [our.bowl %lcm] %poke %lcm-action !>(`lcm-action:lcm`[%clear key])]
    ==
  ?:  =(txt "/status")
    =/  status=@t
      %-  crip
      ;:  weld
        "Model: {(trip mod)}\0a"
        "Pending: {?:(pend "yes" "no")}\0a"
        "Ships: {(a-co:co ~(wyt by wl))}\0a"
        "Error: {?:(=('' last-err) "none" (trip (end 3^100 last-err)))}"
      ==
    `[(send-reply-card bowl msg-source status)]~
  ~
--
::
%-  agent:dbug
=|  state-6:claw
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
          "When asked to find/send images, ALWAYS:\0a"
          "1. Call image_search with a descriptive query\0a"
          "2. Pick the best image URL from the results\0a"
          "3. Call send_dm with ship=<requester> and image_url=<url>\0a"
          "4. Respond confirming what you sent."
        ==
    ==
  :_  this(model 'anthropic/claude-sonnet-4', pending %.n, context default-ctx)
  :~  [%pass /eyre/connect %arvo %e %connect [`/apps/claw/api dap.bowl]]
      ::  subscribe to activity for mentions and group invites
      [%pass /activity %agent [our.bowl %activity] %watch /v4]
  ==
::
++  on-save  !>(state)
::
++  on-load
  |=  =vase
  ^-  (quip card _this)
  =/  old  !<(versioned-state vase)
  =/  new=state-6:claw
    ?-  -.old
        %6  old
        %5
      [%6 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~]
        %4
      [%6 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~]
        %3
      [%6 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~]
        %2
      [%6 api-key.old '' model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~]
        %1
      [%6 api-key.old '' model.old pending.old last-error.old context.old ~ ~ ~ ~]
        %0
      =/  ctx=(map @tas @t)  *(map @tas @t)
      =?  ctx  !=('' system-prompt.old)
        (~(put by ctx) %agent system-prompt.old)
      [%6 api-key.old '' model.old pending.old last-error.old ctx ~ ~ ~ ~]
    ==
  ::  re-establish subscriptions on every load
  =/  sub-cards=(list card)
    :~  [%pass /activity %agent [our.bowl %activity] %leave ~]
        [%pass /activity %agent [our.bowl %activity] %watch /v4]
    ==
  ::  re-subscribe to DMs for all whitelisted ships
  =/  dm-cards=(list card)
    %+  turn  ~(tap by whitelist.new)
    |=  [s=ship r=ship-role:claw]
    [%pass /dm-watch/(scot %p s) %agent [our.bowl %chat] %watch /dm/(scot %p s)]
  ::  sync config to lcm when migrating from older state
  =/  migrate-cards=(list card)
    ?.  =(-.old %6)
      :~  (lcm-sync-config bowl api-key.new model.new)
      ==
    ~
  :_  this(state new)
  :(weld sub-cards dm-cards migrate-cards)
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
        [%config ~]
      =/  j=json
        %-  pairs:enjs:format
        :~  ['model' s+model]
            ['pending' b+pending]
            ['last-error' s+last-error]
            :-  'whitelist'
            %-  pairs:enjs:format
            %+  turn  ~(tap by whitelist)
            |=  [s=ship r=ship-role:claw]
            [(scot %p s) s+?:(=(r %owner) 'owner' 'allowed')]
            :-  'context-keys'
            a+(turn ~(tap in ~(key by context)) |=(k=@tas s+(scot %tas k)))
        ==
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
        [%context ~]
      =/  j=json
        %-  pairs:enjs:format
        %+  turn  ~(tap by context)
        |=  [k=@tas v=@t]
        [(scot %tas k) s+v]
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
        [%context @ ~]
      =/  field=@tas  i.t.api-path
      =/  val=(unit @t)  (~(get by context) field)
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
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html s+(build-prompt bowl context)))]
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
    :_  this(pending %.n)
    :~  [%pass /lcm-clear %agent [our.bowl %lcm] %poke %lcm-action !>(`lcm-action:lcm`[%clear 'direct'])]
    ==
  ::
      %add-ship
    %-  (slog leaf+"claw: added {(scow %p ship.act)} as {(trip ?:(=(%owner role.act) 'owner' 'allowed'))}" ~)
    =.  whitelist  (~(put by whitelist) ship.act role.act)
    :_  this
    :~  [%pass /dm-rsvp/(scot %p ship.act) %agent [our.bowl %chat] %poke %chat-dm-rsvp !>([ship.act %.y])]
        ::  leave first to avoid duplicate wire error
        [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %leave ~]
        [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %watch /dm/(scot %p ship.act)]
    ==
  ::
      %del-ship
    %-  (slog leaf+"claw: removed {(scow %p ship.act)}" ~)
    =.  whitelist  (~(del by whitelist) ship.act)
    ::  dm-history managed by lcm
    =.  dm-pending  (~(del in dm-pending) ship.act)
    :_  this
    :~  [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %leave ~]
    ==
  ::
      %prompt
    ?:  pending  ~|(%claw-busy !!)
    ?:  =('' api-key)  ~|(%claw-no-api-key !!)
    =/  new-msg=msg:claw  ['user' content.act]
    =.  pending  %.y
    =/  sys-prompt=@t  (build-prompt bowl context)
    %-  (slog leaf+"claw: sending prompt..." ~)
    :_  this
    :~  (lcm-ingest bowl 'direct' 'user' content.act)
        (make-llm-request bowl api-key model sys-prompt 'direct' /query ~ `new-msg)
    ==
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
      ::  check for slash commands
      =/  src=msg-source:claw  [%dm from]
      =/  slash-result  (handle-slash bowl text from src model pending api-key last-error whitelist)
      ?^  slash-result  [u.slash-result this]
      ::  send to llm, history managed by lcm
      =.  dm-pending  (~(put in dm-pending) from)
      ?:  =('' api-key)
        =.  dm-pending  (~(del in dm-pending) from)
        :_  this
        :~  (send-dm-card bowl from 'Sorry, I don\'t have an API key configured yet. My owner needs to set one up.')
        ==
      =/  base-prompt=@t  (build-prompt bowl context)
      ::  inject sender context so LLM knows who it's talking to
      =/  nick=@t  (get-nickname bowl from)
      =/  nick-str=@t
        ?:(=('' nick) '' (rap 3 ' (nickname: ' nick ')' ~))
      =/  sys-prompt=@t
        (rap 3 base-prompt '\0a\0a---\0a\0a# Current Conversation\0a\0aYou are in a DM conversation with ' (scot %p from) nick-str '. When they ask you to send them something, use ship=' (scot %p from) ' in the send_dm tool.' ~)
      :_  this
      :~  (lcm-ingest bowl (lcm-key src) 'user' text)
          (make-llm-request bowl api-key model sys-prompt (lcm-key src) /dm-query/(scot %p from) ~ `['user' text])
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
        ?.  (~(has by whitelist) from)
          %-  (slog leaf+"claw: ignoring group invite from {(scow %p from)}" ~)
          `this
        %-  (slog leaf+"claw: accepting group invite from {(scow %p from)}" ~)
        :_  this
        :~  [%pass /group-join %agent [our.bowl %groups] %poke %group-join !>([group.incoming %.y])]
        ==
      ::
          %post
        ?.  mention.incoming  `this
        =/  from=ship  p.id.key.incoming
        ?:  =(from our.bowl)  `this
        ?.  (~(has by whitelist) from)  `this
        =/  text=@t  (story-to-text content.incoming)
        ?:  =('' text)  `this
        =/  =nest:d  channel.incoming
        %-  (slog leaf+"claw: mention from {(scow %p from)} in {(trip ;;(@t kind.nest))}/{(scow %p ship.nest)}/{(trip ;;(@t name.nest))}: {(trip text)}" ~)
        =/  src=msg-source:claw  [%channel kind.nest ship.nest name.nest from]
        ::  check for slash commands
        =/  slash-result  (handle-slash bowl text from src model pending api-key last-error whitelist)
        ?^  slash-result  [u.slash-result this]
        =.  pending-src  (~(put by pending-src) from src)
        =.  dm-pending  (~(put in dm-pending) from)
        ?:  =('' api-key)
          =.  dm-pending  (~(del in dm-pending) from)
          :_  this
          :~  (send-reply-card bowl src 'Sorry, no API key configured.')
          ==
        =/  msg-id=@t  (scot %da q.id.key.incoming)
        =/  ch-str=@t  (rap 3 kind.nest '/' (scot %p ship.nest) '/' name.nest ~)
        %-  (slog leaf+"claw: injecting context: msg_id={<msg-id>} channel={<ch-str>}" ~)
        =/  base-prompt=@t  (build-prompt bowl context)
        =/  nick=@t  (get-nickname bowl from)
        =/  nick-str=@t
          ?:(=('' nick) '' (rap 3 ' (nickname: ' nick ')' ~))
        =/  sys-prompt=@t
          %+  rap  3
          :~  base-prompt
              '\0a\0a---\0a\0a# Current Conversation\0a\0a'
              (scot %p from)
              nick-str
              ' mentioned you in channel '
              ch-str
              '.\0aTheir message ID is: '
              msg-id
              '\0aThe channel nest is: '
              ch-str
              '\0aYour responses are automatically posted in that channel.'
              '\0aTo react to their message, use add_reaction with channel='
              ch-str
              ' and msg_id='
              msg-id
          ==
        :_  this
        :~  (lcm-ingest bowl (lcm-key src) 'user' text)
            (make-llm-request bowl api-key model sys-prompt (lcm-key src) /dm-query/(scot %p from) ~ `['user' text])
        ==
      ::
          %dm-post
        =/  from=ship  p.id.key.incoming
        ?:  =(from our.bowl)  `this
        ?.  (~(has by whitelist) from)  `this
        =/  text=@t  (story-to-text content.incoming)
        ?:  =('' text)  `this
        ?:  (~(has in dm-pending) from)  `this
        %-  (slog leaf+"claw: dm-post from {(scow %p from)}: {(trip text)}" ~)
        =/  src=msg-source:claw  [%dm from]
        ::  check for slash commands
        =/  slash-result  (handle-slash bowl text from src model pending api-key last-error whitelist)
        ?^  slash-result  [u.slash-result this]
        =.  dm-pending  (~(put in dm-pending) from)
        ?:  =('' api-key)
          =.  dm-pending  (~(del in dm-pending) from)
          :_  this
          :~  (send-dm-card bowl from 'Sorry, no API key configured.')
          ==
        =/  msg-id=@t  (scot %da q.id.key.incoming)
        =/  base-prompt=@t  (build-prompt bowl context)
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
        :_  this
        :~  (lcm-ingest bowl (lcm-key src) 'user' text)
            (make-llm-request bowl api-key model sys-prompt (lcm-key src) /dm-query/(scot %p from) ~ `['user' text])
        ==
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
    ::  per-model endpoint returns single object with context_length
    =/  ctx-len=(unit @ud)
      %-  mole  |.
      =/  obj=(map @t json)  (need (me u.jon))
      (ni:dejs:format (~(got by obj) 'context_length'))
    ?~  ctx-len
      %-  (slog leaf+"claw: model not found in OpenRouter response" ~)
      `this
    %-  (slog leaf+"claw: model context window: {(a-co:co u.ctx-len)}" ~)
    :_  this
    :~  [%pass /lcm-config %agent [our.bowl %lcm] %poke %lcm-action !>(`lcm-action:lcm`[%set-config [api-key model 75 16 20.000 1.200 2.000 8 4 u.ctx-len]])]
    ==
  ::
  ::  compaction response
  ::
  ::
      [%tool-http %local-mcp ~]
    ?.  ?=([%khan %arow *] sign)  `this
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
      [%query-tools ~]
    (handle-llm-response sign [%direct ~] ~)
  ::
      [%dm-query @ ~]
    =/  who=ship  (slav %p i.t.wire)
    ::  use stored source (for channel responses) - DON'T delete yet
    ::  pending-src stays until final text response is sent
    =/  src=msg-source:claw  (fall (~(get by pending-src) who) [%dm who])
    (handle-llm-response sign src `who)
  ::
      [%dm-query-tools @ ~]
    =/  who=ship  (slav %p i.t.wire)
    =/  src=msg-source:claw  (fall (~(get by pending-src) who) [%dm who])
    (handle-llm-response sign src `who)
  ::
      [%tool @ ~]  `this  ::  tool poke-acks
  ::
  ::  async tool http response
  ::
      [%tool-http @ ~]
    ?.  ?=([%iris %http-response *] sign)  `this
    =/  resp=client-response:iris  client-response.sign
    ?.  ?=(%finished -.resp)  `this
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
      =.  tool-loop  `tl(follow-msgs (snoc follow-msgs.tl s+url.u.s3-result))
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
    ?^  rest
      =/  next  i.rest
      =/  tl-owner=?
        ?:  =(-.msg-source.tl %direct)  %.y
        =/  r=(unit ship-role:claw)  (~(get by whitelist) (src-ship msg-source.tl))
        &(?=(^ r) =(u.r %owner))
      =/  res=tool-result:tools
        (execute-tool:tools bowl name.next arguments.next brave-key tl-owner)
      ?.  ?=(%async -.res)
        =.  tool-loop  `[msg-source.tl conv-key.tl (snoc new-fmsgs (tool-result-json id.next 'done')) t.rest]
        `this
      =.  tool-loop  `[msg-source.tl conv-key.tl new-fmsgs t.rest]
      :_  this  [card.res]~
    ::  all done - fire llm follow-up
    =/  sys-prompt=@t  (build-prompt bowl context)
    =/  follow-wire=path
      ?:  =(-.msg-source.tl %direct)  /query-tools
      /dm-query-tools/(scot %p (src-ship msg-source.tl))
    :_  this(tool-loop ~)
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
      =/  r=(unit ship-role:claw)  (~(get by whitelist) (src-ship msg-source.tl))
      &(?=(^ r) =(u.r %owner))
    =/  res=tool-result:tools
      (execute-tool:tools bowl name.next arguments.next brave-key tl-owner)
    ?.  ?=(%async -.res)
      ::  sync - add result and recurse
      $(tl [msg-source.tl conv-key.tl (snoc new-fmsgs (tool-result-json id.next 'done')) t.rest])
    ::  keep 'next' as first in pending so khan handler finds its ID
    =.  tool-loop  `[msg-source.tl conv-key.tl new-fmsgs rest]
    :_  this  [card.res]~
  ::  all done - fire LLM follow-up
  =/  sys-prompt=@t  (build-prompt bowl context)
  =/  follow-wire=path
    ?:  =(-.msg-source.tl %direct)  /query-tools
    /dm-query-tools/(scot %p (src-ship msg-source.tl))
  :_  this(tool-loop ~)
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
    =?  dm-pending  !=(-.source %direct)  (~(del in dm-pending) (src-ship source))
    :_  this
    ?:  =(-.source %direct)
      :~  [%give %fact ~[/updates] %claw-update !>(`update:claw`[%error err])]  ==
    :~  (send-reply-card bowl source 'Sorry, I hit an error talking to the LLM provider.')  ==
  ?~  full-file.resp
    =?  pending  =(-.source %direct)  %.n
    =?  dm-pending  !=(-.source %direct)  (~(del in dm-pending) (src-ship source))
    `this
  =/  body=@t  q.data.u.full-file.resp
  =/  is-owner=?
    ?:  =(-.source %direct)  %.y
    =/  who=ship  (src-ship source)
    =/  role=(unit ship-role:claw)  (~(get by whitelist) who)
    &(?=(^ role) =(u.role %owner))
  =/  parsed  (parse-llm-response body)
  ?~  parsed
    %-  (slog leaf+"claw error: parse failed" ~)
    =.  last-error  body
    =?  pending  =(-.source %direct)  %.n
    =?  dm-pending  !=(-.source %direct)  (~(del in dm-pending) (src-ship source))
    :_  this
    ?:  =(-.source %direct)  ~
    :~  (send-reply-card bowl source 'Sorry, I had trouble understanding the response from my LLM provider.')  ==
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
        %dm       ship.source
        %channel  ship.source
        %direct   our.bowl
      ==
    ::  assistant response ingested into lcm via card below
    =?  dm-pending  (~(has in dm-pending) who)  (~(del in dm-pending) who)
    =.  pending-src  (~(del by pending-src) who)
    %-  (slog leaf+"claw reply to {(scow %p who)} via {<-.source>}: {(trip (end 3^80 content))}" ~)
    ::  check if compaction needed: history tokens > 60% of model budget
    :_  this
    :~  (send-reply-card bowl source content)
        [%give %fact ~[/updates] %claw-update !>(`update:claw`[%dm-response who ['assistant' content]])]
        (lcm-ingest bowl (lcm-key source) 'assistant' content)
    ==
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
          (execute-tool:tools bowl name.first arguments.first brave-key is-owner)
        ?.  ?=(%async -.res)
          ::  shouldn't happen, but handle gracefully
          $(async-pending t.async-pending, follow-msgs (snoc follow-msgs (tool-result-json id.first 'unexpected sync')))
        =.  tool-loop
          `[source (lcm-key source) follow-msgs async-pending]
        :_  this
        (weld (flop tool-cards) [card.res]~)
      ::  all sync - fire llm follow-up immediately
      =/  sys-prompt=@t  (build-prompt bowl context)
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
      (execute-tool:tools bowl name.tc arguments.tc brave-key is-owner)
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
