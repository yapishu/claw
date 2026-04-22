# claw

A native Urbit LLM agent that runs as a Gall application. It talks to LLM providers (OpenRouter over HTTPS **or** a local qwen3 model via `%maroon`), integrates with the Groups messaging system, and provides a modular tool system for interacting with your ship and the web.

Unlike openclaw/picoclaw which run as external processes that talk to Urbit over HTTP, claw runs directly on your ship as a first-class Urbit application. It pokes and scries agents natively, subscribes to activity events, and manages state through Gall's persistence.

## Agents

The desk ships nine agents:

| Agent | Purpose |
|-------|---------|
| `%claw` | Main agent — message handling, LLM requests, tool execution, slash commands |
| `%lcm` | Lossless Context Management — conversation storage, DAG-based summarization, context assembly |
| `%maroon` | On-ship LLM inference — loads quantized qwen3 weights into VRAM, serves OpenAI-compatible chat completions via HTTP or gall poke |
| `%mcp-server` | Serves this ship's own MCP tools (list-files, scry, poke-our-agent, commit-desk, …) over JSON-RPC |
| `%mcp-proxy` | Aggregates multiple MCP servers (local + upstream) behind a single `/apps/mcp/mcp` endpoint |
| `%oauth` | OAuth flow helper (Gmail, Google Calendar, Google Drive) — used by MCP tool set |
| `%claw-fileserver` | Static file server for the claw web GUI |
| `%maroon-fileserver` | Static file server for the maroon web GUI |
| `%mcp-fileserver` | Static file server for the mcp-proxy web GUI |

## Providers

`%claw` supports two LLM providers with per-conversation overrides:

| Provider | Transport | API Key | Notes |
|----------|-----------|---------|-------|
| `%openrouter` | Outbound HTTPS via iris | required | Remote, any OpenRouter-catalog model |
| `%maroon` | Direct gall poke (same ship) | none | Local qwen3 inference — no network, no API bill |

The default can be set globally in the GUI (or `:claw &claw-action [%set-default-provider %maroon]`). Individual conversations can pin a different provider via `%set-conv-provider`. The GUI shows a color-coded banner with the active provider.

### Local path (claw ↔ maroon)

When a conversation uses `%maroon`, claw **skips HTTP entirely** — no Eyre, no iris, no loopback TCP. The `make-llm-request` builder emits a gall `%poke` to `%maroon` with a `%maroon-chat-req` cage carrying `[req-id meta body]`, where `body` is the same OpenAI chat JSON that would go to OpenRouter. `%maroon` generates tokens via its tick-based forward loop and pokes `%claw` back with a `%maroon-chat-resp` cage. Claw's `on-poke` dispatches the response through the normal tool/text paths.

This avoids the chunked/keep-alive quirks of using iris for same-ship calls and lets the response include structured metadata (the original `source` + `dm-who`) so the reply routes correctly without any per-request state.

### Tool calls with qwen3

qwen3-bonsai was trained on the **Hermes tool-call format**, not OpenAI function-calls:

```
<tool_call>
{"name":"web_search","arguments":{"query":"cats"}}
</tool_call>
```

`+parse-llm-response` detects `<tool_call>…</tool_call>` blocks in the content string and repackages them into the standard `%tools` shape, so the existing tool loop handles multi-round correctly. `%maroon`'s chat template also renders tool-result messages as `<|im_start|>user\n<tool_response>…</tool_response><|im_end|>` so qwen sees the replies in its expected format.

## Features

### Messaging Integration
- **DM responses**: Whitelisted ships can DM the bot and get LLM-powered responses
- **Channel mentions**: When mentioned (@) in a group channel, responds in that channel
- **Thread replies**: Responds to replies on its own posts; routes back into the same thread
- **Group invites**: Auto-accepts group invitations from whitelisted ships
- **Rich content**: Sends replies with Tlon inline formatting (bold, italic, code, headers, mentions)
- **Counterparty context**: Includes sender's @p in the system prompt
- **Participated thread tracking**: Auto-responds in threads/channels the bot has already participated in, without requiring @mention
- **Message deduplication**: Tracks processed message IDs to prevent double-processing
- **Thinking indicator**: Pokes `%presence` with a 1-minute `%computing` flag while the LLM generates, so DM counterparties see a "thinking…" badge

### Slash Commands

| Command | Description | Access |
|---------|-------------|--------|
| `/help` | Show available commands and tools | All |
| `/model` | Show current model and context window | All |
| `/model <name>` | Set model (fetches context window from OpenRouter) | Owner |
| `/clear` | Clear conversation history for this chat | All |
| `/status` | Show model, pending state, whitelist, last error, owner last-seen | All |
| `/open <channel>` | Set channel to allow all users | Owner |
| `/restrict <channel>` | Set channel back to whitelist-only | Owner |
| `/approve ~ship` | Approve a pending ship | Owner |
| `/deny ~ship` | Deny a pending approval request | Owner |
| `/pending` | List ships awaiting approval | Owner |

### Per-Channel Permissions / Approval Workflow
- Each channel can be `%open` or `%whitelist` (default)
- Non-whitelisted ships DMing the bot trigger an approval request to all `%owner` ships
- Owners manage with `/approve`, `/deny`, `/pending`

### Tool Calling

Tool definitions live in `lib/claw-tools.hoon` and are sent to the LLM in the `tools` request field (qwen3 emits `<tool_call>` blocks; claw extracts them). Tools return either `%sync` (cards + text immediately) or `%async` (fire an iris/gall card, resume when the response arrives).

**Communication**

| Tool | Type | Description |
|------|------|-------------|
| `send_dm` | sync | Send DM with optional image to any ship |
| `send_channel_message` | sync | Post in a group channel with optional image |
| `add_reaction` / `remove_reaction` | sync | Channel message reactions |

**Information**

| Tool | Type | Description |
|------|------|-------------|
| `get_contact` | sync | Look up a ship's profile |
| `list_groups` / `list_channels` | sync | List joined groups / channels |
| `read_channel_history` / `read_dm_history` | sync | Recent messages with ids |

**Memory (LCM)**

| Tool | Type | Description |
|------|------|-------------|
| `search_history` | sync | Search all conversations for a keyword. Returns snippets + summary IDs |
| `describe_summary` | sync | Full content and metadata for a summary ID |
| `list_conversations` | sync | List all conversation keys with counts |

Escalation: `search_history` first to find relevant content, then `describe_summary` for full details.

**Web**

| Tool | Type | Description |
|------|------|-------------|
| `web_search` / `image_search` | async | Brave search; result parsed to top-5 title/url/description lines |
| `http_fetch` | async | Fetch any URL |
| `upload_image` | async | Download image, sign, upload to S3, return public URL |

**Message management**

| Tool | Type | Description |
|------|------|-------------|
| `delete_message` / `edit_message` | sync | Channel message edits |
| `delete_dm` | sync | Delete a DM |

**Ship & group management**

| Tool | Type | Description |
|------|------|-------------|
| `update_profile` | sync | Change bot nickname/avatar |
| `block_ship` / `unblock_ship` | sync | Block/unblock DMs |
| `join_group` / `leave_group` / `create_group` / `update_group` | sync | Group lifecycle (owner only) |
| `invite_to_group` / `kick_from_group` / `ban_from_group` / `unban_from_group` | sync | Group membership (owner only) |
| `add_channel` / `delete_channel` | sync | Group channel admin (owner only) |
| `add_role` / `delete_role` / `assign_role` / `remove_role` | sync | Group role admin (owner only) |

**Scheduled tasks (cron)**

| Tool | Type | Description |
|------|------|-------------|
| `cron_add` / `cron_remove` | sync | Schedule/remove recurring prompts (owner only) |
| `cron_list` | sync | List scheduled tasks |

Standard 5-field cron: `minute hour day-of-month month day-of-week`. Examples: `*/30 * * * *`, `0 9 * * *`, `0 9 * * 1-5`.

**Ship ops (MCP)**

| Tool | Type | Description |
|------|------|-------------|
| `urbit` | async | Execute any MCP tool exposed by this ship (via `%mcp-proxy`). Pass `name` + stringified `arguments` JSON |
| `urbit_list` | sync | List every MCP tool available through the proxy |

The LLM calls `urbit_list` to discover tool schemas and then `urbit` with the exact tool name (e.g. `list-files`, `scry`, `poke-our-agent`, `commit-desk`, `mount-desk`, `install-app`, `revive-agent`). Under the hood, claw scries `%mcp-proxy` for its `client-key`, then POSTs a JSON-RPC `tools/call` to `/apps/mcp/mcp` using that key as `x-api-key`. The proxy fans the call out to every registered upstream server (local + remote) and returns the aggregated response. The LLM-facing names are `urbit` / `urbit_list` because small local models sometimes can't say `local_mcp` without inserting a space.

### Markdown Rendering
LLM responses are parsed into Tlon rich text:
- `# Header` through `###### Header` → header block elements
- `> quoted text` → blockquote inlines
- `**bold**`, `*italic*`, `` `inline code` ``, `~~strike~~`, `~ship` mentions
- `\n`/`\n\n` → line breaks / paragraph splits

### Context & sizing dials
- **`max-response-tokens`** — sent as `max_tokens` in every LLM request (default 1024)
- **`max-context-tokens`** — overrides the per-model heuristic when non-zero; LCM trims oldest-first to fit
- **Dynamic tool hint** — a ~80-token `# Tools` section is appended to every system prompt, showing an example `<tool_call>` block and listing the key tool names (qwen3-specific; harmless for Claude/GPT)

### Bot safety
- **Rate limiting**: max 3 consecutive bot responses per channel; reset on human message
- **Owner heartbeat**: `/status` shows when the owner last posted
- **Busy gate**: `%maroon` rejects overlapping generation requests with 503 so concurrent DMs can't corrupt state

### Lossless Context Management (LCM)

The `%lcm` agent implements the LCM architecture: messages are never deleted, only summarized into a DAG of compaction nodes. Leaf summaries (depth 0) compress raw message chunks; condensed summaries (depth 1+) compress groups of summaries at the shallowest depth first. Context assembly fills the token budget with fresh messages + summaries of older content.

Depth-aware prompts preserve decisions/rationale at leaf level and extract narrative arcs / persistent memory at higher depths. Summaries use XML presentation (`<summary depth="X" range="…">…</summary>`) and track descendant counts.

**Scry endpoints:**
```
.^(json %gx /=lcm=/assemble/{key}/{budget}/json)    :: assembled context
.^(json %gx /=lcm=/grep/{key}/{query}/json)         :: search
.^(json %gx /=lcm=/describe/{key}/{sum-id}/json)    :: summary details
.^(json %gx /=lcm=/stats/{key}/json)                :: conversation stats
.^(json %gx /=lcm=/conversations/json)              :: list conversations
```

### S3 Upload
Scries `%storage` for credentials, generates AWS SigV4 presigned URLs with path-style addressing, uploads with `x-amz-acl: public-read`. Full S3 client in `lib/s3-client.hoon`.

### Web GUI
Served by `%claw-fileserver` at `/apps/claw`. Includes:
- Prominent **active-provider banner** (green for `%maroon`, orange for `%openrouter`) with local URL + override count
- API keys (OpenRouter, Brave), model selection
- Whitelist management (owner/allowed roles)
- Context file editor (identity, soul, agent, user, memory, custom fields)
- Per-conversation provider overrides (add/remove tags)
- Channel permission toggles
- Scheduled-task (cron) editor
- Max response / max context token dials

## Installation

### From ~matwet (if published)
```
|install ~matwet %claw
```

### From source
```
git clone <repo-url> claw
rsync -av --delete desk/ /path/to/your/pier/claw/
```
Then in dojo:
```
|commit %claw
|install our %claw
```

## Configuration

After installation, open `/apps/claw` (GUI) or use dojo:

```
:claw &claw-action [%set-default-provider %maroon]       :: or %openrouter
:claw &claw-action [%set-local-llm-url 'http://localhost:8080']
:claw &claw-action [%set-key 'sk-or-v1-...']            :: openrouter
:claw &claw-action [%set-brave-key '...']
:claw &claw-action [%set-max-response-tokens 1024]
:claw &claw-action [%set-max-context-tokens 8192]       :: 0 = heuristic
:claw &claw-action [%add-ship ~sampel-palnet %owner]
```

### Loading local weights (for `%maroon`)

Generate and poke the weights + tokenizer from the dojo:
```
=payload +claw!maroon-load-qwen3
:maroon &maroon-load-qwen3 payload

=tok +claw!maroon-load-qwen3-tokenizer
:maroon &maroon-load-tokenizer tok
```

`%maroon` auto-warms the weights into VRAM on every commit and on ship restart (via a generic `warm-weights` jet), so you should only need to do this once per ship.

### Whitelist roles
- `%owner` — full access, can change model, use owner-only tools, manage permissions
- `%allowed` — can chat with the bot

## Architecture

```
desk/
├── app/
│   ├── claw.hoon              # Main agent (~2200 lines)
│   ├── lcm.hoon               # LCM agent
│   ├── maroon.hoon            # On-ship qwen3 inference
│   ├── mcp-server.hoon        # Local MCP tools
│   ├── mcp-proxy.hoon         # Aggregate MCP endpoint
│   ├── oauth.hoon             # OAuth helper
│   └── *-fileserver.hoon      # Static GUI servers
├── sur/
│   ├── claw.hoon              # state-14, actions, msg-source, provider, cron-job
│   ├── lcm.hoon               # LCM types
│   ├── maroon.hoon            # maroon gen-state, weights, chat-req/resp
│   ├── mcp.hoon, mcp-proxy.hoon, oauth.hoon
│   ├── chat.hoon, channels.hoon, activity.hoon, contacts.hoon, story.hoon
│   └── presence.hoon          # typing/thinking indicator types
├── lib/
│   ├── claw-tools.hoon        # Tool dispatcher
│   ├── maroon.hoon            # qwen3 forward/decode primitives
│   ├── lagoon.hoon            # Tensor operations (la:)
│   ├── story-parse.hoon       # Markdown ↔ Tlon story
│   ├── cron.hoon              # Cron expression parser
│   └── ...
├── mar/
│   ├── claw-action.hoon, claw-update.hoon
│   ├── maroon-chat-req.hoon, maroon-chat-resp.hoon    :: direct-poke bridge
│   ├── maroon-load.hoon, maroon-load-qwen3.hoon, maroon-load-tokenizer.hoon
│   ├── lcm-action.hoon
│   ├── mcp-proxy-action.hoon, mcp-proxy-update.hoon
│   └── ...
├── gen/
│   └── maroon-load-*.hoon     :: weight loading helpers
├── tests/
├── web/
│   └── index.html             # Management GUI
├── desk.bill, desk.docket-0, sys.kelvin
```

### Data flow

```
incoming DM / mention / thread reply
    → %activity subscription (on-agent)
    → dedup check (seen-msgs) + whitelist/permission check
    → slash-command check
    → approval workflow for non-whitelisted ships
    → build sys-prompt (context + sender + tool-hint)
    → scry %lcm for assembled context within budget
    → make-llm-request
        ├── provider=%openrouter: %pass %arvo %i %request (iris HTTPS)
        └── provider=%maroon:     %pass %agent %poke %maroon-chat-req (gall poke)
    → response arrives
        ├── iris %http-response %finished  (handle-llm-response)
        └── gall %poke %maroon-chat-resp  (on-poke — synthesizes sign-arvo
                                           and re-enters the same dispatch)
    → parse-llm-response
        ├── OpenAI `tool_calls` field     → %tools
        ├── qwen Hermes `<tool_call>`     → %tools  (extract-hermes-calls)
        └── plain content                 → %text
    → %text: sanitize (strip <think>, <|im_end|>…), ingest into %lcm,
             route to source (DM / channel / thread), clear presence
    → %tools: execute via execute-tool
        ├── sync  → card(s) + text result → fire follow-up make-llm-request
        └── async → iris/gall card → await /tool-http wire → finish-tool
            → fire follow-up make-llm-request with tool result appended
    (multi-round: loop until %text)

Compaction (automatic, in %lcm):
    → ingest → token check
    → if > threshold: summarize oldest chunk → cascade condensation
```

### State

**`%claw` (state-14):**
```hoon
api-key, brave-key, model, pending, last-error,
context (map @tas @t), whitelist (map ship ship-role),
dm-pending (set ship), tool-loop (unit tool-pending),
pending-src (map ship msg-source),
channel-perms (map @t channel-perm),
participated (set @t), seen-msgs (set @t),
bot-counts (map @t @ud),
pending-approvals (map ship @t), owner-last-msg @da,
cron-jobs (map @ud cron-job), next-cron-id @ud,
msg-queue (map ship [txt src]),
default-provider, conv-providers (map @t provider), local-llm-url @t,
max-response-tokens @ud, max-context-tokens @ud
```

**`%maroon` (in-memory):** `weights-qwen3`, `config-qwen3`, `tokenizer`, and per-generation `gen-state` (tokens, strategy, KV session id, api=%openai/%poke, poke-caller/req-id/meta for the direct-poke path).

**`%mcp-server` (state-1):** `tools`, `prompts`, `resources`, `auth-token` (auto-generated `@uv` on fresh install; exposed via `.^(@t %gx /=mcp-server=/auth-token/noun)`).

**`%mcp-proxy`:** registered upstream servers, per-server cookies, `client-key` (the `x-api-key` for `/apps/mcp/mcp`; exposed via `.^(@t %gx /=mcp-proxy=/client-key/noun)` — claw scries this).

## Running Tests

```
-test %/tests ~
```

## Adding Tools

Edit `lib/claw-tools.hoon`:

1. Add a tool def to `+tool-defs`:
```hoon
(tool-fn 'my_tool' 'Description for the LLM.'
  (obj ~[['param1' (req-str 'What this param does')]]))
```

2. Add execution logic to `+execute-tool`:
```hoon
?:  =('my_tool' name)
  =,  dejs:format
  =/  p1=@t  ((ot ~[param1+so]) u.args)
  [%sync :~([%pass /tool/my %agent [our.bowl %some-agent] %poke %mark !>(data)]) 'done']
```

Owner-only tools: `?.  owner  [%sync ~ 'error: only the owner can use this tool']`.

## Reusable Libraries

Three libraries in `lib/` are standalone with no agent dependencies:

- **`story-parse.hoon`** — Markdown ↔ Tlon story (headers, blockquotes, bold, italic, code, mentions, line breaks, paragraph splits)
- **`cron.hoon`** — Cron expression parser (standard 5-field `min hour dom month dow`; supports `*`, `*/N`, `N,M`, ranges)
- **`s3-client.hoon`** — AWS SigV4 S3 upload (HMAC-SHA256, signing key derivation, presigned PUT URLs, credential extraction from `%storage`)

## Dependencies

- **OpenRouter API key** — required for `%openrouter` provider
- **Local qwen3 weights + CUDA-equipped runtime** — required for `%maroon` provider
- **Brave Search API key** — optional, for `web_search` / `image_search`
- **S3 credentials** — optional, configured in system `%storage` agent
- **%groups desk** — required (chat/channel/activity/contacts/presence types)

## Credits

Vibecoded with Opus 4.x. MCP integration via [%mcp](https://github.com/gwbtc/urbit-mcp). Inspired by picoclaw and openclaw-tlon. LCM compaction prompts ported from lossless-claw. On-ship inference via `%maroon` running jetted qwen3 on CUDA. Built as a native Urbit alternative that doesn't require external infrastructure.
