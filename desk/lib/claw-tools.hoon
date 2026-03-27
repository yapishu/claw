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
/-  mcp
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
      ::  channel message
      (tool-fn 'send_channel_message' 'Post a message in a group channel. Can include an image. Use the channel nest format like chat/~host/channel-name.' (obj ~[['channel' (req-str 'Channel nest e.g. chat/~host/channel-name')] ['message' (req-str 'Message text')] ['image_url' (opt-str 'Optional image URL')]]))
      ::  s3 upload
      (tool-fn 'upload_image' 'Download an image from a URL and upload it to S3 storage. Returns the permanent S3 URL. Use this when you want to ensure an image is permanently stored. Requires S3 credentials to be configured in the storage agent.' (obj ~[['url' (req-str 'Source image URL to download and upload')]]))
      ::  http fetch
      (tool-fn 'http_fetch' 'Fetch a URL and return its text content. Do NOT use on image/binary URLs.' (obj ~[['url' (req-str 'URL to fetch')]]))
      ::  reactions
      (tool-fn 'add_reaction' 'React to a message in a group channel with an emoji.' (obj ~[['channel' (req-str 'Channel nest e.g. chat/~host/channel-name')] ['msg_id' (req-str 'Message timestamp ID')] ['emoji' (req-str 'Emoji character e.g. a unicode emoji')]]))
      (tool-fn 'remove_reaction' 'Remove your reaction from a channel message.' (obj ~[['channel' (req-str 'Channel nest')] ['msg_id' (req-str 'Message timestamp ID')]]))
      ::  blocking
      (tool-fn 'block_ship' 'Block a ship from sending you direct messages.' (obj ~[['ship' (req-str 'Ship to block e.g. ~sampel-palnet')]]))
      (tool-fn 'unblock_ship' 'Unblock a previously blocked ship.' (obj ~[['ship' (req-str 'Ship to unblock')]]))
      ::  reading
      (tool-fn 'get_contact' 'Get profile information for a ship (nickname, avatar, bio).' (obj ~[['ship' (req-str 'Ship to look up')]]))
      (tool-fn 'list_groups' 'List all groups you have joined.' (obj ~))
      (tool-fn 'list_channels' 'List all channels across all groups.' (obj ~))
      ::  history
      (tool-fn 'read_channel_history' 'Read recent messages from a channel. Returns message IDs, authors, and content.' (obj ~[['channel' (req-str 'Channel nest e.g. chat/~host/channel-name')] ['count' (opt-str 'Number of messages (default 10)')]]))
      ::  MCP tools (call %mcp-server agent via Khan threads)
      (tool-fn 'local_mcp' 'Execute a local MCP server tool. ALWAYS call local_mcp_list first to get exact names. Requires the %mcp desk to be installed - use install_local_mcp if not present. Key tools: list-files, get-file, insert-file, build-file, scry (for agent scries), poke-our-agent, prod-hoon, commit-desk, mount-desk, install-app, nuke-agent, revive-agent.' (obj ~[['name' (req-str 'Exact MCP tool name from local_mcp_list')] ['arguments' (req-str 'JSON object of arguments as a string')]]))
      (tool-fn 'local_mcp_list' 'List all available local MCP server tools. Requires %mcp desk - use install_local_mcp if not present.' (obj ~))
      (tool-fn 'install_local_mcp' 'Install the %mcp desk from ~matwet. This enables local_mcp and local_mcp_list tools for file management, agent control, code execution, and more.' (obj ~))
      ::  LCM history tools
      (tool-fn 'search_history' 'Search compacted conversation history using text search. Searches across messages AND summaries stored by LCM. Returns matching snippets with IDs. Use to find specific content that may have been compacted away. Follow up with describe_summary for full details.' (obj ~[['query' (req-str 'Search terms or topic to find')]]))
      (tool-fn 'describe_summary' 'Look up full metadata and content for an LCM summary by ID. Returns: kind (leaf/condensed), depth, token count, descendant count, time range, source messages, parent summaries, and full content text. Use after search_history to inspect a specific summary.' (obj ~[['id' (req-str 'Summary ID number from search_history results')]]))
      (tool-fn 'list_conversations' 'List all LCM conversations with their message counts and summary counts. Shows which conversations have history available for searching.' (obj ~))
      ::  group management
      (tool-fn 'join_group' 'Join an Urbit group. Owner only.' (obj ~[['group' (req-str 'Group flag e.g. ~sampel/group-name')]]))
      (tool-fn 'leave_group' 'Leave an Urbit group. Owner only.' (obj ~[['group' (req-str 'Group flag e.g. ~sampel/group-name')]]))
  ==
::
::  +execute-tool: run a tool, returns sync result or async card
::
++  execute-tool
  |=  [=bowl:gall name=@t arguments=@t brave-key=@t owner=?]
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
  ::
  ::  send_channel_message: post in a group channel
  ::
  ?:  =('send_channel_message' name)
    =,  dejs-soft:format
    =/  ch=(unit @t)  ((ot ~[channel+so]) u.args)
    =/  m=(unit @t)  ((ot ~[message+so]) u.args)
    =/  img=(unit @t)  ((ot ~[['image_url' so]]) u.args)
    ?~  ch  [%sync ~ 'error: channel required']
    ?~  m  [%sync ~ 'error: message required']
    ::  parse nest string "chat/~host/name" by splitting on /
    =/  parsed=(unit [kind=@tas host=@p name=@tas])
      %-  mole  |.
      =/  parts=tape  (trip u.ch)
      =/  seg1  (scag (need (find "/" parts)) parts)
      =/  rest1  (slag +((need (find "/" parts))) parts)
      =/  seg2  (scag (need (find "/" rest1)) rest1)
      =/  seg3  (slag +((need (find "/" rest1))) rest1)
      [(crip seg1) (slav %p (crip seg2)) (crip seg3)]
    ?~  parsed  [%sync ~ 'error: bad channel format, use chat/~host/name']
    =/  knd=kind:channels
      ?+  kind.u.parsed  %chat
        %chat  %chat
        %diary  %diary
        %heap  %heap
      ==
    =/  =nest:channels  [knd host.u.parsed name.u.parsed]
    =/  verses=(list verse:story)
      ?~  img
        ~[[%inline `(list inline:story)`~[u.m]]]
      ^-  (list verse:story)
      :~  [%inline `(list inline:story)`~[u.m]]
          [%block `block:story`[%image src=u.img height=0 width=0 alt='']]
      ==
    =/  ch-memo=memo:channels  [content=verses author=our.bowl sent=now.bowl]
    =/  ch-essay=essay:channels  [ch-memo /chat ~ ~]
    =/  act=a-channels:channels  [%channel nest [%post [%add ch-essay]]]
    [%sync :~([%pass /tool/ch-msg %agent [our.bowl %channels] %poke %channel-action-1 !>(act)]) (rap 3 'posted in ' u.ch ?~(img '' ' with image') ~)]
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
  ::
  ::  add_reaction: react to channel message
  ::
  ?:  =('add_reaction' name)
    =,  dejs:format
    =/  ch=@t  ((ot ~[channel+so]) u.args)
    =/  mid=@t  ((ot ~[['msg_id' so]]) u.args)
    =/  emoji=@t  ((ot ~[emoji+so]) u.args)
    =/  parsed-nest  (parse-nest ch)
    ?~  parsed-nest  [%sync ~ 'error: bad channel format']
    =/  msg-time=@da  (slav %da mid)
    =/  act=a-channels:channels  [%channel u.parsed-nest [%post [%add-react msg-time our.bowl emoji]]]
    [%sync :~([%pass /tool/react %agent [our.bowl %channels] %poke %channel-action-1 !>(act)]) (rap 3 'reacted with ' emoji ~)]
  ::
  ::  remove_reaction
  ::
  ?:  =('remove_reaction' name)
    =,  dejs:format
    =/  ch=@t  ((ot ~[channel+so]) u.args)
    =/  mid=@t  ((ot ~[['msg_id' so]]) u.args)
    =/  parsed-nest  (parse-nest ch)
    ?~  parsed-nest  [%sync ~ 'error: bad channel format']
    =/  msg-time=@da  (slav %da mid)
    =/  act=a-channels:channels  [%channel u.parsed-nest [%post [%del-react msg-time our.bowl]]]
    [%sync :~([%pass /tool/unreact %agent [our.bowl %channels] %poke %channel-action-1 !>(act)]) 'reaction removed']
  ::
  ::  block_ship
  ::
  ?:  =('block_ship' name)
    =,  dejs:format
    =/  s=@t  ((ot ~[ship+so]) u.args)
    =/  target=ship  (slav %p s)
    [%sync :~([%pass /tool/block %agent [our.bowl %chat] %poke %chat-block-ship !>(target)]) (rap 3 'blocked ' s ~)]
  ::
  ::  unblock_ship
  ::
  ?:  =('unblock_ship' name)
    =,  dejs:format
    =/  s=@t  ((ot ~[ship+so]) u.args)
    =/  target=ship  (slav %p s)
    [%sync :~([%pass /tool/unblock %agent [our.bowl %chat] %poke %chat-unblock-ship !>(target)]) (rap 3 'unblocked ' s ~)]
  ::
  ::  get_contact: scry %contacts for profile info
  ::
  ?:  =('get_contact' name)
    =,  dejs:format
    =/  s=@t  ((ot ~[ship+so]) u.args)
    =/  target=ship  (slav %p s)
    =/  result=(each @t tang)
      %-  mule  |.
      =/  con=contact:ct
        .^(contact:ct %gx /(scot %p our.bowl)/contacts/(scot %da now.bowl)/v1/contact/(scot %p target)/contact-1)
      %-  crip
      %-  zing
      %+  turn  ~(tap by con)
      |=  [k=@tas v=value:ct]
      ^-  tape
      ?+  -.v  "{(trip k)}: (complex)\0a"
        %text  "{(trip k)}: {(trip p.v)}\0a"
        %look  "{(trip k)}: {(trip p.v)}\0a"
        %tint  "{(trip k)}: {(scow %ux p.v)}\0a"
        %ship  "{(trip k)}: {(scow %p p.v)}\0a"
        %numb  "{(trip k)}: {(a-co:co p.v)}\0a"
      ==
    ?:  ?=(%| -.result)  [%sync ~ 'error: could not fetch contact']
    [%sync ~ ?:(=('' p.result) 'no profile data found' p.result)]
  ::
  ::  list_groups: scry %groups
  ::
  ?:  =('list_groups' name)
    =/  result=(each @t tang)
      %-  mule  |.
      =/  groups-json=json
        .^(json %gx /(scot %p our.bowl)/groups/(scot %da now.bowl)/v2/groups/json)
      ::  just return raw json truncated for LLM to parse
      (crip (scag 4.000 (trip (en:json:html groups-json))))
    ?:  ?=(%| -.result)  [%sync ~ 'error: could not list groups']
    [%sync ~ p.result]
  ::
  ::  list_channels: scry %channels
  ::
  ?:  =('list_channels' name)
    =/  result=(each @t tang)
      %-  mule  |.
      =/  ch-json=json
        .^(json %gx /(scot %p our.bowl)/channels/(scot %da now.bowl)/v4/channels/json)
      (crip (scag 4.000 (trip (en:json:html ch-json))))
    ?:  ?=(%| -.result)  [%sync ~ 'error: could not list channels']
    [%sync ~ p.result]
  ::
  ::
  ::  read_channel_history: scry %channels for recent posts
  ::
  ?:  =('read_channel_history' name)
    =,  dejs-soft:format
    =/  ch=(unit @t)  ((ot ~[channel+so]) u.args)
    ?~  ch  [%sync ~ 'error: channel required']
    =/  cnt=(unit @t)  ((ot ~[count+so]) u.args)
    =/  n=@ud  (fall (rush (fall cnt '10') dem) 10)
    =/  parsed-nest  (parse-nest u.ch)
    ?~  parsed-nest  [%sync ~ 'error: bad channel format']
    =/  result=(each @t tang)
      %-  mule  |.
      =/  history=json
        .^(json %gx /(scot %p our.bowl)/channels/(scot %da now.bowl)/v4/(scot %tas kind.u.parsed-nest)/(scot %p ship.u.parsed-nest)/[name.u.parsed-nest]/posts/newest/(scot %ud n)/outline/json)
      (crip (scag 6.000 (trip (en:json:html history))))
    ?:  ?=(%| -.result)  [%sync ~ 'error: could not read channel history']
    [%sync ~ p.result]
  ::
  ::
  ::  install_local_mcp: install %mcp desk from ~matwet
  ::
  ?:  =('install_local_mcp' name)
    [%sync :~([%pass /tool/install-mcp %agent [our.bowl %hood] %poke %kiln-install !>([%mcp ~matwet %mcp])]) 'Installing %mcp desk from ~matwet. This may take a minute. Once installed, local_mcp and local_mcp_list tools will be available.']
  ::
  ::  mcp_list_tools: scry %mcp-server for available tools
  ::
  ?:  =('local_mcp_list' name)
    =/  result=(each @t tang)
      %-  mule  |.
      =/  tools-json=json
        .^(json %gx /(scot %p our.bowl)/mcp-server/(scot %da now.bowl)/tools/json)
      (crip (scag 6.000 (trip (en:json:html tools-json))))
    ?:  ?=(%| -.result)  [%sync ~ 'error: MCP server not available. Install the %mcp desk to enable MCP tools.']
    [%sync ~ p.result]
  ::
  ::  mcp_tool: build and execute an MCP tool via Khan
  ::
  ?:  =('local_mcp' name)
    =,  dejs:format
    =/  tool-name=@t  ((ot ~[name+so]) u.args)
    =/  args-str=@t  ((ot ~[arguments+so]) u.args)
    ::  parse arguments JSON into MCP argument map
    =/  args-json=(unit json)  (de:json:html args-str)
    ?~  args-json  [%sync ~ 'error: invalid arguments JSON']
    =/  args-map=(map name:parameter:tool:mcp argument:tool:mcp)
      ?+  u.args-json  *(map @t argument:tool:mcp)
          [%o *]
        %-  ~(run by p.u.args-json)
        |=  j=json
        ^-  argument:tool:mcp
        ?+  j  ~
          [%s *]  [%string p.j]
          [%n *]  [%number (rash p.j dem)]
          [%b *]  [%boolean p.j]
        ==
      ==
    ::  check if MCP desk and tool file exist before building
    =/  tool-path=path
      /(scot %p our.bowl)/mcp/(scot %da now.bowl)/fil/default/mcp/tools/[tool-name]/hoon
    =/  exists=?
      =/  check=(each ? tang)  (mule |.(.^(? %cu tool-path)))
      ?:(?=(%| -.check) %.n p.check)
    ?.  exists
      [%sync ~ (rap 3 'error: MCP tool "' tool-name '" not found. Use local_mcp_list to see available tools. Install %mcp desk if not present.' ~)]
    =/  build-result=(each tool:mcp tang)
      %-  mule  |.
      !<(tool:mcp .^(vase %ca tool-path))
    ?:  ?=(%| -.build-result)
      [%sync ~ (rap 3 'error: MCP tool "' tool-name '" failed to build.' ~)]
    =/  =tool:mcp  p.build-result
    ::  execute via Khan thread - wrap in mule to catch arg type mismatches
    =/  thread-result=(each shed:khan tang)
      %-  mule  |.
      (thread-builder.tool args-map)
    ?:  ?=(%| -.thread-result)
      [%sync ~ (rap 3 'error: MCP tool "' tool-name '" rejected arguments. Check argument types and names.' ~)]
    [%async [%pass /tool-http/'local-mcp' %arvo %k %lard %mcp p.thread-result]]
  ::
::
  ::  join_group: join an Urbit group (owner only)
  ::
  ?:  =('join_group' name)
    ?.  owner  [%sync ~ 'error: only the owner can use this tool']
    =,  dejs:format
    =/  group-str=@t  ((ot ~[group+so]) u.args)
    =/  parsed=(unit [host=@p name=@tas])  (parse-group-flag group-str)
    ?~  parsed  [%sync ~ 'error: bad group flag, use ~host/group-name']
    =/  grp=[p=ship q=@tas]  [host.u.parsed name.u.parsed]
    [%sync :~([%pass /tool/join-group %agent [our.bowl %groups] %poke %group-join !>([grp %.y])]) (rap 3 'joining group ' group-str ~)]
  ::
  ::  leave_group: leave an Urbit group (owner only)
  ::
  ?:  =('leave_group' name)
    ?.  owner  [%sync ~ 'error: only the owner can use this tool']
    =,  dejs:format
    =/  group-str=@t  ((ot ~[group+so]) u.args)
    =/  parsed=(unit [host=@p name=@tas])  (parse-group-flag group-str)
    ?~  parsed  [%sync ~ 'error: bad group flag, use ~host/group-name']
    =/  grp=[p=ship q=@tas]  [host.u.parsed name.u.parsed]
    [%sync :~([%pass /tool/leave-group %agent [our.bowl %groups] %poke %group-leave !>(grp)]) (rap 3 'leaving group ' group-str ~)]
  ::
  ::  search_history: search LCM conversation history
  ::
  ?:  =('search_history' name)
    =,  dejs-soft:format
    =/  query=(unit @t)  ((ot ~[query+so]) u.args)
    ?~  query  [%sync ~ 'error: query required']
    ::  search all conversations
    =/  result=(each @t tang)
      %-  mule  |.
      ::  get conversation list first
      =/  convs=json
        .^(json %gx /(scot %p our.bowl)/lcm/(scot %da now.bowl)/conversations/json)
      ?.  ?=([%a *] convs)  'no conversations'
      =/  all-results=tape  ~
      =/  items  p.convs
      |-
      ?~  items  (crip (scag 6.000 all-results))
      =/  conv-map=(map @t json)
        ?:(?=([%o *] i.items) p.i.items ~)
      =/  conv-key=@t
        =/  k  (~(get by conv-map) 'key')
        ?~(k '' ?:(?=([%s *] u.k) p.u.k ''))
      ?:  =('' conv-key)  $(items t.items)
      =/  hits=json
        .^(json %gx /(scot %p our.bowl)/lcm/(scot %da now.bowl)/grep/[conv-key]/[u.query]/json)
      ?.  ?=([%a *] hits)  $(items t.items)
      ?~  p.hits  $(items t.items)
      =/  section=tape
        (weld "--- conversation: {(trip conv-key)} ---\0a" (scag 2.000 (trip (en:json:html hits))))
      $(items t.items, all-results (weld all-results (weld section "\0a")))
    ?:  ?=(%| -.result)  [%sync ~ 'error: could not search history']
    [%sync ~ ?:(=('' p.result) 'no matches found' p.result)]
  ::
  ::  describe_summary: look up LCM summary details
  ::
  ?:  =('describe_summary' name)
    =,  dejs-soft:format
    =/  sid=(unit @t)  ((ot ~[id+so]) u.args)
    ?~  sid  [%sync ~ 'error: summary_id required']
    ::  search all conversations for this summary
    =/  result=(each @t tang)
      %-  mule  |.
      =/  convs=json
        .^(json %gx /(scot %p our.bowl)/lcm/(scot %da now.bowl)/conversations/json)
      ?.  ?=([%a *] convs)  'no conversations'
      =/  items  p.convs
      |-
      ?~  items  'summary not found'
      =/  conv-map=(map @t json)
        ?:(?=([%o *] i.items) p.i.items ~)
      =/  conv-key=@t
        =/  k  (~(get by conv-map) 'key')
        ?~(k '' ?:(?=([%s *] u.k) p.u.k ''))
      ?:  =('' conv-key)  $(items t.items)
      =/  desc=json
        .^(json %gx /(scot %p our.bowl)/lcm/(scot %da now.bowl)/describe/[conv-key]/[u.sid]/json)
      ?:  ?=(~ desc)  $(items t.items)
      (crip (scag 6.000 (trip (en:json:html desc))))
    ?:  ?=(%| -.result)  [%sync ~ 'error: could not describe summary']
    [%sync ~ p.result]
  ::
  ::  list_conversations: list all LCM conversations
  ::
  ?:  =('list_conversations' name)
    =/  result=(each @t tang)
      %-  mule  |.
      =/  convs=json
        .^(json %gx /(scot %p our.bowl)/lcm/(scot %da now.bowl)/conversations/json)
      (crip (scag 4.000 (trip (en:json:html convs))))
    ?:  ?=(%| -.result)  [%sync ~ 'error: could not list conversations']
    [%sync ~ p.result]
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
  ::  generate clean key with no ~ chars
  =/  key=@t  (rap 3 (scot %uv (sham now.bowl)) '.' ext ~)
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
  ::  sign only host (simple presigned URL), send ACL as unsigned header
  =/  signed-headers=@t  'host'
  =/  enc-cred=@t
    %-  crip  %-  zing
    %+  turn  (trip credential)
    |=(c=@t ^-(tape ?:(=('/' c) "%2F" [c ~])))
  =/  canonical-qs=@t
    %-  crip
    %+  join-s3  "&"
    :~  "X-Amz-Algorithm=AWS4-HMAC-SHA256"
        "X-Amz-Credential={(trip enc-cred)}"
        "X-Amz-Date={(trip amz-date)}"
        "X-Amz-Expires=3600"
        "X-Amz-SignedHeaders=host"
    ==
  =/  canon-headers=@t
    (crip "host:{(trip host)}\0a")
  =/  canonical-request=@t
    %-  crip
    %+  join-s3  "\0a"
    :~  "PUT"
        (trip (s3-uri-encode s3-path))
        (trip canonical-qs)
        (trip canon-headers)
        (trip signed-headers)
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
  %-  (slog leaf+"claw: s3 presigned={<presigned>}" ~)
  ::  PUT with headers matching signed headers
  =/  put-hed=(list [key=@t value=@t])
    :~  ['Content-Type' content-type]
        ['x-amz-acl' 'public-read']
    ==
  :-  ~
  :_  public-url
  [%pass /tool-http/'upload_put' %arvo %i %request [%'PUT' presigned put-hed `image-data] *outbound-config:iris]
::
::
::  s3 signing helpers (from s3-auth, inlined to avoid type issues)
::
::  manual HMAC-SHA256 using shay (since hmac-sha256l produces wrong results)
::  HMAC(K,m) = SHA256((K ^ opad) || SHA256((K ^ ipad) || m))
++  s3-hmac-sha256
  |=  [key=octs msg=octs]
  ^-  @
  =/  block-size=@ud  64
  ::  if key > block size, hash it first
  =/  k=@
    ?:  (gth p.key block-size)
      (shay p.key q.key)
    q.key
  =/  k-len=@ud  ?:((gth p.key block-size) 32 p.key)
  ::  pad key to block-size with zeros (already zero-padded in atom)
  ::  compute ipad-key and opad-key
  =/  ipad-key=@  (mix k (fil 3 block-size 0x36))
  =/  opad-key=@  (mix k (fil 3 block-size 0x5c))
  ::  inner hash: SHA256(ipad-key || msg)
  =/  inner-data=@  (cat 3 ipad-key q.msg)
  =/  inner-len=@ud  (add block-size p.msg)
  =/  inner-hash=@  (shay inner-len inner-data)
  ::  outer hash: SHA256(opad-key || inner-hash)
  =/  outer-data=@  (cat 3 opad-key inner-hash)
  =/  outer-len=@ud  (add block-size 32)
  (shay outer-len outer-data)
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
  (s3-hmac-sha256 [32 k-service] [(met 3 'aws4_request') 'aws4_request'])
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
::  +parse-nest: parse "chat/~host/name" into nest:channels
++  parse-nest
  |=  ch=@t
  ^-  (unit nest:channels)
  %-  mole  |.
  =/  parts=tape  (trip ch)
  =/  seg1  (scag (need (find "/" parts)) parts)
  =/  rest1  (slag +((need (find "/" parts))) parts)
  =/  seg2  (scag (need (find "/" rest1)) rest1)
  =/  seg3  (slag +((need (find "/" rest1))) rest1)
  =/  knd=kind:channels
    =/  k=@t  (crip seg1)
    ?+(k %chat %chat %chat, %diary %diary, %heap %heap)
  [knd (slav %p (crip seg2)) (crip seg3)]
::
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
::
::  +parse-group-flag: parse "~host/group-name" into [host name]
::
++  parse-group-flag
  |=  flag=@t
  ^-  (unit [host=@p name=@tas])
  %-  mole  |.
  =/  parts=tape  (trip flag)
  =/  idx=@ud  (need (find "/" parts))
  =/  host-str=tape  (scag idx parts)
  =/  name-str=tape  (slag +(idx) parts)
  [(slav %p (crip host-str)) (crip name-str)]
--
