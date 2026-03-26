::  s3-auth: AWS Signature V4 presigned URL validation
::
/-  s3
|%
::  +hmac-sha256: HMAC-SHA256 keyed hash
::
::    key: key as octs
::    msg: message as octs
::    returns: 32-byte hash as @
::
++  hmac-sha256
  |=  [key=octs msg=octs]
  ^-  @
  =/  block-size=@ud  64
  ::  if key > block size, hash it first
  =/  key-bytes=octs
    ?:  (gth p.key block-size)
      [32 (shay p.key q.key)]
    key
  ::  pad key to block-size with zeros
  =/  padded-key=@
    ?:  (lth p.key-bytes block-size)
      q.key-bytes
    q.key-bytes
  ::  inner pad: key XOR 0x3636...
  =/  ipad=@  (fil 3 block-size 0x36)
  =/  opad=@  (fil 3 block-size 0x5c)
  =/  i-key-pad=@  (mix padded-key ipad)
  =/  o-key-pad=@  (mix padded-key opad)
  ::  inner hash: SHA256(i-key-pad ++ msg)
  =/  inner=@
    (shay (add block-size p.msg) (cat 3 i-key-pad q.msg))
  ::  outer hash: SHA256(o-key-pad ++ inner-hash)
  (shay (add block-size 32) (cat 3 o-key-pad inner))
::
::  +hmac-sha256-cord: convenience wrapper for cord inputs
::
++  hmac-sha256-cord
  |=  [key=octs msg=@t]
  ^-  @
  (hmac-sha256 key [(met 3 msg) msg])
::
::  +signing-key: derive SigV4 signing key
::
::    secret: AWS secret access key
::    date: date string YYYYMMDD
::    region: AWS region string
::    service: always "s3"
::
++  signing-key
  |=  [secret=@t date=@t region=@t service=@t]
  ^-  @
  =/  k-date=@
    %-  hmac-sha256-cord
    :_  date
    [(met 3 (cat 3 'AWS4' secret)) (cat 3 'AWS4' secret)]
  =/  k-region=@
    (hmac-sha256 [32 k-date] [(met 3 region) region])
  =/  k-service=@
    (hmac-sha256 [32 k-region] [(met 3 service) service])
  (hmac-sha256 [32 k-service] [12 'aws4_request'])
::
::  +hex-lower: render atom as lowercase hex string
::
++  hex-lower
  |=  dat=@
  ^-  tape
  =/  res=tape  ~
  =/  i=@ud  0
  |-
  ?:  =(i 32)
    (flop res)
  =/  byte=@  (cut 3 [i 1] dat)
  =/  hi=@ud  (div byte 16)
  =/  lo=@ud  (mod byte 16)
  =/  hex-char
    |=  n=@ud
    ^-  @tD
    ?:  (lth n 10)
      (add '0' n)
    (add 'a' (sub n 10))
  %=  $
    i    +(i)
    res  [(hex-char lo) (hex-char hi) res]
  ==
::
::  +hex-lower-cord: render atom as lowercase hex cord
::
++  hex-lower-cord
  |=  dat=@
  ^-  @t
  (crip (hex-lower dat))
::
::  +url-decode: percent-decode a cord
::
++  url-decode
  |=  txt=@t
  ^-  @t
  =/  in=tape  (trip txt)
  =/  out=tape  ~
  |-
  ?~  in  (crip (flop out))
  ?:  &(=(i.in '%') ?=(^ t.in) ?=(^ t.t.in))
    =/  hi  (from-hex-char i.t.in)
    =/  lo  (from-hex-char i.t.t.in)
    ?:  |(?=(~ hi) ?=(~ lo))
      $(in t.in, out [i.in out])
    $(in t.t.t.in, out [(add (mul 16 (need hi)) (need lo)) out])
  $(in t.in, out [i.in out])
::
++  from-hex-char
  |=  c=@tD
  ^-  (unit @ud)
  ?:  &((gte c '0') (lte c '9'))  `(sub c '0')
  ?:  &((gte c 'a') (lte c 'f'))  `(add 10 (sub c 'a'))
  ?:  &((gte c 'A') (lte c 'F'))  `(add 10 (sub c 'A'))
  ~
::
::  +parse-query-params: parse query string into map
::
++  parse-query-params
  |=  query=@t
  ^-  (map @t @t)
  ?:  =('' query)  *(map @t @t)
  =/  pairs=(list [@t @t])
    %+  turn
      (split-on '&' (trip query))
    |=  pair=tape
    ^-  [@t @t]
    =/  idx  (find "=" pair)
    ?~  idx  [(url-decode (crip pair)) '']
    [(url-decode (crip (scag u.idx pair))) (url-decode (crip (slag +(u.idx) pair)))]
  (~(gas by *(map @t @t)) pairs)
::
::  +split-on: split tape on delimiter character
::
++  split-on
  |=  [sep=@tD =tape]
  ^-  (list ^tape)
  =|  acc=^tape
  =|  res=(list ^tape)
  |-
  ?~  tape
    (flop [(flop acc) res])
  ?:  =(i.tape sep)
    $(tape t.tape, acc ~, res [(flop acc) res])
  $(tape t.tape, acc [i.tape acc])
::
::  +uri-encode: percent-encode a cord for S3 canonical URI
::
++  uri-encode
  |=  txt=@t
  ^-  @t
  =/  in=tape  (trip txt)
  =/  out=tape  ~
  |-
  ?~  in  (crip (flop out))
  =/  c  i.in
  ?:  ?|  &((gte c 'A') (lte c 'Z'))
          &((gte c 'a') (lte c 'z'))
          &((gte c '0') (lte c '9'))
          =(c '-')
          =(c '_')
          =(c '.')
          =(c '~')
      ==
    $(in t.in, out [c out])
  ?:  =(c '/')
    $(in t.in, out [c out])
  =/  byte=@ud  `@ud`c
  =/  hi  (div byte 16)
  =/  lo  (mod byte 16)
  =/  hex-ch
    |=  n=@ud
    ^-  @tD
    ?:  (lth n 10)  (add '0' n)
    (add 'A' (sub n 10))
  $(in t.in, out [(hex-ch lo) (hex-ch hi) '%' out])
::
::  +uri-encode-component: percent-encode for query string values
::
::    Like uri-encode but also encodes '/' (required for query params)
::
++  uri-encode-component
  |=  txt=@t
  ^-  @t
  =/  in=tape  (trip txt)
  =/  out=tape  ~
  |-
  ?~  in  (crip (flop out))
  =/  c  i.in
  ?:  ?|  &((gte c 'A') (lte c 'Z'))
          &((gte c 'a') (lte c 'z'))
          &((gte c '0') (lte c '9'))
          =(c '-')
          =(c '_')
          =(c '.')
          =(c '~')
      ==
    $(in t.in, out [c out])
  =/  byte=@ud  `@ud`c
  =/  hi  (div byte 16)
  =/  lo  (mod byte 16)
  =/  hex-ch
    |=  n=@ud
    ^-  @tD
    ?:  (lth n 10)  (add '0' n)
    (add 'A' (sub n 10))
  $(in t.in, out [(hex-ch lo) (hex-ch hi) '%' out])
::
::  +canonical-query-string: build canonical query string for signing
::
::    Excludes X-Amz-Signature, sorts remaining params
::
++  canonical-query-string
  |=  params=(map @t @t)
  ^-  @t
  =/  filtered=(list [@t @t])
    %+  murn
      ~(tap by params)
    |=  [k=@t v=@t]
    ?:  =(k 'X-Amz-Signature')  ~
    `[k v]
  =/  sorted=(list [@t @t])
    %+  sort  filtered
    |=  [[a=@t *] [b=@t *]]
    (aor a b)
  =/  parts=(list tape)
    %+  turn  sorted
    |=  [k=@t v=@t]
    "{(trip (uri-encode-component k))}={(trip (uri-encode-component v))}"
  (crip (join-tapes "&" parts))
::
::  +join-tapes: join list of tapes with separator
::
++  join-tapes
  |=  [sep=tape parts=(list tape)]
  ^-  tape
  ?~  parts  ~
  ?~  t.parts  i.parts
  (weld i.parts (weld sep $(parts t.parts)))
::
::  +canonical-headers: build canonical headers string
::
::    For presigned URLs, typically just "host"
::
++  canonical-headers
  |=  [signed-headers=@t headers=(list [@t @t])]
  ^-  @t
  =/  header-names=(list @t)  (split-cord ';' signed-headers)
  =/  header-map=(map @t @t)
    (~(gas by *(map @t @t)) headers)
  =/  lines=(list tape)
    %+  turn  header-names
    |=  name=@t
    =/  val=@t  (~(gut by header-map) name '')
    "{(trip name)}:{(trip (trim-cord val))}"
  (crip (weld (join-tapes "\0a" lines) "\0a"))
::
::  +split-cord: split a cord on a character
::
++  split-cord
  |=  [sep=@tD =cord]
  ^-  (list @t)
  (turn (split-on sep (trip cord)) crip)
::
::  +trim-cord: trim leading/trailing whitespace
::
++  trim-cord
  |=  =cord
  ^-  @t
  =/  t=tape  (trip cord)
  |-
  ?~  t  ''
  ?:  =(i.t ' ')  $(t t.t)
  (crip (flop (trim-tail (flop t))))
::
++  trim-tail
  |=  =tape
  ^-  ^tape
  ?~  tape  ~
  ?:  =(i.tape ' ')  $(tape t.tape)
  tape
::
::  +validate-presigned-url: validate an AWS SigV4 presigned URL
::
::    method: HTTP method (GET, PUT, etc.)
::    path: URL path (e.g., /s3/bucket/key)
::    query: query string
::    headers: request headers
::    secret: our secret access key
::    access-key: our access key id
::    now: current time
::
::    Returns %.y if valid, %.n if invalid
::
++  validate-presigned-url
  |=  $:  method=@t
          url-path=@t
          query=@t
          headers=(list [@t @t])
          =credentials:s3
          region=@t
          now=@da
      ==
  ^-  ?
  =/  params=(map @t @t)  (parse-query-params query)
  ::  check required params exist
  =/  algo=(unit @t)       (~(get by params) 'X-Amz-Algorithm')
  =/  cred=(unit @t)       (~(get by params) 'X-Amz-Credential')
  =/  date=(unit @t)       (~(get by params) 'X-Amz-Date')
  =/  expires=(unit @t)    (~(get by params) 'X-Amz-Expires')
  =/  signed-h=(unit @t)   (~(get by params) 'X-Amz-SignedHeaders')
  =/  signature=(unit @t)  (~(get by params) 'X-Amz-Signature')
  ?~  algo       %.n
  ?~  cred       %.n
  ?~  date       %.n
  ?~  expires    %.n
  ?~  signed-h   %.n
  ?~  signature  %.n
  ::  verify algorithm
  ?.  =(u.algo 'AWS4-HMAC-SHA256')  %.n
  ::  verify credential starts with our access key
  =/  cred-parts=(list @t)  (split-cord '/' u.cred)
  ?~  cred-parts  %.n
  ?.  =(i.cred-parts access-key-id.credentials)  %.n
  ::  check expiry
  =/  req-time=(unit @da)  (parse-amz-date u.date)
  ?~  req-time  %.n
  =/  exp-seconds=@ud
    (fall (rush u.expires dem) 0)
  =/  expiry=@da
    (add u.req-time (mul exp-seconds ~s1))
  ?:  (gth now expiry)  %.n
  ::  extract date (YYYYMMDD) from X-Amz-Date (YYYYMMDDTHHMMSSZ)
  =/  date-str=@t  (crip (scag 8 (trip u.date)))
  ::  build canonical request
  ::  lowercase header keys for case-insensitive lookup
  =/  lower-headers=(list [@t @t])
    (turn headers |=([k=@t v=@t] [(crip (cass (trip k))) v]))
  =/  canon-qs=@t       (canonical-query-string params)
  =/  canon-headers=@t  (canonical-headers u.signed-h lower-headers)
  =/  canon-req=@t
    %:  crip
      %+  join-tapes  "\0a"
      :~  (trip method)
          (trip (uri-encode (url-decode url-path)))
          (trip canon-qs)
          (trip canon-headers)
          (trip u.signed-h)
          "UNSIGNED-PAYLOAD"
      ==
    ==
  ::  hash canonical request
  =/  canon-hash=@t
    (hex-lower-cord (shay (met 3 canon-req) canon-req))
  ::  build scope
  =/  scope=@t
    %:  crip
      "{(trip date-str)}/{(trip region)}/s3/aws4_request"
    ==
  ::  build string to sign
  =/  string-to-sign=@t
    %:  crip
      %+  join-tapes  "\0a"
      :~  "AWS4-HMAC-SHA256"
          (trip u.date)
          (trip scope)
          (trip canon-hash)
      ==
    ==
  ::  derive signing key
  =/  sk=@
    (signing-key secret-access-key.credentials date-str region 's3')
  ::  compute signature
  =/  computed-sig=@t
    %-  hex-lower-cord
    (hmac-sha256 [32 sk] [(met 3 string-to-sign) string-to-sign])
  ::  compare signatures
  ?.  =(computed-sig u.signature)
    %-  (slog leaf+"s3-server: presigned-url validation failed" ~)
    %-  (slog leaf+"  computed-sig: {(trip computed-sig)}" ~)
    %-  (slog leaf+"  expected-sig: {(trip u.signature)}" ~)
    %-  (slog leaf+"  signed-hdrs: {(trip u.signed-h)}" ~)
    %-  (slog leaf+"  canon-hdrs: {(trip canon-headers)}" ~)
    %.n
  %.y
::
::  +parse-amz-date: parse YYYYMMDDTHHMMSSZ to @da
::
++  parse-amz-date
  |=  date=@t
  ^-  (unit @da)
  =/  t=tape  (trip date)
  ?.  =(16 (lent t))  ~
  =/  y  (rust (scag 4 t) dem)
  =/  m  (rust (swag [4 2] t) dem)
  =/  d  (rust (swag [6 2] t) dem)
  =/  h  (rust (swag [9 2] t) dem)
  =/  mi  (rust (swag [11 2] t) dem)
  =/  s  (rust (swag [13 2] t) dem)
  ?~  y   ~
  ?~  m   ~
  ?~  d   ~
  ?~  h   ~
  ?~  mi  ~
  ?~  s   ~
  %-  some
  %-  year
  [[& u.y] u.m [u.d u.h u.mi u.s ~]]
::
::  +parse-auth-header: parse AWS4-HMAC-SHA256 Authorization header
::
::    Extracts credential, signed-headers, and signature.
::    Returns ~ if the header format is invalid.
::
++  parse-auth-header
  |=  auth=@t
  ^-  (unit [credential=@t signed-headers=@t signature=@t])
  =/  t=tape  (trip auth)
  =/  prefix=tape  "AWS4-HMAC-SHA256 "
  ?.  =(prefix (scag (lent prefix) t))  ~
  =/  cred-idx  (find "Credential=" t)
  =/  sh-idx    (find "SignedHeaders=" t)
  =/  sig-idx   (find "Signature=" t)
  ?~  cred-idx  ~
  ?~  sh-idx    ~
  ?~  sig-idx   ~
  ::  extract value from after "Key=" to next comma or end
  =/  cred-start  (add u.cred-idx 11)
  =/  cred-rest   (slag cred-start t)
  =/  cred-val  (scag (fall (find "," cred-rest) (lent cred-rest)) cred-rest)
  ::
  =/  sh-start  (add u.sh-idx 14)
  =/  sh-rest   (slag sh-start t)
  =/  sh-val  (scag (fall (find "," sh-rest) (lent sh-rest)) sh-rest)
  ::
  =/  sig-start  (add u.sig-idx 10)
  =/  sig-rest   (slag sig-start t)
  =/  sig-val  sig-rest  :: signature is always last
  `[(crip cred-val) (crip sh-val) (crip sig-val)]
::
::  +validate-auth-header: validate AWS SigV4 Authorization header
::
::    method: HTTP method
::    url-path: URL path
::    query: query string
::    headers: request headers
::    credentials: our credentials
::    region: our region
::
::    Returns %.y if valid, %.n if invalid
::
++  validate-auth-header
  |=  $:  method=@t
          url-path=@t
          query=@t
          headers=(list [@t @t])
          =credentials:s3
          region=@t
      ==
  ^-  ?
  ::  find Authorization header (case-insensitive)
  =/  auth-val=(unit @t)
    |-
    ?~  headers  ~
    ?:  =((crip (cass (trip -.i.headers))) 'authorization')
      `+.i.headers
    $(headers t.headers)
  ?~  auth-val  %.n
  ::  parse header
  =/  parsed  (parse-auth-header u.auth-val)
  ?~  parsed  %.n
  =/  cred=@t         credential.u.parsed
  =/  signed-hdrs=@t  signed-headers.u.parsed
  =/  sig=@t          signature.u.parsed
  ::  verify credential starts with our access key
  =/  cred-parts=(list @t)  (split-cord '/' cred)
  ?~  cred-parts  %.n
  ?.  =(i.cred-parts access-key-id.credentials)  %.n
  ::  extract date from credential (second part: YYYYMMDD)
  ?~  t.cred-parts  %.n
  =/  date-str=@t  i.t.cred-parts
  ::  lowercase all header keys for canonical header building
  =/  lower-headers=(list [@t @t])
    (turn headers |=([k=@t v=@t] [(crip (cass (trip k))) v]))
  =/  header-map=(map @t @t)
    (~(gas by *(map @t @t)) lower-headers)
  ::  get x-amz-date
  =/  amz-date=(unit @t)  (~(get by header-map) 'x-amz-date')
  ?~  amz-date  %.n
  ::  get payload hash, default to UNSIGNED-PAYLOAD
  =/  payload-hash=@t
    (fall (~(get by header-map) 'x-amz-content-sha256') 'UNSIGNED-PAYLOAD')
  ::  build canonical request
  =/  params=(map @t @t)  (parse-query-params query)
  =/  canon-qs=@t  (canonical-query-string params)
  =/  canon-hdrs=@t  (canonical-headers signed-hdrs lower-headers)
  =/  canon-req=@t
    %:  crip
      %+  join-tapes  "\0a"
      :~  (trip method)
          (trip (uri-encode (url-decode url-path)))
          (trip canon-qs)
          (trip canon-hdrs)
          (trip signed-hdrs)
          (trip payload-hash)
      ==
    ==
  ::  hash canonical request
  =/  canon-hash=@t
    (hex-lower-cord (shay (met 3 canon-req) canon-req))
  ::  build scope
  =/  scope=@t
    (crip "{(trip date-str)}/{(trip region)}/s3/aws4_request")
  ::  build string to sign
  =/  string-to-sign=@t
    %:  crip
      %+  join-tapes  "\0a"
      :~  "AWS4-HMAC-SHA256"
          (trip u.amz-date)
          (trip scope)
          (trip canon-hash)
      ==
    ==
  ::  derive signing key and compute signature
  =/  sk=@  (signing-key secret-access-key.credentials date-str region 's3')
  =/  computed-sig=@t
    %-  hex-lower-cord
    (hmac-sha256 [32 sk] [(met 3 string-to-sign) string-to-sign])
  ::  compare
  ?.  =(computed-sig sig)
    %-  (slog leaf+"  computed-sig: {(trip computed-sig)}" ~)
    %-  (slog leaf+"  expected-sig: {(trip sig)}" ~)
    %-  (slog leaf+"  canon-qs: {(trip canon-qs)}" ~)
    %-  (slog leaf+"  canon-hdrs: {(trip canon-hdrs)}" ~)
    %-  (slog leaf+"  signed-hdrs: {(trip signed-hdrs)}" ~)
    %-  (slog leaf+"  payload-hash: {(trip payload-hash)}" ~)
    %-  (slog leaf+"  canon-hash: {(trip canon-hash)}" ~)
    %.n
  %.y
--
