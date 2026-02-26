---
name: add-whatsapp
description: Add WhatsApp as a channel on Railway. Handles phone number config, pairing code auth, and group registration.
---

# Add WhatsApp Channel (Railway)

## 1. Configure Phone Number
- AskUserQuestion: WhatsApp phone number (with country code)?
- `railway variable set WHATSAPP_PHONE="+..."`
- Redeploy: `railway up --detach` (or wait for auto-deploy from git push)

## 2. Authenticate
- Wait for service to start, check logs for pairing code
- `railway logs --tail 30` - look for "WhatsApp pairing code: XXXXXXXX"
- Display code, instruct user to enter in WhatsApp > Linked Devices > Link with phone number

## 3. Register Main Group
- AskUserQuestion: Create a solo group or use existing?
- Guide user through group creation and first message
- Find group JID from logs/DB
- Register via sqlite on Railway

## 4. Verify
- User sends test message, check logs for agent response
