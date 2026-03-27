::  s3-client: reusable S3 upload client
::
::  provides AWS SigV4 signing and presigned PUT URL generation.
::  no agent dependencies — takes credentials as parameters.
::
|%
::
::  +s3-hmac-sha256: HMAC-SHA256 using shay
::
++  s3-hmac-sha256
  |=  [key=octs msg=octs]
  ^-  @
  =/  block-size=@ud  64
  =/  k=@
    ?:  (gth p.key block-size)
      (shay p.key q.key)
    q.key
  =/  ipad-key=@  (mix k (fil 3 block-size 0x36))
  =/  opad-key=@  (mix k (fil 3 block-size 0x5c))
  =/  inner-data=@  (cat 3 ipad-key q.msg)
  =/  inner-len=@ud  (add block-size p.msg)
  =/  inner-hash=@  (shay inner-len inner-data)
  =/  outer-data=@  (cat 3 opad-key inner-hash)
  =/  outer-len=@ud  (add block-size 32)
  (shay outer-len outer-data)
::
++  s3-hmac-sha256-cord
  |=  [key=@t msg=@t]
  ^-  @
  (s3-hmac-sha256 [(met 3 key) key] [(met 3 msg) msg])
::
::  +s3-signing-key: derive AWS4 signing key
::
++  s3-signing-key
  |=  [secret=@t date=@t region=@t service=@t]
  ^-  @
  =/  k-secret=@t  (rap 3 'AWS4' secret ~)
  =/  k-date=@  (s3-hmac-sha256-cord k-secret date)
  =/  k-region=@  (s3-hmac-sha256 [32 k-date] [(met 3 region) region])
  =/  k-service=@  (s3-hmac-sha256 [32 k-region] [(met 3 service) service])
  (s3-hmac-sha256 [32 k-service] [(met 3 'aws4_request') 'aws4_request'])
::
::  +s3-hex: convert 32-byte hash to hex cord
::
++  s3-hex
  |=  dat=@
  ^-  @t
  =/  out=tape
    =/  idx  0
    |-
    ?:  =(idx 32)  ~
    =/  byt=@  (cut 3 [idx 1] dat)
    =/  hi  (snag (rsh 0^4 byt) "0123456789abcdef")
    =/  lo  (snag (end 0^4 byt) "0123456789abcdef")
    [hi lo $(idx +(idx))]
  (crip out)
::
::  +s3-uri-encode: URI-encode a path for S3
::
++  s3-uri-encode
  |=  =cord
  ^-  @t
  %-  crip
  %-  zing
  %+  turn  (trip cord)
  |=  c=@t
  ^-  tape
  ?:  ?|  &((gte c 'a') (lte c 'z'))
          &((gte c 'A') (lte c 'Z'))
          &((gte c '0') (lte c '9'))
          =(c '-')  =(c '.')  =(c '_')  =(c '~')  =(c '/')
      ==
    [c ~]
  =/  hi  (snag (rsh 0^4 c) "0123456789ABCDEF")
  =/  lo  (snag (end 0^4 c) "0123456789ABCDEF")
  ['%' hi lo ~]
::
++  join-s3
  |=  [sep=tape parts=(list tape)]
  ^-  tape
  ?~  parts  ~
  ?~  t.parts  i.parts
  (weld i.parts (weld sep $(parts t.parts)))
::
::  +s3-creds: credentials extracted from %storage scry
::
+$  s3-creds
  $:  endpoint=@t
      access-key=@t
      secret-key=@t
      bucket=@t
      region=@t
      public-url-base=@t
  ==
::
::  +s3-presigned-put: build a presigned PUT request
::    returns [card public-url] or ~ if creds are empty
::
++  s3-presigned-put
  |=  [creds=s3-creds now=@da image-data=octs content-type=@t]
  ^-  (unit [card=card:agent:gall url=@t])
  ?:  |(=('' access-key.creds) =('' secret-key.creds) =('' bucket.creds))
    ~
  ::  generate unique key
  =/  ext=@t
    ?:  (test content-type 'image/png')  'png'
    ?:  (test content-type 'image/gif')  'gif'
    ?:  (test content-type 'image/webp')  'webp'
    'jpg'
  =/  key=@t  (rap 3 (scot %uv (sham now)) '.' ext ~)
  ::  date strings
  =/  d=date  (yore now)
  =/  pad  |=(n=@ud ^-(tape ?:((lth n 10) "0{(a-co:co n)}" (a-co:co n))))
  =/  date-str=@t
    (crip "{(a-co:co y.d)}{(pad m.d)}{(pad d.t.d)}")
  =/  amz-date=@t
    (crip "{(a-co:co y.d)}{(pad m.d)}{(pad d.t.d)}T{(pad h.t.d)}{(pad m.t.d)}{(pad s.t.d)}Z")
  ::  host from endpoint
  =/  raw-host=@t
    ?:  !=('' endpoint.creds)
      =/  ep=tape  (trip endpoint.creds)
      ?:  =("https://" (scag 8 `(list @)`ep))  (crip (slag 8 `(list @)`ep))
      ?:  =("http://" (scag 7 `(list @)`ep))  (crip (slag 7 `(list @)`ep))
      endpoint.creds
    (rap 3 's3.' region.creds '.amazonaws.com' ~)
  =/  host=@t  raw-host
  =/  s3-path=@t  (rap 3 '/' bucket.creds '/' key ~)
  =/  s3-url=@t  (rap 3 'https://' host s3-path ~)
  =/  public-url=@t
    ?:  !=('' public-url-base.creds)  (rap 3 public-url-base.creds '/' key ~)
    s3-url
  ::  signing
  =/  scope=@t  (rap 3 date-str '/' region.creds '/s3/aws4_request' ~)
  =/  credential=@t  (rap 3 access-key.creds '/' scope ~)
  =/  enc-cred=@t
    %-  crip  %-  zing
    %+  turn  (trip credential)
    |=(c=@t ^-(tape ?:(=('/' c) "%2F" [c ~])))
  =/  canonical-qs=@t
    %-  crip
    %+  join-s3  "&"
    :~  "X-Amz-Algorithm=AWS4-HMAC-SHA256"
        "X-Amz-Credential={(trip enc-cred)}"
        "X-Amz-Date={(trip amz-date)}"
        "X-Amz-Expires=3600"
        "X-Amz-SignedHeaders=host"
    ==
  =/  canonical-request=@t
    %-  crip
    %+  join-s3  "\0a"
    :~  "PUT"
        (trip (s3-uri-encode s3-path))
        (trip canonical-qs)
        "host:{(trip host)}\0a"
        "host"
        "UNSIGNED-PAYLOAD"
    ==
  =/  canon-hash=@t  (s3-hex (shay (met 3 canonical-request) canonical-request))
  =/  string-to-sign=@t
    %-  crip
    %+  join-s3  "\0a"
    :~  "AWS4-HMAC-SHA256"
        (trip amz-date)
        (trip scope)
        (trip canon-hash)
    ==
  =/  sk=@  (s3-signing-key secret-key.creds date-str region.creds 's3')
  =/  signature=@t
    (s3-hex (s3-hmac-sha256 [32 sk] [(met 3 string-to-sign) string-to-sign]))
  =/  presigned=@t
    (rap 3 s3-url '?' canonical-qs '&X-Amz-Signature=' signature ~)
  =/  put-hed=(list [key=@t value=@t])
    :~  ['Content-Type' content-type]
        ['x-amz-acl' 'public-read']
    ==
  :-  ~
  :_  public-url
  [%pass /tool-http/'upload_put' %arvo %i %request [%'PUT' presigned put-hed `image-data] *outbound-config:iris]
::
::  +scry-s3-creds: extract S3 credentials from %storage agent scries
::    takes the JSON results from credentials and configuration scries
::
++  scry-s3-creds
  |=  [cred-json=json conf-json=json]
  ^-  s3-creds
  =/  me  |=(=json ^-((unit (map @t ^json)) ?.(?=([%o *] json) ~ `p.json)))
  =/  get-str
    |=  [m=(map @t json) k=@t]
    ^-  @t
    =/  v  (~(get by m) k)
    ?~(v '' ?:(?=([%s *] u.v) p.u.v ''))
  =/  extract
    |=  [raw=json field=@t]
    ^-  (map @t json)
    =/  top=(unit (map @t json))  (me raw)
    ?~  top  *(map @t json)
    =/  su=(unit json)  (~(get by u.top) 'storage-update')
    ?~  su  *(map @t json)
    =/  su-map=(unit (map @t json))  (me u.su)
    ?~  su-map  *(map @t json)
    =/  cr=(unit json)  (~(get by u.su-map) field)
    ?~  cr  *(map @t json)
    (fall (me u.cr) *(map @t json))
  =/  cred-map  (extract cred-json 'credentials')
  =/  conf-map  (extract conf-json 'configuration')
  :*  (get-str cred-map 'endpoint')
      (get-str cred-map 'accessKeyId')
      (get-str cred-map 'secretAccessKey')
      (get-str conf-map 'currentBucket')
      (get-str conf-map 'region')
      (get-str conf-map 'publicUrlBase')
  ==
--
