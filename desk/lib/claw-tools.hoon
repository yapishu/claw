::  claw-tools: modular tool system for the claw agent
::
::  to add a new tool:
::  1. add its json definition to +tool-defs
::  2. add its execution case to +execute-tool
::  3. if async, add response parsing to +parse-tool-response
::
/-  claw
/-  ct=contacts
/-  chat
/-  channels
/-  story
/-  mcp
/+  *s3-client
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
      (tool-fn 'read_dm_history' 'Read recent DMs with a ship. Returns message IDs, authors, timestamps, and content.' (obj ~[['ship' (req-str 'Ship to read DM history with e.g. ~sampel-palnet')] ['count' (opt-str 'Number of messages (default 20)')]]))
      ::  MCP tools (call %mcp-server agent via Khan threads)
      (tool-fn 'local_mcp' 'Execute a local MCP server tool. ALWAYS call local_mcp_list first to get exact names. Requires the %mcp desk to be installed - use install_local_mcp if not present. Key tools: list-files, get-file, insert-file, build-file, scry (for agent scries), poke-our-agent, prod-hoon, commit-desk, mount-desk, install-app, nuke-agent, revive-agent.' (obj ~[['name' (req-str 'Exact MCP tool name from local_mcp_list')] ['arguments' (req-str 'JSON object of arguments as a string')]]))
      (tool-fn 'local_mcp_list' 'List all available local MCP server tools. Requires %mcp desk - use install_local_mcp if not present.' (obj ~))
      (tool-fn 'install_local_mcp' 'Install the %mcp desk from ~matwet. This enables local_mcp and local_mcp_list tools for file management, agent control, code execution, and more.' (obj ~))
      ::  LCM history tools
      (tool-fn 'search_history' 'Search compacted conversation history using text search. Searches across messages AND summaries stored by LCM. Returns matching snippets with IDs. Use to find specific content that may have been compacted away. Follow up with describe_summary for full details.' (obj ~[['query' (req-str 'Search terms or topic to find')]]))
      (tool-fn 'describe_summary' 'Look up full metadata and content for an LCM summary by ID. Returns: kind (leaf/condensed), depth, token count, descendant count, time range, source messages, parent summaries, and full content text. Use after search_history to inspect a specific summary.' (obj ~[['id' (req-str 'Summary ID number from search_history results')]]))
      (tool-fn 'list_conversations' 'List all LCM conversations with their message counts and summary counts. Shows which conversations have history available for searching.' (obj ~))
      ::  message management
      (tool-fn 'delete_message' 'Delete a message from a group channel by its timestamp ID.' (obj ~[['channel' (req-str 'Channel nest e.g. chat/~host/channel-name')] ['msg_id' (req-str 'Message timestamp ID')]]))
      (tool-fn 'edit_message' 'Edit a message in a group channel. Replaces the message content.' (obj ~[['channel' (req-str 'Channel nest')] ['msg_id' (req-str 'Message timestamp ID')] ['content' (req-str 'New message content')]]))
      (tool-fn 'delete_dm' 'Delete a direct message. Pass the id field from read_dm_history results (format: ~ship/number).' (obj ~[['ship' (req-str 'DM counterpart ship')] ['id' (req-str 'Message id from read_dm_history (e.g. ~fen/170.141...)')]]))


      ::  group management
      (tool-fn 'join_group' 'Join an Urbit group. Owner only.' (obj ~[['group' (req-str 'Group flag e.g. ~sampel/group-name')]]))
      (tool-fn 'leave_group' 'Leave an Urbit group. Owner only.' (obj ~[['group' (req-str 'Group flag e.g. ~sampel/group-name')]]))
      (tool-fn 'invite_to_group' 'Invite a ship to a group. Owner only.' (obj ~[['group' (req-str 'Group flag e.g. ~sampel/group-name')] ['ship' (req-str 'Ship to invite e.g. ~sampel-palnet')]]))
      (tool-fn 'kick_from_group' 'Remove a ship from a group. Owner only.' (obj ~[['group' (req-str 'Group flag e.g. ~sampel/group-name')] ['ship' (req-str 'Ship to remove')]]))
      ::  cron jobs
      (tool-fn 'cron_add' 'Schedule a recurring task using cron syntax. You will be given the prompt on the cron schedule and process it. Owner only. Cron format: "min hour dom month dow" where each field is: * (any), */N (every N), N (exact), N,M (list). dow: 0=Sun..6=Sat. Examples: "*/30 * * * *" (every 30min), "0 9 * * *" (daily 9am), "0 9 * * 1,3,5" (Mon/Wed/Fri 9am), "0 0 1 * *" (1st of month midnight).' (obj ~[['schedule' (req-str 'Cron expression (5 fields: min hour dom month dow)')] ['prompt' (req-str 'What to do each time (e.g. "Check the weather and summarize")')]]))
      (tool-fn 'cron_list' 'List all scheduled recurring tasks with IDs, prompts, and cron schedules.' (obj ~))
      (tool-fn 'cron_remove' 'Remove a scheduled recurring task by ID. Owner only.' (obj ~[['id' (req-str 'Task ID number')]]))
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
  ::  read_dm_history: read recent DMs with a ship
  ::
  ?:  =('read_dm_history' name)
    =,  dejs-soft:format
    =/  who=(unit @t)  ((ot ~[ship+so]) u.args)
    ?~  who  [%sync ~ 'error: ship required']
    =/  cnt=(unit @t)  ((ot ~[count+so]) u.args)
    =/  n=@ud  (fall (rush (fall cnt '20') dem) 20)
    =/  target=(unit @p)  (slaw %p u.who)
    ?~  target  [%sync ~ 'error: bad ship name']
    =/  result=(each @t tang)
      %-  mule  |.
      =/  history=json
        .^(json %gx /(scot %p our.bowl)/chat/(scot %da now.bowl)/dm/(scot %p u.target)/search/text/0/(scot %ud n)/e/json)
      (crip (scag 6.000 (trip (en:json:html history))))
    ?:  ?=(%| -.result)  [%sync ~ 'error: could not read DM history']
    [%sync ~ ?:(=('' p.result) 'no messages found' p.result)]
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
  ::  invite_to_group: invite a ship to a group (owner only)
  ::
  ?:  =('invite_to_group' name)
    ?.  owner  [%sync ~ 'error: only the owner can use this tool']
    =,  dejs:format
    =/  group-str=@t  ((ot ~[group+so]) u.args)
    =/  who=@t  ((ot ~[ship+so]) u.args)
    =/  parsed=(unit [host=@p name=@tas])  (parse-group-flag group-str)
    ?~  parsed  [%sync ~ 'error: bad group flag']
    =/  target=(unit @p)  (slaw %p who)
    ?~  target  [%sync ~ 'error: bad ship name']
    =/  grp=[p=ship q=@tas]  [host.u.parsed name.u.parsed]
    =/  invite-json=json
      %-  pairs:enjs:format
      :~  :-  'invite'
          %-  pairs:enjs:format
          :~  ['flag' s+group-str]
              ['ships' [%a ~[s+who]]]
              :-  'a-invite'
              %-  pairs:enjs:format
              :~  ['token' ~]
                  ['note' ~]
              ==
          ==
      ==
    [%sync :~([%pass /tool/invite %agent [our.bowl %groups] %poke %group-action-4 !>(invite-json)]) (rap 3 'invited ' who ' to ' group-str ~)]
  ::
  ::  kick_from_group: remove a ship from a group (owner only)
  ::
  ?:  =('kick_from_group' name)
    ?.  owner  [%sync ~ 'error: only the owner can use this tool']
    =,  dejs:format
    =/  group-str=@t  ((ot ~[group+so]) u.args)
    =/  who=@t  ((ot ~[ship+so]) u.args)
    =/  parsed=(unit [host=@p name=@tas])  (parse-group-flag group-str)
    ?~  parsed  [%sync ~ 'error: bad group flag']
    =/  target=(unit @p)  (slaw %p who)
    ?~  target  [%sync ~ 'error: bad ship name']
    =/  grp=[p=ship q=@tas]  [host.u.parsed name.u.parsed]
    =/  kick-json=json
      %-  pairs:enjs:format
      :~  :-  'group'
          %-  pairs:enjs:format
          :~  ['flag' s+group-str]
              :-  'a-group'
              %-  pairs:enjs:format
              :~  :-  'seat'
                  %-  pairs:enjs:format
                  :~  ['ships' [%a ~[s+who]]]
                      ['a-seat' (pairs:enjs:format ~[['del' ~]])]
                  ==
              ==
          ==
      ==
    [%sync :~([%pass /tool/kick %agent [our.bowl %groups] %poke %group-action-4 !>(kick-json)]) (rap 3 'removed ' who ' from ' group-str ~)]
  ::
  ::  delete_message: delete a channel message
  ::
  ?:  =('delete_message' name)
    =,  dejs:format
    =/  ch=@t  ((ot ~[channel+so]) u.args)
    =/  mid=@t  ((ot ~[['msg_id' so]]) u.args)
    =/  parsed-nest  (parse-nest ch)
    ?~  parsed-nest  [%sync ~ 'error: bad channel format']
    =/  msg-time=(unit @da)  (slaw %da mid)
    ?~  msg-time  [%sync ~ 'error: bad message ID']
    =/  =nest:channels  [kind.u.parsed-nest ship.u.parsed-nest name.u.parsed-nest]
    =/  act  [%channel nest [%post [%del u.msg-time]]]
    [%sync :~([%pass /tool/del-msg %agent [our.bowl %channels] %poke %channel-action-1 !>(act)]) 'message deleted']
  ::
  ::  edit_message: edit a channel message
  ::
  ?:  =('edit_message' name)
    =,  dejs:format
    =/  ch=@t  ((ot ~[channel+so]) u.args)
    =/  mid=@t  ((ot ~[['msg_id' so]]) u.args)
    =/  con=@t  ((ot ~[content+so]) u.args)
    =/  parsed-nest  (parse-nest ch)
    ?~  parsed-nest  [%sync ~ 'error: bad channel format']
    =/  msg-time=(unit @da)  (slaw %da mid)
    ?~  msg-time  [%sync ~ 'error: bad message ID']
    =/  =nest:channels  [kind.u.parsed-nest ship.u.parsed-nest name.u.parsed-nest]
    =/  ch-story=story:story  ~[[%inline `(list inline:story)`~[con]]]
    =/  ch-memo=memo:channels  [content=ch-story author=our.bowl sent=now.bowl]
    =/  ch-essay=essay:channels  [ch-memo /chat ~ ~]
    =/  act  [%channel nest [%post [%edit msg-time ch-essay]]]
    [%sync :~([%pass /tool/edit-msg %agent [our.bowl %channels] %poke %channel-action-1 !>(act)]) 'message edited']
  ::
  ::  delete_dm: delete a direct message
  ::
  ?:  =('delete_dm' name)
    =,  dejs-soft:format
    =/  who=(unit @t)  ((ot ~[ship+so]) u.args)
    =/  raw-id=(unit @t)  ((ot ~[id+so]) u.args)
    ?~  who  [%sync ~ 'error: ship required']
    ?~  raw-id  [%sync ~ 'error: id required']
    =/  counterpart=(unit @p)  (slaw %p u.who)
    ?~  counterpart  [%sync ~ 'error: bad ship']
    ::  parse id: "~ship/number.with.dots" → [author time]
    =/  parsed=(unit [p=@p q=@da])
      %-  mole  |.
      =/  id-tape=tape  (trip u.raw-id)
      =/  slash-pos=(unit @ud)  (find "/" id-tape)
      ?~  slash-pos  !!
      =/  author-str=@t  (crip (scag u.slash-pos id-tape))
      =/  time-str=tape  (slag +(u.slash-pos) id-tape)
      ::  strip dots from number
      =/  clean=tape  (skip time-str |=(c=@tD =(c '.')))
      =/  author=@p  (slav %p author-str)
      =/  time=@da  `@da`(rash (crip clean) dem)
      [author time]
    ?~  parsed  [%sync ~ 'error: bad id format (expected ~ship/number)']
    =/  dm-act  [u.counterpart u.parsed [%del ~]]
    [%sync :~([%pass /tool/del-dm %agent [our.bowl %chat] %poke %chat-dm-action-1 !>(dm-act)]) 'DM deleted']
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
  ::  cron_add: schedule a recurring task (owner only)
  ::
  ?:  =('cron_add' name)
    ?.  owner  [%sync ~ 'error: only the owner can schedule tasks']
    =,  dejs-soft:format
    =/  jsched=(unit @t)  ((ot ~[schedule+so]) u.args)
    =/  jprompt=(unit @t)  ((ot ~[prompt+so]) u.args)
    ?~  jsched   [%sync ~ 'error: schedule (cron expression) required']
    ?~  jprompt  [%sync ~ 'error: prompt required']
    [%sync :~([%pass /tool/cron-add %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%cron-add u.jsched u.jprompt])]) (rap 3 'Scheduled cron ' u.jsched ': ' (crip (scag 40 (trip u.jprompt))) ~)]
  ::
  ::  cron_list: list all cron jobs
  ::
  ?:  =('cron_list' name)
    =/  result=(each @t tang)
      %-  mule  |.
      =/  cj=json
        .^(json %gx /(scot %p our.bowl)/claw/(scot %da now.bowl)/cron-jobs/json)
      (crip (scag 4.000 (trip (en:json:html cj))))
    ?:  ?=(%| -.result)
      ::  fallback: scry failed, return empty
      [%sync ~ 'no cron jobs (or scry not available)']
    [%sync ~ p.result]
  ::
  ::  cron_remove: remove a cron job by ID (owner only)
  ::
  ?:  =('cron_remove' name)
    ?.  owner  [%sync ~ 'error: only the owner can remove cron jobs']
    =,  dejs-soft:format
    =/  jid=(unit @t)  ((ot ~[id+so]) u.args)
    ?~  jid  [%sync ~ 'error: id required']
    =/  cid=(unit @ud)  (rush u.jid dem)
    ?~  cid  [%sync ~ 'error: id must be a number']
    [%sync :~([%pass /tool/cron-remove %agent [our.bowl %claw] %poke %claw-action !>(`action:claw`[%cron-remove u.cid])]) (rap 3 'Removed cron job ' u.jid ~)]
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
::  +make-s3-put: build signed S3 PUT request
::    scries %storage for creds, delegates to s3-client library
::
++  make-s3-put
  |=  [=bowl:gall image-data=octs content-type=@t]
  ^-  (unit [=card url=@t])
  =/  cred-result=(each json tang)
    (mule |.(.^(json %gx /(scot %p our.bowl)/storage/(scot %da now.bowl)/credentials/json)))
  ?:  ?=(%| -.cred-result)  ~
  =/  conf-result=(each json tang)
    (mule |.(.^(json %gx /(scot %p our.bowl)/storage/(scot %da now.bowl)/configuration/json)))
  ?:  ?=(%| -.conf-result)  ~
  =/  creds=s3-creds  (scry-s3-creds p.cred-result p.conf-result)
  %-  (slog leaf+"claw: s3 uploading..." ~)
  (s3-presigned-put creds now.bowl image-data content-type)
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
