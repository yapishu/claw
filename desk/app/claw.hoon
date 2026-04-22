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
/-  pr=presence
/+  dbug, default-agent, server, tools=claw-tools
/+  *story-parse, *cron
|%
+$  card  card:agent:gall
+$  versioned-state  $%(state-0:claw state-1:claw state-2:claw state-3:claw state-4:claw state-5:claw state-6:claw state-7:claw state-8:claw state-9:claw state-10:claw state-11:claw state-12:claw state-13:claw state-14:claw)
::
::  +tool-hint: compact summary of how to use tools, injected into
::  every sys-prompt.  ~80 tokens.  Keeps qwen-bonsai aware that the
::  OpenAI-style `tools` param exists and how to invoke calls.
::
::  example tool-call text.  We assemble from bytes so the literal
::  curly braces don't trigger Hoon interpolation in the template.
++  tool-example
  ^-  @t
  =/  lb=@t  (crip `tape`~[`@tD`123])   ::  ASCII '{'
  =/  rb=@t  (crip `tape`~[`@tD`125])   ::  ASCII '}'
  %+  rap  3
  :~  '<tool_call>\0a'  lb  '"name":"web_search","arguments":'
      lb  '"query":"cats"'  rb  rb  '\0a</tool_call>\0a'
  ==
::
++  tool-hint
  ^-  @t
  %+  rap  3
  :~  '# Tools\0a\0a'
      'To call a tool, emit exactly:\0a\0a'
      tool-example
      '\0aStop after the closing tag; the result will be fed back '
      'and you can continue (including calling another tool). '
      'Full schemas are in the `tools` request field. Key tools: '
      'send_dm, send_channel_message, read_dm_history, '
      'read_channel_history, web_search, image_search, http_fetch, '
      'local_mcp_list/local_mcp (ship ops).'
  ==
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
  =.  parts  (snoc parts tool-hint)
  ?~  parts  ''
  =/  out=@t  i.parts
  =/  rem=(list @t)  t.parts
  |-
  ?~  rem  out
  $(rem t.rem, out (rap 3 out '\0a\0a---\0a\0a' i.rem ~))
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
::  +pick-provider: global default, with per-conversation override.
::
++  pick-provider
  |=  $:  conv-key=@t
          default-provider=provider:claw
          conv-providers=(map @t provider:claw)
      ==
  ^-  provider:claw
  =/  o  (~(get by conv-providers) conv-key)
  ?~  o  default-provider
  u.o
::
::  +make-llm-request: build a card that POSTs an OpenAI-format
::  chat.completions body to the provider's endpoint.
::
::    %openrouter: remote host, Bearer auth from api-key.
::    %maroon    : local ship's own Eyre at local-llm-url — the URL
::                 should include scheme + host + port, no trailing path.
::
++  make-llm-request
  |=  $:  =bowl:gall  =provider:claw  api-key=@t
          local-llm-url=@t  model=@t  sys-prompt=@t
          key=@t  =wire
          extra-msgs=(list json)
          pending-msg=(unit msg:claw)
          max-response-tokens=@ud
          max-context-tokens=@ud
          source=msg-source:claw
          dm-who=(unit ship)
      ==
  ^-  card
  ::  scry lcm for assembled context.  User dial `max-context-tokens`
  ::  overrides the per-model heuristic when non-zero; LCM trims
  ::  oldest-first to fit.
  =/  budget=@ud
    ?:(=(0 max-context-tokens) (model-budget model) max-context-tokens)
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
        ['max_tokens' (numb:enjs:format max-response-tokens)]
    ==
  =/  body-cord=@t  (en:json:html body)
  ::  For %maroon (same-ship) we bypass Eyre/iris entirely and poke
  ::  the agent directly.  The iris loopback path was unreliable and
  ::  HTTP adds no value for a call that never leaves the ship.  The
  ::  req-id threads the wire for debuggability; opaque meta carries
  ::  `[source dm-who]` so the response handler can route the reply
  ::  without any new state.
  ?:  ?=(%maroon provider)
    =/  req-id=@t  (spat wire)
    =/  meta=*  [source dm-who]
    :*  %pass  wire  %agent  [our.bowl %maroon]  %poke
        %maroon-chat-req  !>([req-id meta body-cord])
    ==
  =/  hed=(list [key=@t value=@t])
    :~  ['Content-Type' 'application/json']
        ['Authorization' (crip "Bearer {(trip api-key)}")]
    ==
  =/  req=request:http
    :*  %'POST'
        'https://openrouter.ai/api/v1/chat/completions'
        hed  `(as-octs:mimes:html body-cord)
    ==
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
++  send-dm-card
  |=  [=bowl:gall to=ship text=@t]
  ^-  card
  =/  dm-story=story:d  (text-to-story text)
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
  ::  disabled: the contacts scry bails: 4 on some ships (happens at
  ::  the jet layer, escaping +mule).  Returning empty is harmless —
  ::  nick is only a cosmetic system-prompt hint.
  ''
::
::  +has-own-nickname: check if text contains bot's own nickname
::    case-insensitive word check
::
++  has-own-nickname
  |=  [=bowl:gall text=@t]
  ^-  ?
  ::  disabled: contacts scry crashes on some ships
  ::  TODO: cache own nickname on init instead of scrying per-message
  %.n
::
::  +send-reply-card: send a response based on message source
::
++  send-reply-card
  |=  [=bowl:gall =msg-source:claw text=@t]
  ^-  card
  ?-  -.msg-source
      %direct  [%pass /noop %arvo %b %wait (add now.bowl ~s1)]
      %dm      (send-dm-card bowl ship.msg-source text)
      %dm-thread
    ::  DM thread replies: send as regular DM for now
    ::  (activity message-key IDs don't reliably match chat writ IDs)
    (send-dm-card bowl ship.msg-source text)
      %channel
    ::  post in channel as top-level message
    =/  ch-story=story:d  (text-to-story text)
    =/  ch-memo=memo:d  [content=ch-story author=our.bowl sent=now.bowl]
    =/  ch-essay=essay:d  [ch-memo /chat ~ ~]
    =/  =nest:d  [kind.msg-source host.msg-source name.msg-source]
    =/  act=a-channels:d  [%channel nest [%post [%add ch-essay]]]
    [%pass /ch-send %agent [our.bowl %channels] %poke %channel-action-1 !>(act)]
      %thread
    ::  post as reply in a thread
    =/  th-story=story:d  (text-to-story text)
    =/  th-memo=memo:d  [content=th-story author=our.bowl sent=now.bowl]
    =/  =nest:d  [kind.msg-source host.msg-source name.msg-source]
    =/  act=a-channels:d  [%channel nest [%post [%reply parent-id.msg-source [%add th-memo]]]]
    [%pass /ch-send %agent [our.bowl %channels] %poke %channel-action-1 !>(act)]
  ==
::
::  +sanitize-llm: strip ChatML / qwen3-thinking control tokens and the
::  entire <think>…</think> scratchpad before sending the reply to the
::  user.  Local-provider (%maroon) leaks these because its tokenizer
::  emits them as literal text when it hits max_tokens mid-turn.
::
::  +sanitize-llm: strip ChatML control tags and <think>…</think>
::  scratchpads from an LLM reply.  Walks the input tape once.
::
++  sanitize-llm
  |=  t=@t
  ^-  @t
  =/  in=tape  (trip t)
  =/  think-open=tape   "<think>"
  =/  think-close=tape  "</think>"
  =/  im-end=tape       "<|im_end|>"
  =/  im-start=tape     "<|im_start|>"
  =/  eof=tape          "<|endoftext|>"
  =|  out=tape
  =|  skipping=?
  |-  ^-  @t
  ?~  in  (crip (trim-ws (flop (trim-ws out))))
  ?:  skipping
    ?:  (starts-with think-close `tape`in)
      $(in `tape`(slag (lent think-close) `tape`in), skipping %.n)
    $(in `tape`t.in)
  ?:  (starts-with think-open `tape`in)
    $(in `tape`(slag (lent think-open) `tape`in), skipping %.y)
  ?:  (starts-with im-end `tape`in)
    $(in `tape`(slag (lent im-end) `tape`in))
  ?:  (starts-with im-start `tape`in)
    $(in `tape`(slag (lent im-start) `tape`in))
  ?:  (starts-with eof `tape`in)
    $(in `tape`(slag (lent eof) `tape`in))
  $(in `tape`t.in, out [i.in out])
::
::  +starts-with: does tape `hay` start with `pat`?  Purely positional.
::
++  starts-with
  |=  [pat=tape hay=tape]
  ^-  ?
  ?~  pat  %.y
  ?~  hay  %.n
  ?.  =(i.pat i.hay)  %.n
  $(pat t.pat, hay t.hay)
::
::  +trim-ws: strip leading whitespace (space, tab, CR, LF) from a tape.
::
++  trim-ws
  |=  x=tape
  ^-  tape
  ?~  x  x
  ?.  ?|(=(i.x ' ') =(i.x 10) =(i.x 13) =(i.x 9))  x
  $(x `tape`t.x)
::
::  +presence-context: derive a /apps/groups %presence context path
::  from claw's internal msg-source.  Returns ~ for sources with no
::  audience (direct, unsupported thread types).
::
++  presence-context
  |=  src=msg-source:claw
  ^-  (unit path)
  ?-  -.src
      %direct  ~
      %dm  `/dm/(scot %p ship.src)
      %dm-thread  `/dm/(scot %p ship.src)
      %channel
    `/channel/(scot %tas kind.src)/(scot %p host.src)/(scot %tas name.src)
      %thread
    `/channel/(scot %tas kind.src)/(scot %p host.src)/(scot %tas name.src)
  ==
::
::  +presence-card: build a poke to our own %presence agent.
::  kind=%start sets a "computing" flag visible to the appropriate
::  audience (DM counterparty for DMs, channel subscribers for
::  channels).  kind=%stop clears it.  No-ops for contexts with no
::  audience.
::
++  presence-card
  |=  [=bowl:gall src=msg-source:claw kind=?(%start %stop)]
  ^-  (list card)
  =/  ctx=(unit path)  (presence-context src)
  ?~  ctx  ~
  =/  disclose=(set ship)
    ?-  -.src
      %dm         (silt ~[ship.src])
      %dm-thread  (silt ~[ship.src])
      ::  channels: empty disclose = broadcast to all subscribers
      %channel    ~
      %thread     ~
      %direct     ~
    ==
  =/  key=key:pr  [u.ctx our.bowl %computing]
  =/  =action-1:pr
    ?-  kind
        %start
      [%set disclose key `~m1 [icon=~ text=`'thinking...' blob=~]]
        %stop
      [%clear key]
    ==
  :~  [%pass /presence %agent [our.bowl %presence] %poke %presence-action-1 !>(action-1)]
  ==
::
::  +extract-hermes-calls: scan a plain-text assistant reply for
::  <tool_call>…</tool_call> blocks (qwen3's native Hermes format).
::  Each block's contents must be a JSON object with `name` and
::  `arguments` fields.  We return the ORIGINAL text unchanged so the
::  follow-up prompt preserves the tool_call blocks — qwen3 expects
::  its own tool_call in the conversation history when it sees the
::  <tool_response> come back.
::
++  extract-hermes-calls
  |=  text=@t
  ^-  [cleaned=@t calls=(list [id=@t name=@t arguments=@t])]
  =/  open=tape   "<tool_call>"
  =/  close=tape  "</tool_call>"
  =/  in=tape     (trip text)
  =|  calls=(list [id=@t name=@t arguments=@t])
  =|  idx=@ud
  |-  ^-  [cleaned=@t calls=(list [id=@t name=@t arguments=@t])]
  ?~  in
    [text (flop calls)]
  ?.  (starts-with open `tape`in)
    $(in `tape`t.in)
  ::  consume <tool_call> … </tool_call>, extract JSON body
  =/  after-open=tape  (slag (lent open) `tape`in)
  =|  blob=tape
  |-  ^-  [cleaned=@t calls=(list [id=@t name=@t arguments=@t])]
  ?~  after-open
    [text (flop calls)]
  ?:  (starts-with close `tape`after-open)
    =/  remaining=tape  (slag (lent close) `tape`after-open)
    =/  json-text=@t  (crip (flop blob))
    =/  parsed-call=(unit [name=@t arguments=@t])
      =/  r=(each [name=@t arguments=@t] tang)
        %-  mule  |.
        =/  jon=(unit json)  (de:json:html json-text)
        ?~  jon  !!
        =/  m  (need (me u.jon))
        =/  nm  (need (~(get by m) 'name'))
        ?.  ?=([%s *] nm)  !!
        =/  args  (need (~(get by m) 'arguments'))
        =/  arg-str=@t
          ?:  ?=([%s *] args)  p.args
          (en:json:html args)
        [name=p.nm arguments=arg-str]
      ?:(?=(%| -.r) ~ `p.r)
    =/  updated-calls=(list [id=@t name=@t arguments=@t])
      ?~  parsed-call  calls
      =/  sid=@t  (rap 3 'hermes_' (scot %ud idx) ~)
      (snoc calls [sid name.u.parsed-call arguments.u.parsed-call])
    ^$(in `tape`remaining, calls updated-calls, idx +(idx))
  $(after-open `tape`t.after-open, blob [i.after-open blob])
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
    ::  no structured tool_calls field — check for qwen3 Hermes-style
    ::  <tool_call>…</tool_call> blocks in the content text.
    =/  content=json  (need (~(get by msg-map) 'content'))
    ?.  ?=([%s *] content)  !!
    =/  extracted  (extract-hermes-calls p.content)
    ?~  calls.extracted  [%text cleaned.extracted]
    [%tools cleaned.extracted calls.extracted]
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
    `[(send-reply-card bowl msg-source slash-help-text)]~
  ::  /model or /model <name>
  ?:  =(cmd '/model')
    =/  ctx-win=@t  (fall (~(get by ctx) %model-context-window) 'unknown')
    =/  info=@t
      %-  crip
      ;:  weld
        "Model: {(trip mod)}\0a"
        "Context window: {(trip ctx-win)} tokens"
      ==
    `[(send-reply-card bowl msg-source info)]~
  ?:  &((gte (met 3 cmd) 8) =((end [3 7] cmd) '/model '))
    =/  new-model=@t  (crip (trim-ws (trip (rsh [3 7] cmd))))
    ?:  =('' new-model)
      `[(send-reply-card bowl msg-source (rap 3 'Model: ' mod ~))]~
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can change the model.')]~
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Model set to: ' new-model ~))
        [%pass /slash-model %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%set-model new-model])]
    ==
  ?:  =(cmd '/clear')
    =/  key=@t  (lcm-key msg-source)
    %-  some
    :~  (send-reply-card bowl msg-source 'Conversation cleared.')
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
    `[(send-reply-card bowl msg-source status)]~
  ::  /open <channel> - set channel to allow all (owner only)
  ?:  &((gte (met 3 cmd) 7) =((end [3 6] cmd) '/open '))
    =/  ch=@t  (crip (trim-ws (trip (rsh [3 6] cmd))))
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can manage channel permissions.')]~
    ::  poke self to update channel-perms
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Channel ' ch ' set to open.' ~))
        [%pass /slash-perm %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%set-channel-perm ch %open])]
    ==
  ::  /restrict <channel> - set channel to whitelist-only (owner only)
  ?:  &((gte (met 3 cmd) 11) =((end [3 10] cmd) '/restrict '))
    =/  ch=@t  (crip (trim-ws (trip (rsh [3 10] cmd))))
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can manage channel permissions.')]~
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Channel ' ch ' set to whitelist-only.' ~))
        [%pass /slash-perm %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%set-channel-perm ch %whitelist])]
    ==
  ::  /approve ~ship - approve a pending ship (owner only)
  ?:  &((gte (met 3 cmd) 10) =((end [3 9] cmd) '/approve '))
    =/  ship-str=@t  (crip (trim-ws (trip (rsh [3 9] cmd))))
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can approve ships.')]~
    =/  parsed=(unit ship)  (slaw %p ship-str)
    ?~  parsed
      `[(send-reply-card bowl msg-source 'Invalid ship name.')]~
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Approved ' ship-str ' and added to whitelist.' ~))
        [%pass /slash-approve %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%approve u.parsed])]
    ==
  ::  /deny ~ship - deny a pending ship (owner only)
  ?:  &((gte (met 3 cmd) 7) =((end [3 6] cmd) '/deny '))
    =/  ship-str=@t  (crip (trim-ws (trip (rsh [3 6] cmd))))
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can deny ships.')]~
    =/  parsed=(unit ship)  (slaw %p ship-str)
    ?~  parsed
      `[(send-reply-card bowl msg-source 'Invalid ship name.')]~
    %-  some
    :~  (send-reply-card bowl msg-source (rap 3 'Denied ' ship-str '.' ~))
        [%pass /slash-deny %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%deny u.parsed])]
    ==
  ::  /pending - list pending approval requests (owner only)
  ?:  =(cmd '/pending')
    =/  is-owner=?
      =/  role=(unit ship-role:claw)  (~(get by wl) from)
      &(?=(^ role) =(u.role %owner))
    ?.  is-owner
      `[(send-reply-card bowl msg-source 'Only owners can view pending approvals.')]~
    ?:  =(~ pa)
      `[(send-reply-card bowl msg-source 'No pending approval requests.')]~
    =/  lines=(list @t)
      %+  turn  ~(tap by pa)
      |=  [s=ship reason=@t]
      (rap 3 '- ' (scot %p s) ': ' reason ~)
    =/  body=@t
      %+  roll  lines
      |=  [line=@t acc=@t]
      ?:(=('' acc) line (rap 3 acc '\0a' line ~))
    `[(send-reply-card bowl msg-source (rap 3 'Pending approvals:\0a' body ~))]~
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
  :_  %=  this
        model            'anthropic/claude-sonnet-4'
        pending          %.n
        context          default-ctx
        default-provider  %maroon
        local-llm-url    'http://localhost:8080'
        max-response-tokens  1.024
      ==
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
  ?:  ?=(%14 -.old)
    ::  already-current state; nothing to migrate, but still re-arm subs/cron below.
    =/  new  `state-14:claw`old
    =/  rebind-cards=(list card)
      :~  [%pass /eyre/connect %arvo %e %connect [`/apps/claw/api dap.bowl]]
      ==
    =/  sub-cards=(list card)
      :~  [%pass /activity %agent [our.bowl %activity] %leave ~]
          [%pass /activity %agent [our.bowl %activity] %watch /v4]
      ==
    =/  dm-cards=(list card)
      %+  turn  ~(tap by whitelist.new)
      |=  [s=ship r=ship-role:claw]
      [%pass /dm-watch/(scot %p s) %agent [our.bowl %chat] %watch /dm/(scot %p s)]
    =/  cron-cards=(list card)
      %+  murn  ~(tap by cron-jobs.new)
      |=  [cid=@ud job=cron-job:claw]
      ?.  active.job  ~
      =/  nxt=(unit @da)  (next-cron-fire schedule.job now.bowl)
      ?~  nxt  ~
      `[%pass /cron/(scot %ud cid)/(scot %ud version.job) %arvo %b %wait u.nxt]
    :_  this(state new)
    :(weld rebind-cards sub-cards dm-cards cron-cards)
  ::  Cascade: %0..%12 → state-12 → state-13 → state-14.
  ::  %13 short-circuits the state-12 cascade (goes straight to 13→14).
  ::  %14 was early-returned above.
  =/  new-13=state-13:claw
    ?:  ?=(%13 -.old)  old
    =/  new-12=state-12:claw
      ?-  -.old
          %12  old
          %11
        [%12 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old channel-perms.old participated.old seen-msgs.old bot-counts.old pending-approvals.old owner-last-msg.old cron-jobs.old next-cron-id.old ~]
          %10
        [%12 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old channel-perms.old participated.old seen-msgs.old bot-counts.old pending-approvals.old owner-last-msg.old ~ 0 ~]
          %9
        [%12 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old channel-perms.old participated.old seen-msgs.old bot-counts.old pending-approvals.old owner-last-msg.old ~ 0 ~]
          %8
        [%12 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old channel-perms.old participated.old seen-msgs.old ~ ~ *@da ~ 0 ~]
          %7
        [%12 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old channel-perms.old ~ ~ ~ ~ *@da ~ 0 ~]
          %6
        [%12 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old tool-loop.old pending-src.old ~ ~ ~ ~ ~ *@da ~ 0 ~]
          %5
        [%12 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~]
          %4
        [%12 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~]
          %3
        [%12 api-key.old brave-key.old model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~]
          %2
        [%12 api-key.old '' model.old pending.old last-error.old context.old whitelist.old dm-pending.old ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~]
          %1
        [%12 api-key.old '' model.old pending.old last-error.old context.old ~ ~ ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~]
          %0
        =/  ctx=(map @tas @t)  *(map @tas @t)
        =?  ctx  !=('' system-prompt.old)
          (~(put by ctx) %agent system-prompt.old)
        [%12 api-key.old '' model.old pending.old last-error.old ctx ~ ~ ~ ~ ~ ~ ~ ~ ~ *@da ~ 0 ~]
      ==
    :*  %13
        api-key.new-12  brave-key.new-12  model.new-12  pending.new-12
        last-error.new-12  context.new-12  whitelist.new-12
        dm-pending.new-12  tool-loop.new-12  pending-src.new-12
        channel-perms.new-12  participated.new-12  seen-msgs.new-12
        bot-counts.new-12  pending-approvals.new-12
        owner-last-msg.new-12  cron-jobs.new-12  next-cron-id.new-12
        msg-queue.new-12
        %maroon                         ::  default-provider: local first
        *(map @t provider:claw)         ::  conv-providers
        'http://localhost:8080'         ::  local-llm-url
    ==
  =/  new=state-14:claw
    :*  %14
        api-key.new-13  brave-key.new-13  model.new-13  pending.new-13
        last-error.new-13  context.new-13  whitelist.new-13
        dm-pending.new-13  tool-loop.new-13  pending-src.new-13
        channel-perms.new-13  participated.new-13  seen-msgs.new-13
        bot-counts.new-13  pending-approvals.new-13
        owner-last-msg.new-13  cron-jobs.new-13  next-cron-id.new-13
        msg-queue.new-13
        default-provider.new-13  conv-providers.new-13  local-llm-url.new-13
        1.024    ::  max-response-tokens
        0        ::  max-context-tokens (0 = use per-model heuristic)
    ==
  ::  rebind Eyre on every load so /apps/claw/api keeps mapping to us
  ::  across agent revives and vere restarts.
  =/  rebind-cards=(list card)
    :~  [%pass /eyre/connect %arvo %e %connect [`/apps/claw/api dap.bowl]]
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
    ?.  ?|  =(-.old %6)
            =(-.old %9)
            =(-.old %10)
            =(-.old %11)
            =(-.old %12)
        ==
      :~  (lcm-sync-config bowl api-key.new model.new)
      ==
    ~
  ::  re-arm all active cron timers
  =/  cron-cards=(list card)
    %+  murn  ~(tap by cron-jobs.new)
    |=  [cid=@ud job=cron-job:claw]
    ?.  active.job  ~
    =/  nxt=(unit @da)  (next-cron-fire schedule.job now.bowl)
    ?~  nxt  ~
    `[%pass /cron/(scot %ud cid)/(scot %ud version.job) %arvo %b %wait u.nxt]
  :_  this(state new)
  :(weld rebind-cards sub-cards dm-cards migrate-cards cron-cards)
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+  mark
    (on-poke:def mark vase)
  ::
  ::  Direct response from %maroon (same-ship), no iris involved.
  ::  `meta` carries the original `[source dm-who]` so we can route
  ::  the reply without any per-request state.  We handle the reply
  ::  inline here rather than going through on-arvo so the path is
  ::  explicit and doesn't look like HTTP handling.
  ::
      %maroon-chat-resp
    =+  !<([req-id=@t meta=* status=@ud body=@t] vase)
    =+  ;;([source=msg-source:claw dm-who=(unit ship)] meta)
    ::  Hand the decoded body off to on-arvo via a synthetic sign.  The
    ::  on-arvo/handle-llm-body path already owns text-vs-tool-call
    ::  dispatch, multi-round tool loops, sanitize, presence clears,
    ::  and per-source routing.  This keeps a single code path for
    ::  both openrouter (iris) and maroon (poke) responses.
    =/  =response-header:http  [status ~]
    =/  full=(unit mime-data:iris)
      ?:  =('' body)  ~
      `[type='application/json' data=(as-octs:mimes:html body)]
    =/  synthetic-sign=sign-arvo
      [%iris %http-response [%finished response-header full]]
    =/  fake-wire=wire
      ?:  =(-.source %direct)  /query
      /dm-query/(scot %p (src-ship source))/(scot %da now.bowl)
    (on-arvo fake-wire synthetic-sign)
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
            %'set-default-provider'
          ^-  action:claw
          =/  p=@t  ((ot ~[provider+so]) u.jon)
          [%set-default-provider ?:(=('maroon' p) %maroon %openrouter)]
            %'set-conv-provider'
          ^-  action:claw
          =/  [k=@t p=@t]  ((ot ~[['conv-key' so] provider+so]) u.jon)
          [%set-conv-provider k ?:(=('maroon' p) %maroon %openrouter)]
            %'clear-conv-provider'
          ^-  action:claw  [%clear-conv-provider `@t`((ot ~[['conv-key' so]]) u.jon)]
            %'set-local-llm-url'
          ^-  action:claw  [%set-local-llm-url `@t`((ot ~[url+so]) u.jon)]
            %'set-max-response-tokens'
          ^-  action:claw  [%set-max-response-tokens `@ud`((ot ~[tokens+ni]) u.jon)]
            %'set-max-context-tokens'
          ^-  action:claw  [%set-max-context-tokens `@ud`((ot ~[tokens+ni]) u.jon)]
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
            :-  'pending-approvals'
            %-  pairs:enjs:format
            %+  turn  ~(tap by pending-approvals)
            |=  [s=ship reason=@t]
            [(scot %p s) s+reason]
            ['default-provider' s+?:(=(default-provider %maroon) 'maroon' 'openrouter')]
            ['local-llm-url' s+local-llm-url]
            ['max-response-tokens' (numb:enjs:format max-response-tokens)]
            ['max-context-tokens' (numb:enjs:format max-context-tokens)]
            :-  'conv-providers'
            %-  pairs:enjs:format
            %+  turn  ~(tap by conv-providers)
            |=  [k=@t p=provider:claw]
            [k s+?:(=(p %maroon) 'maroon' 'openrouter')]
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
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html s+(build-prompt bowl context owner-last-msg)))]
    ::
        [%cron-jobs ~]
      =/  j=json
        :-  %a
        %+  turn  ~(tap by cron-jobs)
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
      =/  j=json
        %-  pairs:enjs:format
        %+  turn  ~(tap by channel-perms)
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
      %set-channel-perm
    %-  (slog leaf+"claw: channel '{(trip channel.act)}' set to {<perm.act>}" ~)
    `this(channel-perms (~(put by channel-perms) channel.act perm.act))
  ::
      %approve
    %-  (slog leaf+"claw: approved {(scow %p ship.act)}" ~)
    =.  pending-approvals  (~(del by pending-approvals) ship.act)
    =.  whitelist  (~(put by whitelist) ship.act %allowed)
    :_  this
    :~  [%pass /dm-rsvp/(scot %p ship.act) %agent [our.bowl %chat] %poke %chat-dm-rsvp !>([ship.act %.y])]
        [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %leave ~]
        [%pass /dm-watch/(scot %p ship.act) %agent [our.bowl %chat] %watch /dm/(scot %p ship.act)]
        (send-dm-card bowl ship.act 'Your access has been approved. You can now talk to me!')
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
    =/  cid=@ud  next-cron-id
    =/  job=cron-job:claw  [cid schedule.act prompt.act %.y 0 now.bowl]
    =.  cron-jobs  (~(put by cron-jobs) cid job)
    =.  next-cron-id  +(cid)
    :_  this
    :~  [%pass /cron/(scot %ud cid)/(scot %ud 0) %arvo %b %wait u.nxt]
    ==
  ::
      %cron-remove
    %-  (slog leaf+"claw: cron-remove {(a-co:co cron-id.act)}" ~)
    =.  cron-jobs  (~(del by cron-jobs) cron-id.act)
    `this
  ::
      %set-default-provider
    %-  (slog leaf+"claw: default provider set to {<provider.act>}" ~)
    `this(default-provider provider.act)
  ::
      %set-conv-provider
    %-  (slog leaf+"claw: conv '{(trip conv-key.act)}' provider set to {<provider.act>}" ~)
    `this(conv-providers (~(put by conv-providers) conv-key.act provider.act))
  ::
      %clear-conv-provider
    %-  (slog leaf+"claw: conv '{(trip conv-key.act)}' provider cleared" ~)
    `this(conv-providers (~(del by conv-providers) conv-key.act))
  ::
      %set-local-llm-url
    %-  (slog leaf+"claw: local-llm-url set to '{(trip url.act)}'" ~)
    `this(local-llm-url url.act)
  ::
      %set-max-response-tokens
    %-  (slog leaf+"claw: max-response-tokens = {<tokens.act>}" ~)
    `this(max-response-tokens tokens.act)
  ::
      %set-max-context-tokens
    %-  (slog leaf+"claw: max-context-tokens = {<tokens.act>}" ~)
    `this(max-context-tokens tokens.act)
  ::
      %prompt
    ?:  pending  ~|(%claw-busy !!)
    ?:  ?&  =(%openrouter (pick-provider 'direct' default-provider conv-providers))
            =('' api-key)
        ==
      ~|(%claw-no-api-key !!)
    =/  new-msg=msg:claw  ['user' content.act]
    =.  pending  %.y
    =/  sys-prompt=@t  (build-prompt bowl context owner-last-msg)
    %-  (slog leaf+"claw: sending prompt..." ~)
    :_  this
    :~  (lcm-ingest bowl 'direct' 'user' content.act)
        (make-llm-request bowl (pick-provider 'direct' default-provider conv-providers) api-key local-llm-url model sys-prompt 'direct' /query ~ `new-msg max-response-tokens max-context-tokens [%direct ~] ~)
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
          :-  'pending-approvals'
          %-  pairs:enjs:format
          %+  turn  ~(tap by pending-approvals)
          |=  [s=ship reason=@t]
          [(scot %p s) s+reason]
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
    ``json+!>(s+(build-prompt bowl context owner-last-msg))
      [%x %cron-jobs ~]
    =/  j=json
      :-  %a
      %+  turn  ~(tap by cron-jobs)
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
      ::  /dm-watch (chat writ-response) is kept subscribed for owner
      ::  heartbeat + rate-limit bookkeeping only.  LLM dispatch is
      ::  owned by the /activity %dm-post branch so every DM lands
      ::  with the activity msg-id for dedup.  Running both paths
      ::  caused duplicate LLM calls and iris duct collisions.
      =/  text=@t  (story-to-text ;;(story:d content-noun))
      ?:  =('' text)  `this
      =/  dmw-role=(unit ship-role:claw)  (~(get by whitelist) from)
      =?  owner-last-msg  &(?=(^ dmw-role) =(u.dmw-role %owner))
        now.bowl
      =/  dmw-rl-key=@t  (rap 3 'dm/' (scot %p from) ~)
      =.  bot-counts  (~(put by bot-counts) dmw-rl-key 0)
      `this
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
        =/  from=ship  p.id.key.incoming
        ?:  =(from our.bowl)  `this
        ::  check channel permissions: %open allows anyone, %whitelist or missing requires whitelist
        =/  =nest:d  channel.incoming
        =/  ch-key=@t  (rap 3 kind.nest '/' (scot %p ship.nest) '/' name.nest ~)
        =/  ch-perm=(unit channel-perm:claw)  (~(get by channel-perms) ch-key)
        ?.  ?|  (~(has by whitelist) from)
                &(?=(^ ch-perm) =(u.ch-perm %open))
            ==
          ::  approval workflow: notify owner if mentioned by unknown ship
          =/  post-text=@t  (story-to-text content.incoming)
          =/  post-nick=?  (has-own-nickname bowl post-text)
          ?.  |(mention.incoming post-nick)  `this
          ?:  (~(has by pending-approvals) from)  `this
          %-  (slog leaf+"claw: access request from {(scow %p from)}" ~)
          =/  reason=@t  (rap 3 'mentioned in ' ch-key ': ' (end 3^100 post-text) ~)
          =.  pending-approvals  (~(put by pending-approvals) from reason)
          ::  notify all owners
          =/  owner-cards=(list card)
            %+  murn  ~(tap by whitelist)
            |=  [s=ship r=ship-role:claw]
            ?.  =(r %owner)  ~
            `(send-dm-card bowl s (rap 3 'Access request from ' (scot %p from) ': ' reason '\0a\0aUse /approve ' (scot %p from) ' or /deny ' (scot %p from) ~))
          [owner-cards this]
        =/  text=@t  (story-to-text content.incoming)
        ::  respond if mentioned OR if text contains our nickname
        =/  nick-match=?  (has-own-nickname bowl text)
        ?.  |(mention.incoming nick-match)  `this
        ?:  =('' text)  `this
        ::  dedup: skip if already seen
        =/  evt-id=@t  (rap 3 'post/' (scot %p from) '/' (scot %da q.id.key.incoming) ~)
        ?:  (~(has in seen-msgs) evt-id)  `this
        =.  seen-msgs  (~(put in seen-msgs) evt-id)
        =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
        ::  owner heartbeat tracking
        =/  post-from-role=(unit ship-role:claw)  (~(get by whitelist) from)
        =?  owner-last-msg  &(?=(^ post-from-role) =(u.post-from-role %owner))
          now.bowl
        ::  bot rate limiting: reset count (human message in channel)
        =.  bot-counts  (~(put by bot-counts) ch-key 0)
        %-  (slog leaf+"claw: mention from {(scow %p from)} in {(trip ;;(@t kind.nest))}/{(scow %p ship.nest)}/{(trip ;;(@t name.nest))}: {(trip text)}" ~)
        =/  src=msg-source:claw  [%channel kind.nest ship.nest name.nest from]
        ::  track participated channel
        =.  participated  (~(put in participated) ch-key)
        ::  check for slash commands
        =/  slash-result  (handle-slash bowl text from src model pending api-key last-error whitelist context pending-approvals owner-last-msg)
        ?^  slash-result  [u.slash-result this]
        ::  bot rate limiting: check before responding
        =/  ch-bot-count=@ud  (~(gut by bot-counts) ch-key 0)
        ?:  (gth ch-bot-count 3)
          %-  (slog leaf+"claw: rate limited in {(trip ch-key)} (count={<ch-bot-count>})" ~)
          `this
        =.  pending-src  (~(put by pending-src) from src)
        =.  dm-pending  (~(put in dm-pending) from)
        ?:  ?&  =(%openrouter (pick-provider (lcm-key src) default-provider conv-providers))
                =('' api-key)
            ==
          =.  dm-pending  (~(del in dm-pending) from)
          :_  this
          :~  (send-reply-card bowl src 'Sorry, no API key configured.')
          ==
        =/  msg-id=@t  (scot %da q.id.key.incoming)
        =/  ch-str=@t  (rap 3 kind.nest '/' (scot %p ship.nest) '/' name.nest ~)
        %-  (slog leaf+"claw: injecting context: msg_id={<msg-id>} channel={<ch-str>}" ~)
        =/  base-prompt=@t  (build-prompt bowl context owner-last-msg)
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
        %+  weld  (presence-card bowl src %start)
        :~  (lcm-ingest bowl (lcm-key src) 'user' text)
            (make-llm-request bowl (pick-provider (lcm-key src) default-provider conv-providers) api-key local-llm-url model sys-prompt (lcm-key src) /dm-query/(scot %p from)/(scot %da now.bowl) ~ `['user' text] max-response-tokens max-context-tokens src `from)
        ==
      ::
          %dm-post
        =/  from=ship  p.id.key.incoming
        ?:  =(from our.bowl)  `this
        ?.  (~(has by whitelist) from)
          ::  approval workflow: notify owner of DM from unknown ship
          =/  dm-text=@t  (story-to-text content.incoming)
          ?:  =('' dm-text)  `this
          ?:  (~(has by pending-approvals) from)  `this
          %-  (slog leaf+"claw: access request via DM from {(scow %p from)}" ~)
          =/  reason=@t  (rap 3 'DM: ' (end 3^100 dm-text) ~)
          =.  pending-approvals  (~(put by pending-approvals) from reason)
          =/  owner-cards=(list card)
            %+  murn  ~(tap by whitelist)
            |=  [s=ship r=ship-role:claw]
            ?.  =(r %owner)  ~
            `(send-dm-card bowl s (rap 3 'Access request from ' (scot %p from) ': ' reason '\0a\0aUse /approve ' (scot %p from) ' or /deny ' (scot %p from) ~))
          [owner-cards this]
        =/  text=@t  (story-to-text content.incoming)
        ?:  =('' text)  `this
        ::  dedup by activity msg-id (unique per DM) so repeat identical
        ::  text does not collide.  /dm-watch is a no-op for dispatch so
        ::  we no longer need a cross-path shared key.
        =/  evt-id=@t  (rap 3 'dmp/' (scot %p from) '/' (scot %da q.id.key.incoming) ~)
        ?:  (~(has in seen-msgs) evt-id)  `this
        =.  seen-msgs  (~(put in seen-msgs) evt-id)
        =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
        ::  owner heartbeat tracking
        =/  dmp-role=(unit ship-role:claw)  (~(get by whitelist) from)
        =?  owner-last-msg  &(?=(^ dmp-role) =(u.dmp-role %owner))
          now.bowl
        ::  bot rate limiting: reset count (human DM received)
        =/  dmp-rl-key=@t  (rap 3 'dm/' (scot %p from) ~)
        =.  bot-counts  (~(put by bot-counts) dmp-rl-key 0)
        %-  (slog leaf+"claw: dm-post from {(scow %p from)}: {(trip text)}" ~)
        =/  src=msg-source:claw  [%dm from]
        ::  check for slash commands
        =/  slash-result  (handle-slash bowl text from src model pending api-key last-error whitelist context pending-approvals owner-last-msg)
        ?^  slash-result  [u.slash-result this]
        =.  dm-pending  (~(put in dm-pending) from)
        ?:  ?&  =(%openrouter (pick-provider (lcm-key src) default-provider conv-providers))
                =('' api-key)
            ==
          =.  dm-pending  (~(del in dm-pending) from)
          :_  this
          :~  (send-dm-card bowl from 'Sorry, no API key configured.')
          ==
        =/  msg-id=@t  (scot %da q.id.key.incoming)
        =/  base-prompt=@t  (build-prompt bowl context owner-last-msg)
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
        %+  weld  (presence-card bowl src %start)
        :~  (lcm-ingest bowl (lcm-key src) 'user' text)
            (make-llm-request bowl (pick-provider (lcm-key src) default-provider conv-providers) api-key local-llm-url model sys-prompt (lcm-key src) /dm-query/(scot %p from)/(scot %da now.bowl) ~ `['user' text] max-response-tokens max-context-tokens src `from)
        ==
      ::
          %dm-reply
        =/  from=ship  p.id.key.incoming
        ?:  =(from our.bowl)  `this
        ?.  (~(has by whitelist) from)  `this
        =/  text=@t  (story-to-text content.incoming)
        ?:  =('' text)  `this
        =/  pid=[p=@p q=@da]  [p.id.parent.incoming q.id.parent.incoming]
        ::  dedup
        =/  evt-id=@t  (rap 3 'dmr/' (scot %p from) '/' (scot %da q.id.key.incoming) ~)
        ?:  (~(has in seen-msgs) evt-id)  `this
        =.  seen-msgs  (~(put in seen-msgs) evt-id)
        =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
        ::  owner heartbeat tracking
        =/  dmr-role=(unit ship-role:claw)  (~(get by whitelist) from)
        =?  owner-last-msg  &(?=(^ dmr-role) =(u.dmr-role %owner))
          now.bowl
        %-  (slog leaf+"claw: dm-reply from {(scow %p from)} parent={<pid>}: {(trip text)}" ~)
        ::  DM thread reply: route response back to the same thread
        =/  src=msg-source:claw  [%dm-thread from pid]
        =/  slash-result  (handle-slash bowl text from src model pending api-key last-error whitelist context pending-approvals owner-last-msg)
        ?^  slash-result  [u.slash-result this]
        =.  dm-pending  (~(put in dm-pending) from)
        ?:  ?&  =(%openrouter (pick-provider (lcm-key src) default-provider conv-providers))
                =('' api-key)
            ==
          =.  dm-pending  (~(del in dm-pending) from)
          :_  this
          :~  (send-dm-card bowl from 'Sorry, no API key configured.')
          ==
        =/  base-prompt=@t  (build-prompt bowl context owner-last-msg)
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
        =.  pending-src  (~(put by pending-src) from src)
        :_  this
        %+  weld  (presence-card bowl src %start)
        :~  (lcm-ingest bowl (lcm-key src) 'user' text)
            (make-llm-request bowl (pick-provider (lcm-key src) default-provider conv-providers) api-key local-llm-url model sys-prompt (lcm-key src) /dm-query/(scot %p from)/(scot %da now.bowl) ~ `['user' text] max-response-tokens max-context-tokens src `from)
        ==
      ::
          %reply
        ::  respond if mentioned, replying to our post, nickname match, or participated thread
        =/  parent-author=ship  p.id.parent.incoming
        =/  from=ship  p.id.key.incoming
        ?:  =(from our.bowl)  `this
        =/  =nest:d  channel.incoming
        =/  ch-key=@t  (rap 3 kind.nest '/' (scot %p ship.nest) '/' name.nest ~)
        =/  ch-perm=(unit channel-perm:claw)  (~(get by channel-perms) ch-key)
        ?.  ?|  (~(has by whitelist) from)
                &(?=(^ ch-perm) =(u.ch-perm %open))
            ==
          `this
        =/  text=@t  (story-to-text content.incoming)
        ?:  =('' text)  `this
        ::  build thread key for participated check
        =/  parent-time=@da  q.id.parent.incoming
        =/  thread-key=@t  (rap 3 'thread/' kind.nest '/' (scot %p ship.nest) '/' name.nest '/' (scot %da parent-time) ~)
        =/  nick-match=?  (has-own-nickname bowl text)
        =/  in-participated=?  (~(has in participated) thread-key)
        ?.  ?|  mention.incoming
                =(parent-author our.bowl)
                nick-match
                in-participated
            ==
          `this
        ::  dedup
        =/  evt-id=@t  (rap 3 'rpl/' (scot %p from) '/' (scot %da q.id.key.incoming) ~)
        ?:  (~(has in seen-msgs) evt-id)  `this
        =.  seen-msgs  (~(put in seen-msgs) evt-id)
        =?  seen-msgs  (gth ~(wyt in seen-msgs) 1.000)  ~
        ::  owner heartbeat tracking
        =/  rpl-role=(unit ship-role:claw)  (~(get by whitelist) from)
        =?  owner-last-msg  &(?=(^ rpl-role) =(u.rpl-role %owner))
          now.bowl
        ::  bot rate limiting: reset count (human message in thread)
        =.  bot-counts  (~(put by bot-counts) thread-key 0)
        ::  track participated thread
        =.  participated  (~(put in participated) thread-key)
        %-  (slog leaf+"claw: reply from {(scow %p from)} in thread {(scow %p ship.nest)}/{(trip name.nest)}" ~)
        =/  src=msg-source:claw  [%thread kind.nest ship.nest name.nest parent-time from]
        =/  slash-result  (handle-slash bowl text from src model pending api-key last-error whitelist context pending-approvals owner-last-msg)
        ?^  slash-result  [u.slash-result this]
        ::  bot rate limiting: check before responding
        =/  thr-bot-count=@ud  (~(gut by bot-counts) thread-key 0)
        ?:  (gth thr-bot-count 3)
          %-  (slog leaf+"claw: rate limited in thread (count={<thr-bot-count>})" ~)
          `this
        =.  pending-src  (~(put by pending-src) from src)
        =.  dm-pending  (~(put in dm-pending) from)
        ?:  ?&  =(%openrouter (pick-provider (lcm-key src) default-provider conv-providers))
                =('' api-key)
            ==
          =.  dm-pending  (~(del in dm-pending) from)
          :_  this
          :~  (send-reply-card bowl src 'Sorry, no API key configured.')
          ==
        =/  base-prompt=@t  (build-prompt bowl context owner-last-msg)
        =/  nick=@t  (get-nickname bowl from)
        =/  nick-str=@t
          ?:(=('' nick) '' (rap 3 ' (nickname: ' nick ')' ~))
        =/  sys-prompt=@t
          %+  rap  3
          :~  base-prompt
              '\0a\0a---\0a\0a# Current Conversation\0a\0a'
              (scot %p from)
              nick-str
              ' replied in a thread in channel '
              ch-key
              '.\0aYour response will be posted in the same thread.'
          ==
        :_  this
        %+  weld  (presence-card bowl src %start)
        :~  (lcm-ingest bowl (lcm-key src) 'user' text)
            (make-llm-request bowl (pick-provider (lcm-key src) default-provider conv-providers) api-key local-llm-url model sys-prompt (lcm-key src) /dm-query/(scot %p from)/(scot %da now.bowl) ~ `['user' text] max-response-tokens max-context-tokens src `from)
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
    =/  job=(unit cron-job:claw)  (~(get by cron-jobs) u.cid)
    ?~  job  `this
    ::  ignore stale fires
    ?.  &(active.u.job =(u.ver version.u.job))  `this
    %-  (slog leaf+"claw: cron fire schedule='{(trip schedule.u.job)}'" ~)
    ::  process the prompt through the LLM (skip openrouter with no key;
    ::  %maroon is fine without)
    ?:  ?&  =(%openrouter (pick-provider 'direct' default-provider conv-providers))
            =('' api-key)
        ==
      `this
    =/  sys-prompt=@t  (build-prompt bowl context owner-last-msg)
    ::  bump version and reschedule
    =/  next-ver=@ud  +(version.u.job)
    =.  cron-jobs  (~(put by cron-jobs) u.cid u.job(version next-ver))
    ::  compute next fire time from cron schedule
    =/  nxt=(unit @da)  (next-cron-fire schedule.u.job now.bowl)
    ::  fire LLM request and re-arm timer
    :_  this
    =/  cards=(list card)
      :~  (lcm-ingest bowl 'direct' 'system' (rap 3 '[Scheduled: ' schedule.u.job '] ' prompt.u.job ~))
          (make-llm-request bowl (pick-provider 'direct' default-provider conv-providers) api-key local-llm-url model sys-prompt 'direct' /cron-query ~ `['system' prompt.u.job] max-response-tokens max-context-tokens [%direct ~] ~)
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
    =.  context  (~(put by context) %model-context-window (crip (a-co:co u.ctx-len)))
    :_  this
    :~  [%pass /lcm-config %agent [our.bowl %lcm] %poke %lcm-action !>(`lcm-action:lcm`[%set-config [api-key model 75 16 20.000 1.200 2.000 8 4 u.ctx-len]])]
    ==
  ::
  ::  compaction response
  ::
  ::
      [%query ~]
    (handle-llm-response sign [%direct ~] ~)
  ::
      [%query-tools *]
    (handle-llm-response sign [%direct ~] ~)
  ::
      [%dm-query @ *]
    =/  who=ship  (slav %p i.t.wire)
    ::  use stored source (for channel responses) - DON'T delete yet
    ::  pending-src stays until final text response is sent
    =/  src=msg-source:claw  (fall (~(get by pending-src) who) [%dm who])
    (handle-llm-response sign src `who)
  ::
      [%dm-query-tools @ *]
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
        =/  r=(each tool-result:tools tang)
          (mule |.((execute-tool:tools bowl name.next arguments.next brave-key tl-owner local-llm-url)))
        ?:(?=(%| -.r) [%sync ~ 'error: tool crashed'] p.r)
      ?.  ?=(%async -.res)
        =.  tool-loop  `[msg-source.tl conv-key.tl (snoc new-fmsgs (tool-result-json id.next 'done')) t.rest]
        `this
      =.  tool-loop  `[msg-source.tl conv-key.tl new-fmsgs t.rest]
      :_  this  [card.res]~
    ::  all done - fire llm follow-up
    =/  sys-prompt=@t  (build-prompt bowl context owner-last-msg)
    =/  follow-wire=path
      ?:  =(-.msg-source.tl %direct)  /query-tools/(scot %da now.bowl)
      /dm-query-tools/(scot %p (src-ship msg-source.tl))/(scot %da now.bowl)
    :_  this(tool-loop ~)
    :~  (make-llm-request bowl (pick-provider conv-key.tl default-provider conv-providers) api-key local-llm-url model sys-prompt conv-key.tl follow-wire new-fmsgs ~ max-response-tokens max-context-tokens msg-source.tl ?:(=(-.msg-source.tl %direct) ~ `(src-ship msg-source.tl)))
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
      =/  r=(each tool-result:tools tang)
        (mule |.((execute-tool:tools bowl name.next arguments.next brave-key tl-owner local-llm-url)))
      ?:(?=(%| -.r) [%sync ~ 'error: tool crashed'] p.r)
    ?.  ?=(%async -.res)
      ::  sync - add result and recurse
      $(tl [msg-source.tl conv-key.tl (snoc new-fmsgs (tool-result-json id.next 'done')) t.rest])
    ::  keep 'next' as first in pending so khan handler finds its ID
    =.  tool-loop  `[msg-source.tl conv-key.tl new-fmsgs rest]
    :_  this  [card.res]~
  ::  all done - fire LLM follow-up
  =/  sys-prompt=@t  (build-prompt bowl context owner-last-msg)
  =/  follow-wire=path
    ?:  =(-.msg-source.tl %direct)  /query-tools/(scot %da now.bowl)
    /dm-query-tools/(scot %p (src-ship msg-source.tl))/(scot %da now.bowl)
  :_  this(tool-loop ~)
  :~  (make-llm-request bowl (pick-provider conv-key.tl default-provider conv-providers) api-key local-llm-url model sys-prompt conv-key.tl follow-wire new-fmsgs ~ max-response-tokens max-context-tokens msg-source.tl ?:(=(-.msg-source.tl %direct) ~ `(src-ship msg-source.tl)))
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
  ~&  >  [%hlr-enter sign-tag=-.sign source-tag=-.source]
  ?.  ?=([%iris %http-response *] sign)
    ~&  >  [%hlr-bail-not-iris]
    `this
  =/  resp=client-response:iris  client-response.sign
  ?.  ?=(%finished -.resp)
    ~&  >  [%hlr-bail-not-finished -.resp]
    `this
  =/  code=@ud  status-code.response-header.resp
  =/  body=@t
    ?~  full-file.resp  ''
    q.data.u.full-file.resp
  ~&  >  [%hlr-calling-body code=code body-len=(met 3 body)]
  (handle-llm-body code body source dm-who)
::
::  +handle-llm-body: shared post-parse logic for both the iris HTTP
::  path and the direct-poke (%maroon-chat-resp) path.  Takes a status
::  code and the raw response body; everything else is identical.
::
++  handle-llm-body
  |=  $:  code=@ud
          body=@t
          source=msg-source:claw
          dm-who=(unit ship)
      ==
  ^-  (quip card _this)
  ~&  >  [%hlb-enter code=code body-len=(met 3 body) source-tag=-.source]
  ::  error handling
  ?.  =(200 code)
    =/  err=@t  ?:(=('' body) 'http error' body)
    %-  (slog leaf+"claw error [{(a-co:co code)}]: {(trip err)}" ~)
    =.  last-error  err
    =?  pending  =(-.source %direct)  %.n
    =?  dm-pending  !=(-.source %direct)  (~(del in dm-pending) (src-ship source))
    ::  surface the provider's error body so the user can see *why*
    ::  (e.g. "no model loaded", "busy", quota exceeded, etc.).
    =/  short-err=@t  (crip (scag 240 (trip err)))
    =/  reply=@t
      (rap 3 'LLM error [' (scot %ud code) ']: ' short-err ~)
    :_  this
    %+  weld  (presence-card bowl source %stop)
    ?:  =(-.source %direct)
      :~  [%give %fact ~[/updates] %claw-update !>(`update:claw`[%error err])]  ==
    :~  (send-reply-card bowl source reply)  ==
  ?:  =('' body)
    =?  pending  =(-.source %direct)  %.n
    =?  dm-pending  !=(-.source %direct)  (~(del in dm-pending) (src-ship source))
    `this
  =/  is-owner=?
    ?:  =(-.source %direct)  %.y
    =/  who=ship  (src-ship source)
    =/  role=(unit ship-role:claw)  (~(get by whitelist) who)
    &(?=(^ role) =(u.role %owner))
  =/  parsed  (parse-llm-response body)
  ~&  >  [%hlb-parsed ?~(parsed 'NONE' -.u.parsed)]
  ?~  parsed
    %-  (slog leaf+"claw error: parse failed" ~)
    =.  last-error  body
    =?  pending  =(-.source %direct)  %.n
    =?  dm-pending  !=(-.source %direct)  (~(del in dm-pending) (src-ship source))
    :_  this
    %+  weld  (presence-card bowl source %stop)
    ?:  =(-.source %direct)  ~
    :~  (send-reply-card bowl source 'Sorry, I had trouble understanding the response from my LLM provider.')  ==
  ::
  ?-  -.u.parsed
  ::
  ::  text response - deliver to user
  ::
      %text
    =/  content=@t  (sanitize-llm content.u.parsed)
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
    =?  dm-pending  (~(has in dm-pending) who)  (~(del in dm-pending) who)
    =.  pending-src  (~(del by pending-src) who)
    ::  track participated: mark channel/thread so we respond to follow-ups
    =.  participated
      ?+  -.source  participated
        %channel  (~(put in participated) (rap 3 kind.source '/' (scot %p host.source) '/' name.source ~))
        %thread   (~(put in participated) (lcm-key source))
      ==
    ::  bot rate limiting: increment count for this conversation key
    =/  resp-rl-key=@t  (lcm-key source)
    =/  cur-bot-count=@ud  (~(gut by bot-counts) resp-rl-key 0)
    =.  bot-counts  (~(put by bot-counts) resp-rl-key +(cur-bot-count))
    %-  (slog leaf+"claw reply to {(scow %p who)} via {<-.source>}: {(trip (end 3^80 content))}" ~)
    =/  response-cards=(list card)
      :~  (send-reply-card bowl source content)
          [%give %fact ~[/updates] %claw-update !>(`update:claw`[%dm-response who ['assistant' content]])]
          (lcm-ingest bowl (lcm-key source) 'assistant' content)
      ==
    :_  this
    (weld response-cards (presence-card bowl source %stop))
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
            (mule |.((execute-tool:tools bowl name.first arguments.first brave-key is-owner local-llm-url)))
          ?:(?=(%| -.r) [%sync ~ 'error: tool crashed'] p.r)
        ?.  ?=(%async -.res)
          ::  shouldn't happen, but handle gracefully
          $(async-pending t.async-pending, follow-msgs (snoc follow-msgs (tool-result-json id.first 'unexpected sync')))
        =.  tool-loop
          `[source (lcm-key source) follow-msgs async-pending]
        :_  this
        (weld (flop tool-cards) [card.res]~)
      ::  all sync - fire llm follow-up immediately
      =/  sys-prompt=@t  (build-prompt bowl context owner-last-msg)
      =/  follow-wire=path
        ?:  =(-.source %direct)  /query-tools/(scot %da now.bowl)
        /dm-query-tools/(scot %p (src-ship source))/(scot %da now.bowl)
      :_  this
      %+  weld  (flop tool-cards)
      :~  (make-llm-request bowl (pick-provider (lcm-key source) default-provider conv-providers) api-key local-llm-url model sys-prompt (lcm-key source) follow-wire follow-msgs ~ max-response-tokens max-context-tokens source ?:(=(-.source %direct) ~ `(src-ship source)))
      ==
    ::  execute this tool
    =/  tc  i.remaining
    %-  (slog leaf+"claw: tool {(trip name.tc)}" ~)
    =/  res=tool-result:tools
      =/  r=(each tool-result:tools tang)
        (mule |.((execute-tool:tools bowl name.tc arguments.tc brave-key is-owner local-llm-url)))
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
