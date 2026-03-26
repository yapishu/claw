::  claw: llm agent harness types
::
|%
+$  msg  [role=@t content=@t]
+$  ship-role  ?(%owner %allowed)
::
+$  action
  $%  [%set-key key=@t]
      [%set-model model=@t]
      [%set-brave-key key=@t]
      [%prompt content=@t]
      [%clear ~]
      [%set-context field=@tas content=@t]
      [%append-context field=@tas content=@t]
      [%del-context field=@tas]
      [%add-ship =ship role=ship-role]
      [%del-ship =ship]
  ==
::
+$  update
  $%  [%response =msg]
      [%error error=@t]
      [%pending ~]
      [%dm-response =ship =msg]
  ==
::
::  message source: where did the message come from
::
+$  msg-source
  $%  [%dm =ship]
      [%channel kind=?(%chat %diary %heap) host=@p name=@tas =ship]
      [%direct ~]
  ==
::
::  tool loop state for async tool execution
::
+$  tool-pending
  $:  =msg-source
      hist=(list msg)
      follow-msgs=(list json)
      pending=(list [id=@t name=@t arguments=@t])
  ==
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
+$  state-1
  $:  %1
      api-key=@t
      model=@t
      history=(list msg)
      pending=?
      last-error=@t
      context=(map @tas @t)
  ==
+$  state-2
  $:  %2
      api-key=@t
      model=@t
      history=(list msg)
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-history=(map ship (list msg))
      dm-pending=(set ship)
  ==
+$  state-3
  $:  %3
      api-key=@t
      brave-key=@t
      model=@t
      history=(list msg)
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-history=(map ship (list msg))
      dm-pending=(set ship)
      tool-loop=(unit tool-pending)
      pending-src=(map ship msg-source)
  ==
::
+$  versioned-state
  $%  state-0
      state-1
      state-2
      state-3
  ==
--
