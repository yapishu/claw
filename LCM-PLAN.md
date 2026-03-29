# LCM Agent Technical Plan

## Overview

A native Urbit Gall agent (`%lcm`) that provides Lossless Context Management for claw. It runs as a separate agent on the same desk, managing conversation storage, DAG-based summarization, and context assembly/retrieval.

## Architecture

```
  claw agent                           lcm agent
  ──────────                           ─────────
  DM/mention arrives
    │
    ├─ poke %lcm [%ingest key msg]     → stores message
    │
    ├─ scry %lcm /assemble/key/budget  → returns assembled context
    │     (summaries + fresh tail)
    │
    ├─ call OpenRouter with context
    │
    ├─ poke %lcm [%ingest key reply]   → stores response
    │                                   → evaluates compaction trigger
    │                                   → if threshold hit:
    │                                      fires async LLM summarization
    │                                      via Iris (uses claw's API key)
    │                                      stores summary in DAG
    │                                      updates context-items
    │
    └─ tools: lcm_grep, lcm_describe   → scry %lcm for search/metadata
```

## State Design

```hoon
+$  lcm-config
  $:  api-key=@t                ::  OpenRouter key (set by claw)
      model=@t                  ::  model for summarization
      context-threshold=@ud     ::  % of budget to trigger (default 75)
      fresh-tail=@ud            ::  protected recent messages (default 16)
      leaf-chunk-tokens=@ud     ::  max tokens per leaf pass (default 20000)
      leaf-target-tokens=@ud    ::  target summary size (default 1200)
      condense-target-tokens=@ud  ::  target condensed size (default 2000)
      leaf-min-fanout=@ud       ::  min msgs for leaf pass (default 8)
      condense-min-fanout=@ud   ::  min summaries for condense (default 4)
  ==

+$  stored-msg
  $:  seq=@ud                   ::  monotonic within conversation
      role=@t                   ::  user/assistant/system/tool
      content=@t
      token-est=@ud             ::  ceil(bytes/4)
      created=@da
  ==

+$  summary
  $:  id=@ud                    ::  monotonic summary ID
      kind=?(%leaf %condensed)
      depth=@ud                 ::  0=leaf, 1+=condensed
      content=@t                ::  summary text
      token-est=@ud
      source-msgs=(set @ud)     ::  seq numbers of covered messages
      parent-sums=(set @ud)     ::  parent summary IDs (for condensed)
      earliest=@da
      latest=@da
      created=@da
  ==

+$  context-item
  $%  [%msg seq=@ud]
      [%sum id=@ud]
  ==

+$  conversation
  $:  messages=(map @ud stored-msg)     ::  seq -> msg (never deleted)
      summaries=(map @ud summary)       ::  id -> summary
      context-items=(list context-item) ::  ordered active context
      next-seq=@ud
      next-sum=@ud
  ==

+$  compact-state
  $%  [%idle ~]
      [%running key=@t]
  ==

+$  lcm-state
  $:  conversations=(map @t conversation)  ::  key -> conversation
      =lcm-config
      =compact-state
  ==
```

## Conversation Keys

Each conversation is identified by a key string:
- DM with ~ship: `"dm/~ship-name"`
- Channel: `"channel/chat/~host/name"`
- Direct prompt: `"direct"`

## Poke Actions

```hoon
+$  lcm-action
  $%  ::  ingest a message into a conversation
      [%ingest key=@t role=@t content=@t]
      ::  manually trigger compaction
      [%compact key=@t]
      ::  configure the LCM engine
      [%set-config =lcm-config]
      ::  clear a conversation
      [%clear key=@t]
  ==
```

## Scry Paths

```
/x/assemble/[key]/[budget-ud]/json
  → JSON array of messages (summaries as system msgs + fresh tail)
  → ready to be used as LLM context

/x/grep/[key]/[query]/json
  → search results from messages and summaries

/x/describe/[sum-id-ud]/[key]/json
  → summary metadata, parents, children, source messages

/x/stats/[key]/json
  → conversation stats (msg count, summary count, token counts)

/x/conversations/json
  → list of conversation keys with basic stats
```

## Context Assembly Algorithm

```
assemble(conversation, budget):
  1. items = context-items (ordered list)
  2. fresh-tail = last N items (N = config.fresh-tail)
  3. fresh-tokens = sum(token-est) for fresh-tail items
  4. remaining = budget - fresh-tokens
  5. for each item before fresh-tail (oldest first):
     - resolve to summary or message
     - if fits in remaining: include, subtract tokens
     - if summary: wrap as "[Summary of messages X-Y]\n{content}"
     - if message: include as-is
     - stop when remaining exhausted
  6. return: included items + fresh-tail
```

## Compaction Algorithm

### Trigger
After each `%ingest`, check:
```
total_tokens(context-items) > (budget * context-threshold / 100)
AND compact-state == %idle
AND raw_messages_outside_fresh_tail >= leaf-min-fanout
```

### Leaf Pass (depth 0)
1. Select oldest chunk of raw messages outside fresh tail
2. Cap at `leaf-chunk-tokens` tokens
3. Build summarization prompt:
   - System: "You are a context compaction engine..."
   - User: previous summary (if any) + raw message text
   - Target: ~leaf-target-tokens
4. Send to OpenRouter (async via Iris)
5. On response:
   - Create summary with depth=0, source-msgs={selected seqs}
   - Replace selected context-items with single [%sum id]
   - Messages stay in state (never deleted)

### Condensed Pass (depth 1+)
1. Count summaries at each depth
2. If depth-D count >= condense-min-fanout:
   - Select oldest chunk of depth-D summaries
   - Concatenate their content with time headers
   - Summarize at depth D+1
   - Replace in context-items
   - Old summaries stay in state (for expansion)

### Summarization Prompts

**Leaf (depth 0):**
```
Compress the following conversation segment into a concise summary.
Preserve: key facts, decisions, user preferences, file operations,
action items, names/identifiers. Drop: repetition, filler, resolved
intermediate states. Track file operations as "Files: path (action)".
End with: "Expand for details about: <what was compressed>"
Target: ~{target} tokens. Plain text only.
```

**Condensed (depth 1):**
```
Compact these leaf summaries into a single memory node.
Preserve: decisions and rationale, superseded decisions,
completed tasks with outcomes, in-progress items, blockers,
specific references. Drop: unchanged context, dead ends,
resolved transient states. Include timeline with timestamps.
End with: "Expand for details about: <what was compressed>"
Target: ~{target} tokens.
```

**Condensed (depth 2+):**
```
Create a high-level memory node from these summaries.
Keep only durable context: key decisions, current state,
active constraints, important relationships, lessons learned.
Drop: operational detail, method specifics, resolved issues.
Brief timeline with dates. Plain text.
End with: "Expand for details about: <what was compressed>"
Target: ~{target} tokens.
```

### Escalation
1. Normal attempt (temperature 0.2)
2. If output too large: aggressive retry (tighter prompt, lower target)
3. If LLM fails: deterministic truncation to ~512 tokens + marker

## Retrieval Tools

### lcm_grep
Substring search (case-insensitive) across:
- All raw message content in conversation
- All summary content in conversation
Returns: matching snippets with context, seq/sum-id, timestamps

### lcm_describe
Given a summary ID, return:
- Summary content, depth, token count
- Source message seq numbers (for leaf)
- Parent/child summary IDs
- Time range (earliest/latest)
- Descendant count

### lcm_expand (future)
Given a summary ID, return its children or source messages.
Allows recursive drill-down into compacted context.

## Integration with Claw

### Changes to claw agent:

1. **On message receive** (DM/channel mention):
   ```hoon
   ::  ingest user message into LCM
   [%pass /lcm %agent [our.bowl %lcm] %poke %lcm-action !>([%ingest key 'user' text])]
   ```

2. **Before LLM call** (in make-llm-request):
   ```hoon
   ::  scry LCM for assembled context instead of using raw history
   =/  assembled=(list msg)
     .^((list msg) %gx /=lcm=/assemble/[key]/(scot %ud budget)/noun)
   ```

3. **After LLM response**:
   ```hoon
   ::  ingest response into LCM
   [%pass /lcm %agent [our.bowl %lcm] %poke %lcm-action !>([%ingest key 'assistant' content])]
   ```

4. **Tool definitions** (in claw-tools.hoon):
   - `lcm_grep` → scries %lcm
   - `lcm_describe` → scries %lcm
   - `lcm_stats` → scries %lcm

5. **Config sync**: claw passes API key to %lcm via `%set-config` poke

### What stays in claw:
- Whitelist, pending state, tool loop, msg-source routing
- The tool-calling LLM loop
- DM/channel sending

### What moves to %lcm:
- Message storage (replaces dm-history)
- Context assembly (replaces assemble-context + hard cap)
- Compaction (replaces the current basic compaction)
- History search

## Files to Create

```
sur/lcm.hoon          ::  types (stored-msg, summary, conversation, actions)
app/lcm.hoon          ::  Gall agent (~400 lines)
mar/lcm-action.hoon   ::  poke mark
```

## Files to Modify

```
app/claw.hoon         ::  integrate with %lcm (poke/scry instead of raw history)
lib/claw-tools.hoon   ::  add lcm_grep, lcm_describe tools
sur/claw.hoon         ::  remove compaction state (moves to %lcm)
desk.bill             ::  add %lcm to agent list
```

## Implementation Order

1. Types (`sur/lcm.hoon`)
2. Agent skeleton with state, on-init, on-save/on-load
3. Ingest handler (store messages, update context-items)
4. Assembly scry (summaries + fresh tail within budget)
5. Compaction trigger + leaf pass (async via Iris)
6. Compaction response handler (create summary, update context-items)
7. Condensed pass
8. grep/describe scries
9. Integration: wire claw to use %lcm
10. Remove old compaction from claw
11. Tool definitions (lcm_grep, lcm_describe)

## Configuration Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| context-threshold | 75 | % of budget to trigger compaction |
| fresh-tail | 16 | Protected recent messages |
| leaf-chunk-tokens | 20000 | Max tokens per leaf pass |
| leaf-target-tokens | 1200 | Target leaf summary size |
| condense-target-tokens | 2000 | Target condensed summary size |
| leaf-min-fanout | 8 | Min messages for leaf pass |
| condense-min-fanout | 4 | Min summaries for condense pass |
