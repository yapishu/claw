::  claw: llm agent harness types
::
|%
::  a chat message
::
+$  msg  [role=@t content=@t]
::  permission levels for whitelisted ships
::
+$  ship-role  ?(%owner %allowed)
::  poke actions
::
+$  action
  $%  [%set-key key=@t]
      [%set-model model=@t]
      [%prompt content=@t]
      [%clear ~]
      ::  context management
      [%set-context field=@tas content=@t]
      [%append-context field=@tas content=@t]
      [%del-context field=@tas]
      ::  dm whitelist
      [%add-ship =ship role=ship-role]
      [%del-ship =ship]
  ==
::  subscription updates
::
+$  update
  $%  [%response =msg]
      [%error error=@t]
      [%pending ~]
      [%dm-response =ship =msg]
  ==
::  agent states
::
+$  state-0
  $:  %0
      api-key=@t
      model=@t
      system-prompt=@t
      history=(list msg)
      pending=?
      last-error=@t
  ==
::
+$  state-1
  $:  %1
      api-key=@t
      model=@t
      history=(list msg)
      pending=?
      last-error=@t
      context=(map @tas @t)
  ==
::
+$  state-2
  $:  %2
      api-key=@t
      model=@t
      ::  direct conversation (via poke)
      history=(list msg)
      pending=?
      last-error=@t
      ::  context files
      context=(map @tas @t)
      ::  dm integration
      whitelist=(map ship ship-role)
      dm-history=(map ship (list msg))
      dm-pending=(set ship)
  ==
::
+$  versioned-state
  $%  state-0
      state-1
      state-2
  ==
--
