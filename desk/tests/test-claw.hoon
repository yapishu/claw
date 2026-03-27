/-  claw
/+  *test
=>
|%
++  lcm-key
  |=  =msg-source:claw
  ^-  @t
  ?-  -.msg-source
    %direct   'direct'
    %dm       (rap 3 'dm/' (scot %p ship.msg-source) ~)
    %channel  (rap 3 'channel/' kind.msg-source '/' (scot %p host.msg-source) '/' name.msg-source ~)
  ==
++  model-budget
  |=  mod=@t
  ^-  @ud
  =/  m=tape  (cass (trip mod))
  ?:  !=(~ (find "claude" m))  150.000
  ?:  !=(~ (find "gpt-4" m))   100.000
  ?:  !=(~ (find "gemini" m))  800.000
  50.000
++  me
  |=  =json
  ^-  (unit (map @t ^json))
  ?.  ?=([%o *] json)  ~
  `p.json
++  parse-llm-response
  |=  body=@t
  ^-  (unit ?([%text content=@t] [%tools content=@t calls=(list [id=@t name=@t arguments=@t])]))
  =/  jon=(unit json)  (de:json:html body)
  ?~  jon  ~
  %-  mole  |.
  =/  choices=json  (need (~(get by (need (me u.jon))) 'choices'))
  ?.  ?=([%a [* *]] choices)  !!
  =/  choice=json  i.p.choices
  =/  msg=json  (need (~(get by (need (me choice))) 'message'))
  =/  msg-map=(map @t json)  (need (me msg))
  =/  tc=(unit json)  (~(get by msg-map) 'tool_calls')
  ?~  tc
    =/  content=json  (need (~(get by msg-map) 'content'))
    ?.  ?=([%s *] content)  !!
    [%text p.content]
  ?.  ?=([%a *] u.tc)  !!
  =/  tc-content=@t
    =/  ct=(unit json)  (~(get by msg-map) 'content')
    ?~  ct  ''
    ?:  ?=([%s *] u.ct)  p.u.ct
    ''
  =/  calls=(list [id=@t name=@t arguments=@t])
    %+  turn  p.u.tc
    |=  tc-item=json
    =/  tcm=(map @t json)  (need (me tc-item))
    =/  fn=json  (need (~(get by tcm) 'function'))
    =/  fnm=(map @t json)  (need (me fn))
    :+  (so:dejs:format (need (~(get by tcm) 'id')))
      (so:dejs:format (need (~(get by fnm) 'name')))
    (so:dejs:format (need (~(get by fnm) 'arguments')))
  [%tools tc-content calls]
++  tool-result-json
  |=  [tid=@t con=@t]
  ^-  json
  %-  pairs:enjs:format
  :~  ['role' s+'tool']
      ['tool_call_id' s+tid]
      ['content' s+con]
  ==
++  make-text-body
  |=  con=@t
  ^-  @t
  %-  en:json:html
  %-  pairs:enjs:format
  :~  :-  'choices'
      :-  %a
      :~  %-  pairs:enjs:format
          :~  :-  'message'
              %-  pairs:enjs:format
              :~  ['role' s+'assistant']
                  ['content' s+con]
              ==
          ==
      ==
  ==
++  make-tool-body
  |=  [con=@t calls=(list [tid=@t tname=@t args=@t])]
  ^-  @t
  %-  en:json:html
  %-  pairs:enjs:format
  :~  :-  'choices'
      :-  %a
      :~  %-  pairs:enjs:format
          :~  :-  'message'
              %-  pairs:enjs:format
              :~  ['role' s+'assistant']
                  ['content' s+con]
                  :-  'tool_calls'
                  :-  %a
                  %+  turn  calls
                  |=  [tid=@t tname=@t args=@t]
                  %-  pairs:enjs:format
                  :~  ['id' s+tid]
                      ['type' s+'function']
                      :-  'function'
                      %-  pairs:enjs:format
                      :~  ['name' s+tname]
                          ['arguments' s+args]
                      ==
                  ==
              ==
          ==
      ==
  ==
--
|%
++  test-lcm-key-direct
  (expect-eq !>('direct') !>((lcm-key [%direct ~])))
++  test-model-budget-claude
  (expect-eq !>(150.000) !>((model-budget 'anthropic/claude-sonnet-4')))
++  test-parse-text-simple
  =/  body=@t  (make-text-body 'Hello world!')
  =/  result  (parse-llm-response body)
  (expect-eq !>(`[%text 'Hello world!']) !>(result))
++  test-parse-bad-json
  (expect-eq !>(~) !>((parse-llm-response 'not json at all')))
++  test-parse-tool
  =/  body=@t  (make-tool-body '' ~[['call_abc' 'web_search' 'query-urbit']])
  =/  result  (parse-llm-response body)
  ?~  result  ['parse returned ~' ~]
  ?.  ?=(%tools -.u.result)  ['expected %tools' ~]
  (expect-eq !>(1) !>((lent calls.u.result)))
++  test-tool-result-json
  =/  j=json  (tool-result-json 'call_1' 'results')
  ?.  ?=([%o *] j)  ['expected json object' ~]
  (expect-eq !>(`s+'tool') !>((~(get by p.j) 'role')))
--
