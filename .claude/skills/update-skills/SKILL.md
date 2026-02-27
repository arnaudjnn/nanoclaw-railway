# Update Agent Skills

Pulls the latest version of all agent skills listed in `container/skills/manifest.json`.

## Instructions

### 1. Read the manifest

Read `container/skills/manifest.json`. It maps skill names to GitHub repos:
```json
{
  "resend-skills": "resend/resend-skills"
}
```

If the manifest is empty or missing, tell the user: "No agent skills registered. Use `/add-skill` to install one."

### 2. Update each skill

For each entry in the manifest:

```bash
npx skills add <repo> -y
cp -r .claude/skills/<name> container/skills/<name>
```

Log which skills were updated.

### 3. Show results

Summarize what was updated. Ask the user if they want to commit and push.