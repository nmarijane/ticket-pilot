<div align="center">

# ticket-pilot

**Issue tracker integration for Claude Code**

*Go from ticket to pull request without leaving your terminal.*

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/claude--code-plugin-blueviolet)](https://code.claude.com/docs/en/plugins)
[![Linear](https://img.shields.io/badge/Linear-supported-5E6AD2)](https://linear.app)
[![GitHub Issues](https://img.shields.io/badge/GitHub_Issues-supported-333)](https://github.com)
[![Jira](https://img.shields.io/badge/Jira-supported-0052CC)](https://www.atlassian.com/software/jira)

</div>

---

## The Problem

You're in your terminal. You have a ticket to work on. So you:

1. Open the browser
2. Find the ticket
3. Read the description
4. Copy the acceptance criteria
5. Switch back to your editor
6. Create a branch
7. Start coding
8. Go back to check that one comment you forgot
9. ...

**What if you could just type one command?**

```
/ticket-pilot:resolve ENG-123
```

ticket-pilot reads the ticket, understands the requirements, writes the code, runs the tests, and opens the PR. All from your terminal.

---

## Features

### `/ticket-pilot:setup` — One-time project configuration

```
/ticket-pilot:setup                    # interactive setup wizard
/ticket-pilot:setup --tracker linear   # quick setup
```

Configures which tracker this project uses. Saves to `.claude/ticket-pilot.json` so every command knows exactly where to look — no guessing, no prompts. Run once per project.

### `/ticket-pilot:resolve` — Ticket to PR in one command

```
/ticket-pilot:resolve ENG-123              # guided: review each step
/ticket-pilot:resolve ENG-123 --auto       # autonomous: sit back and watch
```

Reads the ticket, analyzes the codebase, creates a branch, implements the solution, runs tests, commits, and opens a PR. In **guided** mode, you approve each step. In **auto** mode, it handles everything (with a hard gate: tests must pass before committing).

### `/ticket-pilot:triage` — Prioritize smarter

```
/ticket-pilot:triage ENG-123                          # single ticket
/ticket-pilot:triage ENG-123 ENG-124 ENG-125          # batch analysis
/ticket-pilot:triage --sprint                          # entire sprint
```

Analyzes tickets against the actual codebase to estimate complexity (S/M/L/XL), suggest priority, identify risks and dependencies, and recommend the optimal order to tackle them.

### `/ticket-pilot:explore` — Understand before you build

```
/ticket-pilot:explore                 # browse recent tickets, pick one
/ticket-pilot:explore ENG-123         # deep dive into a specific ticket
/ticket-pilot:explore #42
```

Without arguments, lists recent open tickets and lets you pick one interactively. With a ticket ID, fetches the ticket, searches the codebase for related files, and presents a structured summary with impacted files, technical context, and open questions. Zero modifications.

### `/ticket-pilot:create` — Write tickets from code context

```
/ticket-pilot:create --tracker linear
/ticket-pilot:create --tracker github Fix the login timeout bug
```

Analyzes the codebase to generate structured tickets with title, description, acceptance criteria, and suggested labels. Previews before creating.

### Interactive Picker — Browse and select tickets visually

```bash
./scripts/pick.sh                          # my tickets → pick action
./scripts/pick.sh resolve                  # my tickets → resolve selected
./scripts/pick.sh explore --all            # all open tickets
./scripts/pick.sh triage --sprint          # current sprint tickets
./scripts/pick.sh --tracker jira resolve   # force a specific tracker
```

Navigate with arrow keys, type to filter, press Enter to select. Requires [`gum`](https://github.com/charmbracelet/gum) (`brew install gum`).

---

## How It Works

```
                         You type: /ticket-pilot:resolve ENG-123
                                          |
                                          v
                              +---------------------+
                              |   Detect Tracker    |
                              | (config > MCP > ID) |
                              +---------------------+
                                          |
                         +----------------+----------------+
                         |                |                |
                    Linear MCP       gh CLI        Atlassian MCP
                         |                |                |
                         v                v                v
                              +---------------------+
                              |    Fetch Ticket     |
                              +---------------------+
                                          |
                                          v
                              +---------------------+
                              |  Analyze Codebase   |
                              +---------------------+
                                          |
                                          v
                              +---------------------+
                              | Implement & Test    |
                              +---------------------+
                                          |
                                          v
                              +---------------------+
                              |   Commit & PR       |
                              +---------------------+
```

**Zero dependencies.** The plugin is pure Markdown — no build step, no npm install, no runtime. It orchestrates tools that are already on your machine.

---

## Quick Start

### 1. Clone

```bash
git clone https://github.com/nmarijane/ticket-pilot.git
```

### 2. Connect a tracker

| Tracker | One-liner |
|---------|-----------|
| **Linear** | `claude mcp add --transport http linear https://mcp.linear.app/mcp` |
| **GitHub** | `brew install gh && gh auth login` |
| **Jira** | Configure the [Atlassian MCP server](https://www.npmjs.com/package/@anthropic/mcp-atlassian) |

### 3. Launch

```bash
claude --plugin-dir ./ticket-pilot
```

### 4. Go

```
/ticket-pilot:explore ENG-123
```

---

## Configuration

Optionally create `.claude/ticket-pilot.json` in your project root to skip tracker detection:

```json
{
  "tracker": "linear",
  "teamPrefixes": ["ENG", "DES"],
  "defaultPrefix": "ENG",
  "defaultMode": "guided"
}
```

| Field | Description | Default |
|-------|-------------|---------|
| `tracker` | `linear`, `github`, or `jira` | Auto-detected |
| `teamPrefixes` | Team prefixes for this project | — |
| `defaultPrefix` | Default team when creating tickets | — |
| `defaultMode` | `guided` or `auto` for `/resolve` | `guided` |

All fields are optional. Without this file, ticket-pilot auto-detects the tracker from your MCP servers and ticket ID format.

---

## Supported Trackers

|  | Linear | GitHub Issues | Jira |
|--|--------|--------------|------|
| Read tickets | Yes | Yes | Yes |
| Create tickets | Yes | Yes | Yes |
| Update status | Yes | Via PR | Yes |
| Add comments | Yes | Yes | Yes |
| Sprint/cycle view | Yes | Milestones | Yes |
| Branch name from ticket | Yes | — | — |

---

## Architecture

ticket-pilot is a **pure-skills plugin** — every file is Markdown.

```
ticket-pilot/
  .claude-plugin/plugin.json       # Plugin manifest
  skills/
    setup/SKILL.md                 # Project configuration wizard
    resolve/SKILL.md               # Ticket -> PR workflow
    triage/SKILL.md                # Priority & complexity analysis
    explore/SKILL.md               # Read-only ticket summary + browse
    create/SKILL.md                # Structured ticket creation
  agents/
    resolver.md                    # Subagent: implementation
    triager.md                     # Subagent: batch analysis
  scripts/
    detect-tracker.sh              # ID format detection
```

No TypeScript. No build step. No `node_modules`. Just Markdown files that tell Claude what to do.

**Want to add a feature?** Edit a `.md` file and submit a PR.

---

## Contributing

This is an open-source project and contributions are very welcome!

1. **Fork** the repository
2. **Create** a feature branch
3. **Edit** the relevant `SKILL.md` or agent file
4. **Test** with `claude --plugin-dir ./ticket-pilot`
5. **Submit** a pull request

### Ideas for contributions

- Add support for more trackers (Asana, Shortcut, YouTrack, ...)
- Improve triage heuristics
- Add a `/ticket-pilot:status` command for checking ticket state
- Better sprint detection across trackers
- Localization of ticket templates

---

## License

[MIT](LICENSE) — do whatever you want with it.
