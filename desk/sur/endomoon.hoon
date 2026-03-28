::  endomoon: types for in-process moon agent
::
::  enables a planet to operate a moon identity without running
::  a separate urbit process. the planet derives the moon's keys
::  from jael and handles packet encrypt/decrypt, presenting the
::  moon as a real network participant.
::
/-  d=channels
/-  g=groups
|%
::  $moon-config: endomoon configuration
::
+$  moon-config
  $:  =moon=ship              ::  the moon's @p (must be our earl)
      lyf=life                 ::  planet life used for key derivation
      enabled=?                ::  whether endomoon is active
  ==
::  --- kernel <-> endomoon api ---
::
::  raw blobs passed through the ames vane as passthrough.
::  vere accepts packets addressed to the registered endomoon
::  (--endomoon flag) and injects them as %moon-hear tasks.
::  outbound blobs go as %moon-send tasks.
::
+$  mohr-data  [=lane:ames blob=@]
+$  mosd-data  [=lane:ames blob=@]
::
::  --- endomoon peer state ---
::
::  simplified peer tracking. we only handle single-fragment
::  messages (sufficient for groups/chat which are <1kb).
::  no congestion control or fragment reassembly.
::
+$  peer-state
  $:  =ship                    ::  remote peer
      her-life=life            ::  their current life
      her-public-key=pass      ::  their public key
      sym-key=@                ::  derived ecdh shared secret
      ::  outbound flow tracking
      next-bone=bone           ::  next bone to allocate
      by-duct=(map @t bone)    ::  flow-key -> bone
      next-msg=(map bone @ud)  ::  per-bone next outbound msg num
      ::  inbound flow tracking
      last-acked=(map bone @ud)  ::  per-bone last message we acked
      ::  route
      =lane:ames               ::  last known lane for this peer
  ==
::
::  $plea-data: decoded application-level message from wire
::
+$  plea-data
  $:  =bone
      msg-num=@ud
      vane=@tas
      =path
      payload=*
  ==
::
::  --- endomoon -> claw events ---
::
::  emitted as facts on /events subscription path.
::  claw maps these directly to its existing msg-source types.
::
+$  moon-event
  $%  ::  dm received from a remote ship
      [%dm-received from=ship text=@t content=story:d]
      ::  dm reply in a thread
      [%dm-reply from=ship parent-id=[p=@p q=@da] text=@t content=story:d]
      ::  channel post (mention, reply, etc)
      [%channel-post =nest:d from=ship text=@t content=story:d]
      ::  thread reply
      [%channel-reply =nest:d from=ship parent=@da text=@t content=story:d]
      ::  group invitation
      [%group-invite from=ship group=flag:g]
      ::  status/error messages
      [%status msg=@t]
  ==
::
::  --- claw -> endomoon commands ---
::
::  poked with %endomoon-command mark.
::
+$  moon-command
  $%  ::  lifecycle
      [%enable =moon=ship]     ::  activate endomoon with this moon
      [%disable ~]             ::  deactivate
      ::  messaging
      [%send-dm to=ship text=@t]
      [%send-channel =nest:d text=@t]
      [%send-reply =nest:d parent=@da text=@t]
      ::  groups
      [%join-group =flag:g]
      [%leave-group =flag:g]
      [%accept-dm from=ship]
  ==
::
::  --- agent state ---
::
+$  endomoon-state
  $:  %0
      config=(unit moon-config)
      ::  moon crypto material (derived from jael on enable)
      moon-sec=ring            ::  tagged private key for ecdh
      moon-pub=pass            ::  tagged public key
      ::  per-peer protocol state
      peers=(map ship peer-state)
      ::  groups client state
      joined-groups=(set flag:g)
      joined-channels=(set nest:d)
      ::  dm state
      dm-accepted=(set ship)   ::  ships whose dm invitations we accepted
  ==
--
