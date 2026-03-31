::  claw: llm agent harness types
::
|%
+$  msg  [role=@t content=@t]
+$  ship-role  ?(%owner %allowed)
::
::  $bot-config: per-bot identity and configuration
::
+$  bot-config
  $:  bot-name=(unit @t)
      bot-avatar=(unit @t)
      model=(unit @t)
      api-key=(unit @t)
      brave-key=(unit @t)
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      channel-perms=(map @t channel-perm)
      cron-jobs=(map @ud cron-job)
      next-cron-id=@ud
  ==
::
+$  action
  $%  ::  global defaults
      [%set-key key=@t]
      [%set-model model=@t]
      [%set-brave-key key=@t]
      [%prompt content=@t]
      [%clear ~]
      ::  bot management
      [%add-bot id=@tas]
      [%del-bot id=@tas]
      [%set-default-bot id=@tas]
      ::  per-bot config (scoped by bot-id)
      [%bot-set-name id=@tas name=(unit @t)]
      [%bot-set-avatar id=@tas avatar=(unit @t)]
      [%bot-set-model id=@tas model=(unit @t)]
      [%bot-set-key id=@tas key=(unit @t)]
      [%bot-set-brave-key id=@tas key=(unit @t)]
      [%bot-set-context id=@tas field=@tas content=@t]
      [%bot-append-context id=@tas field=@tas content=@t]
      [%bot-del-context id=@tas field=@tas]
      [%bot-add-ship id=@tas =ship role=ship-role]
      [%bot-del-ship id=@tas =ship]
      [%bot-set-channel-perm id=@tas channel=@t perm=channel-perm]
      [%bot-cron-add id=@tas schedule=@t prompt=@t]
      [%bot-cron-remove id=@tas cron-id=@ud]
      ::  legacy single-bot actions (operate on default bot)
      [%set-context field=@tas content=@t]
      [%append-context field=@tas content=@t]
      [%del-context field=@tas]
      [%add-ship =ship role=ship-role]
      [%del-ship =ship]
      [%set-channel-perm channel=@t perm=channel-perm]
      [%approve =ship]
      [%deny =ship]
      [%cron-add schedule=@t prompt=@t]
      [%cron-remove cron-id=@ud]
      [%set-bot-name name=(unit @t)]
      [%set-bot-avatar avatar=(unit @t)]
  ==
::
+$  update
  $%  [%response =msg]
      [%error error=@t]
      [%pending ~]
      [%dm-response =ship =msg]
  ==
::
::  message source: where did the message come from
::
+$  msg-source
  $%  [%dm =ship]
      [%dm-thread =ship parent-id=[p=@p q=@da]]
      [%channel kind=?(%chat %diary %heap) host=@p name=@tas =ship]
      [%thread kind=?(%chat %diary %heap) host=@p name=@tas parent-id=@da =ship]
      [%direct ~]
  ==
::
::  tool loop state for async tool execution
::
+$  tool-pending
  $:  =msg-source
      conv-key=@t
      follow-msgs=(list json)
      pending=(list [id=@t name=@t arguments=@t])
  ==
::
+$  state-0
  $:  %0
      api-key=@t
      model=@t
      system-prompt=@t
      history=(list msg)
      pending=?
      last-error=@t
  ==
+$  state-1
  $:  %1
      api-key=@t
      model=@t
      history=(list msg)
      pending=?
      last-error=@t
      context=(map @tas @t)
  ==
+$  state-2
  $:  %2
      api-key=@t
      model=@t
      history=(list msg)
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-history=(map ship (list msg))
      dm-pending=(set ship)
  ==
::  state-3: original shape (do not modify)
+$  state-3
  $:  %3
      api-key=@t
      brave-key=@t
      model=@t
      history=(list msg)
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-history=(map ship (list msg))
      dm-pending=(set ship)
      tool-loop-3=*
  ==
::
+$  state-4
  $:  %4
      api-key=@t
      brave-key=@t
      model=@t
      history=(list msg)
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-history=(map ship (list msg))
      dm-pending=(set ship)
      tool-loop-4=*
      pending-src=(map ship msg-source)
  ==
::
::  context summary: compressed representation of old messages
::
+$  summary
  $:  id=@ud
      depth=@ud
      token-est=@ud
      created=@da
      msg-range=[from=@ud to=@ud]
      content=@t
  ==
::
+$  compact-state
  $%  [%idle ~]
      [%running target=(unit ship)]
  ==
::
+$  state-5
  $:  %5
      api-key=@t
      brave-key=@t
      model=@t
      history=(list msg)
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-history=(map ship (list msg))
      dm-pending=(set ship)
      tool-loop-5=*
      pending-src=(map ship msg-source)
      ::  compaction
      summaries=(map @ud summary)
      dm-summaries=(map ship (map @ud summary))
      next-sum-id=@ud
      compact=compact-state
  ==
::
::  state-6: history/compaction moved to %lcm agent
+$  state-6
  $:  %6
      api-key=@t
      brave-key=@t
      model=@t
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-pending=(set ship)
      tool-loop=(unit tool-pending)
      pending-src=(map ship msg-source)
  ==
::
::  channel permission: who can talk to the bot in a given channel
::
+$  channel-perm  ?(%open %whitelist)
::
::  state-7: per-channel permissions
+$  state-7
  $:  %7
      api-key=@t
      brave-key=@t
      model=@t
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-pending=(set ship)
      tool-loop=(unit tool-pending)
      pending-src=(map ship msg-source)
      channel-perms=(map @t channel-perm)
  ==
::
::  state-8: participated threads + dedup
+$  state-8
  $:  %8
      api-key=@t
      brave-key=@t
      model=@t
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-pending=(set ship)
      tool-loop=(unit tool-pending)
      pending-src=(map ship msg-source)
      channel-perms=(map @t channel-perm)
      participated=(set @t)
      seen-msgs=(set @t)
  ==
::
::  state-9: bot rate limiting, approval workflow, owner heartbeat
+$  state-9
  $:  %9
      api-key=@t
      brave-key=@t
      model=@t
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-pending=(set ship)
      tool-loop=(unit tool-pending)
      pending-src=(map ship msg-source)
      channel-perms=(map @t channel-perm)
      participated=(set @t)
      seen-msgs=(set @t)
      bot-counts=(map @t @ud)
      pending-approvals=(map ship @t)
      owner-last-msg=@da
  ==
::
::
::  cron job: scheduled prompt on a cron schedule
::    schedule: cron expression (5 fields: min hour dom month dow)
::    examples: '*/30 * * * *' (every 30min), '0 9 * * *' (daily 9am)
::
+$  cron-job
  $:  id=@ud
      schedule=@t
      prompt=@t
      active=?
      version=@ud
      created=@da
  ==
::
::  state-10: cron jobs (frozen - old cron-job type)
+$  state-10
  $:  %10
      api-key=@t
      brave-key=@t
      model=@t
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-pending=(set ship)
      tool-loop=(unit tool-pending)
      pending-src=(map ship msg-source)
      channel-perms=(map @t channel-perm)
      participated=(set @t)
      seen-msgs=(set @t)
      bot-counts=(map @t @ud)
      pending-approvals=(map ship @t)
      owner-last-msg=@da
      cron-jobs-10=*
      next-cron-id=@ud
  ==
::
::  state-11: cron with proper schedule expressions
+$  state-11
  $:  %11
      api-key=@t
      brave-key=@t
      model=@t
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-pending=(set ship)
      tool-loop=(unit tool-pending)
      pending-src=(map ship msg-source)
      channel-perms=(map @t channel-perm)
      participated=(set @t)
      seen-msgs=(set @t)
      bot-counts=(map @t @ud)
      pending-approvals=(map ship @t)
      owner-last-msg=@da
      cron-jobs=(map @ud cron-job)
      next-cron-id=@ud
  ==
::
::  state-12: message queue for busy responses
+$  state-12
  $:  %12
      api-key=@t
      brave-key=@t
      model=@t
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-pending=(set ship)
      tool-loop=(unit tool-pending)
      pending-src=(map ship msg-source)
      channel-perms=(map @t channel-perm)
      participated=(set @t)
      seen-msgs=(set @t)
      bot-counts=(map @t @ud)
      pending-approvals=(map ship @t)
      owner-last-msg=@da
      cron-jobs=(map @ud cron-job)
      next-cron-id=@ud
      msg-queue=(map ship [txt=@t src=msg-source])
  ==
::
::  state-13: bot identity (bot-meta author for messages)
+$  state-13
  $:  %13
      api-key=@t
      brave-key=@t
      model=@t
      pending=?
      last-error=@t
      context=(map @tas @t)
      whitelist=(map ship ship-role)
      dm-pending=(set ship)
      tool-loop=(unit tool-pending)
      pending-src=(map ship msg-source)
      channel-perms=(map @t channel-perm)
      participated=(set @t)
      seen-msgs=(set @t)
      bot-counts=(map @t @ud)
      pending-approvals=(map ship @t)
      owner-last-msg=@da
      cron-jobs=(map @ud cron-job)
      next-cron-id=@ud
      msg-queue=(map ship [txt=@t src=msg-source])
      bot-name=(unit @t)
      bot-avatar=(unit @t)
  ==
::
::  state-14: multi-bot support
+$  state-14
  $:  %14
      api-key=@t
      brave-key=@t
      model=@t
      pending=?
      last-error=@t
      seen-msgs=(set @t)
      pending-approvals=(map ship @t)
      owner-last-msg=@da
      msg-queue=(map ship [txt=@t src=msg-source])
      ::  per-bot state
      bots=(map @tas bot-config)
      default-bot=@tas
      dm-pending=(set [@tas ship])
      pending-src=(map [@tas ship] msg-source)
      participated=(map @tas (set @t))
      bot-counts=(map [@tas @t] @ud)
      tool-loops=(map @tas tool-pending)
  ==
::
+$  versioned-state
  $%  state-0
      state-1
      state-2
      state-3
      state-4
      state-5
      state-6
      state-7
      state-8
      state-9
      state-10
      state-11
      state-12
      state-13
      state-14
  ==
--
