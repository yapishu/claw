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
    ==
  --
++  grab
  |%
  ++  noun  update:claw
  --
++  grad  %noun
--
