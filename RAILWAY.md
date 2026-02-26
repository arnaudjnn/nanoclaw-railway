# Deploy and Host NanoClaw on Railway

NanoClaw is a personal AI assistant powered by Claude that connects to messaging channels (WhatsApp, Telegram, Slack, Discord). It runs Claude Agent SDK in isolated processes, giving each group its own memory, skills, and tools - including web browsing, file management, and scheduled tasks.

## About Hosting NanoClaw

Deploying NanoClaw on Railway involves running a single Node.js service that spawns Claude Agent SDK processes for each incoming message. A persistent volume stores authentication state, SQLite databases, group memory, and conversation history. The service uses a multi-stage Docker build that bundles Chromium (for web browsing), the Claude Code CLI, and the agent-runner into one image. The service starts channel-agnostic -use the `/setup` skill in Claude Code to configure your API key, choose a messaging channel, and connect.

## Common Use Cases

- Personal AI assistant accessible from your phone or desktop: ask questions, search the web, browse pages, and manage tasks
- Group-aware assistant that maintains separate memory and context per chat group, with customizable triggers and behavior
- Scheduled task automation with recurring prompts (daily summaries, reminders, monitoring) running on cron schedules

## Dependencies for NanoClaw Hosting

- An Anthropic API key (`ANTHROPIC_API_KEY`)
- NanoClaw is channel-agnostic -connect WhatsApp, Telegram, Slack, or Discord via the `/setup` skill

### Deployment Dependencies

- [NanoClaw GitHub Repository](https://github.com/qwibitai/nanoclaw)
- [Anthropic API](https://console.anthropic.com/) for Claude access

### Implementation Details

NanoClaw requires these Railway environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Yes | API key for Claude model access |
| `ASSISTANT_NAME` | No | Bot display name (default: `Andy`) |
| `TZ` | No | Timezone for scheduled tasks and log timestamps (default: `UTC`) |

A Railway volume must be mounted at `/data` for persistent storage (auth state, SQLite, group files).

After deployment, run `/setup` in Claude Code to configure your API key, choose a messaging channel, and connect.

## Differences from the Local (Docker) Setup

The upstream [NanoClaw repository](https://github.com/qwibitai/nanoclaw) runs each agent invocation inside a Docker container, providing OS-level isolation between the host and the agent's filesystem. On Railway, Docker-in-Docker is not available, so agents run as child Node.js processes instead. Here's what changes:

| Feature | Local (Docker) | Railway |
|---------|---------------|---------|
| Agent isolation | Each agent runs in its own container with separate filesystem | Agents run as child processes sharing the host filesystem |
| Filesystem sandboxing | Container mounts restrict what the agent can read/write | Directory-based separation (no OS-level enforcement) |
| Resource limits | Docker CPU/memory limits per container | Railway service-level resource limits |
| Availability | Depends on your machine being on and connected | Always on - Railway keeps the service running 24/7 |
| Network | Requires stable home internet and open ports | Railway handles networking, SSL, and uptime |

### Why This Is Fine for Personal Use

NanoClaw is designed as a **personal assistant** - you control who has access and what groups are registered. The agent already runs with `--dangerously-skip-permissions` (bypassing Claude Code's permission prompts), so container isolation is a defense-in-depth layer, not the primary security boundary. For a single-user deployment:

- **You are the only one sending prompts** - there's no untrusted input that could exploit the lack of sandboxing
- **The agent only writes to its group folder** - the Claude SDK's working directory is scoped to `/data/groups/{group}/`
- **Secrets are protected** - API keys are passed via stdin and stripped from Bash subprocesses by a PreToolUse hook, same as Docker mode
- **The real advantage is uptime** - Railway keeps your assistant available 24/7 without needing a always-on home machine

If you need multi-tenant isolation or expose the bot to untrusted users, consider the local Docker setup instead.

## Why Deploy NanoClaw on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying NanoClaw on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
