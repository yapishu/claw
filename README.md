# claw

A native Urbit multi-bot LLM agent. Run multiple independent bot identities on a single ship — each with its own name, avatar, personality, conversation history, tools, and permissions. Bots respond to mentions in Tlon group channels and DMs.

## How It Works

Claw is built on [grubbery](https://github.com/gwbtc/grubbery), a framework that turns a single Gall agent into a little operating system with a typed filesystem, a process supervisor, and capability boundaries.

In grubbery, all state lives in a tree of typed files called a **tarball**. Each file can have a running **fiber** process attached to it — the file is the durable state, the process is disposable. On reload, processes are rebuilt from file state and code rather than serialized continuations. If a process finishes, its file is deleted; if it crashes, it restarts automatically. A **nexus** defines how a subtree behaves: `on-load` declares the schema (what files and directories exist), `on-file` defines the per-file process, and `on-manu` documents it. Fibers are written in a sequential monadic style (`;<  result  bind:m  (operation)`) and can poke other files, peek at state, subscribe to changes, make HTTP requests, set timers, and send Gall cards — all without blocking each other. Directories can have **weirs** (sandbox rules) that restrict what child processes can reach.

The advantage over plain Gall: instead of one monolithic agent with an opaque state blob and a giant event dispatcher, you get many small supervised processes with inspectable file-based state, natural lifecycles, and hierarchical permissions. The cost is another abstraction layer — worth it when your app wants lots of independently-running tasks (like multiple bots).

In claw, each bot is a separate process with its own files. A root process subscribes to Tlon activity events and DM watches, figures out which bot is being addressed, and routes the message to that bot's process. The bot reads its config and context files, builds a prompt, calls the LLM, and sends the response back to the channel or DM.

```
/config.json                     # global: api_key, model, brave_key
/bots-registry.json              # {bot-id: name, ...}
/main.sig                        # root process: listens for messages, routes to bots
/bots/
  brap/
    main.sig                     # bot process: handles messages, calls LLM
    config.json                  # name, avatar, model override, whitelist, cron
    context/
      identity.txt               # who the bot is
      soul.txt                   # personality and voice
      agent.txt                  # behavioral instructions
      memory.txt                 # persistent memory
  wanda/
    main.sig                     # separate process, independent from brap
    config.json
    context/...
```

## Features

- **Multiple bots per ship** — each with independent identity, personality, model, API key, whitelist, and conversation history
- **Bot-meta identity** — bot messages show with the bot's nickname and avatar in Tlon
- **Tag activation** — type `@botname` in a channel to activate a specific bot
- **DM routing** — mention a bot's name in a DM to talk to it
- **46 built-in tools** — web search, image search, channel/DM management, group admin, contacts, MCP integration, cron scheduling
- **Tool loop** — bots execute tool calls and feed results back to the LLM (max 5 rounds)
- **Per-bot whitelist** — control which ships can talk to each bot
- **Cron jobs** — schedule recurring prompts per bot
- **Conversation memory** — LCM (Lossless Context Management) stores all messages and summarizes old ones to fit within token budgets
- **Web GUI** — manage bots, config, context, whitelist, and cron at `/apps/claw/`
- **Error feedback** — HTTP errors and tool failures are reported back to the user with details
- **Sub-agents** — bots can delegate tasks to temporary worker processes that run independently and report back when done

## Installation

```
|install ~matwet %claw
```

Or from source:
```
git clone [repo-url] claw
cd claw
rsync -av desk/ /path/to/pier/claw/
|commit %claw
|install our %claw
```

## Setup

After install, set your API key. Open the GUI at `/apps/claw/` or use dojo:

```hoon
:claw-grub [%write-json / %'config.json' (pairs:enjs:format ~[['api_key' s+'YOUR-OPENROUTER-KEY'] ['model' s+'anthropic/claude-sonnet-4.5'] ['brave_key' s+'']])]
```

A default bot named `brap` is created on install. Tag `@brap` in a channel or mention "brap" in a DM to talk to it.

## Managing Bots

### GUI

The web GUI at `/apps/claw/` lets you:
- Add and delete bots
- Edit per-bot config (name, avatar, model, API key overrides)
- Edit context files (identity, soul, agent, memory)
- Manage per-bot whitelists (add/remove ships with owner/allowed roles)
- Add/remove cron jobs (scheduled recurring prompts)

### Dojo

```hoon
:: add a bot
:claw-grub [%add-bot %coder 'Coder']

:: write context files
:claw-grub [%write-txt /bots/coder/context %'identity.txt' 'You are Coder, a programming assistant on Urbit.']
:claw-grub [%write-txt /bots/coder/context %'soul.txt' 'You write clean code. You explain your reasoning.']

:: delete a bot
:claw-grub [%del-bot %coder]
```

### Config Format

**Global** (`config.json`):
```json
{"api_key": "sk-or-...", "model": "anthropic/claude-sonnet-4.5", "brave_key": "..."}
```

**Per-bot** (`bots/{id}/config.json`):
```json
{
  "name": "brap",
  "avatar": "https://...",
  "model": "",
  "api_key": "",
  "brave_key": "",
  "whitelist": {"~sampel-palnet": "owner", "~zod": "allowed"},
  "cron": [{"schedule": "0 9 * * *", "prompt": "Good morning! Check the weather."}]
}
```

Empty `model`/`api_key`/`brave_key` falls back to the global config. Empty whitelist means open to all ships.

## Permissions

Each bot has its own whitelist in its config:

| Role | Access |
|------|--------|
| `owner` | Full access — can use owner-only tools (group management, cron) |
| `allowed` | Can chat with the bot |
| *(empty whitelist)* | Open to all ships |

The host ship is automatically added as `owner` when a bot is created.

## Tools

Bots can use 46 tools via the OpenAI tool-calling protocol:

**Communication**: `send_dm`, `send_channel_message`, `add_reaction`, `remove_reaction`

**Reading**: `get_contact`, `list_contacts`, `list_groups`, `list_channels`, `read_channel_history`, `read_dm_history`, `search_messages`

**Web**: `web_search`, `image_search`, `http_fetch`, `upload_image`

**Memory**: `search_history`, `describe_summary`, `list_conversations`

**Message management**: `delete_message`, `edit_message`, `delete_dm`, `react_dm`, `unreact_dm`

**Profile**: `update_profile` (change bot name/avatar)

**Group admin** (owner only): `join_group`, `leave_group`, `create_group`, `update_group`, `invite_to_group`, `kick_from_group`, `ban_from_group`, `unban_from_group`, `add_channel`, `delete_channel`, `add_role`, `delete_role`, `assign_role`, `remove_role`

**Cron** (owner only): `cron_add`, `cron_list`, `cron_remove`

**MCP**: `local_mcp`, `local_mcp_list`, `install_local_mcp`

**Sub-agents**: `delegate` (spawn a temporary worker process for async tasks)

## Sub-Agents

Bots can delegate tasks to temporary sub-agent processes using the `delegate` tool. A sub-agent is a short-lived grub (file + process) that:

1. Gets created under `/bots/{id}/tasks/{task-id}/`
2. Inherits the parent bot's config, context, and API key
3. Runs an independent LLM call with the delegated instructions
4. Sends the result back to the conversation (DM or channel)
5. Auto-deletes when complete

This is useful for research, complex analysis, or any multi-step task the bot wants to run in the background while continuing to respond to other messages. The bot tells the user "I've delegated this to a sub-agent" and the sub-agent reports back when done.

## Cron

Each bot can have scheduled tasks. Cron expressions use standard 5-field format: `minute hour day-of-month month day-of-week`.

Examples:
- `*/30 * * * *` — every 30 minutes
- `0 9 * * *` — daily at 9am
- `0 9 * * 1-5` — weekday mornings
- `0 */6 * * *` — every 6 hours

The bot receives the prompt on schedule and processes it like a normal message.

## Conversation Memory (LCM)

The `%lcm` agent stores all messages permanently and summarizes old ones to fit within token budgets:

- Messages are never deleted — only compressed into summaries
- Summaries form a DAG with increasing levels of abstraction
- Context assembly fills the token budget with recent messages plus summaries of older content
- Each bot has isolated conversation history (namespaced by bot-id)

## HTTP API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/apps/claw/` | GET | Management GUI |
| `/apps/claw/api/config` | GET | Global config |
| `/apps/claw/api/bots` | GET | Bot registry with names |
| `/apps/claw/api/bot/{id}/config` | GET | Bot config |
| `/apps/claw/api/bot/{id}/context` | GET | Bot context files |
| `/apps/claw/api/tree` | GET | Full filesystem tree |
| `/apps/claw/api/action` | POST | Write operations |

POST actions: `set-key`, `set-model`, `set-brave-key`, `add-bot`, `del-bot`, `bot-set-name`, `bot-set-avatar`, `bot-set-model`, `bot-set-key`, `bot-set-brave-key`, `bot-set-context`, `bot-del-context`, `bot-add-ship`, `bot-del-ship`, `bot-cron-add`, `bot-cron-remove`, `bot-set-channel-perm`

## Agents

| Agent | Purpose |
|-------|---------|
| `%claw-grub` | Main agent — hosts all bot processes, manages the filesystem, handles HTTP |
| `%lcm` | Conversation storage and summarization |

## Dependencies

- **OpenRouter API key** — for LLM access
- **Brave Search API key** — optional, for web/image search
- **%groups desk** — required (Tlon Groups), with bot-meta support (see below)
- **%mcp desk** — optional, for MCP tools (can be installed by the bot itself)

### Groups Frontend (bot-meta support)

Bot messages use the `bot-meta` author type so they display with the bot's own nickname and avatar instead of the host ship's identity. This requires the [`reid/bot`](https://github.com/tloncorp/tlon-apps/tree/reid/bot) branch of `tloncorp/tlon-apps`, which adds frontend support for rendering bot authors, `@botname` mention autocomplete, and bot badge display.

On live ships, you only need to update the glob (the frontend bundle). Update `desk.docket-0` on the `%groups` desk to point at this glob:
```
https://bin.aeroe.io/groups/glob-0v7.icpsd.i0mb4.b8bda.vshk9.bhnf2.glob
```

On fakenet ships, the pill ships with an older version of the `%groups` desk that doesn't include the backend `bot-meta` type. You'll need to also update the desk contents from the `reid/bot` branch of `tloncorp/tlon-apps` before the glob will work.

Without this, claw still works but bot messages will show as authored by the host ship (no distinct bot identity in the UI).

## Credits

Vibecoded with Opus 4.6 and [%mcp](https://github.com/gwbtc/urbit-mcp) by the [GroundWire](https://groundwire.io/) crew. Inspired by the [tlon](https://github.com/user/openclaw-tlon) OpenClaw plugin. LCM reimplemented from the example of [lossless-claw](https://github.com/user/lossless-claw). Built as a native Urbit alternative that doesn't require external infrastructure.
