::  lcm: lossless context management agent
::
::  stores conversations, builds DAG summaries via LLM,
::  assembles token-budgeted context for claw.
::
/-  lcm
/+  default-agent, dbug
|%
+$  card  card:agent:gall
+$  versioned-state  versioned-state:lcm
::
++  estimate-tokens
  |=  text=@t
  ^-  @ud
  (div (add (met 3 text) 3) 4)
::
++  model-budget
  |=  mod=@t
  ^-  @ud
  =/  m=tape  (cass (trip mod))
  ?:  !=(~ (find "claude" m))  150.000
  ?:  !=(~ (find "gpt-4" m))   100.000
  ?:  !=(~ (find "gemini" m))  800.000
  50.000
::
::  +effective-budget: use context-window if set, else model-budget
::
++  effective-budget
  |=  cfg=lcm-config:lcm
  ^-  @ud
  ?:  (gth context-window.cfg 0)
    context-window.cfg
  (model-budget model.cfg)
::
::  +context-tokens: total tokens in active context
::
++  context-tokens
  |=  =conversation:lcm
  ^-  @ud
  %+  roll  context-items.conversation
  |=  [ci=context-item:lcm acc=@ud]
  ?-  -.ci
      %msg
    =/  m=(unit stored-msg:lcm)  (~(get by messages.conversation) seq.ci)
    ?~  m  acc
    (add acc token-est.u.m)
      %sum
    =/  s=(unit summary:lcm)  (~(get by summaries.conversation) id.ci)
    ?~  s  acc
    (add acc token-est.u.s)
  ==
::
::  +format-timestamp: format @da to [YYYY-MM-DD HH:MM] string
::
++  format-timestamp
  |=  d=@da
  ^-  tape
  =/  dt=date  (yore d)
  ;:  weld
    "["
    (a-co:co y.dt)
    "-"
    ?:((lth m.dt 10) "0" "")
    (a-co:co m.dt)
    "-"
    ?:((lth d.t.dt 10) "0" "")
    (a-co:co d.t.dt)
    " "
    ?:((lth h.t.dt 10) "0" "")
    (a-co:co h.t.dt)
    ":"
    ?:((lth m.t.dt 10) "0" "")
    (a-co:co m.t.dt)
    "] "
  ==
::
::  +assemble: build context from summaries + fresh tail within budget
::
++  assemble
  |=  [=conversation:lcm budget=@ud]
  ^-  (list [role=@t content=@t])
  =/  items=(list context-item:lcm)  context-items.conversation
  =/  len=@ud  (lent items)
  =/  tail-n=@ud  (min len 16)  ::  TODO: use config
  =/  fresh=(list context-item:lcm)  (slag (sub len tail-n) items)
  =/  before=(list context-item:lcm)  (scag (sub len tail-n) items)
  ::  resolve fresh tail (always included)
  =/  fresh-msgs=(list [role=@t content=@t])
    %+  murn  fresh
    |=  ci=context-item:lcm
    ^-  (unit [role=@t content=@t])
    ?-  -.ci
        %msg
      =/  m=(unit stored-msg:lcm)  (~(get by messages.conversation) seq.ci)
      ?~  m  ~
      `[role.u.m content.u.m]
        %sum
      =/  s=(unit summary:lcm)  (~(get by summaries.conversation) id.ci)
      ?~  s  ~
      =/  txt=@t
        %+  rap  3
        :~  '<summary depth="'
            (scot %ud depth.u.s)
            '" range="'
            (scot %da earliest.u.s)
            ' - '
            (scot %da latest.u.s)
            '">\0a'
            content.u.s
            '\0a</summary>'
        ==
      `['system' txt]
    ==
  =/  fresh-tok=@ud
    %+  roll  fresh-msgs
    |=  [[r=@t c=@t] acc=@ud]
    (add acc (estimate-tokens c))
  =/  remaining=@ud  ?:((gth fresh-tok budget) 0 (sub budget fresh-tok))
  ::  fill remaining budget from oldest items
  =/  prefix=(list [role=@t content=@t])  ~
  |-
  ?~  before  (weld prefix fresh-msgs)
  =/  ci  i.before
  =/  resolved=(unit [role=@t content=@t tok=@ud])
    ?-  -.ci
        %msg
      =/  m=(unit stored-msg:lcm)  (~(get by messages.conversation) seq.ci)
      ?~  m  ~
      `[role.u.m content.u.m token-est.u.m]
        %sum
      =/  s=(unit summary:lcm)  (~(get by summaries.conversation) id.ci)
      ?~  s  ~
      =/  txt=@t
        %+  rap  3
        :~  '<summary depth="'
            (scot %ud depth.u.s)
            '" range="'
            (scot %da earliest.u.s)
            ' - '
            (scot %da latest.u.s)
            '">\0a'
            content.u.s
            '\0a</summary>'
        ==
      `['system' txt token-est.u.s]
    ==
  ?~  resolved  $(before t.before)
  ?:  (gth tok.u.resolved remaining)
    ::  skip items that don't fit, try next
    $(before t.before)
  %=  $
    before     t.before
    remaining  (sub remaining tok.u.resolved)
    prefix     (snoc prefix [-.u.resolved +<.u.resolved])
  ==
::
::  +select-leaf-chunk: pick oldest raw msgs outside fresh tail for compaction
::
++  select-leaf-chunk
  |=  [=conversation:lcm max-tokens=@ud fresh-tail-n=@ud]
  ^-  (list @ud)
  =/  items  context-items.conversation
  =/  len  (lent items)
  =/  cutoff  (sub len (min len fresh-tail-n))
  =/  eligible  (scag cutoff items)
  ::  collect raw message seqs until we hit max-tokens
  =/  collected=(list @ud)  ~
  =/  tok=@ud  0
  |-
  ?~  eligible  (flop collected)
  ?.  ?=(%msg -.i.eligible)  $(eligible t.eligible)
  =/  m=(unit stored-msg:lcm)  (~(get by messages.conversation) seq.i.eligible)
  ?~  m  $(eligible t.eligible)
  ?:  (gth (add tok token-est.u.m) max-tokens)
    ?~  collected  ::  always take at least one
      (flop [seq.i.eligible collected])
    (flop collected)
  %=  $
    eligible   t.eligible
    tok        (add tok token-est.u.m)
    collected  [seq.i.eligible collected]
  ==
::
::  +select-condensation-group: find shallowest group of summaries for condensation
::  returns ~ if no group meets condense-min-fanout
::
++  select-condensation-group
  |=  [=conversation:lcm fresh-tail-n=@ud min-fanout=@ud]
  ^-  (unit [depth=@ud ids=(list @ud)])
  =/  items  context-items.conversation
  =/  len  (lent items)
  =/  cutoff  (sub len (min len fresh-tail-n))
  =/  eligible  (scag cutoff items)
  ::  collect summary ids by depth, find shallowest group
  =/  depth-map=(map @ud (list @ud))  ~
  |-
  ?~  eligible
    ::  find shallowest depth with enough summaries
    =/  depths=(list @ud)
      %+  sort  ~(tap in ~(key by depth-map))
      lth
    |-
    ?~  depths  ~
    =/  ids=(list @ud)  (~(got by depth-map) i.depths)
    ?:  (gte (lent ids) min-fanout)
      `[i.depths (flop ids)]
    $(depths t.depths)
  ?.  ?=(%sum -.i.eligible)
    $(eligible t.eligible)
  =/  s=(unit summary:lcm)  (~(get by summaries.conversation) id.i.eligible)
  ?~  s  $(eligible t.eligible)
  =/  d=@ud  depth.u.s
  =/  existing=(list @ud)  (fall (~(get by depth-map) d) ~)
  %=  $
    eligible   t.eligible
    depth-map  (~(put by depth-map) d [id.i.eligible existing])
  ==
::
::  +depth-prompt: return the system prompt for a given compaction depth
::
++  depth-prompt
  |=  [depth=@ud target=@ud]
  ^-  @t
  =/  target-tape=tape  (a-co:co target)
  ?:  =(0 depth)
    ::  leaf prompt
    %-  crip
    ;:  weld
      "You summarize a SEGMENT of a conversation for future model turns. "
      "Treat this as incremental memory compaction input, not a full-conversation summary.\0a\0a"
      "Normal summary policy:\0a"
      "- Preserve key decisions, rationale, constraints, and active tasks.\0a"
      "- Keep essential technical details needed to continue work safely.\0a"
      "- Remove obvious repetition and conversational filler.\0a\0a"
      "Output requirements:\0a"
      "- Plain text only.\0a"
      "- No preamble, headings, or markdown formatting.\0a"
      "- Keep it concise while preserving required details.\0a"
      "- Track file operations (created, modified, deleted, renamed) with file paths and current status.\0a"
      "- If no file operations appear, include exactly: \"Files: none\".\0a"
      "- If timestamps appear in the input, note the approximate time range covered "
      "and preserve timestamps for key events (decisions, completions, state changes).\0a"
      "- End with a line: \"Expand for details about: <comma-separated list of what was dropped or compressed>\"\0a"
      "- Target length: about "
      target-tape
      " tokens or less."
    ==
  ?:  =(1 depth)
    ::  condensed d1 prompt
    %-  crip
    ;:  weld
      "You are compacting leaf-level conversation summaries into a single condensed memory node.\0a"
      "You are preparing context for a fresh model instance that will continue this conversation.\0a"
      "Focus on what matters for continuation:\0a"
      "- Decisions made and their rationale (only when rationale matters going forward)\0a"
      "- Decisions from earlier that were altered or superseded, and what replaced them\0a"
      "- Tasks or topics completed, with outcomes (not just \"done\" -- what was the result?)\0a"
      "- Things still in progress: current state, what remains\0a"
      "- Blockers, open questions, and unresolved tensions\0a"
      "- Specific references (names, paths, URLs, identifiers) that future turns will need\0a\0a"
      "Drop minutiae -- operational details that won't affect future turns:\0a"
      "- Intermediate exploration or dead ends when the conclusion is known (keep the conclusion)\0a"
      "- Transient states that are already resolved\0a"
      "- Tool-internal mechanics and process scaffolding\0a"
      "- Verbose references when shorter forms would suffice\0a\0a"
      "Use plain text. No mandatory structure -- organize however makes the content clearest.\0a"
      "Mention sequence and causality (\"after fixing X, moved to Y\") but keep timestamps light.\0a"
      "Mark decisions that supersede earlier ones.\0a\0a"
      "End with: \"Expand for details about: <list of compressed-away specifics>\"\0a"
      "Target length: about "
      target-tape
      " tokens."
    ==
  ?:  =(2 depth)
    ::  condensed d2 prompt
    %-  crip
    ;:  weld
      "You are condensing multiple session-level summaries into a higher-level memory node.\0a"
      "Each input summary covers a significant block of conversation. "
      "Your job is to extract the arc:\0a"
      "what was the goal, what happened, and what carries forward.\0a\0a"
      "A future model instance will read this to understand the trajectory of this conversation --\0a"
      "not the details of each session, but the overall shape of what occurred and where things stand.\0a\0a"
      "Preserve:\0a"
      "- Decisions that are still in effect and their rationale\0a"
      "- Decisions that evolved: what changed and why\0a"
      "- Completed work with outcomes (not process)\0a"
      "- Active constraints, limitations, and known issues\0a"
      "- Current state of anything still in progress\0a"
      "- Key references only if they're still relevant\0a\0a"
      "Drop:\0a"
      "- Per-session operational minutiae\0a"
      "- Specific identifiers and references that were only relevant within a session\0a"
      "- Anything \"planned\" in an earlier summary and \"completed\" in a later one -- just record the completion\0a"
      "- Intermediate states that a later summary supersedes\0a"
      "- How things were done (unless the method itself was the decision)\0a\0a"
      "Use plain text. Brief section headers are fine if they help organize.\0a"
      "Focus on the narrative arc, not per-session chronology.\0a"
      "End with: \"Expand for details about: <list of compressed-away specifics>\"\0a"
      "Target length: about "
      target-tape
      " tokens."
    ==
  ::  depth 3+ prompt
  %-  crip
  ;:  weld
    "You are creating a high-level memory node from multiple phase-level summaries.\0a"
    "This node may persist for the entire remaining conversation. "
    "Only include what a fresh model\0a"
    "instance would need to pick up this conversation cold -- possibly days or weeks from now.\0a\0a"
    "Think: \"what would I need to know?\" not \"what happened?\"\0a\0a"
    "Preserve:\0a"
    "- Key decisions and their rationale\0a"
    "- What was accomplished and its current state\0a"
    "- Active constraints and hard limitations\0a"
    "- Important relationships between people, systems, or concepts\0a"
    "- Lessons learned (\"don't do X because Y\")\0a\0a"
    "Drop:\0a"
    "- All operational and process detail\0a"
    "- How things were done (only what was decided and the outcome)\0a"
    "- Specific references unless they're essential for continuation\0a"
    "- Progress narratives (everything is either done or captured as current state)\0a\0a"
    "Use plain text. Be ruthlessly concise.\0a"
    "End with: \"Expand for details about: <list of compressed-away specifics>\"\0a"
    "Target length: about "
    target-tape
    " tokens."
  ==
::
::  +make-compact-request: build LLM summarization request
::
++  make-compact-request
  |=  [=bowl:gall cfg=lcm-config:lcm msgs=(list stored-msg:lcm) depth=@ud =wire]
  ^-  card
  =/  target=@ud
    ?:  =(0 depth)  leaf-target-tokens.cfg
    condense-target-tokens.cfg
  =/  sys=@t  (depth-prompt depth target)
  =/  msg-text=@t
    %-  crip
    %-  zing
    %+  turn  msgs
    |=  m=stored-msg:lcm
    ;:  weld
      (format-timestamp created.m)
      (trip role.m)
      ": "
      (trip content.m)
      "\0a"
    ==
  =/  api-msgs=json
    :-  %a
    :~  (pairs:enjs:format ~[['role' s+'system'] ['content' s+sys]])
        (pairs:enjs:format ~[['role' s+'user'] ['content' s+msg-text]])
    ==
  =/  body=json
    (pairs:enjs:format ~[['model' s+model.cfg] ['messages' api-msgs]])
  =/  body-cord=@t  (en:json:html body)
  =/  hed=(list [key=@t value=@t])
    :~  ['Content-Type' 'application/json']
        ['Authorization' (crip "Bearer {(trip api-key.cfg)}")]
    ==
  [%pass wire %arvo %i %request [%'POST' 'https://openrouter.ai/api/v1/chat/completions' hed `(as-octs:mimes:html body-cord)] *outbound-config:iris]
::
::  +make-condensed-request: build LLM condensation request from summaries
::
++  make-condensed-request
  |=  [=bowl:gall cfg=lcm-config:lcm sums=(list summary:lcm) new-depth=@ud =wire]
  ^-  card
  =/  target=@ud  condense-target-tokens.cfg
  =/  sys=@t  (depth-prompt new-depth target)
  =/  sum-text=@t
    %-  crip
    %-  zing
    %+  turn  sums
    |=  s=summary:lcm
    ;:  weld
      "--- Summary (depth "
      (a-co:co depth.s)
      ", "
      (trip (scot %da earliest.s))
      " to "
      (trip (scot %da latest.s))
      ") ---\0a"
      (trip content.s)
      "\0a\0a"
    ==
  =/  api-msgs=json
    :-  %a
    :~  (pairs:enjs:format ~[['role' s+'system'] ['content' s+sys]])
        (pairs:enjs:format ~[['role' s+'user'] ['content' s+sum-text]])
    ==
  =/  body=json
    (pairs:enjs:format ~[['model' s+model.cfg] ['messages' api-msgs]])
  =/  body-cord=@t  (en:json:html body)
  =/  hed=(list [key=@t value=@t])
    :~  ['Content-Type' 'application/json']
        ['Authorization' (crip "Bearer {(trip api-key.cfg)}")]
    ==
  [%pass wire %arvo %i %request [%'POST' 'https://openrouter.ai/api/v1/chat/completions' hed `(as-octs:mimes:html body-cord)] *outbound-config:iris]
::
::  +parse-response: extract text from OpenRouter response
::
++  parse-response
  |=  body=@t
  ^-  (unit @t)
  =/  jon=(unit json)  (de:json:html body)
  ?~  jon  ~
  %-  mole  |.
  ^-  @t
  =,  dejs:format
  =/  choices=(list @t)
    %.  u.jon
    (ot ~[choices+(ar (ot ~[message+(ot ~[content+so])]))])
  ?~  choices  !!
  i.choices
--
::
%-  agent:dbug
=|  state-1:lcm
=*  state  -
^-  agent:gall
|_  =bowl:gall
+*  this  .
    def   ~(. (default-agent this %|) bowl)
::
++  on-init
  ^-  (quip card _this)
  %-  (slog leaf+"lcm: initialized" ~)
  =/  default-cfg=lcm-config:lcm
    :*  ''  'anthropic/claude-sonnet-4'
        75  16  20.000  1.200  2.000  8  4  0
    ==
  `this(lcm-config default-cfg)
::
++  on-save  !>(state)
::
++  on-load
  |=  =vase
  ^-  (quip card _this)
  =/  old  !<(versioned-state vase)
  ?-  -.old
      %1  `this(state old)
  ::
      %0
    %-  (slog leaf+"lcm: migrating state-0 to state-1" ~)
    ::  pull fields from untyped old state via ;;
    =/  old-convs=(map @t conversation:lcm)
      =/  raw  conversations.old
      ::  rebuild conversations, migrating summaries to add new fields
      %-  ~(run by ;;((map @t *) raw))
      |=  val=*
      ^-  conversation:lcm
      =/  raw-conv  ;;([messages=* summaries=* context-items=* next-seq=@ud next-sum=@ud] val)
      =/  old-msgs=(map @ud stored-msg:lcm)  ;;((map @ud stored-msg:lcm) messages.raw-conv)
      =/  old-sums=(map @ud *)  ;;((map @ud *) summaries.raw-conv)
      =/  new-sums=(map @ud summary:lcm)
        %-  ~(run by old-sums)
        |=  v=*
        ^-  summary:lcm
        =/  old-sum
          ;;  $:  id=@ud  kind=?(%leaf %condensed)  depth=@ud
              content=@t  token-est=@ud
              source-msgs=(set @ud)  parent-sums=(set @ud)
              earliest=@da  latest=@da  created=@da
          ==
          v
        :*  id.old-sum  kind.old-sum  depth.old-sum
            content.old-sum  token-est.old-sum
            source-msgs.old-sum  parent-sums.old-sum
            earliest.old-sum  latest.old-sum  created.old-sum
            0  0
        ==
      =/  old-citems=(list context-item:lcm)  ;;((list context-item:lcm) context-items.raw-conv)
      [old-msgs new-sums old-citems next-seq.raw-conv next-sum.raw-conv]
    =/  old-cfg  ;;([api-key=@t model=@t context-threshold=@ud fresh-tail=@ud leaf-chunk-tokens=@ud leaf-target-tokens=@ud condense-target-tokens=@ud leaf-min-fanout=@ud condense-min-fanout=@ud] lcm-config.old)
    =/  new-cfg=lcm-config:lcm
      :*  api-key.old-cfg  model.old-cfg
          context-threshold.old-cfg  fresh-tail.old-cfg
          leaf-chunk-tokens.old-cfg  leaf-target-tokens.old-cfg
          condense-target-tokens.old-cfg  leaf-min-fanout.old-cfg
          condense-min-fanout.old-cfg  0
      ==
    =/  old-cs=compact-state:lcm  ;;(compact-state:lcm compact-state.old)
    `this(state [%1 old-convs new-cfg old-cs])
  ==
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?>  =(src our):bowl
  ?.  ?=(%lcm-action mark)
    (on-poke:def mark vase)
  =/  act=lcm-action:lcm  !<(lcm-action:lcm vase)
  ?-  -.act
  ::
      %set-config
    %-  (slog leaf+"lcm: config updated" ~)
    `this(lcm-config lcm-config.act)
  ::
      %clear
    %-  (slog leaf+"lcm: cleared {(trip key.act)}" ~)
    `this(conversations (~(del by conversations) key.act))
  ::
      %ingest
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key.act) *conversation:lcm)
    =/  tok=@ud  (estimate-tokens content.act)
    =/  =stored-msg:lcm
      [next-seq.conv role.act content.act tok now.bowl]
    =.  messages.conv  (~(put by messages.conv) next-seq.conv stored-msg)
    =.  context-items.conv  (snoc context-items.conv [%msg next-seq.conv])
    =.  next-seq.conv  +(next-seq.conv)
    =.  conversations  (~(put by conversations) key.act conv)
    ::  check compaction trigger
    =/  total-tok=@ud  (context-tokens conv)
    =/  budget=@ud  (effective-budget lcm-config)
    =/  threshold=@ud  (div (mul budget context-threshold.lcm-config) 100)
    ::  count raw msgs outside fresh tail
    =/  items-len=@ud  (lent context-items.conv)
    =/  tail-n=@ud  (min items-len fresh-tail.lcm-config)
    =/  eligible=(list context-item:lcm)  (scag (sub items-len tail-n) context-items.conv)
    =/  raw-count=@ud
      %+  roll  eligible
      |=  [ci=context-item:lcm acc=@ud]
      ?:(?=(%msg -.ci) +(acc) acc)
    ?.  &(?=([%idle ~] compact-state) (gth total-tok threshold) (gte raw-count leaf-min-fanout.lcm-config) !=('' api-key.lcm-config))
      `this
    ::  trigger leaf compaction
    =/  chunk=(list @ud)
      (select-leaf-chunk conv leaf-chunk-tokens.lcm-config fresh-tail.lcm-config)
    ?:  (lth (lent chunk) 3)  `this
    =/  chunk-msgs=(list stored-msg:lcm)
      %+  murn  chunk
      |=(seq=@ud (~(get by messages.conv) seq))
    %-  (slog leaf+"lcm: compacting {(a-co:co (lent chunk))} messages for {(trip key.act)}" ~)
    :_  this(compact-state [%running key.act])
    :~  (make-compact-request bowl lcm-config chunk-msgs 0 /compact/[key.act])
    ==
  ::
      %compact
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key.act) *conversation:lcm)
    ?.  ?=([%idle ~] compact-state)
      %-  (slog leaf+"lcm: compaction already running" ~)
      `this
    =/  chunk=(list @ud)
      (select-leaf-chunk conv leaf-chunk-tokens.lcm-config fresh-tail.lcm-config)
    ?:  (lth (lent chunk) 3)
      %-  (slog leaf+"lcm: not enough messages to compact" ~)
      `this
    =/  chunk-msgs=(list stored-msg:lcm)
      %+  murn  chunk
      |=(seq=@ud (~(get by messages.conv) seq))
    %-  (slog leaf+"lcm: manually compacting {(a-co:co (lent chunk))} messages" ~)
    :_  this(compact-state [%running key.act])
    :~  (make-compact-request bowl lcm-config chunk-msgs 0 /compact/[key.act])
    ==
  ==
::
++  on-watch
  |=  =path
  ^-  (quip card _this)
  (on-watch:def path)
::
++  on-leave  on-leave:def
::
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  ?+  path  ~
  ::
  ::  assemble context for a conversation within token budget
  ::
      [%x %assemble @ @ ~]
    =/  key=@t  i.t.t.path
    =/  budget=@ud  (slav %ud i.t.t.t.path)
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key) *conversation:lcm)
    =/  msgs=(list [role=@t content=@t])
      (assemble conv budget)
    =/  j=json
      :-  %a
      %+  turn  msgs
      |=  [role=@t content=@t]
      (pairs:enjs:format ~[['role' s+role] ['content' s+content]])
    ``json+!>(j)
  ::
  ::  search messages and summaries
  ::
      [%x %grep @ @ ~]
    =/  key=@t  i.t.t.path
    =/  query=@t  i.t.t.t.path
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key) *conversation:lcm)
    =/  q=tape  (cass (trip query))
    ::  search summaries
    =/  sum-hits=(list json)
      %+  murn  ~(val by summaries.conv)
      |=  s=summary:lcm
      ?.  !=(~ (find q (cass (trip content.s))))  ~
      %-  some
      %-  pairs:enjs:format
      :~  ['type' s+'summary']
          ['id' (numb:enjs:format id.s)]
          ['depth' (numb:enjs:format depth.s)]
          ['content' s+(crip (scag 500 (trip content.s)))]
      ==
    ::  search messages
    =/  msg-hits=(list json)
      %+  murn  ~(val by messages.conv)
      |=  m=stored-msg:lcm
      ?.  !=(~ (find q (cass (trip content.m))))  ~
      %-  some
      %-  pairs:enjs:format
      :~  ['type' s+'message']
          ['seq' (numb:enjs:format seq.m)]
          ['role' s+role.m]
          ['content' s+(crip (scag 300 (trip content.m)))]
      ==
    ``json+!>(a+(weld sum-hits msg-hits))
  ::
  ::  describe a summary
  ::
      [%x %describe @ @ ~]
    =/  key=@t  i.t.t.path
    =/  sid=@ud  (slav %ud i.t.t.t.path)
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key) *conversation:lcm)
    =/  s=(unit summary:lcm)  (~(get by summaries.conv) sid)
    ?~  s  ``json+!>(~)
    =/  j=json
      %-  pairs:enjs:format
      :~  ['id' (numb:enjs:format id.u.s)]
          ['kind' s+?:(=(%leaf kind.u.s) 'leaf' 'condensed')]
          ['depth' (numb:enjs:format depth.u.s)]
          ['content' s+content.u.s]
          ['token-est' (numb:enjs:format token-est.u.s)]
          ['source-msgs' a+(turn ~(tap in source-msgs.u.s) |=(n=@ud (numb:enjs:format n)))]
          ['parent-sums' a+(turn ~(tap in parent-sums.u.s) |=(n=@ud (numb:enjs:format n)))]
          ['earliest' s+(scot %da earliest.u.s)]
          ['latest' s+(scot %da latest.u.s)]
          ['descendant-count' (numb:enjs:format descendant-count.u.s)]
          ['descendant-tokens' (numb:enjs:format descendant-tokens.u.s)]
      ==
    ``json+!>(j)
  ::
  ::  conversation stats
  ::
      [%x %stats @ ~]
    =/  key=@t  i.t.t.path
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key) *conversation:lcm)
    =/  j=json
      %-  pairs:enjs:format
      :~  ['messages' (numb:enjs:format ~(wyt by messages.conv))]
          ['summaries' (numb:enjs:format ~(wyt by summaries.conv))]
          ['context-items' (numb:enjs:format (lent context-items.conv))]
          ['total-tokens' (numb:enjs:format (context-tokens conv))]
      ==
    ``json+!>(j)
  ::
  ::  list conversations
  ::
      [%x %conversations ~]
    =/  j=json
      :-  %a
      %+  turn  ~(tap by conversations)
      |=  [key=@t conv=conversation:lcm]
      %-  pairs:enjs:format
      :~  ['key' s+key]
          ['messages' (numb:enjs:format ~(wyt by messages.conv))]
          ['summaries' (numb:enjs:format ~(wyt by summaries.conv))]
      ==
    ``json+!>(j)
  ==
::
++  on-agent  on-agent:def
::
++  on-arvo
  |=  [=wire sign=sign-arvo]
  ^-  (quip card _this)
  ?+  wire  (on-arvo:def wire sign)
  ::
  ::  leaf compaction response
  ::
      [%compact @ ~]
    =/  key=@t  i.t.wire
    ?.  ?=([%iris %http-response *] sign)
      =.  compact-state  [%idle ~]
      `this
    =/  resp=client-response:iris  client-response.sign
    ?.  ?=(%finished -.resp)
      =.  compact-state  [%idle ~]
      `this
    ?.  =(200 status-code.response-header.resp)
      %-  (slog leaf+"lcm: compaction LLM call failed, will retry" ~)
      =.  compact-state  [%idle ~]
      `this
    ?~  full-file.resp
      =.  compact-state  [%idle ~]
      `this
    =/  parsed=(unit @t)  (parse-response q.data.u.full-file.resp)
    ?~  parsed
      %-  (slog leaf+"lcm: could not parse compaction response" ~)
      =.  compact-state  [%idle ~]
      `this
    =/  summary-text=@t  u.parsed
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key) *conversation:lcm)
    ::  find which seqs were in the chunk (raw msgs in context-items
    ::  before fresh tail that were selected)
    =/  chunk=(list @ud)
      (select-leaf-chunk conv leaf-chunk-tokens.lcm-config fresh-tail.lcm-config)
    =/  chunk-set=(set @ud)  (silt chunk)
    ::  get time range from compacted messages
    =/  earliest=@da  now.bowl
    =/  latest=@da  *@da
    =.  earliest
      %+  roll  chunk
      |=  [seq=@ud acc=@da]
      =/  m=(unit stored-msg:lcm)  (~(get by messages.conv) seq)
      ?~  m  acc
      ?:((lth created.u.m acc) created.u.m acc)
    =.  latest
      %+  roll  chunk
      |=  [seq=@ud acc=@da]
      =/  m=(unit stored-msg:lcm)  (~(get by messages.conv) seq)
      ?~  m  acc
      ?:((gth created.u.m acc) created.u.m acc)
    ::  compute descendant tracking for leaf summary
    =/  desc-count=@ud  (lent chunk)
    =/  desc-tokens=@ud
      %+  roll  chunk
      |=  [seq=@ud acc=@ud]
      =/  m=(unit stored-msg:lcm)  (~(get by messages.conv) seq)
      ?~  m  acc
      (add acc token-est.u.m)
    ::  create summary
    =/  sid=@ud  next-sum.conv
    =/  =summary:lcm
      :*  sid  %leaf  0
          summary-text  (estimate-tokens summary-text)
          chunk-set  ~
          earliest  latest  now.bowl
          desc-count  desc-tokens
      ==
    =.  summaries.conv  (~(put by summaries.conv) sid summary)
    =.  next-sum.conv  +(sid)
    ::  replace compacted items in context-items with summary ref
    =/  new-items=(list context-item:lcm)
      =/  inserted=?  %.n
      %+  murn  context-items.conv
      |=  ci=context-item:lcm
      ^-  (unit context-item:lcm)
      ?.  ?=(%msg -.ci)  `ci
      ?.  (~(has in chunk-set) seq.ci)  `ci
      ::  replace first compacted msg with summary, skip rest
      ?.  inserted
        =.  inserted  %.y
        `[%sum sid]
      ~
    =.  context-items.conv  new-items
    =.  conversations  (~(put by conversations) key conv)
    =.  compact-state  [%idle ~]
    %-  (slog leaf+"lcm: created summary {(a-co:co sid)} ({(a-co:co (lent chunk))} msgs -> {(a-co:co (estimate-tokens summary-text))} tokens)" ~)
    ::  check for condensation opportunity
    =/  cond-group  (select-condensation-group conv fresh-tail.lcm-config condense-min-fanout.lcm-config)
    ?~  cond-group  `this
    =/  cdepth=@ud  depth.u.cond-group
    =/  cids=(list @ud)  ids.u.cond-group
    =/  cond-sums=(list summary:lcm)
      %+  murn  cids
      |=(id=@ud (~(get by summaries.conv) id))
    ?:  (lth (lent cond-sums) condense-min-fanout.lcm-config)
      `this
    =/  new-depth=@ud  +(cdepth)
    %-  (slog leaf+"lcm: triggering condensation of {(a-co:co (lent cond-sums))} depth-{(a-co:co cdepth)} summaries for {(trip key)}" ~)
    :_  this(compact-state [%running key])
    :~  (make-condensed-request bowl lcm-config cond-sums new-depth /compact-condensed/[key]/[(scot %ud new-depth)])
    ==
  ::
  ::  condensed compaction response
  ::
      [%compact-condensed @ @ ~]
    =/  key=@t  i.t.wire
    =/  new-depth=@ud  (slav %ud i.t.t.wire)
    ?.  ?=([%iris %http-response *] sign)
      =.  compact-state  [%idle ~]
      `this
    =/  resp=client-response:iris  client-response.sign
    ?.  ?=(%finished -.resp)
      =.  compact-state  [%idle ~]
      `this
    ?.  =(200 status-code.response-header.resp)
      %-  (slog leaf+"lcm: condensation LLM call failed" ~)
      =.  compact-state  [%idle ~]
      `this
    ?~  full-file.resp
      =.  compact-state  [%idle ~]
      `this
    =/  parsed=(unit @t)  (parse-response q.data.u.full-file.resp)
    ?~  parsed
      %-  (slog leaf+"lcm: could not parse condensation response" ~)
      =.  compact-state  [%idle ~]
      `this
    =/  summary-text=@t  u.parsed
    =/  conv=conversation:lcm
      (fall (~(get by conversations) key) *conversation:lcm)
    ::  re-find the condensation group (same depth, before fresh tail)
    =/  child-depth=@ud  (dec new-depth)
    =/  cond-group  (select-condensation-group conv fresh-tail.lcm-config condense-min-fanout.lcm-config)
    ::  if no group found at expected depth, just store and bail
    =/  cids=(list @ud)
      ?~  cond-group  ~
      ?.  =(child-depth depth.u.cond-group)  ~
      ids.u.cond-group
    ?:  =(~ cids)
      %-  (slog leaf+"lcm: condensation group no longer present, discarding" ~)
      =.  compact-state  [%idle ~]
      `this
    =/  cid-set=(set @ud)  (silt cids)
    =/  child-sums=(list summary:lcm)
      %+  murn  cids
      |=(id=@ud (~(get by summaries.conv) id))
    ::  compute time range from children
    =/  earliest=@da  now.bowl
    =/  latest=@da  *@da
    =.  earliest
      %+  roll  child-sums
      |=  [s=summary:lcm acc=@da]
      ?:((lth earliest.s acc) earliest.s acc)
    =.  latest
      %+  roll  child-sums
      |=  [s=summary:lcm acc=@da]
      ?:((gth latest.s acc) latest.s acc)
    ::  compute descendant tracking
    =/  desc-count=@ud
      %+  roll  child-sums
      |=  [s=summary:lcm acc=@ud]
      (add acc +(descendant-count.s))
    =/  desc-tokens=@ud
      %+  roll  child-sums
      |=  [s=summary:lcm acc=@ud]
      (add acc (add token-est.s descendant-tokens.s))
    ::  collect all source-msgs from children
    =/  all-src=(set @ud)
      %+  roll  child-sums
      |=  [s=summary:lcm acc=(set @ud)]
      (~(uni in acc) source-msgs.s)
    ::  create condensed summary
    =/  sid=@ud  next-sum.conv
    =/  =summary:lcm
      :*  sid  %condensed  new-depth
          summary-text  (estimate-tokens summary-text)
          all-src  cid-set
          earliest  latest  now.bowl
          desc-count  desc-tokens
      ==
    =.  summaries.conv  (~(put by summaries.conv) sid summary)
    =.  next-sum.conv  +(sid)
    ::  replace child summaries in context-items with new condensed ref
    =/  new-items=(list context-item:lcm)
      =/  inserted=?  %.n
      %+  murn  context-items.conv
      |=  ci=context-item:lcm
      ^-  (unit context-item:lcm)
      ?.  ?=(%sum -.ci)  `ci
      ?.  (~(has in cid-set) id.ci)  `ci
      ?.  inserted
        =.  inserted  %.y
        `[%sum sid]
      ~
    =.  context-items.conv  new-items
    =.  conversations  (~(put by conversations) key conv)
    =.  compact-state  [%idle ~]
    %-  (slog leaf+"lcm: created condensed summary {(a-co:co sid)} (depth {(a-co:co new-depth)}, {(a-co:co (lent child-sums))} children -> {(a-co:co (estimate-tokens summary-text))} tokens)" ~)
    `this
  ==
::
++  on-fail  on-fail:def
--
