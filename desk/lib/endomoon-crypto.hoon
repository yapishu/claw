::  endomoon-crypto: ames packet crypto for in-process moon
::
::  reimplements the critical ames encode/decode/encrypt/decrypt
::  arms for use by the endomoon agent. must exactly match the
::  wire format in ames.hoon and lull.hoon.
::
::  reference: ames.hoon +etch-shut-packet (line 463)
::             ames.hoon +sift-shut-packet (line 499)
::             ames.hoon +derive-symmetric-key (line 298)
::             lull.hoon +etch-shot (line 1544)
::             lull.hoon +sift-shot (line 1454)
::             jael.hoon %earl scry (line 1287)
::
|%
::  ames-internal types (defined in ames.hoon, not exported in lull.hoon)
::
+$  fragment-meat
  $:  num-fragments=fragment-num:ames
      =fragment-num:ames
      =fragment:ames
  ==
+$  ack-meat  (each fragment-num:ames [ok=? lag=@dr])
+$  shut-meat  (each fragment-meat ack-meat)
::
::  +protocol-version: must match lull.hoon
::
++  protocol-version  `?(%0 %1 %2 %3 %4 %5 %6 %7)`%0
::  +packet-size: fragment size in bloqs (2^13 = 8kb)
::
++  packet-size  13
::
::  +derive-moon-keys: derive moon keypair from planet's jael
::
::  the planet's jael can derive any moon's keypair via the
::  %earl scry path. returns the full crub core.
::
::  jael computes: moon-sec = shaf(%earl, sham(our, lyf, sec, who))
::  then: cub = pit:nu:crub:crypto(128, moon-sec)
::
++  derive-moon-keys
  |=  [our=ship now=@da =moon=ship]
  ^-  [sec=ring pub=pass cub=acru:ames lyf=life]
  ::  check if fakeship
  =/  is-fake=?  .^(? %j /(scot %p our)/fake/(scot %da now))
  ?:  is-fake
    ::  fakeships derive keys deterministically from @p with 512 bits
    =/  cub=acru:ames  (pit:nu:crub:crypto 512 moon-ship)
    [sec:ex:cub pub:ex:cub cub 1]
  ::  real ships: derive from parent's ring via %earl path
  =/  lyf=life
    .^(@ %j /(scot %p our)/life/(scot %da now)/(scot %p our))
  =/  our-sec=ring
    .^(ring %j /(scot %p our)/vein/(scot %da now)/(scot %ud lyf))
  =/  moon-secret=@  (shaf %earl (sham our lyf our-sec moon-ship))
  =/  cub=acru:ames  (pit:nu:crub:crypto 128 moon-secret)
  [sec:ex:cub pub:ex:cub cub lyf]
::
::  +derive-symmetric-key: ecdh shared secret
::
::  mirrors ames.hoon +derive-symmetric-key (line 298-309)
::  public-key has 'b' tag, private-key has 'B' tag
::
++  derive-symmetric-key
  |=  [=public-key:ames =private-key:ames]
  ^-  symmetric-key:ames
  ::  strip 'b' tag from public key
  ?>  =('b' (end 3 public-key))
  =.  public-key  (rsh 8 (rsh 3 public-key))
  ::  strip 'B' tag from private key
  ?>  =('B' (end 3 private-key))
  =.  private-key  (rsh 8 (rsh 3 private-key))
  ::
  `@`(shar:ed:crypto public-key private-key)
::
::  +ship-meta: ship byte size and rank for wire encoding
::
::  mirrors lull.hoon +ship-meta (line 1582)
::
++  ship-meta
  |=  =ship
  ^-  [size=@ =rank:ames]
  =/  size=@  (met 3 ship)
  ?:  (lte size 2)  [2 %0b0]
  ?:  (lte size 4)  [4 %0b1]
  ?:  (lte size 8)  [8 %0b10]
  [16 %0b11]
::
::  +etch-shot: serialize a $shot to a blob
::
::  mirrors lull.hoon +etch-shot (line 1544-1573)
::
++  etch-shot
  |=  shot:ames
  ^-  blob:ames
  =/  sndr-meta  (ship-meta sndr)
  =/  rcvr-meta  (ship-meta rcvr)
  ::
  =/  body=@
    ;:  mix
      sndr-tick
      (lsh 2 rcvr-tick)
      (lsh 3 sndr)
      (lsh [3 +(size.sndr-meta)] rcvr)
      (lsh [3 +((add size.sndr-meta size.rcvr-meta))] content)
    ==
  =/  checksum  (end [0 20] (mug body))
  =?  body  ?=(^ origin)  (mix u.origin (lsh [3 6] body))
  ::
  =/  header=@
    %+  can  0
    :~  [2 reserved=0]
        [1 req]
        [1 sam]
        [3 protocol-version]
        [2 rank.sndr-meta]
        [2 rank.rcvr-meta]
        [20 checksum]
        [1 relayed=.?(origin)]
    ==
  (mix header (lsh 5 body))
::
::  +sift-shot: deserialize a blob into a $shot
::
::  mirrors lull.hoon +sift-shot (line 1454-1511)
::
++  sift-shot
  |=  =blob:ames
  ^-  shot:ames
  ~|  %endomoon-sift-shot-fail
  ::  first 32 (2^5) bits are header; the rest is body
  =/  header  (end 5 blob)
  =/  body    (rsh 5 blob)
  ::  read header
  =/  req  =(& (cut 0 [2 1] header))
  =/  sam  =(& (cut 0 [3 1] header))
  =/  version  (cut 0 [4 3] header)
  ?.  =(protocol-version version)
    ~|  endomoon-protocol-version+version  !!
  ::
  =/  sndr-size  (sift-ship-size:ames (cut 0 [7 2] header))
  =/  rcvr-size  (sift-ship-size:ames (cut 0 [9 2] header))
  =/  checksum   (cut 0 [11 20] header)
  =/  relayed    (cut 0 [31 1] header)
  ::  origin, if present, is 6 octets at the start of body
  =^  origin=(unit @)  body
    ?:  =(| relayed)
      [~ body]
    =/  len  (sub (met 3 body) 6)
    [`(end [3 6] body) (rsh [3 6] body)]
  ::  verify checksum (does not apply to origin)
  ?.  =(checksum (end [0 20] (mug body)))
    ~|  %endomoon-checksum  !!
  ::  read life ticks (4 bits each)
  =/  sndr-tick  (cut 0 [0 4] body)
  =/  rcvr-tick  (cut 0 [4 4] body)
  ::  read variable-length addresses
  =/  off   1
  =^  sndr  off  [(cut 3 [off sndr-size] body) (add off sndr-size)]
  =^  rcvr  off  [(cut 3 [off rcvr-size] body) (add off rcvr-size)]
  ::  content is the rest
  =/  content  (cut 3 [off (sub (met 3 body) off)] body)
  [[sndr rcvr] req sam sndr-tick rcvr-tick origin content]
::
::  +encrypt-shut-packet: encrypt a shut-packet into a shot
::
::  mirrors ames.hoon +etch-shut-packet (line 463-496)
::  produces a complete shot ready for etch-shot serialization
::
++  encrypt-shut-packet
  |=  $:  =bone:ames
          =message-num:ames
          meat=shut-meat
          =symmetric-key:ames
          sndr=ship
          rcvr=ship
          sndr-life=@
          rcvr-life=@
      ==
  ^-  shot:ames
  ::  build and jam the shut-packet [bone message-num meat]
  =/  pkt  [bone message-num meat]
  ::  encrypt with aes-siv
  =/  vec  ~[sndr rcvr sndr-life rcvr-life]
  =/  [siv=@uxH len=@ cyf=@ux]
    (~(en sivc:aes:crypto (shaz symmetric-key) vec) (jam pkt))
  ::  build shot
  :*  ^=       dyad  [sndr rcvr]
      ^=        req  ?=(%& -.meat)
      ^=        sam  &
      ^=  sndr-tick  (mod sndr-life 16)
      ^=  rcvr-tick  (mod rcvr-life 16)
      ^=     origin  ~
      ^=    content  :(mix siv (lsh 7 len) (lsh [3 18] cyf))
  ==
::
::  +decrypt-shut-packet: decrypt a shot's content into a shut-packet
::
::  mirrors ames.hoon +sift-shut-packet (line 499-513)
::
++  decrypt-shut-packet
  |=  [=shot:ames =symmetric-key:ames sndr-life=@ rcvr-life=@]
  ^-  (unit [bone:ames message-num:ames meat=shut-meat])
  ::  verify life ticks match
  ?.  ?&  =(sndr-tick.shot (mod sndr-life 16))
          =(rcvr-tick.shot (mod rcvr-life 16))
      ==
    ~
  ::  extract siv, length, ciphertext from content
  =/  siv  (end 7 content.shot)
  =/  len  (end 4 (rsh 7 content.shot))
  =/  cyf  (rsh [3 18] content.shot)
  ::  decrypt with aes-siv
  =/  vec  ~[sndr.shot rcvr.shot sndr-life rcvr-life]
  =/  plain=(unit @)
    (~(de sivc:aes:crypto (shaz symmetric-key) vec) siv len cyf)
  ?~  plain  ~
  ::  deserialize shut-packet
  =/  pkt  (cue u.plain)
  %-  some
  ;;  [bone:ames message-num:ames shut-meat]
  pkt
::
::  +make-plea-shut-packet: build a single-fragment plea message
::
::  wraps a gall plea into a shut-packet structure.
::  only handles single-fragment messages (<8kb after jam).
::
++  make-plea-shut-packet
  |=  [=bone:ames msg-num=@ud vane=@tas =path payload=*]
  ^-  [bone:ames message-num:ames shut-meat]
  ::  jam the plea wrapped in message type (matches ames format)
  =/  message-blob=@  (jam [%plea vane path payload])
  =/  num-frags=@  (met packet-size message-blob)
  ::  single fragment: fragment-num=0, fragment=full-message
  ?>  (lte num-frags 1)
  =/  frag=@  message-blob
  =/  meat  [%& [num-frags=`fragment-num:ames`(max 1 num-frags) fragment-num=`fragment-num:ames`0 fragment=`fragment:ames`frag]]
  [bone `message-num:ames`msg-num meat]
::
::  +make-ack-shut-packet: build a message-level ack
::
::  ack bone = the plea bone with bit 0 flipped (response direction)
::
++  make-ack-shut-packet
  |=  [plea-bone=bone:ames msg-num=@ud ok=?]
  ^-  [bone:ames message-num:ames shut-meat]
  ::  response bone: flip bit 0
  =/  ack-bone=bone:ames  (mix plea-bone 1)
  [ack-bone `message-num:ames`msg-num [%| [%| ok lag=~s0]]]
::
::  +decode-plea: extract application message from a fragment
::
::  for single-fragment messages, reassemble and decode the plea.
::
++  decode-plea
  |=  [=bone:ames msg-num=message-num:ames meat=shut-meat]
  ^-  (unit [vane=@tas =path payload=*])
  ::  only handle fragment meat (not acks)
  ?.  ?=(%& -.meat)
    ~
  ::  only handle single-fragment messages
  ?.  =(0 fragment-num.p.meat)
    ~
  ::  deserialize the message
  =/  msg  (cue fragment.p.meat)
  ::  message is tagged: [%plea [vane path payload]]
  ?.  ?=([%plea *] msg)
    ~
  =/  [vane=@tas =path payload=*]  ;;([@tas path *] +.msg)
  `[vane path payload]
::
::  +encode-keys-packet: build address attestation for galaxy
::
::  sends this to our galaxy so it records our lane for the moon.
::  mirrors ames.hoon +encode-keys-packet (line 312-323)
::
++  encode-keys-packet
  |=  [sndr=ship rcvr=ship sndr-life=life]
  ^-  shot:ames
  :*  [sndr rcvr]
      &
      &
      (mod sndr-life 16)
      `@`1
      origin=~
      content=`@`%keys
  ==
--
