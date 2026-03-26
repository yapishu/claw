# claw

A native Urbit LLM agent that runs as a Gall application. It connects to LLM providers via OpenRouter, integrates with the Groups messaging system, and provides a modular tool system for interacting with your ship and the web.

Unlike openclaw/picoclaw which run as external processes that talk to Urbit over HTTP, claw runs directly on your ship as a first-class Urbit application. It pokes and scries agents natively, subscribes to activity events, and manages state through Gall's persistence.

## Features

### Messaging Integration
- **DM responses**: Whitelisted ships can DM the bot and get LLM-powered responses
- **Channel mentions**: When mentioned (@) in a group channel, responds in that channel
- **Group invites**: Auto-accepts group invitations from whitelisted ships
- **Rich content**: Sends messages with image blocks, not just plain text

### Context System
- **Identity, Soul, Agent, User, Memory** files that shape the bot's personality and knowledge
- Context files persist across conversations and restarts
- Editable via the web GUI or pokes
- Per-conversation context injection (who you're talking to, which channel, message IDs)

### Tool Calling
The agent implements the OpenAI tool-calling protocol. When the LLM needs to take an action, it returns tool calls which the agent executes and loops back with results. Tools are defined in `lib/claw-tools.hoon` and are modular — add new tools by appending a definition and execution case.

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
| `web_search` | async | Brave web search (POST) |
| `image_search` | async | Brave image search (via web search) |
| `http_fetch` | async | Fetch any URL |
| `upload_image` | async | Download image → sign → upload to S3 → return public URL |
| `local_mcp` | async | Execute any MCP server tool via Khan threads |
| `local_mcp_list` | sync | List available MCP tools |
| `install_local_mcp` | sync | Install the %mcp desk from ~matwet |
| `search_history` | sync | Search conversation history and summaries |

### S3 Upload
- Scries `%storage` agent for credentials and configuration
- Generates AWS SigV4 presigned URLs
- Uploads with `x-amz-acl: public-read` for public access
- Custom HMAC-SHA256 implementation (inlined, no library dependency)

### MCP Integration
- Builds MCP tool files directly from Clay (`/fil/default/mcp/tools/`)
- Executes tool thread-builders via Khan `%lard`
- No HTTP auth needed — direct agent-to-Clay-to-Khan
- Graceful fallback if %mcp desk isn't installed
- Self-bootstrapping: `install_local_mcp` installs the desk from ~matwet

### Context Compaction
- Token-budget-aware context assembly (model-specific limits)
- Automatic summarization: when conversation exceeds 20 messages, oldest messages are summarized by the LLM
- Summaries stored alongside raw history, included in context by depth
- Fresh tail (last 10 messages) always kept raw
- `search_history` tool for recalling compacted context

### Web GUI
- Served by `claw-fileserver` at `/apps/claw`
- Configure API keys (OpenRouter, Brave), model selection
- Manage whitelist (add/remove ships with owner/allowed roles)
- Edit context files (identity, soul, agent, user, memory, custom)
- Appears as a tile in Landscape

### Activity Subscription
- Subscribes to `%activity` agent for channel mentions and group invites
- Re-establishes all subscriptions on every code update (on-load)
- Filters events through whitelist before processing

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

### Whitelist roles
- `%owner` — full access, auto-accept DM invites
- `%allowed` — can chat with the bot

### Context files
Set via poke or GUI:
```
:claw &claw-action [%set-context %identity 'You are a helpful assistant on ~your-ship.']
:claw &claw-action [%set-context %soul 'You are concise and knowledgeable.']
:claw &claw-action [%set-context %memory 'The user prefers short responses.']
```

## Architecture

```
~/gits/np/claw/desk/
├── app/
│   ├── claw.hoon              # Main Gall agent (~1200 lines)
│   ├── claw-fileserver.hoon   # Static file server for GUI
│   └── fileserver/config.hoon # Fileserver configuration
├── sur/
│   ├── claw.hoon              # Agent types (state, actions, updates)
│   ├── mcp.hoon               # MCP tool types
│   ├── chat.hoon              # Groups chat types
│   ├── channels.hoon          # Groups channel types
│   ├── activity.hoon          # Activity/notification types
│   ├── contacts.hoon          # Contact types
│   ├── groups.hoon            # Group types
│   ├── story.hoon             # Rich content types
│   └── ...                    # Other shared types
├── lib/
│   ├── claw-tools.hoon        # Modular tool system (~500 lines)
│   ├── default-agent.hoon     # Standard Gall helpers
│   ├── dbug.hoon              # Debug wrapper
│   └── server.hoon            # HTTP helpers
├── mar/
│   ├── claw-action.hoon       # Poke mark
│   ├── claw-update.hoon       # Subscription mark
│   ├── channel/action-1.hoon  # Channel posting mark
│   └── ...                    # Standard marks
├── web/
│   └── index.html             # Management GUI
├── desk.bill                  # [%claw %claw-fileserver]
├── desk.docket-0              # Landscape tile
└── sys.kelvin                 # [%zuse 410] [%zuse 409]
```

### Data flow

```
DM/mention arrives
    → %activity subscription (on-agent)
    → whitelist check
    → extract sender, content, channel, message ID
    → build system prompt (context files + conversation info)
    → POST to OpenRouter with tools
    → parse response
    ├── text response → route to source (DM or channel)
    └── tool_calls → execute tools → loop back to LLM
        ├── sync tools: poke/scry, return immediately
        └── async tools: fire Iris/Khan, wait for response, continue
```

### State (v5)
```hoon
+$  state-5
  $:  %5
      api-key=@t              :: OpenRouter API key
      brave-key=@t            :: Brave Search API key
      model=@t                :: e.g. 'anthropic/claude-sonnet-4'
      history=(list msg)      :: direct conversation history
      pending=?               :: direct query in flight
      last-error=@t           :: last error message
      context=(map @tas @t)   :: context files (identity, soul, etc.)
      whitelist=(map ship ship-role)
      dm-history=(map ship (list msg))
      dm-pending=(set ship)
      tool-loop=(unit tool-pending)   :: async tool state
      pending-src=(map ship msg-source) :: response routing
      summaries=(map @ud summary)     :: direct history summaries
      dm-summaries=(map ship (map @ud summary)) :: per-ship summaries
      next-sum-id=@ud
      compact=compact-state           :: compaction status
  ==
```

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
  ::  sync tool: return cards + result text
  [%sync :~([%pass /tool/my %agent [our.bowl %some-agent] %poke %mark !>(data)]) 'done']
  ::  OR async tool: return an Iris/Khan card
  [%async [%pass /tool-http/'my_tool' %arvo %i %request ...]]
```

For async tools, add a response handler in `app/claw.hoon` under the `[%tool-http ...]` wire in `on-arvo`.

## Scry Endpoints

```
.^(json %gx /=claw=/history/json)        :: conversation history
.^(json %gx /=claw=/last/json)           :: last message
.^(json %gx /=claw=/config/json)         :: config + whitelist
.^(json %gx /=claw=/context/json)        :: all context files
.^(json %gx /=claw=/context/identity/json) :: specific context file
.^(json %gx /=claw=/prompt/json)         :: assembled system prompt
.^(json %gx /=claw=/dm-history/~ship/json) :: DM history with ship
```

## HTTP API

All endpoints at `/apps/claw/api/` (requires auth):

| Method | Path | Description |
|--------|------|-------------|
| GET | `/config` | Current configuration |
| GET | `/context` | All context files |
| GET | `/context/:field` | Single context file |
| GET | `/history` | Conversation history |
| GET | `/dm-history/:ship` | DM history |
| GET | `/prompt` | Preview system prompt |
| POST | `/action` | Execute any claw action (JSON body) |

### Action JSON format
```json
{"action": "set-key", "key": "sk-or-v1-..."}
{"action": "set-model", "model": "anthropic/claude-sonnet-4"}
{"action": "set-brave-key", "key": "BSA..."}
{"action": "add-ship", "ship": "~sampel-palnet", "role": "owner"}
{"action": "del-ship", "ship": "~sampel-palnet"}
{"action": "set-context", "field": "identity", "content": "You are..."}
{"action": "clear"}
```

## Dependencies

- **OpenRouter API key** — for LLM access
- **Brave Search API key** — optional, for web/image search
- **S3 credentials** — optional, configured in system `%storage` agent
- **%mcp desk** — optional, for MCP tools (auto-installable via `install_local_mcp`)
- **%groups desk** — required, for chat/channel/activity types

## Credits

Inspired by [picoclaw](https://github.com/user/picoclaw) and [openclaw-tlon](https://github.com/user/openclaw-tlon). Built as a native Urbit alternative that doesn't require external infrastructure.
