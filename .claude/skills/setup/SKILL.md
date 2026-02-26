---
name: setup
description: Initial NanoClaw setup on Railway. Configures API keys, asks which messaging channel to use, and delegates to the appropriate channel skill.
---

# NanoClaw Setup (Railway)

## 1. Check Railway CLI
- `railway version` - install if missing
- `railway login` - authenticate if needed
- `railway link` - connect to project

## 2. Configure Environment
- AskUserQuestion: Anthropic API key?
- AskUserQuestion: Bot name? (default: Andy)
- Set ANTHROPIC_API_KEY, ASSISTANT_NAME, TZ via `railway variable set`

## 3. Choose Channel
AskUserQuestion: Which messaging channel?
- WhatsApp -> invoke /add-whatsapp
- Telegram -> invoke /add-telegram
- Slack -> invoke /add-slack
- Discord -> invoke /add-discord

## 4. Verify
- `railway logs --tail 50` to confirm connection