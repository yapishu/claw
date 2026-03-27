# claw

A native Urbit LLM agent that runs as a Gall application. It connects to LLM providers via OpenRouter, integrates with the Groups messaging system, and provides a modular tool system for interacting with your ship and the web.

Unlike openclaw/picoclaw which run as external processes that talk to Urbit over HTTP, claw runs directly on your ship as a first-class Urbit application. It pokes and scries agents natively, subscribes to activity events, and manages state through Gall's persistence.

## Agents

The desk ships three agents:

| Agent | Purpose |
|-------|---------|
| `%claw` | Main agent — message handling, LLM requests, tool execution, slash commands |
| `%lcm` | Lossless Context Management — conversation storage, DAG-based summarization, context assembly |
| `%claw-fileserver` | Static file server for the web GUI |

## Features

### Messaging Integration
- **DM responses**: Whitelisted ships can DM the bot and get LLM-powered responses
- **Channel mentions**: When mentioned (@) in a group channel, responds in that channel
- **Thread replies**: Responds to replies on its own posts in channels; routes responses back into the same thread
- **DM thread replies**: Handles thread replies in DMs
- **Group invites**: Auto-accepts group invitations from whitelisted ships
- **Rich content**: Sends messages with proper Tlon inline formatting (bold, italic, code, headers, mentions)
- **Counterparty context**: Includes sender's @p and nickname (from %contacts) in the system prompt
- **Participated thread tracking**: Auto-responds in threads/channels the bot has already participated in, without requiring @mention
- **Message deduplication**: Tracks processed message IDs (up to 1000) to prevent double-processing

### Slash Commands
Messages starting with `/` are intercepted before the LLM:

| Command | Description | Access |
|---------|-------------|--------|
| `/help` | Show available commands and tools | All |
| `/model` | Show current model and context window | All |
| `/model <name>` | Set model (fetches context window from OpenRouter) | Owner |
| `/clear` | Clear conversation history for this chat | All |
| `/status` | Show model, pending state, whitelist count, last error, owner last-seen | All |
| `/open <channel>` | Set channel to allow all users (not just whitelisted) | Owner |
| `/restrict <channel>` | Set channel back to whitelist-only | Owner |
| `/approve ~ship` | Approve a pending ship (adds to whitelist as %allowed) | Owner |
| `/deny ~ship` | Deny a pending approval request | Owner |
| `/pending` | List ships awaiting approval | Owner |

### Per-Channel Permissions
- Each channel can be set to `%open` (anyone can interact) or `%whitelist` (only whitelisted ships, default)
- Whitelisted ships can always interact regardless of channel setting
- Owner always has access everywhere
- Manage via `/open` and `/restrict` slash commands

### Approval Workflow
- When a non-whitelisted ship DMs or mentions the bot, an approval request is created
- All owner ships are notified via DM with the requester's @p and context
- Owners can `/approve ~ship` or `/deny ~ship` to manage access
- `/pending` lists all outstanding approval requests

### Tool Calling
The agent implements the OpenAI tool-calling protocol. When the LLM needs to take an action, it returns tool calls which the agent executes and loops back with results.

**Communication tools:**

| Tool | Type | Description |
|------|------|-------------|
| `send_dm` | sync | Send DM with optional image to any ship |
| `send_channel_message` | sync | Post in a group channel with optional image |
| `add_reaction` | sync | React to a channel message with emoji |
| `remove_reaction` | sync | Remove a reaction |

**Information tools:**

| Tool | Type | Description |
|------|------|-------------|
| `get_contact` | sync | Look up a ship's profile (nickname, bio, avatar) |
| `list_groups` | sync | List joined groups |
| `list_channels` | sync | List all channels |
| `read_channel_history` | sync | Read recent messages from a channel |

**Memory tools (LCM):**

| Tool | Type | Description |
|------|------|-------------|
| `search_history` | sync | Search ALL conversations for a keyword/topic. Returns matching snippets with summary IDs |
| `describe_summary` | sync | Get full content and metadata for a summary ID (kind, depth, tokens, time range, source messages) |
| `list_conversations` | sync | List all conversation keys with message/summary counts |

Escalation pattern: `search_history` first to find relevant content, then `describe_summary` for full details on specific summaries.

**Web tools:**

| Tool | Type | Description |
|------|------|-------------|
| `web_search` | async | Brave web search (POST) |
| `image_search` | async | Brave image search |
| `http_fetch` | async | Fetch any URL |
| `upload_image` | async | Download image, sign, upload to S3, return public URL |

**Ship management tools:**

| Tool | Type | Description |
|------|------|-------------|
| `update_profile` | sync | Change bot nickname/avatar via %contacts |
| `block_ship` / `unblock_ship` | sync | Block/unblock ships from DMs |
| `join_group` | sync | Join a group (owner only) |
| `leave_group` | sync | Leave a group (owner only) |

**Scheduled tasks (cron):**

| Tool | Type | Description |
|------|------|-------------|
| `cron_add` | sync | Schedule a recurring task with a cron expression (owner only) |
| `cron_list` | sync | List all scheduled tasks with IDs, schedules, and prompts |
| `cron_remove` | sync | Remove a scheduled task by ID (owner only) |

Cron expressions use standard 5-field format: `minute hour day-of-month month day-of-week`. Examples: `*/30 * * * *` (every 30min), `0 9 * * *` (daily 9am), `0 */6 * * *` (every 6hr), `0 9 * * 1-5` (weekday mornings).

**MCP tools:**

| Tool | Type | Description |
|------|------|-------------|
| `local_mcp` | async | Execute any MCP server tool via Khan threads |
| `local_mcp_list` | sync | List available MCP tools |
| `install_local_mcp` | sync | Install the %mcp desk from ~matwet |

### Markdown Rendering
LLM responses are parsed into proper Tlon rich text:
- `# Header` through `###### Header` → header block elements
- `> quoted text` → blockquote inlines
- `**bold**` → bold inlines
- `*italic*` → italic inlines
- `` `inline code` `` → inline-code elements
- `~~strikethrough~~` → strike inlines
- `~ship-name` → clickable ship mention inlines
- `\n` → line break inlines
- `\n\n` → paragraph separation (separate verses)

### Bot Safety
- **Bot-to-bot rate limiting**: Tracks consecutive bot responses per channel (max 3), resets when a human messages. Prevents bot loop escalation.
- **Owner heartbeat**: Tracks when the owner last sent a message, shown in `/status`
- **Media extraction**: Extracts image blocks from incoming messages as `[Image: alt - src]` for LLM context

### Lossless Context Management (LCM)

The `%lcm` agent implements the LCM architecture for intelligent conversation management. It stores all messages permanently and uses LLM-driven summarization to keep context within token budgets.

**Architecture:**
- Messages are never deleted — only summarized into a DAG of compaction nodes
- Leaf summaries (depth 0) compress raw message chunks
- Condensed summaries (depth 1+) compress groups of summaries at the shallowest depth first
- Context assembly fills the token budget with fresh messages + summaries of older content

**Depth-aware prompts** (ported from lossless-claw):
- **Depth 0 (leaf)**: Preserves decisions, rationale, file operations, timestamps
- **Depth 1**: Condenses leaf summaries into session-level memory — focuses on continuation context
- **Depth 2**: Extracts narrative arcs from session summaries — goals, outcomes, trajectory
- **Depth 3+**: High-level persistent memory — key decisions, accomplishments, constraints, lessons

**Features:**
- Dynamic context window: fetches actual `context_length` from OpenRouter per model
- XML-style summary presentation: `<summary depth="X" range="...">content</summary>`
- Timestamp injection: every message prefixed with `[YYYY-MM-DD HH:MM]` in leaf pass
- Descendant tracking: each summary knows how many nodes and tokens it compressed
- Automatic compaction triggers when token usage exceeds threshold (default 75%)
- Cascading condensation: after leaf pass, checks for condensation opportunities at higher depths

**Scry endpoints:**
```
.^(json %gx /=lcm=/assemble/{key}/{budget}/json)    :: assembled context
.^(json %gx /=lcm=/grep/{key}/{query}/json)          :: search messages/summaries
.^(json %gx /=lcm=/describe/{key}/{sum-id}/json)     :: summary details
.^(json %gx /=lcm=/stats/{key}/json)                 :: conversation stats
.^(json %gx /=lcm=/conversations/json)               :: list conversations
```

### S3 Upload
- Scries `%storage` agent for credentials and configuration
- Generates AWS SigV4 presigned URLs with path-style addressing
- Uploads with `x-amz-acl: public-read` for public access
- Full S3 client extracted as reusable `lib/s3-client.hoon`

### MCP Integration
- Builds MCP tool files directly from Clay (`/fil/default/mcp/tools/`)
- Executes tool thread-builders via Khan `%lard`
- No HTTP auth needed — direct agent-to-Clay-to-Khan
- Self-bootstrapping: `install_local_mcp` installs the desk from ~matwet

### Web GUI
- Served by `claw-fileserver` at `/apps/claw`
- Configure API keys (OpenRouter, Brave), model selection
- Manage whitelist (add/remove ships with owner/allowed roles)
- Edit context files (identity, soul, agent, user, memory, custom)
- **Channel permissions**: toggle channels between open/whitelist, scrollable + filterable
- **Scheduled tasks**: add/remove cron jobs with standard cron expressions
- Appears as a tile in Landscape

## Installation

### From ~matwet (recommended)
```
|install ~matwet %claw
```

### From source
```
# Clone the repo
git clone [repo-url] claw
cd claw

# Copy desk files to your ship's mounted claw desk
rsync -av --delete desk/ /path/to/your/pier/claw/

# In the dojo
|commit %claw
|install our %claw
```

## Configuration

After installation, open the GUI at `/apps/claw` or configure via dojo:

```
:claw &claw-action [%set-key 'sk-or-v1-your-openrouter-key']
:claw &claw-action [%set-model 'anthropic/claude-sonnet-4']
:claw &claw-action [%set-brave-key 'your-brave-api-key']
:claw &claw-action [%add-ship ~sampel-palnet %owner]
```

Or via DM slash commands (from an owner ship):
```
/model anthropic/claude-sonnet-4
/status
/clear
/open chat/~host/channel-name
/approve ~new-ship
```

### Whitelist roles
- `%owner` — full access, can change model, use owner-only tools, manage permissions
- `%allowed` — can chat with the bot

### Context files
```
:claw &claw-action [%set-context %identity 'You are a helpful assistant on ~your-ship.']
:claw &claw-action [%set-context %soul 'You are concise and knowledgeable.']
:claw &claw-action [%set-context %memory 'The user prefers short responses.']
```

## Architecture

```
desk/
├── app/
│   ├── claw.hoon              # Main agent — messaging, LLM, tools, slash commands (~1800 lines)
│   ├── lcm.hoon               # LCM agent — conversation storage, DAG summarization (~900 lines)
│   ├── claw-fileserver.hoon   # Static file server for GUI
│   └── fileserver/config.hoon
├── sur/
│   ├── claw.hoon              # Agent types (state-11, actions, msg-source, cron-job)
│   ├── lcm.hoon               # LCM types (state-1, conversation, summary, lcm-config)
│   ├── mcp.hoon               # MCP tool types
│   ├── chat.hoon              # Groups chat types
│   ├── channels.hoon          # Groups channel types
│   ├── activity.hoon          # Activity/notification types
│   ├── contacts.hoon          # Contact types
│   ├── story.hoon             # Rich text types (inline, block, verse)
│   └── ...
├── lib/
│   ├── claw-tools.hoon        # Tool dispatcher (27 tools)
│   ├── story-parse.hoon       # Markdown ↔ Tlon story (reusable)
│   ├── cron.hoon              # Cron expression parser (reusable)
│   ├── s3-client.hoon         # AWS SigV4 S3 upload client (reusable)
│   ├── test.hoon              # Unit test library
│   └── ...
├── mar/
│   ├── claw-action.hoon       # Poke mark
│   ├── claw-update.hoon       # Subscription mark
│   ├── lcm-action.hoon        # LCM poke mark
│   └── channel/action-1.hoon  # Channel posting mark
├── tests/
│   ├── test-claw.hoon         # Helper function tests
│   ├── test-lcm.hoon          # LCM engine tests
│   └── test-pipeline.hoon     # E2E pipeline tests
├── web/
│   └── index.html             # Management GUI
├── desk.bill                  # [%claw %claw-fileserver %lcm]
├── desk.docket-0
└── sys.kelvin
```

### Data flow

```
DM/mention/thread-reply arrives
    → %activity subscription (on-agent)
    → message deduplication check (seen-msgs)
    → whitelist + channel permission check
    → slash command check (/model, /clear, /help, /status, /open, /approve, etc.)
    → approval workflow for non-whitelisted ships
    → extract sender, content, channel, message ID
    → look up sender nickname from %contacts
    → ingest user message into %lcm
    → build system prompt (context files + sender info + owner heartbeat)
    → scry %lcm for assembled context (summaries + fresh tail within budget)
    → POST to OpenRouter with tools
    → parse response
    ├── text response → markdown-to-story → ingest into %lcm → route to source
    │   (DM, channel, or thread) → track participated → update bot-counts
    └── tool_calls → execute tools → loop back to LLM
        ├── sync tools: poke/scry, return immediately
        └── async tools: fire Iris/Khan, wait for response, continue

Compaction (automatic):
    → %lcm ingest triggers token check
    → if total tokens > threshold (75% of context window):
        → select oldest message chunk → LLM leaf summarization → store summary
        → check for condensation opportunity (enough summaries at shallowest depth)
        → if so: LLM condensed summarization → store higher-depth summary
        → cascades until token budget is met
```

### State

**claw (state-11):**
```hoon
api-key, brave-key, model, pending, last-error,
context (map @tas @t), whitelist (map ship ship-role),
dm-pending (set ship), tool-loop (unit tool-pending),
pending-src (map ship msg-source),
channel-perms (map @t channel-perm),
participated (set @t), seen-msgs (set @t),
bot-counts (map @t @ud),
pending-approvals (map ship @t),
owner-last-msg @da,
cron-jobs (map @ud cron-job), next-cron-id @ud
```
Each `cron-job` stores: schedule (5-field cron expression), prompt, active flag, version (for stale timer detection), created timestamp.

**lcm (state-1):**
```hoon
conversations (map @t conversation), lcm-config, compact-state
```
Each conversation contains messages (never deleted), summaries (DAG nodes with descendant tracking), context-items (ordering), and sequence counters.

## Running Tests

```
-test %/tests ~
```

Tests cover: lcm-key generation, model budget, LLM response parsing, token estimation, context assembly (ordering, budgets, fresh tail), leaf chunk selection, and full pipeline (ingest → assemble → verify).

## Adding Tools

Edit `lib/claw-tools.hoon`:

1. Add the tool definition to `+tool-defs`:
```hoon
(tool-fn 'my_tool' 'Description for the LLM.' (obj ~[['param1' (req-str 'What this param does')]]))
```

2. Add execution logic to `+execute-tool`:
```hoon
?:  =('my_tool' name)
  =,  dejs:format
  =/  p1=@t  ((ot ~[param1+so]) u.args)
  ::  sync: return cards + result text
  [%sync :~([%pass /tool/my %agent [our.bowl %some-agent] %poke %mark !>(data)]) 'done']
  ::  OR async: return an Iris/Khan card
  [%async [%pass /tool-http/'my_tool' %arvo %i %request ...]]
```

For owner-only tools, check `?.  owner  [%sync ~ 'error: only the owner can use this tool']`.

## Reusable Libraries

Three libraries are extracted as standalone modules with no agent dependencies. Other desks can copy and import them directly:

**`lib/story-parse.hoon`** — Markdown to Tlon rich text conversion
```hoon
/+  *story-parse
(text-to-story 'Hello **world**, check ~zod')  :: → story with bold + mention
(story-to-text some-story)                      :: → plain text extraction
```
Handles: headers (`#`), blockquotes (`>`), bold, italic, strikethrough, inline code, ship mentions, line breaks, paragraph splitting.

**`lib/cron.hoon`** — Cron expression parser
```hoon
/+  *cron
(next-cron-fire '*/30 * * * *' now)  :: → (unit @da) next 30-min mark
(next-cron-fire '0 9 * * 1-5' now)  :: → (unit @da) next weekday 9am
(parse-cron-field '*/15' 0 59)      :: → (set @ud) {0 15 30 45}
```
Standard 5-field format (min hour dom month dow). Supports `*`, `*/N`, `N`, `N,M,O`.

**`lib/s3-client.hoon`** — S3 upload with AWS SigV4 signing
```hoon
/+  *s3-client
=/  creds  (scry-s3-creds cred-json conf-json)  :: extract from %storage
(s3-presigned-put creds now image-data 'image/png')  :: → (unit [card url])
```
Includes: HMAC-SHA256, signing key derivation, hex encoding, URI encoding, presigned PUT URL generation, credential extraction from `%storage` agent JSON.

## Dependencies

- **OpenRouter API key** — for LLM access
- **Brave Search API key** — optional, for web/image search
- **S3 credentials** — optional, configured in system `%storage` agent
- **%mcp desk** — optional, for MCP tools (auto-installable via `install_local_mcp`)
- **%groups desk** — required, for chat/channel/activity types

## Credits

Vibecoded with Opus 4.6 and [%mcp](https://github.com/gwbtc/urbit-mcp) by the GroundWire crew. Inspired by [picoclaw](https://github.com/user/picoclaw) and [openclaw-tlon](https://github.com/user/openclaw-tlon). LCM compaction prompts ported from [lossless-claw](https://github.com/user/lossless-claw). Built as a native Urbit alternative that doesn't require external infrastructure.
