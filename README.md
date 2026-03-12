# ticket-pilot

Issue tracker integration for Claude Code — resolve, triage, explore, and create tickets from your terminal.

## Features

| Command | Description |
|---------|-------------|
| `/ticket-pilot:resolve` | Read a ticket, implement the solution, and create a PR |
| `/ticket-pilot:triage` | Analyze tickets for priority, complexity, and dependencies |
| `/ticket-pilot:explore` | Read-only summary of a ticket with codebase context |
| `/ticket-pilot:create` | Create a well-structured ticket from a conversation |

Supports **Linear**, **GitHub Issues**, and **Jira** through existing MCP servers and the `gh` CLI.

## Installation

**Manual (development):**

```bash
git clone https://github.com/nmeridjen/ticket-pilot.git
claude --plugin-dir ./ticket-pilot
```

## Prerequisites

Set up at least one tracker before using the plugin:

| Tracker | Setup |
|---------|-------|
| **Linear** | `claude mcp add --transport http linear https://mcp.linear.app/mcp` |
| **GitHub** | `brew install gh && gh auth login` |
| **Jira** | Configure the Atlassian MCP server for your instance |

## Usage

### Explore a ticket

```
/ticket-pilot:explore ENG-123
/ticket-pilot:explore #42
```

### Resolve a ticket

```
/ticket-pilot:resolve ENG-123              # guided mode (default)
/ticket-pilot:resolve ENG-123 --auto       # fully autonomous
```

### Triage tickets

```
/ticket-pilot:triage ENG-123                          # single ticket
/ticket-pilot:triage ENG-123 ENG-124 ENG-125          # batch
/ticket-pilot:triage --sprint                          # current sprint
```

### Create a ticket

```
/ticket-pilot:create --tracker linear
/ticket-pilot:create --tracker github Fix the login timeout bug
```

## Configuration

Create `.claude/ticket-pilot.json` in your project root (optional):

```json
{
  "tracker": "linear",
  "teamPrefixes": ["ENG", "DES"],
  "defaultPrefix": "ENG",
  "defaultMode": "guided"
}
```

| Field | Description |
|-------|-------------|
| `tracker` | Default tracker: `linear`, `github`, or `jira` |
| `teamPrefixes` | Team prefixes used in this project (for Linear/Jira) |
| `defaultPrefix` | Default team prefix when creating tickets |
| `defaultMode` | Default mode for `/resolve`: `guided` or `auto` |

All fields are optional.

## Supported Trackers

| Feature | Linear | GitHub | Jira |
|---------|--------|--------|------|
| Read tickets | Yes | Yes | Yes |
| Create tickets | Yes | Yes | Yes |
| Update status | Yes | Via PR | Yes |
| Add comments | Yes | Yes | Yes |
| Sprint/cycle view | Yes | Milestones | Yes |

## Contributing

Contributions are welcome! This is a pure Markdown plugin — no build step required.

1. Fork the repository
2. Create a feature branch
3. Edit the relevant `SKILL.md` or agent file
4. Test with `claude --plugin-dir ./ticket-pilot`
5. Submit a pull request

## License

MIT
