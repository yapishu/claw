|%
++  web-root  ^-  (list @t)
  /apps/mcp
++  file-root  ^-  path
  /fil/mcp
++  index  ^-  $@(~ [~ path])
  `/index/html
++  extension  ^-  ?(%need %path %fall)
  %fall
++  auth  ^-  $@(? [? (list [path ?])])
  &
--
