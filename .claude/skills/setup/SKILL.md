---
name: setup
description: Initial NanoClaw setup on Railway. Configures API keys, asks which messaging channel to use, applies channel code on-demand, deploys, and registers — all in one flow.
---

# NanoClaw Setup (Railway)

This skill is the single entry point for Railway deployments. It handles everything: environment config, on-demand code changes, deployment, and channel registration. Do NOT invoke the upstream `/add-whatsapp`, `/add-telegram`, `/add-slack`, or `/add-discord` skills — those are for local setups. This skill handles the full Railway flow inline.

**Principle:** Do the work. Only pause when genuine user action is required (creating a bot, scanning a QR code, pasting a token). If something is broken, fix it.

---

## Critical: Multi-Channel Resilience Rules

These rules apply to ALL code changes. They prevent one channel's failure from breaking others.

### Rule 1: Wrap every channel connect() in try/catch

In `src/index.ts`, every `await channel.connect()` MUST be wrapped:

```typescript
try {
  await channel.connect();
} catch (err) {
  logger.error({ err }, '{Channel} failed to connect, continuing with other channels');
}
```

This prevents one broken channel from blocking the rest.

### Rule 2: WhatsApp must NOT call process.exit() on Railway

In `src/channels/whatsapp.ts`, the logout handler calls `process.exit(0)` on disconnect. On Railway with multiple channels, this kills everything. The code must guard:

```typescript
if (!IS_RAILWAY) {
  process.exit(0);
}
```

If this guard is missing, add it. Check the `connection === 'close'` handler where `shouldReconnect` is false.

### Rule 3: WhatsApp connect() must resolve on logout

`WhatsAppChannel.connect()` returns a Promise that only resolves when `onFirstOpen()` fires (on successful connection open). If WhatsApp is logged out (401), the promise hangs forever, blocking `main()` from reaching other channels.

Fix: in the logout branch (where `shouldReconnect` is false), also call `onFirstOpen?.()` on Railway:

```typescript
if (IS_RAILWAY) {
  onFirstOpen?.();  // Unblock main() so other channels can start
}
```

### Rule 4: Channel tokens must read process.env on Railway

Railway sets env vars directly on the process, not in `.env` files. Any channel constructor that reads tokens via `readEnvFile()` MUST fall back to `process.env`:

```typescript
const env = readEnvFile(['TOKEN_VAR']);
const token = env.TOKEN_VAR || process.env.TOKEN_VAR;
```

Currently affects: **Slack** (reads `SLACK_BOT_TOKEN` and `SLACK_APP_TOKEN` internally in constructor).
Does NOT affect: Telegram, Discord (they receive tokens as constructor arguments from `config.ts`, which already reads `process.env`).

### Rule 5: Unique folder names per registered group

The `registered_groups` table has a UNIQUE constraint on `folder`. Each channel registration MUST use a different folder name:

| Scenario | Folder naming |
|----------|---------------|
| First/only channel | `main` |
| Adding a 2nd channel type | `{channel}-main` (e.g., `slack-main`, `tg-main`, `dc-main`) |
| Additional groups on same channel | `{channel}-{purpose}` (e.g., `slack-work`, `tg-family`) |

**CRITICAL:** Using `INSERT OR REPLACE` with the same folder as an existing group will DELETE the old registration. Always check existing registrations first.

---

## 1. Check Railway CLI

- `railway --version` — install if missing (`npm i -g @railway/cli` or `brew install railway`)
- `railway status` — check if linked to a project. If it shows project/environment/service, it's ready. If not:
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

First, check what's already configured:

```bash
railway variables
```

Check for existing tokens (`WHATSAPP_PHONE`, `TELEGRAM_BOT_TOKEN`, `SLACK_BOT_TOKEN`, `DISCORD_BOT_TOKEN`) and existing channel source files (`src/channels/{channel}.ts`).

If channels already exist, ask if the user wants to add another or reconfigure.

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

**WhatsApp:** Skip code changes — WhatsApp is the default channel, already in the source tree. But verify the resilience rules are applied (Rules 2 and 3 in whatsapp.ts, Rule 1 in index.ts).

**Telegram / Slack / Discord:**

### 1. Check if already applied

Look for `src/channels/{channel}.ts`. If it exists, skip to Phase A step 6 (verify resilience rules in index.ts and whatsapp.ts).

### 2. Copy channel files

```bash
cp .claude/skills/add-{channel}/add/src/channels/{channel}.ts src/channels/
cp .claude/skills/add-{channel}/add/src/channels/{channel}.test.ts src/channels/
```

### 3. Apply Railway compatibility fixes to copied files

The upstream skill templates are designed for local `.env`-based setups. After copying, apply these fixes for Railway:

**Slack only — fix token reading (Rule 4):**

In the just-copied `src/channels/slack.ts`, find the constructor's token reading block and add `process.env` fallback:

```typescript
// BEFORE (upstream template):
const env = readEnvFile(['SLACK_BOT_TOKEN', 'SLACK_APP_TOKEN']);
const botToken = env.SLACK_BOT_TOKEN;
const appToken = env.SLACK_APP_TOKEN;

// AFTER (Railway-compatible):
const env = readEnvFile(['SLACK_BOT_TOKEN', 'SLACK_APP_TOKEN']);
const botToken = env.SLACK_BOT_TOKEN || process.env.SLACK_BOT_TOKEN;
const appToken = env.SLACK_APP_TOKEN || process.env.SLACK_APP_TOKEN;
```

Also fix the TypeScript type error on `msg.user` (which is `string | undefined`):

```typescript
// BEFORE:
(await this.resolveUserName(msg.user)) ||

// AFTER:
(await this.resolveUserName(msg.user ?? '')) ||
```

**Telegram / Discord:** No post-copy fixes needed — they receive tokens as constructor arguments.

### 4. Install npm package

```bash
npm install {package}
```

### 5. Edit `src/config.ts`

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

### 6. Edit `src/index.ts`

Add import and conditional channel creation in `main()`, after the WhatsApp block. **IMPORTANT:** Apply Rule 1 — wrap the WhatsApp connect AND the new channel connect in try/catch.

Check and fix if needed — the WhatsApp block should look like:

```typescript
if (...) {
  whatsapp = new WhatsAppChannel(channelOpts);
  channels.push(whatsapp);
  try {
    await whatsapp.connect();
  } catch (err) {
    logger.error({ err }, 'WhatsApp failed to connect, continuing with other channels');
  }
}
```

Then add the new channel AFTER the WhatsApp block:

**Telegram:**
```typescript
import { TelegramChannel } from './channels/telegram.js';
import { ..., TELEGRAM_BOT_TOKEN } from './config.js';

if (TELEGRAM_BOT_TOKEN) {
  const telegram = new TelegramChannel(TELEGRAM_BOT_TOKEN, channelOpts);
  channels.push(telegram);
  try {
    await telegram.connect();
  } catch (err) {
    logger.error({ err }, 'Telegram failed to connect, continuing with other channels');
  }
}
```

**Slack:**
```typescript
import { SlackChannel } from './channels/slack.js';
import { ..., SLACK_BOT_TOKEN } from './config.js';

if (SLACK_BOT_TOKEN) {
  const slack = new SlackChannel(channelOpts);
  channels.push(slack);
  try {
    await slack.connect();
  } catch (err) {
    logger.error({ err }, 'Slack failed to connect, continuing with other channels');
  }
}
```

**Discord:**
```typescript
import { DiscordChannel } from './channels/discord.js';
import { ..., DISCORD_BOT_TOKEN } from './config.js';

if (DISCORD_BOT_TOKEN) {
  const discord = new DiscordChannel(DISCORD_BOT_TOKEN, channelOpts);
  channels.push(discord);
  try {
    await discord.connect();
  } catch (err) {
    logger.error({ err }, 'Discord failed to connect, continuing with other channels');
  }
}
```

### 7. Verify WhatsApp resilience (Rules 2 + 3)

Read `src/channels/whatsapp.ts` and check the `connection === 'close'` handler:

**Rule 2 — No process.exit on Railway:**
Find the block where `shouldReconnect` is false. It must NOT call `process.exit()` on Railway:
```typescript
} else {
  logger.info('Logged out. Run /setup to re-authenticate.');
  if (IS_RAILWAY) {
    onFirstOpen?.();  // Rule 3: unblock main()
  } else {
    process.exit(0);
  }
}
```

**Rule 3 — Resolve connect() on logout:**
In the same block, `onFirstOpen?.()` must be called on Railway so the `connect()` Promise resolves and `main()` can proceed to start other channels.

If either fix is missing, apply them.

### 8. Build

```bash
npm run build
```

Fix any TypeScript errors before proceeding.

### 9. Commit and push

```bash
git add src/channels/{channel}.ts src/channels/{channel}.test.ts src/index.ts src/config.ts src/channels/whatsapp.ts package.json package-lock.json
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

Use `railway up --detach` to deploy the local code directly — this is faster and more reliable than waiting for a git-triggered build:

```bash
railway up --detach
```

Then wait ~90s for build + deploy. If `railway up` fails, fall back to `railway redeploy --yes`.

### 4. Wait and verify connection

Wait for the deploy, then check logs:

```bash
sleep 90 && railway logs --tail 50
```

If the build hasn't finished, wait and retry. Look for "State loaded" with a `groupCount` and channel connection messages.

**WhatsApp (fresh pairing):** Look for `WhatsApp pairing code: XXXXXXXX`. Display it and instruct:
> 1. Open WhatsApp on your phone
> 2. Go to **Settings > Linked Devices > Link a Device**
> 3. Tap **Link with phone number instead**
> 4. Enter the pairing code displayed above

The pairing code expires in ~20s. If expired, redeploy to get a new one.

**WhatsApp (stale auth):** If logs show a 401 error + "Logged out", the auth creds are stale. Clear them:
```bash
railway ssh "rm -rf /data/store/auth && echo 'Auth cleared'"
railway redeploy --yes
```
Then wait for the new pairing code.

After linking, check logs for `Connected to WhatsApp`.

**Telegram:** Look for bot started / connected message.

**Slack:** Look for `Connected to Slack` message.

**Discord:** Look for Discord logged in message.

---

## Phase D: Register Channel

### 1. Check existing registrations and get ASSISTANT_NAME

```bash
railway ssh "node -e \"
const db = require('better-sqlite3')('/data/store/messages.db');
console.log('=== Registered Groups ===');
console.log(JSON.stringify(db.prepare('SELECT * FROM registered_groups').all(), null, 2));
console.log('=== Available Chats ===');
console.log(JSON.stringify(db.prepare('SELECT jid, name, is_group FROM chats ORDER BY last_message_time DESC LIMIT 20').all(), null, 2));
\""
```

Also read ASSISTANT_NAME:
```bash
railway variables
```

### 2. Determine folder name (Rule 5)

Check existing registrations from step 1.

- If NO existing registrations → use `main`
- If registrations exist and this is a NEW channel type → use `{channel}-main` (e.g., `slack-main`, `tg-main`, `dc-main`)
- NEVER reuse a folder name that's already taken

### 3. Guide user to create/join chat and get the ID

**WhatsApp:**
> 1. Open WhatsApp, tap **New Group**
> 2. Add the bot's phone number (the WHATSAPP_PHONE number) as a participant
> 3. Name the group the same as the bot name (e.g., "Andy")
> 4. Create the group and confirm when done

WhatsApp needs a redeploy to sync group metadata before we can get the JID:

1. Create group folder first (before redeploy to avoid extra redeploy):
   ```bash
   railway ssh "mkdir -p /data/groups/<FOLDER> && cat > /data/groups/<FOLDER>/CLAUDE.md << 'EOF'
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

### 4. Create group folder and register — single SSH command

Run both the folder creation and DB registration in one SSH call to avoid multiple round trips:

```bash
railway ssh "
mkdir -p /data/groups/<FOLDER> &&
cat > /data/groups/<FOLDER>/CLAUDE.md << 'CEOF'
# <ASSISTANT_NAME> — <DISPLAY_NAME>

You are <ASSISTANT_NAME>, a personal assistant. Be helpful, concise, and friendly.
CEOF

node -e \"
const db = require('better-sqlite3')('/data/store/messages.db');
db.prepare('INSERT OR REPLACE INTO registered_groups (jid, name, folder, trigger_pattern, added_at, requires_trigger) VALUES (?, ?, ?, ?, ?, ?)').run('<JID>', '<DISPLAY_NAME>', '<FOLDER>', '@<ASSISTANT_NAME>', new Date().toISOString(), 0);
console.log(JSON.stringify(db.prepare('SELECT * FROM registered_groups').all(), null, 2));
\"
"
```

Replace:
- `<JID>` — full prefixed ID (e.g., `slack:C0123456789`, `tg:-1001234567890`, `dc:1234567890123456`, `120363...@g.us`)
- `<DISPLAY_NAME>` — human-readable name (e.g., "Giorgio Slack")
- `<FOLDER>` — unique folder name determined in step 2
- `<ASSISTANT_NAME>` — bot name from env vars

NOTE: `requires_trigger` is `0` (false) for the main group — every message gets a response.

**IMPORTANT:** After running, verify the output shows ALL expected registrations (both old and new). If an old registration disappeared, the folder UNIQUE constraint was violated — fix immediately.

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
   Confirm `groupCount` in the "State loaded" log line matches the expected number of registered groups.

2. Ask the user to send a test message in the registered chat/channel:
   - Main channel: any message works (no trigger needed)

3. Check logs for the agent response:
   ```bash
   railway logs --tail 30
   ```

---

## Final Verification

- `railway logs --tail 50` to confirm everything is connected and responding
- Congratulate the user — setup is complete!

## How the bot works

- **Main channel**: The registered channel with folder "main" (or `{channel}-main`) does NOT require any trigger — every message gets a response
- **Additional channels**: Register more channels with different folder names. In non-main channels, users must use the trigger (e.g., `@Andy`)
- **Multiple channel types**: You can run multiple channel types simultaneously (e.g., WhatsApp + Telegram + Slack). Run `/setup` again to add another channel — Phase A will add the code, and existing channels keep working

## Troubleshooting

### Service crashes immediately after deploy
Check `railway logs --tail 50`. Common causes:
- **WhatsApp 401 + process.exit**: Apply Rule 2 (no process.exit on Railway)
- **Channel constructor throws**: Apply Rule 4 (process.env fallback for tokens)
- **connect() hangs then times out**: Apply Rule 3 (resolve promise on logout)

### New channel doesn't start but old channel works
- **connect() blocked**: WhatsApp's connect() Promise never resolved → Apply Rule 3
- **try/catch missing**: Old channel threw, killed main() → Apply Rule 1

### Registration disappears after adding new channel
- **Folder UNIQUE conflict**: Both channels used the same folder name → Apply Rule 5, use different folder names

### WhatsApp shows pairing code but then gets 401
- Stale auth creds exist: `railway ssh "rm -rf /data/store/auth"` then `railway redeploy --yes`

### Build takes too long / redeploy not picking up changes
- Use `railway up --detach` instead of `railway redeploy --yes` to push local code directly
- Check if a git-triggered build is already in progress (builds queue, don't overlap)