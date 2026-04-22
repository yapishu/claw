|%
++  web-root  ^-  (list @t)
  /apps/maroon
++  file-root  ^-  path
  /fil/maroon
++  index  ^-  $@(~ [~ path])
  `/index/html
++  extension  ^-  ?(%need %path %fall)
  %fall
++  auth  ^-  $@(? [? (list [path ?])])
  &
--
