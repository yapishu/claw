::  endomoon: in-process moon agent
::
/-  endomoon
/-  c=chat
/-  d=channels
/-  g=groups
/+  default-agent, dbug, endomoon-crypto
/+  *story-parse
|%
+$  card  card:agent:gall
+$  state  endomoon-state:endomoon
--
::
%-  agent:dbug
=|  state=state
^-  agent:gall
|_  =bowl:gall
+*  this  .
    def  ~(. (default-agent this %.n) bowl)
    cry  endomoon-crypto
::
++  on-init
  ^-  (quip card _this)
  %-  (slog leaf+"endomoon: initialized (inactive)" ~)
  `this
::
++  on-save  !>(state)
::
++  on-load
  |=  =vase
  ^-  (quip card _this)
  =/  old  !<(endomoon-state:endomoon vase)
  `this(state old)
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  %-  (slog leaf+"endomoon: on-poke mark={<mark>}" ~)
  |^
  ?+  mark  (on-poke:def mark vase)
      %noun
    =/  noun  !<(* vase)
    %-  (slog leaf+"endomoon: noun is-mohr={<?=([%mohr *] noun)>}" ~)
    ?.  ?=([%mohr *] noun)
      %-  (slog leaf+"endomoon: not mohr, ignoring" ~)
      `this
    %-  (slog leaf+"endomoon: mohr matched" ~)
    =/  raw-pair=^  ;;(^ +.noun)
    =/  =lane:ames  ;;(lane:ames -.raw-pair)
    =/  blob=@  ;;(@ +.raw-pair)
    ::  try to decode blob as a raw local plea first (from ames on-plea intercept)
    ::  format: (jam [plea ship]) where plea = [vane path payload]
    =/  raw=(unit *)  (mole |.((cue blob)))
    ?:  ?&  ?=(^ raw)
            ?=([[@ * *] @] u.raw)
        ==
      =/  plea-noun=*  -.u.raw
      =/  from=ship  ;;(@p +.u.raw)
      =/  vane=@tas  ;;(@tas -.plea-noun)
      =/  payload=*  +>.plea-noun
      ::  payload is gall's ames-request-all: [%0 request]
      ::  where request is [%m mark noun] for pokes
      ?.  ?=([%0 %m @ *] payload)
        %-  (slog leaf+"endomoon: non-poke plea from {(scow %p from)}, skipping" ~)
        `this
      =/  poke-mark=@tas  ;;(@tas +>-.payload)
      =/  poke-data=*  +>+.payload
      %-  (slog leaf+"endomoon: poke from {(scow %p from)} mark={<poke-mark>}" ~)
      (handle-poke-plea from poke-mark poke-data)
    ::  otherwise try decrypting as an ames packet from the wire
    =/  hmh-result=(each (quip card _this) tang)
      (mule |.((handle-moon-hear lane blob)))
    ?:  ?=(%& -.hmh-result)
      %-  (slog leaf+"endomoon: handle-moon-hear ok, {<(lent -.p.hmh-result)>} cards" ~)
      p.hmh-result
    %-  (slog leaf+"endomoon: handle-moon-hear crashed:" ~)
    %-  (slog p.hmh-result)
    `this
  ::
      %endomoon-command
    =/  cmd=moon-command:endomoon  !<(moon-command:endomoon vase)
    (handle-command cmd)
  ==
  ::
  ++  handle-command
    |=  cmd=moon-command:endomoon
    ^-  (quip card _this)
    ?-  -.cmd
        %enable   (enable-moon moon-ship.cmd)
        %disable  (disable-moon ~)
        %send-dm  (send-dm to.cmd text.cmd)
        %send-channel  (send-channel-post nest.cmd text.cmd)
        %send-reply    (send-channel-reply nest.cmd parent.cmd text.cmd)
        %join-group    (join-group flag.cmd)
        %leave-group   (leave-group flag.cmd)
        %accept-dm     (accept-dm from.cmd)
    ==
  ::
  ++  enable-moon
    |=  =moon=ship
    ^-  (quip card _this)
    ?>  =(%earl (clan:title moon-ship))
    ?>  =(our.bowl (sein:title our.bowl now.bowl moon-ship))
    =/  [sec=ring pub=pass cub=acru:ames lyf=life]
      (derive-moon-keys:cry our.bowl now.bowl moon-ship)
    =/  cfg=moon-config:endomoon  [moon-ship lyf %.y]
    ::  walk sponsorship chain to find galaxy
    =/  galaxy=ship
      =/  s=ship  (sein:title our.bowl now.bowl moon-ship)
      |-
      ?:  =(%czar (clan:title s))  s
      $(s (sein:title our.bowl now.bowl s))
    ::  register moon's public key AND sponsor in jael
    ::  both are needed: keys for crypto, sponsor for route fallback
    =/  key-udiff=udiff:point:jael
      [[`@uxblockhash`0 `@udblocknumber`0] %keys [life=1 crypto-suite=1 pass=pub] boot=%.y]
    =/  spon-udiff=udiff:point:jael
      [[`@uxblockhash`0 `@udblocknumber`0] %spon `our.bowl]
    %-  (slog leaf+"endomoon: enabled {(scow %p moon-ship)}, registering in jael" ~)
    ::  clear peer cache entirely on re-enable so fresh bones are used
    :_  this(state state(config `cfg, moon-sec sec, moon-pub pub, peers ~))
    :~  [%pass /moon-jael-keys %arvo %j %moon moon-ship key-udiff]
        [%pass /moon-jael-spon %arvo %j %moon moon-ship spon-udiff]
    ==
  ::
  ++  disable-moon
    |=  ~
    ^-  (quip card _this)
    %-  (slog leaf+"endomoon: disabled" ~)
    `this(state state(config ~))
  ::
  ++  handle-moon-hear
    |=  [=lane:ames blob=@]
    ^-  (quip card _this)
    ?:  =(~ config.state)
      %-  (slog leaf+"endomoon: packet but not enabled" ~)
      `this
    =/  cfg=moon-config:endomoon  (need config.state)
    =/  result=(each shot:ames tang)
      (mule |.((sift-shot:cry blob)))
    ?:  ?=(%| -.result)
      %-  (slog leaf+"endomoon: bad shot" ~)
      `this
    =/  shot=shot:ames  p.result
    ?.  =(rcvr.shot moon-ship.cfg)
      `this
    ?:  =(content.shot `@`%keys)
      `this
    =^  peer=peer-state:endomoon  peers.state
      (ensure-peer sndr.shot lane)
    %-  (slog leaf+"endomoon: peer established, sym-key={<sym-key.peer>}" ~)
    %-  (slog leaf+"endomoon: shot sndr-tick={<sndr-tick.shot>} rcvr-tick={<rcvr-tick.shot>} req={<req.shot>}" ~)
    %-  (slog leaf+"endomoon: expected sndr-tick={<(mod her-life.peer 16)>} rcvr-tick={<(mod lyf.cfg 16)>}" ~)
    ::  step-by-step decrypt to find the crash
    =/  siv  (end 7 content.shot)
    =/  len  (end 4 (rsh 7 content.shot))
    =/  cyf  (rsh [3 18] content.shot)
    =/  vec  ~[sndr.shot rcvr.shot her-life.peer lyf.cfg]
    =/  aes-key=@  (shaz sym-key.peer)
    %-  (slog leaf+"endomoon: aes-key={<aes-key>} len={<len>}" ~)
    %-  (slog leaf+"endomoon: calling de:sivc" ~)
    =/  plain=(unit @)
      =/  core  ~(. sivc:aes:crypto aes-key vec)
      (de:core siv len cyf)
    ?~  plain
      %-  (slog leaf+"endomoon: AES decrypt returned ~, wrong key!" ~)
      `this
    %-  (slog leaf+"endomoon: AES decrypt ok, cue-ing" ~)
    =/  decrypted=(unit [bone:ames message-num:ames shut-meat:endomoon-crypto])
      (mole |.(;;([bone:ames message-num:ames shut-meat:endomoon-crypto] (cue u.plain))))
    ?~  decrypted
      %-  (slog leaf+"endomoon: decrypt failed from {(scow %p sndr.shot)}" ~)
      `this
    =/  [=bone:ames msg-num=message-num:ames meat=shut-meat:endomoon-crypto]
      u.decrypted
    =.  lane.peer  lane
    =.  peers.state  (~(put by peers.state) sndr.shot peer)
    ?:  ?=(%| -.meat)
      `this
    =/  plea=(unit [vane=@tas =path payload=*])
      (decode-plea:cry bone msg-num meat)
    ?~  plea
      %-  (slog leaf+"endomoon: failed to decode plea from {(scow %p sndr.shot)}" ~)
      `this
    ::  send ack back to sender
    =/  ack-cards=(list card)
      (make-and-send-ack sndr.shot peer bone msg-num)
    =.  last-acked.peer  (~(put by last-acked.peer) bone msg-num)
    =.  peers.state  (~(put by peers.state) sndr.shot peer)
    ::  only handle gall pleas
    ?.  =(vane.u.plea %g)
      %-  (slog leaf+"endomoon: non-gall plea vane={<vane.u.plea>} from {(scow %p sndr.shot)}" ~)
      :_  this  ack-cards
    ::  gall plea payload is ames-request-all: [%0 request]
    =/  gall-payload=*  payload.u.plea
    ?.  ?=([%0 *] gall-payload)
      %-  (slog leaf+"endomoon: unknown gall format from {(scow %p sndr.shot)}" ~)
      :_  this  ack-cards
    =/  request=*  +.gall-payload
    ?+  -.request
      %-  (slog leaf+"endomoon: unhandled request type {<-.request>} from {(scow %p sndr.shot)}" ~)
      :_  this  ack-cards
    ::  %m = poke (mark + data)
        %m
      =/  poke-mark=@tas  ;;(@tas +<.request)
      =/  poke-data=*  +>.request
      %-  (slog leaf+"endomoon: remote poke from {(scow %p sndr.shot)} mark={<poke-mark>}" ~)
      =/  res=(quip card _this)  (handle-poke-plea sndr.shot poke-mark poke-data)
      :_  +.res
      (weld ack-cards -.res)
    ::  %s = watch (subscribe to path)
        %s
      %-  (slog leaf+"endomoon: watch request from {(scow %p sndr.shot)}" ~)
      ::  TODO: handle subscription requests
      :_  this  ack-cards
    ::  %u = leave (unsubscribe)
        %u
      %-  (slog leaf+"endomoon: leave from {(scow %p sndr.shot)}" ~)
      :_  this  ack-cards
    ==
  ::
  ++  ensure-peer
    |=  [who=ship =lane:ames]
    ^-  [peer-state:endomoon (map ship peer-state:endomoon)]
    =/  existing  (~(get by peers.state) who)
    ?^  existing  [u.existing peers.state]
    ::  get their public key from ames peer-state (works on fakeships)
    ::  falls back to jael if ames doesn't know them
    =/  her-pub=(unit @)
      =/  result=(each * tang)
        %-  mule  |.
        .^(* %ax /(scot %p our.bowl)/$/(scot %da now.bowl)/peers/(scot %p who))
      ?:  ?=(%| -.result)
        %-  (slog leaf+"endomoon: ames scry failed for {(scow %p who)}" ~)
        ~
      ::  ship-state: [%known [sym-key life rift pub-key sponsor] ...]
      ::  pub-key is 4th element of the inner tuple
      ?.  ?=([%known *] p.result)
        %-  (slog leaf+"endomoon: peer {(scow %p who)} not known in ames" ~)
        ~
      ::  peer-state: [%known [sym life rift pub spon] route qos ...]
      ::  just grab the public-key by scrying the specific path
      =/  pk-result=(each * tang)
        %-  mule  |.
        =/  ps  .^(* %ax /(scot %p our.bowl)/$/(scot %da now.bowl)/peers/(scot %p who))
        ::  [%known [sym life rift pub spon] ...]
        ::  pub-key is public-key:ames which is @uwpublickey
        =/  inner=*  -.+.ps  ::  [sym life rift pub spon]
        =/  sym=*  -.inner
        =/  r1=*   +.inner   ::  [life rift pub spon]
        =/  r2=*   +.r1      ::  [rift pub spon]
        =/  r3=*   +.r2      ::  [pub spon]
        -.r3                  ::  pub
      ?:  ?=(%| -.pk-result)
        %-  (slog leaf+"endomoon: failed to extract pub key for {(scow %p who)}" ~)
        ~
      ?@  p.pk-result
        %-  (slog leaf+"endomoon: got pub key (atom) for {(scow %p who)}" ~)
        (some p.pk-result)
      %-  (slog leaf+"endomoon: pub key is CELL for {(scow %p who)}, head={<-.p.pk-result>}" ~)
      ~
    =/  her-lyf=life  1
    ?~  her-pub
      %-  (slog leaf+"endomoon: no key for {(scow %p who)}, will retry" ~)
      =/  peer=peer-state:endomoon  [who 1 *pass 0 (mul 4 (mod (mug now.bowl) 1.000)) ~ ~ ~ lane]
      [peer peers.state]
    =/  sym=@  (derive-symmetric-key:cry `pass`u.her-pub moon-sec.state)
    =/  peer=peer-state:endomoon  [who her-lyf `pass`u.her-pub sym (mul 4 (mod (mug now.bowl) 1.000)) ~ ~ ~ lane]
    [peer (~(put by peers.state) who peer)]
  ::
  ++  make-and-send-ack
    |=  [to=ship =peer-state:endomoon =bone:ames msg-num=@ud]
    ^-  (list card)
    ?~  config.state  ~
    =/  [ab=bone:ames an=message-num:ames am=shut-meat:endomoon-crypto]
      (make-ack-shut-packet:cry bone msg-num %.y)
    =/  as=shot:ames
      (encrypt-shut-packet:cry ab an am sym-key.peer-state moon-ship.u.config.state ship.peer-state lyf.u.config.state her-life.peer-state)
    :~  [%pass /moon-send/ack %arvo %a %mosd lane.peer-state (etch-shot:cry as)]
    ==
  ::
  ++  route-plea
    |=  [from=ship vane=@tas =path payload=*]
    ^-  (list card)
    ?.  =(vane %g)  ~
    =/  result=(each (list card) tang)
      (mule |.((decode-payload from payload)))
    ?:(?=(%| -.result) ~ p.result)
  ::
  ++  handle-poke-plea
    |=  [from=ship poke-mark=@tas poke-data=*]
    ^-  (quip card _this)
    ?+  poke-mark
      %-  (slog leaf+"endomoon: unhandled mark {<poke-mark>}" ~)
      `this
    ::
        %helm-hi
      %-  (slog leaf+"endomoon: hi from {(scow %p from)}" ~)
      `this
    ::
        ?(%chat-dm-action-1 %chat-dm-diff-1)
      %-  (slog leaf+"endomoon: DM poke from {(scow %p from)}" ~)
      ::  debug: log the shape of poke-data so we can see the type
      %-  (slog leaf+"endomoon: data shape: {<`*`[-.poke-data -.+.poke-data]>}" ~)
      =/  diff=(each diff:writs:c tang)  (mule |.(;;(diff:writs:c poke-data)))
      ?.  ?=(%& -.diff)
        =/  act=(each action:dm:c tang)  (mule |.(;;(action:dm:c poke-data)))
        ?.  ?=(%& -.act)
          %-  (slog leaf+"endomoon: cast failed for both diff and action" ~)
          `this
        %-  (slog leaf+"endomoon: cast as action:dm ok" ~)
        =/  =memo:d  ;;(memo:d -.-.+.p.act)
        =/  text=@t  (story-to-text content.memo)
        ?:  =('' text)  `this
        %-  (slog leaf+"endomoon: DM text: {(trip text)}" ~)
        :_  this
        :~  [%give %fact ~[/events] %endomoon-event !>(`moon-event:endomoon`[%dm-received from text (text-to-story text)])]
        ==
      %-  (slog leaf+"endomoon: cast as diff:writs ok" ~)
      ?.  ?=([* [%add *]] p.diff)
        %-  (slog leaf+"endomoon: diff not an %add" ~)
        `this
      %-  (slog leaf+"endomoon: delta is %add, extracting text" ~)
      ::  diff:writs = [id delta], delta = [%add essay seal]
      ::  essay = [memo kind-data quips seals]
      ::  just grab content from the raw noun
      =/  delta=*  +.p.diff
      =/  essay=*  +<.delta         ::  first arg after %add tag
      =/  content=*  -<.essay       ::  memo is head of essay, content is head of memo
      =/  text=@t
        =/  result=(each @t tang)
          %-  mule  |.
          (story-to-text ;;((list verse:d) content))
        ?:(?=(%| -.result) '' p.result)
      ?:  =('' text)  `this
      %-  (slog leaf+"endomoon: DM text: {(trip text)}, emitting event" ~)
      :_  this
      :~  [%give %fact ~[/events] %endomoon-event !>(`moon-event:endomoon`[%dm-received from text (text-to-story text)])]
      ==
    ==
  ::
  ++  decode-payload
    |=  [from=ship payload=*]
    ^-  (list card)
    =/  result=(each [@tas *] tang)
      (mule |.((extract-poke payload)))
    ?:  ?=(%| -.result)  ~
    =/  [poke-mark=@tas poke-data=*]  p.result
    ?+  poke-mark  ~
        %chat-dm-diff-1
      =/  act=(each action:dm:c tang)  (mule |.(;;(action:dm:c poke-data)))
      ?:  ?=(%| -.act)  ~
      =/  text=(unit @t)  (get-dm-text p.act)
      ?~  text  ~
      :~  [%give %fact ~[/events] %endomoon-event !>(`moon-event:endomoon`[%dm-received from u.text (text-to-story u.text)])]
      ==
        %chat-dm-rsvp  ~
        %channel-update  ~
    ==
  ::
  ++  extract-poke
    |=  payload=*
    ^-  [@tas *]
    ::  try to find [%poke mark data] at various nesting depths
    ?:  ?=([%poke @ *] payload)
      [`@tas`+<.payload +>.payload]
    ?:  ?=([@ %poke @ *] payload)
      [`@tas`+<+.payload +>+.payload]
    ?:  ?=([* @ %poke @ *] payload)
      [`@tas`+<+>.payload +>+>.payload]
    !!
  ::
  ++  get-dm-text
    |=  act=action:dm:c
    ^-  (unit @t)
    =/  diff=diff:writs:c  +.act
    ?.  ?=([* [%add *]] diff)  ~
    =/  =essay:c  ;;(essay:c +>.diff)
    =/  =memo:d  ;;(memo:d -.essay)
    =/  =story:d  content.memo
    =/  parts=(list @t)
      %+  turn  story
      |=  =verse:d
      ?-  -.verse
          %block  ''
          %inline
        %+  roll  p.verse
        |=  [=inline:d acc=@t]
        =/  chunk=@t
          ?@  inline  inline
          ?+  -.inline  ''
            %ship  (scot %p p.inline)
          ==
        (rap 3 acc chunk ~)
      ==
    `(rap 3 (join ' ' parts))
  ::
  ++  send-as-moon
    |=  [to=ship vane=@tas =path payload=*]
    ^-  (quip card _this)
    ?~  config.state  `this
    =^  peer=peer-state:endomoon  peers.state
      =/  existing  (~(get by peers.state) to)
      ?^  existing  [u.existing peers.state]
      (ensure-peer to [%.y `@pC`(sein:title our.bowl now.bowl to)])
    ?:  =(0 sym-key.peer)
      %-  (slog leaf+"endomoon: no key for {(scow %p to)}" ~)
      `this
    =/  flow-key=@t  (crip "{(scow %p to)}/{(trip vane)}")
    =/  =bone:ames
      =/  existing  (~(get by by-duct.peer) flow-key)
      ?^  existing  u.existing
      next-bone.peer
    =?  by-duct.peer  !(~(has by by-duct.peer) flow-key)
      (~(put by by-duct.peer) flow-key bone)
    =?  next-bone.peer  !(~(has by by-duct.peer) flow-key)
      (add next-bone.peer 4)
    =/  msg-num=@ud  (~(gut by next-msg.peer) bone 1)
    =.  next-msg.peer  (~(put by next-msg.peer) bone +(msg-num))
    %-  (slog leaf+"endomoon: send-as-moon bone={<bone>} msg={<msg-num>} to={<to>} lane={<lane.peer>}" ~)
    =/  [sb=bone:ames sn=message-num:ames sm=shut-meat:endomoon-crypto]
      (make-plea-shut-packet:cry bone msg-num vane path payload)
    %-  (slog leaf+"endomoon: encrypting sym={<sym-key.peer>}" ~)
    =/  os=shot:ames
      (encrypt-shut-packet:cry sb sn sm sym-key.peer moon-ship.u.config.state to lyf.u.config.state her-life.peer)
    %-  (slog leaf+"endomoon: encrypted, sending via mosd" ~)
    =.  peers.state  (~(put by peers.state) to peer)
    :_  this
    :~  [%pass /moon-send/plea %arvo %a %mosd lane.peer (etch-shot:cry os)]
    ==
  ::
  ++  send-dm
    |=  [to=ship text=@t]
    ^-  (quip card _this)
    ?~  config.state  `this
    =/  dm-story=story:d  ~[[%inline ~[text]]]
    =/  dm-memo=memo:d  [content=dm-story author=moon-ship.u.config.state sent=now.bowl]
    =/  dm-essay=essay:c  [dm-memo [%chat /] ~ ~]
    =/  dm-delta=delta:writs:c  [%add dm-essay ~]
    =/  dm-diff=diff:writs:c  [[moon-ship.u.config.state now.bowl] dm-delta]
    =/  dm-act=action:dm:c  [to dm-diff]
    %-  (slog leaf+"endomoon: sending DM to {(scow %p to)}" ~)
    ::  for local targets, poke their %chat directly with the diff
    ::  (ames crypto path won't work for local since planet doesn't
    ::  have the moon registered as an ames peer)
    ?:  =(to our.bowl)
      %-  (slog leaf+"endomoon: local DM+RSVP as {(scow %p moon-ship.u.config.state)}" ~)
      :_  this
      :~  [%pass /endo-rsvp/(scot %p to) %arvo %a %emlc moon-ship.u.config.state %chat %chat-dm-rsvp (jam [moon-ship.u.config.state %.y])]
          [%pass /endo-dm/(scot %p to) %arvo %a %emlc moon-ship.u.config.state %chat %chat-dm-diff-1 (jam dm-diff)]
      ==
    ::  for remote targets, route through ames's real crypto via %mosd
    =^  peer=peer-state:endomoon  peers.state
      =/  existing  (~(get by peers.state) to)
      ?^  existing  [u.existing peers.state]
      (ensure-peer to [%.y `@pC`(sein:title our.bowl now.bowl to)])
    ::  always send RSVP first, then DM
    =/  rsvp-bone=bone:ames  next-bone.peer
    =/  rsvp-num=@ud  (~(gut by next-msg.peer) rsvp-bone 1)
    =.  next-msg.peer  (~(put by next-msg.peer) rsvp-bone +(rsvp-num))
    ::  allocate a NEW bone for the DM (bone+4)
    =/  dm-bone=bone:ames  (add rsvp-bone 4)
    =/  dm-num=@ud  (~(gut by next-msg.peer) dm-bone 1)
    =.  next-msg.peer  (~(put by next-msg.peer) dm-bone +(dm-num))
    =.  next-bone.peer  (add dm-bone 4)
    =.  peers.state  (~(put by peers.state) to peer)
    ::  RSVP: accept the DM conversation
    ::  RSVP: accept the DM conversation
    =/  hi-plea=@  (jam [%plea %g %ge %chat ~ [%0 %m %chat-dm-rsvp [moon-ship.u.config.state %.y]]])
    ::  DM content — plea noun FLAT: [%plea vane path-elem... ~ payload]
    =/  dm-plea=@  (jam [%plea %g %ge %chat ~ [%0 %m %chat-dm-diff-1 dm-diff]])
    =/  dm-blob=@  (jam [%endo moon-ship.u.config.state to dm-bone dm-num dm-plea])
    =/  hi-blob=@  (jam [%endo moon-ship.u.config.state to rsvp-bone rsvp-num hi-plea])
    %-  (slog leaf+"endomoon: sending HI+DM to {(scow %p to)}" ~)
    :_  this
    :~  [%pass /endo-hi/(scot %p to) %arvo %a %mosd [%.y `@pC`to] hi-blob]
        [%pass /endo-dm/(scot %p to) %arvo %a %mosd [%.y `@pC`to] dm-blob]
    ==
  ::
  ++  send-channel-post
    |=  [=nest:d text=@t]
    ^-  (quip card _this)
    ?~  config.state  `this
    =/  ch-story=story:d  (text-to-story text)
    =/  ch-memo=memo:d  [content=ch-story author=moon-ship.u.config.state sent=now.bowl]
    =/  ch-essay=essay:d  [ch-memo /chat ~ ~]
    =/  act=a-channels:d  [%channel nest [%post [%add ch-essay]]]
    =/  host=ship  +<.nest
    (send-as-moon host %g /deal (jam act))
  ::
  ++  send-channel-reply
    |=  [=nest:d parent=@da text=@t]
    ^-  (quip card _this)
    ?~  config.state  `this
    =/  th-story=story:d  (text-to-story text)
    =/  th-memo=memo:d  [content=th-story author=moon-ship.u.config.state sent=now.bowl]
    =/  act=a-channels:d  [%channel nest [%post [%reply parent [%add th-memo]]]]
    =/  host=ship  +<.nest
    (send-as-moon host %g /deal (jam act))
  ::
  ++  join-group
    |=  =flag:g
    ^-  (quip card _this)
    ?~  config.state  `this
    =.  joined-groups.state  (~(put in joined-groups.state) flag)
    %-  (slog leaf+"endomoon: joining group {<flag>}" ~)
    (send-as-moon -.flag %g /deal (jam [%group-join flag %.y]))
  ::
  ++  leave-group
    |=  =flag:g
    ^-  (quip card _this)
    ?~  config.state  `this
    =.  joined-groups.state  (~(del in joined-groups.state) flag)
    `this
  ::
  ++  accept-dm
    |=  from=ship
    ^-  (quip card _this)
    ?~  config.state  `this
    =.  dm-accepted.state  (~(put in dm-accepted.state) from)
    (send-as-moon from %g /deal (jam [from %.y]))
  --
::
++  on-watch
  |=  =path
  ^-  (quip card _this)
  ?+  path  (on-watch:def path)
      [%events ~]
    ?>  =(src.bowl our.bowl)
    `this
  ==
::
++  on-agent
  |=  [=wire =sign:agent:gall]
  ^-  (quip card _this)
  `this
::
++  on-arvo
  |=  [=wire sign=sign-arvo]
  ^-  (quip card _this)
  `this
::
++  on-leave
  |=  =path
  ^-  (quip card _this)
  `this
::
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  ?+  path  ~
      [%x %config ~]
    =/  cfg=@t
      ?~  config.state  'disabled'
      (crip "enabled: {(scow %p moon-ship.u.config.state)}")
    ``noun+!>(cfg)
      [%x %peers ~]
    ``noun+!>(~(key by peers.state))
      [%x %status ~]
    ``noun+!>([~(wyt by peers.state) ~(wyt in joined-groups.state)])
  ==
::
++  on-fail
  |=  [=term =tang]
  ^-  (quip card _this)
  %-  (slog leaf+"endomoon: fail {<term>}" ~)
  `this
--
