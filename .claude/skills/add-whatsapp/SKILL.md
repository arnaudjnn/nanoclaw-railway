---
name: add-whatsapp
description: Add WhatsApp as a channel on Railway. Handles phone number config, pairing code auth, and group registration.
---

# Add WhatsApp Channel (Railway)

## 1. Configure Phone Number
- AskUserQuestion: WhatsApp phone number (with country code, e.g. +1234567890)?
- `railway variable set WHATSAPP_PHONE="+..."`
- Redeploy: `railway redeploy --yes`

## 2. Authenticate (Link Device)
- Wait ~15s for the service to start, then check logs for the pairing code:
  `railway logs --tail 30` — look for "WhatsApp pairing code: XXXXXXXX"
- Display the code and instruct the user:
  1. Open WhatsApp on your phone
  2. Go to **Settings > Linked Devices > Link a Device**
  3. Tap **Link with phone number instead**
  4. Enter the pairing code displayed above
- After linking, check logs again to confirm: `Connected to WhatsApp`

## 3. Create and Register Main Group
- Read ASSISTANT_NAME from Railway variables (`railway variables` — look for ASSISTANT_NAME)
- Instruct the user to create a WhatsApp group:
  1. Open WhatsApp, tap **New Group**
  2. Add the bot's phone number (the WHATSAPP_PHONE number) as a participant
  3. Name the group the same as ASSISTANT_NAME (e.g. "Andy")
  4. Create the group and confirm when done
- The bot syncs group metadata on startup, so a redeploy is needed for the new group to appear in the DB. Before redeploying, prepare everything via `railway ssh` so only ONE redeploy is needed:
  1. Create the group folder and CLAUDE.md on the volume:
     ```
     railway ssh "mkdir -p /data/groups/main && cat > /data/groups/main/CLAUDE.md << 'EOF'
     # <ASSISTANT_NAME> — Main Group

     You are <ASSISTANT_NAME>, a personal assistant. Be helpful, concise, and friendly.
     EOF"
     ```
  2. Redeploy (this triggers group sync AND loads the registration): `railway redeploy --yes`
  3. Wait ~20s, then find the group JID by querying the chats table:
     ```
     railway ssh "node -e \"const db = require('better-sqlite3')('/data/store/messages.db'); console.log(JSON.stringify(db.prepare('SELECT jid, name, is_group FROM chats WHERE is_group = 1 ORDER BY last_message_time DESC').all(), null, 2));\""
     ```
  4. Auto-select the group whose name matches ASSISTANT_NAME. If no match, show the list and ask the user which one to register
  5. Register the group and redeploy to load it:
     ```
     railway ssh "node -e \"const db = require('better-sqlite3')('/data/store/messages.db'); db.prepare('INSERT OR REPLACE INTO registered_groups (jid, name, folder, trigger_pattern, added_at, requires_trigger) VALUES (?, ?, ?, ?, ?, ?)').run('<JID>', '<NAME>', 'main', '@<ASSISTANT_NAME>', new Date().toISOString(), 1); console.log(JSON.stringify(db.prepare('SELECT * FROM registered_groups').all(), null, 2));\""
     ```
     `railway redeploy --yes`
  6. Check logs to confirm `groupCount: 1`

NOTE: Two redeploys are unavoidable — the first discovers the group JID (via WhatsApp sync), the second loads the registration into memory. The CLAUDE.md is created before the first redeploy to avoid a third.

## 4. Verify
- Ask the user to send a test message in the group (e.g. "what time is it?" — no `@` prefix needed in the main group)
- Check logs for agent response: `railway logs --tail 30`

## How the bot works in WhatsApp

- **Main group**: The group registered with folder "main" does NOT require any trigger — every message gets a response. Just type normally.
- **Other groups**: The bot's phone number can be added to any WhatsApp group. To register additional groups, use the same SQL insert with a different folder name. In non-main groups, users must mention the bot by starting their message with `@<ASSISTANT_NAME>` (e.g. `@Andy`) — either by typing `@` and selecting the bot from the participant list, or by typing the name manually.
