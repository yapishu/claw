::  claw: minimal llm agent harness with groups dm integration
::
::  sends prompts to openrouter with full structured context.
::  watches %chat for dms from whitelisted ships, processes
::  them through the llm, and responds via dm.
::
/-  claw
/-  c=chat
/-  d=channels
/+  dbug, default-agent, server, tools=claw-tools
|%
+$  card  card:agent:gall
+$  versioned-state  $%(state-0:claw state-1:claw state-2:claw state-3:claw)
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
  |=  $:  =bowl:gall  api-key=@t  model=@t  sys-prompt=@t
          msgs=(list msg:claw)  =wire
          extra-msgs=(list json)  ::  tool-call follow-up messages
      ==
  ^-  card
  =/  api-msgs=json
    :-  %a
    %+  weld
      %+  turn  [['system' sys-prompt] msgs]
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
--
::
%-  agent:dbug
=|  state-3:claw
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
  :_  this(model 'anthropic/claude-sonnet-4', pending %.n, context default-ctx)
  :~  [%pass /eyre/connect %arvo %e %connect [`/apps/claw/api dap.bowl]]
  ==
::
++  on-save  !>(state)
::
++  on-load
  |=  =vase
  ^-  (quip card _this)
  =/  old  !<(versioned-state vase)
  ?-  -.old
      %3  `this(state old)
      %2
    `this(state [%3 api-key.old '' model.old history.old pending.old last-error.old context.old whitelist.old dm-history.old dm-pending.old ~])
      %1
    `this(state [%3 api-key.old '' model.old history.old pending.old last-error.old context.old ~ ~ ~ ~])
      %0
    =/  ctx=(map @tas @t)  *(map @tas @t)
    =?  ctx  !=('' system-prompt.old)
      (~(put by ctx) %agent system-prompt.old)
    `this(state [%3 api-key.old '' model.old history.old pending.old last-error.old ctx ~ ~ ~ ~])
  ==
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
        :-  %a
        %+  turn  history
        |=  =msg:claw
        (pairs:enjs:format ~[['role' s+role.msg] ['content' s+content.msg]])
      [[200 cors-headers] `(as-octs:mimes:html (en:json:html j))]
    ::
        [%dm-history @ ~]
      =/  who=ship  (slav %p i.t.api-path)
      =/  hist=(list msg:claw)  (fall (~(get by dm-history) who) ~)
      =/  j=json
        :-  %a
        %+  turn  hist
        |=  =msg:claw
        (pairs:enjs:format ~[['role' s+role.msg] ['content' s+content.msg]])
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
    `this(api-key key.act)
  ::
      %set-model
    %-  (slog leaf+"claw: model set to {(trip model.act)}" ~)
    `this(model model.act)
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
    :~  (make-llm-request bowl api-key model sys-prompt history /query ~)
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
        =.  dm-pending  (~(del in dm-pending) from)
        :_  this
        :~  (send-dm-card bowl from 'Sorry, I don\'t have an API key configured yet. My owner needs to set one up.')
        ==
      =/  sys-prompt=@t  (build-prompt bowl context)
      :_  this
      :~  (make-llm-request bowl api-key model sys-prompt hist /dm-query/(scot %p from) ~)
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
  |^
  ?+  wire  (on-arvo:def wire sign)
  ::
      [%eyre %connect ~]
    `this
  ::
      [%query ~]
    (handle-llm-response sign %direct ~ history)
  ::
      [%query-tools ~]
    (handle-llm-response sign %direct ~ history)
  ::
      [%dm-query @ ~]
    =/  who=ship  (slav %p i.t.wire)
    =/  hist=(list msg:claw)  (fall (~(get by dm-history) who) ~)
    (handle-llm-response sign [%dm who] `who hist)
  ::
      [%dm-query-tools @ ~]
    =/  who=ship  (slav %p i.t.wire)
    =/  hist=(list msg:claw)  (fall (~(get by dm-history) who) ~)
    (handle-llm-response sign [%dm who] `who hist)
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
    ::  find the call id for this tool
    =/  tc-id=@t
      =/  found  (skim pending.tl |=([id=@t n=@t a=@t] =(n tool-name)))
      ?~  found  'unknown'
      id.i.found
    =/  new-fmsgs=(list json)  (snoc follow-msgs.tl (tool-result-json tc-id result))
    =/  rest=(list [id=@t name=@t arguments=@t])
      ^-  (list [@t @t @t])
      (skip pending.tl |=([id=@t n=@t a=@t] =(n tool-name)))
    ::  if more pending, fire next
    ?^  rest
      =/  next  i.rest
      =/  res=tool-result:tools
        (execute-tool:tools bowl name.next arguments.next brave-key)
      ?.  ?=(%async -.res)
        =.  tool-loop  `[source.tl hist.tl (snoc new-fmsgs (tool-result-json id.next 'done')) t.rest]
        `this
      =.  tool-loop  `[source.tl hist.tl new-fmsgs t.rest]
      :_  this  [card.res]~
    ::  all done - fire llm follow-up
    =/  sys-prompt=@t  (build-prompt bowl context)
    =/  follow-wire=path
      ?:  ?=(%direct source.tl)  /query-tools
      /dm-query-tools/(scot %p ship.source.tl)
    :_  this(tool-loop ~)
    :~  (make-llm-request bowl api-key model sys-prompt hist.tl follow-wire new-fmsgs)
    ==
  ==
::
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
          source=?(%direct [%dm =ship])
          dm-who=(unit ship)
          hist=(list msg:claw)
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
    =?  pending  ?=(%direct source)  %.n
    =?  dm-pending  ?=([%dm *] source)  (~(del in dm-pending) ship.source)
    :_  this
    ?:  ?=(%direct source)
      :~  [%give %fact ~[/updates] %claw-update !>(`update:claw`[%error err])]  ==
    :~  (send-dm-card bowl ship.source 'Sorry, I hit an error talking to the LLM provider.')  ==
  ?~  full-file.resp
    =?  pending  ?=(%direct source)  %.n
    =?  dm-pending  ?=([%dm *] source)  (~(del in dm-pending) ship.source)
    `this
  =/  body=@t  q.data.u.full-file.resp
  =/  parsed  (parse-llm-response body)
  ?~  parsed
    %-  (slog leaf+"claw error: parse failed" ~)
    =.  last-error  body
    =?  pending  ?=(%direct source)  %.n
    =?  dm-pending  ?=([%dm *] source)  (~(del in dm-pending) ship.source)
    :_  this
    ?:  ?=(%direct source)  ~
    :~  (send-dm-card bowl ship.source 'Sorry, I had trouble understanding the response from my LLM provider.')  ==
  ::
  ?-  -.u.parsed
  ::
  ::  text response - deliver to user
  ::
      %text
    =/  content=@t  content.u.parsed
    =.  last-error  ''
    ?:  ?=(%direct source)
      =.  history  (snoc history ['assistant' content])
      =.  pending  %.n
      %-  (slog leaf+"< {(trip content)}" ~)
      :_  this
      :~  [%give %fact ~[/updates] %claw-update !>(`update:claw`[%response ['assistant' content]])]  ==
    ::  dm response - send back as dm
    =/  who  ship.source
    =.  dm-history  (~(put by dm-history) who (snoc hist ['assistant' content]))
    =.  dm-pending  (~(del in dm-pending) who)
    %-  (slog leaf+"claw dm to {(scow %p who)}: {(trip content)}" ~)
    :_  this
    :~  (send-dm-card bowl who content)
        [%give %fact ~[/updates] %claw-update !>(`update:claw`[%dm-response who ['assistant' content]])]
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
          (execute-tool:tools bowl name.first arguments.first brave-key)
        ?.  ?=(%async -.res)
          ::  shouldn't happen, but handle gracefully
          $(async-pending t.async-pending, follow-msgs (snoc follow-msgs (tool-result-json id.first 'unexpected sync')))
        =.  tool-loop
          `[source hist follow-msgs async-pending]
        :_  this
        (weld (flop tool-cards) [card.res]~)
      ::  all sync - fire llm follow-up immediately
      =/  sys-prompt=@t  (build-prompt bowl context)
      =/  follow-wire=path
        ?:  ?=(%direct source)  /query-tools
        /dm-query-tools/(scot %p ship.source)
      :_  this
      %+  weld  (flop tool-cards)
      :~  (make-llm-request bowl api-key model sys-prompt hist follow-wire follow-msgs)
      ==
    ::  execute this tool
    =/  tc  i.remaining
    %-  (slog leaf+"claw: tool {(trip name.tc)}" ~)
    =/  res=tool-result:tools
      (execute-tool:tools bowl name.tc arguments.tc brave-key)
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
