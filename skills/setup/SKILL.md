---
name: setup
description: Configure ticket-pilot for this project. Sets the tracker (linear, github, jira), team prefixes, and default mode. Saves to .claude/ticket-pilot.json.
argument-hint: [--tracker linear|github|jira]
---

# Setup ticket-pilot

Configure ticket-pilot for this project so tracker detection is always deterministic.

## Input

Arguments: `$ARGUMENTS`

If `--tracker` is provided in arguments, use that value. Otherwise, ask the user.

## Step 1: Detect Current Config

Check if `.claude/ticket-pilot.json` already exists in the project root. If it does, read it and show the current configuration to the user:

```
## Current Configuration

- **Tracker:** [tracker]
- **Team prefixes:** [prefixes or "not set"]
- **Default prefix:** [prefix or "not set"]
- **Default mode:** [mode or "guided"]

Want to update these settings?
```

If the user says no, stop here.

## Step 2: Choose Tracker

If no config exists or the user wants to update:

Ask the user which tracker they use for this project:

1. **GitHub Issues** — uses `gh` CLI
2. **Linear** — uses Linear MCP server
3. **Jira** — uses Atlassian MCP server

Verify the chosen tracker is accessible:
- **GitHub:** Run `gh auth status`
- **Linear:** Check if Linear MCP server is available
- **Jira:** Check if Atlassian MCP server is available

If the tracker is not accessible, warn the user and provide setup instructions, but still save the config.

## Step 3: Tracker-Specific Settings

### Linear
- Ask for team prefixes used in this project (e.g., `ENG`, `DES`). These help with ticket detection.
- Ask for a default prefix for creating tickets (e.g., `ENG`).

### Jira
- Ask for project keys used in this project (e.g., `PROJ`, `OPS`). These help with ticket detection.
- Ask for a default project key for creating tickets.

### GitHub
- No additional settings needed (repo is inferred from git remote).

## Step 4: Default Mode

Ask the user their preferred mode for `/ticket-pilot:resolve`:

1. **guided** (default) — approve each step before proceeding
2. **auto** — fully autonomous, only stops if tests fail

## Step 5: Save Config

Create the `.claude/` directory if it doesn't exist, then write `.claude/ticket-pilot.json`:

```json
{
  "tracker": "<chosen tracker>",
  "teamPrefixes": ["ENG", "DES"],
  "defaultPrefix": "ENG",
  "defaultMode": "guided"
}
```

Only include fields that have values. Minimal example for GitHub:

```json
{
  "tracker": "github",
  "defaultMode": "guided"
}
```

After saving, confirm:

```
Configuration saved to .claude/ticket-pilot.json

All ticket-pilot commands will now use [tracker] for this project.
```

**Remind the user** to add `.claude/ticket-pilot.json` to version control so the team shares the same config, or to `.gitignore` if they prefer personal settings.
