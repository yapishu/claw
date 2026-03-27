::  lcm: lossless context management types
::
::  manages conversation storage, DAG-based summarization,
::  and token-budget-aware context assembly.
::
|%
::  a stored message (never deleted, only summarized)
::
+$  stored-msg
  $:  seq=@ud
      role=@t
      content=@t
      token-est=@ud
      created=@da
  ==
::  a summary node in the compaction DAG
::
+$  summary
  $:  id=@ud
      kind=?(%leaf %condensed)
      depth=@ud
      content=@t
      token-est=@ud
      source-msgs=(set @ud)
      parent-sums=(set @ud)
      earliest=@da
      latest=@da
      created=@da
  ==
::  a reference in the active context ordering
::
+$  context-item
  $%  [%msg seq=@ud]
      [%sum id=@ud]
  ==
::  a conversation with its messages, summaries, and context
::
+$  conversation
  $:  messages=(map @ud stored-msg)
      summaries=(map @ud summary)
      context-items=(list context-item)
      next-seq=@ud
      next-sum=@ud
  ==
::  compaction status
::
+$  compact-state
  $%  [%idle ~]
      [%running key=@t]
  ==
::  lcm configuration
::
+$  lcm-config
  $:  api-key=@t
      model=@t
      context-threshold=@ud
      fresh-tail=@ud
      leaf-chunk-tokens=@ud
      leaf-target-tokens=@ud
      condense-target-tokens=@ud
      leaf-min-fanout=@ud
      condense-min-fanout=@ud
  ==
::  poke actions
::
+$  lcm-action
  $%  [%ingest key=@t role=@t content=@t]
      [%compact key=@t]
      [%set-config =lcm-config]
      [%clear key=@t]
  ==
::  agent state
::
+$  state-0
  $:  %0
      conversations=(map @t conversation)
      =lcm-config
      =compact-state
  ==
--
