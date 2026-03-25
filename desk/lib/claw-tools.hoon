::  claw-tools: modular tool system for the claw agent
::
::  to add a new tool:
::  1. add its json definition to +tool-defs
::  2. add its execution case to +execute-tool
::
/-  ct=contacts
/-  chat
/-  channels
/-  story
|%
+$  card  card:agent:gall
::
::  +tool-defs: json array of tool definitions for the openrouter api
::
++  tool-defs
  ^-  json
  :-  %a
  :~  (tool-fn 'update_profile' 'Update the bot display name and/or avatar on the Urbit network. Use this when asked to change nickname, name, or profile picture.' (obj ~[['nickname' (opt-str 'New display name')] ['avatar' (opt-str 'Avatar image URL')]]))
  ::
      (tool-fn 'send_dm' 'Send a direct message to another ship on the Urbit network.' (obj ~[['ship' (req-str 'Target ship, e.g. ~sampel-palnet')] ['message' (req-str 'Message text to send')]]))
  ==
::
::  +execute-tool: run a tool and return cards + result text
::
++  execute-tool
  |=  [=bowl:gall name=@t arguments=@t]
  ^-  [cards=(list card) result=@t]
  =/  args=(unit json)  (de:json:html arguments)
  ?~  args  [~ 'error: invalid json arguments']
  ?:  =('update_profile' name)
    =,  dejs-soft:format
    =/  nick=(unit @t)  ((ot ~[nickname+so]) u.args)
    =/  avatar=(unit @t)  ((ot ~[avatar+so]) u.args)
    =/  con=contact:ct
      =/  m=contact:ct  *contact:ct
      =?  m  ?=(^ nick)   (~(put by m) 'nickname' [%text u.nick])
      =?  m  ?=(^ avatar)  (~(put by m) 'avatar' [%look u.avatar])
      m
    ?:  =(~ con)  [~ 'error: no nickname or avatar provided']
    =/  act=action:ct  [%self con]
    =/  result=@t
      %+  rap  3
      :~  'profile updated'
          ?~(nick '' (rap 3 ' nickname=' u.nick ~))
          ?~(avatar '' ' avatar set')
      ==
    :_  result
    :~  [%pass /tool/update-profile %agent [our.bowl %contacts] %poke %contact-action-1 !>(act)]
    ==
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
    :_  (crip "message sent to {(trip s)}")
    :~  [%pass /tool/send-dm %agent [our.bowl %chat] %poke %chat-dm-action-1 !>(dm-act)]
    ==
  [~ (crip "error: unknown tool '{(trip name)}'")]
::
::  json builder helpers
::
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
