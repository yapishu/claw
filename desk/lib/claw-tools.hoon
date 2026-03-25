::  claw-tools: modular tool system for the claw agent
::
::  to add a new tool:
::  1. add its json definition to +tool-defs
::  2. add its execution case to +execute-tool
::  3. if async, add response parsing to +parse-tool-response
::
/-  ct=contacts
/-  chat
/-  channels
/-  story
|%
+$  card  card:agent:gall
::
+$  tool-result
  $%  [%sync cards=(list card) result=@t]
      [%async =card]
  ==
::
::  +tool-defs: tool definitions for the openrouter api
::
++  tool-defs
  ^-  json
  :-  %a
  :~  ::  profile management
      (tool-fn 'update_profile' 'Update bot display name and/or avatar on Urbit.' (obj ~[['nickname' (opt-str 'New display name')] ['avatar' (opt-str 'Avatar image URL')]]))
      ::  messaging
      (tool-fn 'send_dm' 'Send a direct message to another Urbit ship.' (obj ~[['ship' (req-str 'Target ship e.g. ~sampel-palnet')] ['message' (req-str 'Message text')]]))
      ::  web search
      (tool-fn 'web_search' 'Search the web using Brave Search. Returns titles, URLs, and descriptions.' (obj ~[['query' (req-str 'Search query')] ['count' (opt-str 'Number of results (1-10, default 5)')]]))
      ::  image search
      (tool-fn 'image_search' 'Search for images using Brave Image Search. Returns image URLs with metadata.' (obj ~[['query' (req-str 'Image search query')] ['count' (opt-str 'Number of results (1-10, default 5)')]]))
      ::  http fetch
      (tool-fn 'http_fetch' 'Fetch a URL and return its text content. Do NOT use on image/binary URLs.' (obj ~[['url' (req-str 'URL to fetch')]]))
  ==
::
::  +execute-tool: run a tool, returns sync result or async card
::
++  execute-tool
  |=  [=bowl:gall name=@t arguments=@t brave-key=@t]
  ^-  tool-result
  =/  args=(unit json)  (de:json:html arguments)
  ?~  args  [%sync ~ 'error: invalid json arguments']
  ::
  ::  update_profile: poke %contacts
  ::
  ?:  =('update_profile' name)
    =,  dejs-soft:format
    =/  nick=(unit @t)  ((ot ~[nickname+so]) u.args)
    =/  avatar=(unit @t)  ((ot ~[avatar+so]) u.args)
    =/  con=contact:ct
      =/  m=contact:ct  *contact:ct
      =?  m  ?=(^ nick)   (~(put by m) 'nickname' [%text u.nick])
      =?  m  ?=(^ avatar)  (~(put by m) 'avatar' [%look u.avatar])
      m
    ?:  =(~ con)  [%sync ~ 'error: no nickname or avatar provided']
    =/  act=action:ct  [%self con]
    =/  result=@t
      %+  rap  3
      :~  'profile updated'
          ?~(nick '' (rap 3 ' nickname=' u.nick ~))
          ?~(avatar '' ' avatar set')
      ==
    [%sync :~([%pass /tool/profile %agent [our.bowl %contacts] %poke %contact-action-1 !>(act)]) result]
  ::
  ::  send_dm: poke %chat
  ::
  ?:  =('send_dm' name)
    =,  dejs:format
    =/  [s=@t m=@t]  ((ot ~[ship+so message+so]) u.args)
    =/  to=ship  (slav %p s)
    =/  dm-story  `(list verse:story)`~[[%inline `(list inline:story)`~[m]]]
    =/  dm-memo=memo:channels  [content=dm-story author=our.bowl sent=now.bowl]
    =/  dm-essay=essay:chat  [dm-memo [%chat /] ~ ~]
    =/  dm-delta=delta:writs:chat  [%add dm-essay ~]
    =/  dm-diff=diff:writs:chat  [[our.bowl now.bowl] dm-delta]
    =/  dm-act=action:dm:chat  [to dm-diff]
    [%sync :~([%pass /tool/dm %agent [our.bowl %chat] %poke %chat-dm-action-1 !>(dm-act)]) (rap 3 'message sent to ' s ~)]
  ::
  ::  web_search: async brave search api
  ::
  ?:  =('web_search' name)
    ?:  =('' brave-key)  [%sync ~ 'error: no brave api key configured']
    =,  dejs-soft:format
    =/  q=(unit @t)  ((ot ~[query+so]) u.args)
    ?~  q  [%sync ~ 'error: query required']
    =/  cnt=(unit @t)  ((ot ~[count+so]) u.args)
    =/  n=@t  (fall cnt '5')
    =/  post-body=json
      (pairs:enjs:format ~[['q' s+u.q] ['count' (numb:enjs:format (fall (rush n dem) 5))]])
    =/  body-cord=@t  (en:json:html post-body)
    %-  (slog leaf+"claw: brave search: {(trip u.q)}" ~)
    =/  hed=(list [key=@t value=@t])
      :~  ['Content-Type' 'application/json']
          ['Accept' 'application/json']
          ['X-Subscription-Token' brave-key]
      ==
    =/  bod=(unit octs)  `(as-octs:mimes:html body-cord)
    [%async [%pass /tool-http/'web_search' %arvo %i %request [%'POST' 'https://api.search.brave.com/res/v1/web/search' hed bod] *outbound-config:iris]]
  ::
  ::  image_search: async brave image search
  ::
  ?:  =('image_search' name)
    ?:  =('' brave-key)  [%sync ~ 'error: no brave api key configured']
    =,  dejs-soft:format
    =/  q=(unit @t)  ((ot ~[query+so]) u.args)
    ?~  q  [%sync ~ 'error: query required']
    =/  cnt=(unit @t)  ((ot ~[count+so]) u.args)
    =/  n=@t  (fall cnt '5')
    =/  post-body=json
      (pairs:enjs:format ~[['q' s+u.q] ['count' (numb:enjs:format (fall (rush n dem) 5))]])
    =/  body-cord=@t  (en:json:html post-body)
    =/  hed=(list [key=@t value=@t])
      :~  ['Content-Type' 'application/json']
          ['Accept' 'application/json']
          ['X-Subscription-Token' brave-key]
      ==
    =/  bod=(unit octs)  `(as-octs:mimes:html body-cord)
    [%async [%pass /tool-http/'image_search' %arvo %i %request [%'POST' 'https://api.search.brave.com/res/v1/images/search' hed bod] *outbound-config:iris]]
  ::
  ::  http_fetch: async generic GET
  ::
  ?:  =('http_fetch' name)
    =,  dejs:format
    =/  url=@t  ((ot ~[url+so]) u.args)
    [%async [%pass /tool-http/'http_fetch' %arvo %i %request [%'GET' url ~ ~] *outbound-config:iris]]
  ::
  [%sync ~ (rap 3 'error: unknown tool ' name ~)]
::
::  +parse-tool-response: parse async tool http response
::
++  parse-tool-response
  |=  [name=@t body=@t]
  ^-  @t
  ::
  ?:  =('web_search' name)
    ::  return raw json truncated - llm can parse it
    (crip (scag 6.000 (trip body)))
  ::
  ?:  =('image_search' name)
    (crip (scag 6.000 (trip body)))
  ::
  ?:  =('http_fetch' name)
    ::  return raw body, truncated
    =/  body-tape  (trip body)
    (crip (scag 8.000 body-tape))
  ::
  body
::
::  helpers
::
++  me
  |=  =json
  ^-  (unit (map @t ^json))
  ?.  ?=([%o *] json)  ~
  `p.json
++  tool-fn
  |=  [name=@t desc=@t params=json]
  ^-  json
  %-  pairs:enjs:format
  :~  ['type' s+'function']
      :-  'function'
      %-  pairs:enjs:format
      :~  ['name' s+name]
          ['description' s+desc]
          ['parameters' params]
      ==
  ==
++  obj
  |=  props=(list [@t json])
  ^-  json
  %-  pairs:enjs:format
  :~  ['type' s+'object']
      ['properties' (pairs:enjs:format props)]
  ==
++  req-str
  |=  desc=@t
  ^-  json
  (pairs:enjs:format ~[['type' s+'string'] ['description' s+desc]])
++  opt-str
  |=  desc=@t
  ^-  json
  (pairs:enjs:format ~[['type' s+'string'] ['description' s+desc]])
--
