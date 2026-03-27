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
- **Group invites**: Auto-accepts group invitations from whitelisted ships
- **Rich content**: Sends messages with image blocks, not just plain text
- **Counterparty context**: Automatically includes the sender's @p and nickname (from %contacts) in the system prompt

### Slash Commands
Messages starting with `/` are intercepted before the LLM:

| Command | Description | Access |
|---------|-------------|--------|
| `/help` | Show available commands and tools | All |
| `/model` | Show current model | All |
| `/model <name>` | Set model (fetches context window from OpenRouter) | Owner |
| `/clear` | Clear conversation history for this chat | All |
| `/status` | Show model, pending state, whitelist count, last error | All |

### Context System
- **Identity, Soul, Agent, User, Memory** files that shape the bot's personality and knowledge
- Context files persist across conversations and restarts
- Editable via the web GUI or pokes
- Per-conversation context injection (who you're talking to, which channel, message IDs)

### Tool Calling
The agent implements the OpenAI tool-calling protocol. When the LLM needs to take an action, it returns tool calls which the agent executes and loops back with results. Tools are defined in `lib/claw-tools.hoon` and are modular.

**Built-in tools:**

| Tool | Type | Description |
|------|------|-------------|
| `update_profile` | sync | Change bot nickname/avatar via %contacts |
| `send_dm` | sync | Send DM with optional image to any ship |
| `send_channel_message` | sync | Post in a group channel with optional image |
| `add_reaction` | sync | React to a channel message with emoji |
| `remove_reaction` | sync | Remove a reaction |
| `block_ship` / `unblock_ship` | sync | Block/unblock ships from DMs |
| `get_contact` | sync | Look up a ship's profile |
| `list_groups` | sync | List joined groups |
| `list_channels` | sync | List all channels |
| `read_channel_history` | sync | Read recent messages from a channel |
| `join_group` | sync | Join a group (owner only) |
| `leave_group` | sync | Leave a group (owner only) |
| `web_search` | async | Brave web search (POST) |
| `image_search` | async | Brave image search |
| `http_fetch` | async | Fetch any URL |
| `upload_image` | async | Download image, sign, upload to S3, return public URL |
| `local_mcp` | async | Execute any MCP server tool via Khan threads |
| `local_mcp_list` | sync | List available MCP tools |
| `install_local_mcp` | sync | Install the %mcp desk from ~matwet |
| `search_history` | sync | Search conversation history and summaries |

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
- Generates AWS SigV4 presigned URLs
- Uploads with `x-amz-acl: public-read` for public access
- Custom HMAC-SHA256 implementation (inlined, no library dependency)

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
```

### Whitelist roles
- `%owner` — full access, can change model, use owner-only tools
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
│   ├── claw.hoon              # Main agent — messaging, LLM, tools, slash commands
│   ├── lcm.hoon               # LCM agent — conversation storage, DAG summarization
│   ├── claw-fileserver.hoon   # Static file server for GUI
│   └── fileserver/config.hoon
├── sur/
│   ├── claw.hoon              # Agent types (state-6, actions, updates, tool-pending)
│   ├── lcm.hoon               # LCM types (state-1, conversation, summary, lcm-config)
│   ├── mcp.hoon               # MCP tool types
│   ├── chat.hoon              # Groups chat types
│   ├── channels.hoon          # Groups channel types
│   ├── activity.hoon          # Activity/notification types
│   ├── contacts.hoon          # Contact types
│   └── ...
├── lib/
│   ├── claw-tools.hoon        # Modular tool system (20 tools, ~700 lines)
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
DM/mention arrives
    → %activity subscription (on-agent)
    → whitelist check
    → slash command check (intercept /model, /clear, /help, /status)
    → extract sender, content, channel, message ID
    → look up sender nickname from %contacts
    → ingest user message into %lcm
    → build system prompt (context files + sender info)
    → scry %lcm for assembled context (summaries + fresh tail within budget)
    → POST to OpenRouter with tools
    → parse response
    ├── text response → ingest into %lcm → route to source (DM or channel)
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

**claw (state-6):**
```hoon
api-key, brave-key, model, pending, last-error,
context (map @tas @t), whitelist (map ship ship-role),
dm-pending (set ship), tool-loop (unit tool-pending),
pending-src (map ship msg-source)
```

**lcm (state-1):**
```hoon
conversations (map @t conversation), lcm-config, compact-state
```
Each conversation contains messages (never deleted), summaries (DAG nodes), context-items (ordering), and sequence counters.

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

## Dependencies

- **OpenRouter API key** — for LLM access
- **Brave Search API key** — optional, for web/image search
- **S3 credentials** — optional, configured in system `%storage` agent
- **%mcp desk** — optional, for MCP tools (auto-installable via `install_local_mcp`)
- **%groups desk** — required, for chat/channel/activity types

## Credits

Vibecoded with Opus 4.5 and [%mcp](https://github.com/gwbtc/urbit-mcp) by the GroundWire crew. Inspired by [picoclaw](https://github.com/user/picoclaw) and [openclaw-tlon](https://github.com/user/openclaw-tlon). LCM compaction prompts ported from [lossless-claw](https://github.com/user/lossless-claw). Built as a native Urbit alternative that doesn't require external infrastructure.
