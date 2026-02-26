# Setup Railway

Deploy and configure NanoClaw on Railway. Handles WhatsApp authentication on a running Railway service.

**Prerequisite**: The service must already be deployed on Railway with env vars configured (ANTHROPIC_API_KEY, WHATSAPP_PHONE, ASSISTANT_NAME) and a volume mounted at `/data`.

## Steps

### 1. Check Railway CLI

```bash
railway version
```

If missing, tell the user to install it:
```bash
npm install -g @railway/cli
```

Then authenticate:
```bash
railway login
```

### 2. Link to Project

Link the local directory to the Railway project:

```bash
railway link
```

This is interactive — the user selects their project and service.

### 3. WhatsApp Authentication

Use the pairing code method via `railway shell`. First read the phone number:

```bash
railway variables | grep WHATSAPP_PHONE
```

Then run WhatsApp auth inside the running service:

```bash
railway shell
# Inside the shell:
npx tsx setup/index.ts --step whatsapp-auth --method pairing-code --phone $WHATSAPP_PHONE
```

Display the pairing code to the user. They need to:
1. Open WhatsApp on their phone
2. Go to Settings → Linked Devices → Link a Device
3. Choose "Link with phone number instead"
4. Enter the pairing code

### 4. Verify Connection

Check the logs to confirm WhatsApp connected successfully:

```bash
railway logs --tail 50
```

Look for: "WhatsApp connection ready" or similar success message.

### 5. Restart if Needed

If the service needs a restart after auth:

```bash
railway up
```

## Troubleshooting

- **Auth state not persisting**: Ensure a Railway volume is mounted at `/data`. The auth store lives at `/data/store/`.
- **Pairing code expired**: Re-run the auth step. Codes expire after ~60 seconds.
- **Service not found**: Run `railway link` again to connect to the correct project.
