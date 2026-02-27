---
name: setup
description: Initial NanoClaw setup on Railway. Configures API keys, asks which messaging channel to use, applies channel code on-demand, deploys, and registers — all in one flow.
---

# NanoClaw Setup (Railway)

This skill is the single entry point for Railway deployments. It handles everything: environment config, on-demand code changes, deployment, and channel registration. Do NOT invoke the upstream `/add-whatsapp`, `/add-telegram`, `/add-slack`, or `/add-discord` skills — those are for local setups. This skill handles the full Railway flow inline.

**Principle:** Do the work. Only pause when genuine user action is required (creating a bot, scanning a QR code, pasting a token). If something is broken, fix it.

## 1. Check Railway CLI

- `railway version` — install if missing
- `railway login` — authenticate if needed
- `railway link` — connect to project

## 2. Configure Environment

- AskUserQuestion: Anthropic API key?
- AskUserQuestion: Bot name? (default: Andy)
- AskUserQuestion: Timezone? (or detect from system)
- Set via `railway variable set`:
  - `ANTHROPIC_API_KEY="..."`
  - `ASSISTANT_NAME="..."`
  - `TZ="..."`

## 3. Choose Channel

AskUserQuestion: Which messaging channel?
- **WhatsApp**
- **Telegram**
- **Slack**
- **Discord**

Then proceed with the unified flow below. All 4 channels follow the same Phase A → E structure.

---

## Channel Reference

| Channel | npm package | Already in source? | Token env var(s) | Source file | Constructor |
|---------|-----------|-------------------|-------------------|-------------|-------------|
| WhatsApp | `@whiskeysockets/baileys` | **Yes** | `WHATSAPP_PHONE` | `whatsapp.ts` | `new WhatsAppChannel(channelOpts)` |
| Telegram | `grammy` | No | `TELEGRAM_BOT_TOKEN` | `telegram.ts` | `new TelegramChannel(TOKEN, channelOpts)` |
| Slack | `@slack/bolt` | No | `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN` | `slack.ts` | `new SlackChannel(channelOpts)` (reads tokens internally) |
| Discord | `discord.js` | No | `DISCORD_BOT_TOKEN` | `discord.ts` | `new DiscordChannel(TOKEN, channelOpts)` |

---

## Phase A: Apply Code Changes

**WhatsApp:** Skip this phase entirely — WhatsApp is the default channel, already in the source tree.

**Telegram / Slack / Discord:**

### 1. Check if already applied

Look for `src/channels/{channel}.ts`. If it exists, skip to Phase B.

### 2. Copy channel files

```bash
cp .claude/skills/add-{channel}/add/src/channels/{channel}.ts src/channels/
cp .claude/skills/add-{channel}/add/src/channels/{channel}.test.ts src/channels/
```

### 3. Install npm package

```bash
npm install {package}
```

### 4. Edit `src/config.ts`

Add the token env var(s) to the `readEnvFile()` call and export them.

**Telegram:**
```typescript
const envConfig = readEnvFile(['ASSISTANT_NAME', 'ASSISTANT_HAS_OWN_NUMBER', 'TELEGRAM_BOT_TOKEN']);
export const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || envConfig.TELEGRAM_BOT_TOKEN || '';
```

**Discord:** Same pattern with `DISCORD_BOT_TOKEN`.

**Slack:**
```typescript
const envConfig = readEnvFile(['ASSISTANT_NAME', 'ASSISTANT_HAS_OWN_NUMBER', 'SLACK_BOT_TOKEN', 'SLACK_APP_TOKEN']);
export const SLACK_BOT_TOKEN = process.env.SLACK_BOT_TOKEN || envConfig.SLACK_BOT_TOKEN || '';
export const SLACK_APP_TOKEN = process.env.SLACK_APP_TOKEN || envConfig.SLACK_APP_TOKEN || '';
```

### 5. Edit `src/index.ts`

Add import and conditional channel creation in `main()`, after the WhatsApp block.

**Telegram:**
```typescript
// Import at top:
import { TelegramChannel } from './channels/telegram.js';
import { ..., TELEGRAM_BOT_TOKEN } from './config.js';

// In main(), after WhatsApp block:
if (TELEGRAM_BOT_TOKEN) {
  const telegram = new TelegramChannel(TELEGRAM_BOT_TOKEN, channelOpts);
  channels.push(telegram);
  await telegram.connect();
}
```

**Slack:**
```typescript
import { SlackChannel } from './channels/slack.js';
import { ..., SLACK_BOT_TOKEN } from './config.js';

if (SLACK_BOT_TOKEN) {
  const slack = new SlackChannel(channelOpts);
  channels.push(slack);
  await slack.connect();
}
```

**Discord:**
```typescript
import { DiscordChannel } from './channels/discord.js';
import { ..., DISCORD_BOT_TOKEN } from './config.js';

if (DISCORD_BOT_TOKEN) {
  const discord = new DiscordChannel(DISCORD_BOT_TOKEN, channelOpts);
  channels.push(discord);
  await discord.connect();
}
```

### 6. Build

```bash
npm run build
```

Fix any TypeScript errors before proceeding.

### 7. Commit and push

```bash
git add src/channels/{channel}.ts src/channels/{channel}.test.ts src/index.ts src/config.ts package.json package-lock.json
git commit -m "feat: add {channel} channel support"
git push
```

This triggers a Railway rebuild. No need to redeploy yet — we'll set env vars first and redeploy once.

---

## Phase B: Bot/Account Setup Guidance

Guide the user through creating the bot or configuring the account. They need the credentials for Phase C.

### WhatsApp

AskUserQuestion: WhatsApp phone number (with country code, e.g. +1234567890)?

No bot creation needed — WhatsApp uses phone number + pairing code.

### Telegram

> 1. Open Telegram and search for `@BotFather`
> 2. Send `/newbot` and follow prompts:
>    - Bot name: Something friendly (e.g., "Andy Assistant")
>    - Bot username: Must end with "bot" (e.g., "andy_ai_bot")
> 3. Copy the bot token (looks like `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)
>
> **Important for group chats**: Disable Group Privacy so the bot can see all messages:
> 1. In @BotFather, send `/mybots` and select your bot
> 2. Go to **Bot Settings** > **Group Privacy** > **Turn off**

### Slack

> 1. Go to [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → **From scratch**
> 2. Enable **Socket Mode** (sidebar) → generate App-Level Token (`xapp-...`) — copy it
> 3. **Event Subscriptions** → Enable → Subscribe to bot events: `message.channels`, `message.groups`, `message.im`
> 4. **OAuth & Permissions** → Add Bot Token Scopes: `chat:write`, `channels:history`, `groups:history`, `im:history`, `channels:read`, `groups:read`, `users:read`
> 5. **Install App** → Install to Workspace → copy Bot User OAuth Token (`xoxb-...`)

### Discord

> 1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
> 2. Click **New Application** → name it (e.g., "Andy Assistant")
> 3. Go to **Bot** tab → **Reset Token** → copy the token immediately
> 4. Under **Privileged Gateway Intents**, enable:
>    - **Message Content Intent** (required)
>    - **Server Members Intent** (optional)
> 5. Go to **OAuth2** > **URL Generator**:
>    - Scopes: `bot`
>    - Bot Permissions: `Send Messages`, `Read Message History`, `View Channels`
>    - Copy the generated URL and open it to invite the bot to your server

---

## Phase C: Set Env Vars + Deploy

### 1. Collect credentials

AskUserQuestion to collect the token(s)/phone number from the user.

### 2. Set env vars on Railway

**WhatsApp:** `railway variable set WHATSAPP_PHONE="+..."`

**Telegram:** `railway variable set TELEGRAM_BOT_TOKEN="..."`

**Slack:** `railway variable set SLACK_BOT_TOKEN="..." SLACK_APP_TOKEN="..."`

**Discord:** `railway variable set DISCORD_BOT_TOKEN="..."`

### 3. Deploy

```bash
railway redeploy --yes
```

### 4. Wait and verify connection

Wait ~15-20s for the service to start, then check logs:

```bash
railway logs --tail 30
```

**WhatsApp:** Look for `WhatsApp pairing code: XXXXXXXX`. Display it and instruct:
> 1. Open WhatsApp on your phone
> 2. Go to **Settings > Linked Devices > Link a Device**
> 3. Tap **Link with phone number instead**
> 4. Enter the pairing code displayed above

After linking, check logs again for `Connected to WhatsApp`.

**Telegram:** Look for bot started / connected message.

**Slack:** Look for Slack connected message.

**Discord:** Look for Discord logged in message.

---

## Phase D: Register Channel

### 1. Read ASSISTANT_NAME

```bash
railway variables
```
Look for ASSISTANT_NAME value.

### 2. Guide user to create/join chat and get the ID

**WhatsApp:**
> 1. Open WhatsApp, tap **New Group**
> 2. Add the bot's phone number (the WHATSAPP_PHONE number) as a participant
> 3. Name the group the same as the bot name (e.g., "Andy")
> 4. Create the group and confirm when done

WhatsApp needs a redeploy to sync group metadata before we can get the JID:

1. Create group folder first (before redeploy to avoid extra redeploy):
   ```bash
   railway ssh "mkdir -p /data/groups/main && cat > /data/groups/main/CLAUDE.md << 'EOF'
   # <ASSISTANT_NAME> — Main Group

   You are <ASSISTANT_NAME>, a personal assistant. Be helpful, concise, and friendly.
   EOF"
   ```
2. Redeploy to trigger group sync:
   ```bash
   railway redeploy --yes
   ```
3. Wait ~20s, then find the group JID:
   ```bash
   railway ssh "node -e \"const db = require('better-sqlite3')('/data/store/messages.db'); console.log(JSON.stringify(db.prepare('SELECT jid, name, is_group FROM chats WHERE is_group = 1 ORDER BY last_message_time DESC').all(), null, 2));\""
   ```
4. Auto-select the group whose name matches ASSISTANT_NAME. If no match, show the list and AskUserQuestion.

**Telegram:**
> 1. Add the bot to a Telegram group (or open a DM with the bot)
> 2. Send `/chatid` in the group — the bot will reply with the chat ID
> 3. The ID format is `tg:123456789` or `tg:-1001234567890`

AskUserQuestion: What is the chat ID?

**Slack:**
> 1. Add the bot to a Slack channel: right-click channel → **View channel details** → **Integrations** → **Add apps**
> 2. Get the channel ID from the URL: `https://app.slack.com/client/T.../C0123456789` — the `C...` part
> 3. The ID format is `slack:C0123456789`

AskUserQuestion: What is the channel ID?

**Discord:**
> 1. Enable Developer Mode: **User Settings** > **Advanced** > **Developer Mode**
> 2. Right-click the text channel → **Copy Channel ID**
> 3. The ID format is `dc:1234567890123456`

AskUserQuestion: What is the channel ID?

### 3. Create group folder (if not already done for WhatsApp)

```bash
railway ssh "mkdir -p /data/groups/main && cat > /data/groups/main/CLAUDE.md << 'EOF'
# <ASSISTANT_NAME> — Main Group

You are <ASSISTANT_NAME>, a personal assistant. Be helpful, concise, and friendly.
EOF"
```

### 4. Register in SQLite

```bash
railway ssh "node -e \"const db = require('better-sqlite3')('/data/store/messages.db'); db.prepare('INSERT OR REPLACE INTO registered_groups (jid, name, folder, trigger_pattern, added_at, requires_trigger) VALUES (?, ?, ?, ?, ?, ?)').run('<JID>', '<NAME>', 'main', '@<ASSISTANT_NAME>', new Date().toISOString(), 0); console.log(JSON.stringify(db.prepare('SELECT * FROM registered_groups').all(), null, 2));\""
```

Replace `<JID>` with the full prefixed ID, `<NAME>` with a display name, `<ASSISTANT_NAME>` with the bot name.

NOTE: `requires_trigger` is `0` (false) for the main group — every message gets a response.

### 5. Redeploy to load registration

```bash
railway redeploy --yes
```

NOTE for WhatsApp: Two redeploys are unavoidable — the first discovers the group JID (via WhatsApp sync), the second loads the registration. The CLAUDE.md is created before the first redeploy to avoid a third.

---

## Phase E: Verify

1. Wait ~15-20s, then check logs:
   ```bash
   railway logs --tail 30
   ```
   Confirm `groupCount: 1` in the "State loaded" log line.

2. Ask the user to send a test message in the registered chat/channel:
   - Main channel: any message works (no trigger needed)

3. Check logs for the agent response:
   ```bash
   railway logs --tail 30
   ```

---

## 4. Final Verification

- `railway logs --tail 50` to confirm everything is connected and responding
- Congratulate the user — setup is complete!

## How the bot works

- **Main channel**: The registered channel with folder "main" does NOT require any trigger — every message gets a response
- **Additional channels**: Register more channels with different folder names. In non-main channels, users must use the trigger (e.g., `@Andy`)
- **Multiple channel types**: You can run multiple channel types simultaneously (e.g., WhatsApp + Telegram). Run `/setup` again to add another channel — Phase A will add the code, and existing channels keep working