# Add Agent Skill

Installs a skill for NanoClaw agents — both locally (for testing) and in the container (for production). Skills are auto-updated on every deploy via `container/skills/manifest.json`.

## Instructions

Follow these steps interactively:

### 1. Get the skill repo

Ask the user: "Which GitHub repo contains the skill? (e.g., `resend/resend-skills`)"

### 2. Install the skill

```bash
npx skills add <repo> -y
```

This puts the skill in `.claude/skills/<name>` (for local testing). The skill name is usually the second part of the repo (e.g., `resend/resend-skills` → `resend-skills`).

Then copy it to `container/skills/<name>` (for production agents):

```bash
cp -r .claude/skills/<name> container/skills/<name>
```

If `container/skills/<name>` already exists, ask the user whether to overwrite.

### 3. Register in manifest

Add the skill to `container/skills/manifest.json` so it auto-updates on every deploy:

```json
{
  "<name>": "<owner>/<repo>"
}
```

### 4. Check for MCP server needs

Read the skill's files to check if it references `mcp__` tools or needs an MCP server.

Ask the user: "Does this skill need an MCP server? If yes, what's the npm package name and what environment variables does it need?"

If yes, add the server to `.mcp.json` (used both locally and synced to containers):
```json
{
  "mcpServers": {
    "<name>": {
      "command": "npx",
      "args": ["-y", "<package>@latest"],
      "env": {
        "ENV_VAR_1": "${ENV_VAR_1}"
      }
    }
  }
}
```

### 5. Set env vars

If MCP server was configured, tell the user to set the env vars:
- Locally: add to `.env.local`
- Railway: set via `railway variables set KEY=value` or the Railway dashboard

### 6. Commit and push

Stage the new skill files and commit:
```
git add container/skills/<name> container/skills/manifest.json .mcp.json
git commit -m "feat: add <name> agent skill"
```

Ask the user if they want to push and redeploy now.