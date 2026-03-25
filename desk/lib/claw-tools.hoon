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
    =/  url=@t  (rap 3 'https://api.search.brave.com/res/v1/web/search?q=' (crip (en-urlt:html (trip u.q))) '&count=' n ~)
    =/  hed=(list [key=@t value=@t])
      :~  ['Accept' 'application/json']
          ['X-Subscription-Token' brave-key]
      ==
    [%async [%pass /tool-http/web-search %arvo %i %request [%'GET' url hed ~] *outbound-config:iris]]
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
    =/  url=@t  (rap 3 'https://api.search.brave.com/res/v1/images/search?q=' (crip (en-urlt:html (trip u.q))) '&count=' n ~)
    =/  hed=(list [key=@t value=@t])
      :~  ['Accept' 'application/json']
          ['X-Subscription-Token' brave-key]
      ==
    [%async [%pass /tool-http/image-search %arvo %i %request [%'GET' url hed ~] *outbound-config:iris]]
  ::
  ::  http_fetch: async generic GET
  ::
  ?:  =('http_fetch' name)
    =,  dejs:format
    =/  url=@t  ((ot ~[url+so]) u.args)
    [%async [%pass /tool-http/fetch %arvo %i %request [%'GET' url ~ ~] *outbound-config:iris]]
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
    =/  jon=(unit json)  (de:json:html body)
    ?~  jon  'error: invalid json from brave'
    =/  results=(unit json)
      ?~  (me u.jon)  ~
      (~(get by (need (me u.jon))) 'web')
    ?~  results  'no web results found'
    =/  hits=(unit json)
      ?~  (me u.results)  ~
      (~(get by (need (me u.results))) 'results')
    ?~  hits  'no results found'
    ?.  ?=([%a *] u.hits)  'no results array'
    %-  crip
    %-  zing
    %+  turn  (scag 10 p.u.hits)
    |=  item=json
    =/  m=(unit (map @t json))  (me item)
    ?~  m  ~
    =/  title  (fall (bind (~(get by u.m) 'title') |=(j=json ?:(?=([%s *] j) (trip p.j) ""))) "")
    =/  url  (fall (bind (~(get by u.m) 'url') |=(j=json ?:(?=([%s *] j) (trip p.j) ""))) "")
    =/  desc  (fall (bind (~(get by u.m) 'description') |=(j=json ?:(?=([%s *] j) (trip p.j) ""))) "")
    "{title}\0a  {url}\0a  {desc}\0a\0a"
  ::
  ?:  =('image_search' name)
    =/  jon=(unit json)  (de:json:html body)
    ?~  jon  'error: invalid json from brave'
    =/  results=(unit json)
      ?~  (me u.jon)  ~
      (~(get by (need (me u.jon))) 'results')
    ?~  results  'no image results found'
    ?.  ?=([%a *] u.results)  'no results array'
    %-  crip
    %-  zing
    %+  turn  (scag 10 p.u.results)
    |=  item=json
    =/  m=(unit (map @t json))  (me item)
    ?~  m  ~
    =/  title  (fall (bind (~(get by u.m) 'title') |=(j=json ?:(?=([%s *] j) (trip p.j) ""))) "")
    =/  props  (bind (~(get by u.m) 'properties') |=(j=json (fall (me j) *(map @t json))))
    =/  img-url
      %-  fall  :_  ""
      ?~  props  (bind (~(get by u.m) 'url') |=(j=json ?:(?=([%s *] j) (trip p.j) "")))
      (bind (~(get by u.props) 'url') |=(j=json ?:(?=([%s *] j) (trip p.j) "")))
    =/  source  (fall (bind (~(get by u.m) 'source') |=(j=json ?:(?=([%s *] j) (trip p.j) ""))) "")
    "{title}\0a  Image: {img-url}\0a  Source: {source}\0a\0a"
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
