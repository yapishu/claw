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
::  s3-auth imported inline to avoid fire-core issues
::  only the functions we actually use
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
  :~  ::  profile
      (tool-fn 'update_profile' 'Update bot display name and/or avatar on Urbit.' (obj ~[['nickname' (opt-str 'New display name')] ['avatar' (opt-str 'Avatar image URL')]]))
      ::  messaging - text
      (tool-fn 'send_dm' 'Send a direct message to another Urbit ship. Can include an image.' (obj ~[['ship' (req-str 'Target ship e.g. ~sampel-palnet')] ['message' (req-str 'Message text')] ['image_url' (opt-str 'Optional image URL to attach')]]))
      ::  web search (POST - works with Iris)
      (tool-fn 'web_search' 'Search the web using Brave Search. Returns web results with titles, URLs, and descriptions.' (obj ~[['query' (req-str 'Search query')] ['count' (opt-str 'Number of results (1-10, default 5)')]]))
      ::  image search (GET with token in query string)
      (tool-fn 'image_search' 'Search for images using Brave Image Search. Returns image URLs. Use send_dm with image_url to send found images.' (obj ~[['query' (req-str 'Image search query')] ['count' (opt-str 'Number of results (1-10, default 5)')]]))
      ::  s3 upload
      (tool-fn 'upload_image' 'Download an image from a URL and upload it to S3 storage. Returns the permanent S3 URL. Use this when you want to ensure an image is permanently stored. Requires S3 credentials to be configured in the storage agent.' (obj ~[['url' (req-str 'Source image URL to download and upload')]]))
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
  ::  send_dm: poke %chat with optional image block
  ::
  ?:  =('send_dm' name)
    =,  dejs-soft:format
    =/  s=(unit @t)  ((ot ~[ship+so]) u.args)
    =/  m=(unit @t)  ((ot ~[message+so]) u.args)
    =/  img=(unit @t)  ((ot ~[['image_url' so]]) u.args)
    ?~  s  [%sync ~ 'error: ship required']
    ?~  m  [%sync ~ 'error: message required']
    =/  to=ship  (slav %p u.s)
    ::  build story: text paragraph + optional image block
    =/  verses=(list verse:story)
      ?~  img
        ~[[%inline `(list inline:story)`~[u.m]]]
      ^-  (list verse:story)
      :~  [%inline `(list inline:story)`~[u.m]]
          [%block `block:story`[%image src=u.img height=0 width=0 alt='']]
      ==
    =/  dm-memo=memo:channels  [content=verses author=our.bowl sent=now.bowl]
    =/  dm-essay=essay:chat  [dm-memo [%chat /] ~ ~]
    =/  dm-delta=delta:writs:chat  [%add dm-essay ~]
    =/  dm-diff=diff:writs:chat  [[our.bowl now.bowl] dm-delta]
    =/  dm-act=action:dm:chat  [to dm-diff]
    [%sync :~([%pass /tool/dm %agent [our.bowl %chat] %poke %chat-dm-action-1 !>(dm-act)]) (rap 3 'message sent to ' u.s ?~(img '' ' with image') ~)]
  ::
  ::  web_search: POST to brave (works with Iris)
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
    =/  hed=(list [key=@t value=@t])
      :~  ['Content-Type' 'application/json']
          ['Accept' 'application/json']
          ['X-Subscription-Token' brave-key]
      ==
    [%async [%pass /tool-http/'web_search' %arvo %i %request [%'POST' 'https://api.search.brave.com/res/v1/web/search' hed `(as-octs:mimes:html body-cord)] *outbound-config:iris]]
  ::
  ::  image_search: bare GET (no headers - token in query string)
  ::
  ?:  =('image_search' name)
    ?:  =('' brave-key)  [%sync ~ 'error: no brave api key configured']
    =,  dejs-soft:format
    =/  q=(unit @t)  ((ot ~[query+so]) u.args)
    ?~  q  [%sync ~ 'error: query required']
    =/  cnt=(unit @t)  ((ot ~[count+so]) u.args)
    =/  n=@t  (fall cnt '5')
    ::  use web search POST (image endpoint rejects our GET)
    ::  prefix query to bias toward image results
    =/  post-body=json
      (pairs:enjs:format ~[['q' s+(rap 3 u.q ' images pictures' ~)] ['count' (numb:enjs:format (fall (rush n dem) 5))]])
    =/  body-cord=@t  (en:json:html post-body)
    =/  hed=(list [key=@t value=@t])
      :~  ['Content-Type' 'application/json']
          ['Accept' 'application/json']
          ['X-Subscription-Token' brave-key]
      ==
    [%async [%pass /tool-http/'image_search' %arvo %i %request [%'POST' 'https://api.search.brave.com/res/v1/web/search' hed `(as-octs:mimes:html body-cord)] *outbound-config:iris]]
  ::
  ::  http_fetch: bare GET
  ::
  ::
  ::  upload_image: phase 1 - fetch image from source URL
  ::  phase 2 (S3 PUT) happens in +make-s3-put below
  ::
  ?:  =('upload_image' name)
    =,  dejs:format
    =/  url=@t  ((ot ~[url+so]) u.args)
    ::  scry storage for credentials
    =/  cred-result=(each json tang)
      (mule |.(.^(json %gx /(scot %p our.bowl)/storage/(scot %da now.bowl)/credentials/json)))
    ?:  ?=(%| -.cred-result)
      [%sync ~ 'error: no S3 credentials configured. set up storage in system preferences.']
    =/  conf-result=(each json tang)
      (mule |.(.^(json %gx /(scot %p our.bowl)/storage/(scot %da now.bowl)/configuration/json)))
    ?:  ?=(%| -.conf-result)
      [%sync ~ 'error: no S3 configuration found.']
    %-  (slog leaf+"claw: upload_image: fetching {(trip url)}" ~)
    ::  fetch the source image - bare GET
    [%async [%pass /tool-http/'upload_image' %arvo %i %request [%'GET' url ~ ~] *outbound-config:iris]]
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
  ::  return raw json/text truncated - llm extracts what it needs
  (crip (scag 6.000 (trip body)))
::
::  +make-s3-put: build signed S3 PUT request from fetched image data
::
::    returns [card s3-url] where card is the Iris PUT request
::    and s3-url is the final public URL of the uploaded object.
::
++  make-s3-put
  |=  [=bowl:gall image-data=octs content-type=@t]
  ^-  (unit [=card url=@t])
  ::  scry storage for creds and config
  =/  cred-result=(each json tang)
    (mule |.(.^(json %gx /(scot %p our.bowl)/storage/(scot %da now.bowl)/credentials/json)))
  ?:  ?=(%| -.cred-result)  ~
  =/  conf-result=(each json tang)
    (mule |.(.^(json %gx /(scot %p our.bowl)/storage/(scot %da now.bowl)/configuration/json)))
  ?:  ?=(%| -.conf-result)  ~
  ::  extract fields from json
  ::  response is {"storage-update":{"credentials":{...}}}
  =/  cred-map=(map @t json)
    =/  top=(unit (map @t json))  (me p.cred-result)
    ?~  top  *(map @t json)
    =/  su=(unit json)  (~(get by u.top) 'storage-update')
    ?~  su  *(map @t json)
    =/  su-map=(unit (map @t json))  (me u.su)
    ?~  su-map  *(map @t json)
    =/  cr=(unit json)  (~(get by u.su-map) 'credentials')
    ?~  cr  *(map @t json)
    (fall (me u.cr) *(map @t json))
  =/  conf-map=(map @t json)
    =/  top=(unit (map @t json))  (me p.conf-result)
    ?~  top  *(map @t json)
    =/  su=(unit json)  (~(get by u.top) 'storage-update')
    ?~  su  *(map @t json)
    =/  su-map=(unit (map @t json))  (me u.su)
    ?~  su-map  *(map @t json)
    =/  cr=(unit json)  (~(get by u.su-map) 'configuration')
    ?~  cr  *(map @t json)
    (fall (me u.cr) *(map @t json))
  =/  endpoint=@t     (fall (bind (~(get by cred-map) 'endpoint') |=(j=json ?:(?=([%s *] j) p.j ''))) '')
  =/  access-key=@t   (fall (bind (~(get by cred-map) 'accessKeyId') |=(j=json ?:(?=([%s *] j) p.j ''))) '')
  =/  secret-key=@t   (fall (bind (~(get by cred-map) 'secretAccessKey') |=(j=json ?:(?=([%s *] j) p.j ''))) '')
  =/  bucket=@t       (fall (bind (~(get by conf-map) 'currentBucket') |=(j=json ?:(?=([%s *] j) p.j ''))) '')
  =/  region=@t       (fall (bind (~(get by conf-map) 'region') |=(j=json ?:(?=([%s *] j) p.j ''))) '')
  =/  pub-base=@t     (fall (bind (~(get by conf-map) 'publicUrlBase') |=(j=json ?:(?=([%s *] j) p.j ''))) '')
  ?:  |(=('' access-key) =('' secret-key) =('' bucket))
    ~
  ::  generate unique key
  =/  ext=@t
    ?:  (test content-type 'image/png')  'png'
    ?:  (test content-type 'image/gif')  'gif'
    ?:  (test content-type 'image/webp')  'webp'
    'jpg'
  =/  key=@t  (rap 3 'claw/' (scot %da now.bowl) '.' ext ~)
  ::  compute date strings
  =/  d=date  (yore now.bowl)
  =/  pad
    |=  n=@ud
    ^-  tape
    ?:  (lth n 10)  "0{(a-co:co n)}"
    (a-co:co n)
  =/  date-str=@t
    %-  crip
    "{(a-co:co y.d)}{(pad m.d)}{(pad d.t.d)}"
  =/  amz-date=@t
    %-  crip
    "{(a-co:co y.d)}{(pad m.d)}{(pad d.t.d)}T{(pad h.t.d)}{(pad m.t.d)}{(pad s.t.d)}Z"
  ::  build s3 url
  ::  endpoint may be "https://ams3.digitaloceanspaces.com" (with protocol)
  ::  or "s3.us-east-1.amazonaws.com" (without protocol)
  =/  raw-host=@t
    ?:  !=('' endpoint)
      ::  strip https:// prefix if present
      =/  ep=tape  (trip endpoint)
      ?:  =("https://" (scag 8 ep))  (crip (slag 8 ep))
      ?:  =("http://" (scag 7 ep))  (crip (slag 7 ep))
      endpoint
    (rap 3 's3.' region '.amazonaws.com' ~)
  ::  path-style (matches aws cli presign format):
  ::  https://endpoint/bucket/key with Host: endpoint
  =/  host=@t  raw-host
  =/  s3-path=@t  (rap 3 '/' bucket '/' key ~)
  =/  s3-url=@t  (rap 3 'https://' host s3-path ~)
  =/  public-url=@t
    ?:  !=('' pub-base)  (rap 3 pub-base '/' key ~)
    s3-url
  ::  presigned URL: auth in query string, matches aws cli output exactly
  =/  scope=@t  (rap 3 date-str '/' region '/s3/aws4_request' ~)
  =/  credential=@t  (rap 3 access-key '/' scope ~)
  =/  signed-headers=@t  'host'
  ::  encode credential for query string (/ -> %2F)
  =/  enc-cred=@t
    %-  crip  %-  zing
    %+  turn  (trip credential)
    |=(c=@t ^-(tape ?:(=('/' c) "%2F" [c ~])))
  ::  canonical query string (alphabetically sorted, no signature)
  =/  canonical-qs=@t
    %-  crip
    %+  join-s3  "&"
    :~  "X-Amz-Algorithm=AWS4-HMAC-SHA256"
        "X-Amz-Credential={(trip enc-cred)}"
        "X-Amz-Date={(trip amz-date)}"
        "X-Amz-Expires=3600"
        "X-Amz-SignedHeaders=host"
    ==
  ::  canonical request
  =/  canon-headers=@t
    (crip "host:{(trip host)}\0a")
  =/  canonical-request=@t
    %-  crip
    %+  join-s3  "\0a"
    :~  "PUT"
        (trip (s3-uri-encode s3-path))
        (trip canonical-qs)
        (trip canon-headers)
        "host"
        "UNSIGNED-PAYLOAD"
    ==
  =/  canon-hash=@t
    (s3-hex (shay (met 3 canonical-request) canonical-request))
  =/  string-to-sign=@t
    %-  crip
    %+  join-s3  "\0a"
    :~  "AWS4-HMAC-SHA256"
        (trip amz-date)
        (trip scope)
        (trip canon-hash)
    ==
  =/  sk=@  (s3-signing-key secret-key date-str region 's3')
  =/  signature=@t
    (s3-hex (s3-hmac-sha256 [32 sk] [(met 3 string-to-sign) string-to-sign]))
  =/  presigned=@t
    (rap 3 s3-url '?' canonical-qs '&X-Amz-Signature=' signature ~)
  %-  (slog leaf+"claw: s3 uploading to {(trip public-url)}" ~)
  ::  PUT with no custom headers (auth is entirely in URL)
  ::  bucket is already public so no ACL needed
  :-  ~
  :_  public-url
  [%pass /tool-http/'upload_put' %arvo %i %request [%'PUT' presigned ~ `image-data] *outbound-config:iris]
::
::
::  s3 signing helpers (from s3-auth, inlined to avoid type issues)
::
++  s3-hmac-sha256
  |=  [key=octs msg=octs]
  ^-  @
  (hmac-sha256l:hmac:crypto key msg)
++  s3-hmac-sha256-cord
  |=  [key=@t msg=@t]
  ^-  @
  (s3-hmac-sha256 [(met 3 key) key] [(met 3 msg) msg])
++  s3-signing-key
  |=  [secret=@t date=@t region=@t service=@t]
  ^-  @
  =/  k-secret=@t  (rap 3 'AWS4' secret ~)
  =/  k-date=@  (s3-hmac-sha256-cord k-secret date)
  =/  k-region=@  (s3-hmac-sha256 [32 k-date] [(met 3 region) region])
  =/  k-service=@  (s3-hmac-sha256 [32 k-region] [(met 3 service) service])
  (s3-hmac-sha256 [32 k-service] 14 'aws4_request')
++  s3-hex
  |=  dat=@
  ^-  @t
  =/  out=tape
    =/  idx  0
    |-
    ?:  =(idx 32)  ~
    =/  byt=@  (cut 3 [idx 1] dat)
    =/  hi  (snag (rsh 0^4 byt) "0123456789abcdef")
    =/  lo  (snag (end 0^4 byt) "0123456789abcdef")
    :-  hi
    :-  lo
    $(idx +(idx))
  (crip out)
++  s3-uri-encode
  |=  =cord
  ^-  @t
  %-  crip
  %-  zing
  %+  turn  (trip cord)
  |=  c=@t
  ^-  tape
  ?:  ?|  &((gte c 'a') (lte c 'z'))
          &((gte c 'A') (lte c 'Z'))
          &((gte c '0') (lte c '9'))
          =(c '-')  =(c '.')  =(c '_')  =(c '~')  =(c '/')
      ==
    [c ~]
  =/  hi  (snag (rsh 0^4 c) "0123456789ABCDEF")
  =/  lo  (snag (end 0^4 c) "0123456789ABCDEF")
  ['%' hi lo ~]
++  join-s3
  |=  [sep=tape parts=(list tape)]
  ^-  tape
  ?~  parts  ~
  ?~  t.parts  i.parts
  (weld i.parts (weld sep $(parts t.parts)))
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
