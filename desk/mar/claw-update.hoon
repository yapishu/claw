/-  claw
|_  upd=update:claw
++  grow
  |%
  ++  noun  upd
  ++  json
    =,  enjs:format
    ^-  ^json
    ?-  -.upd
        %response
      %-  pairs
      :~  ['type' s+'response']
          ['role' s+role.msg.upd]
          ['content' s+content.msg.upd]
      ==
    ::
        %error
      %-  pairs
      :~  ['type' s+'error']
          ['error' s+error.upd]
      ==
    ::
        %pending
      (pairs ~[['type' s+'pending']])
    ::
        %dm-response
      %-  pairs
      :~  ['type' s+'dm-response']
          ['ship' s+(scot %p ship.upd)]
          ['role' s+role.msg.upd]
          ['content' s+content.msg.upd]
      ==
    ==
  --
++  grab
  |%
  ++  noun  update:claw
  --
++  grad  %noun
--
