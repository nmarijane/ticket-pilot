---
name: triage
description: Analyze issue tracker tickets and provide priority, complexity, and dependency recommendations. Use when you want to evaluate tickets before starting work.
argument-hint: [TICKET-ID] [--batch ID...] [--sprint]
---

# Triage Tickets

You are analyzing tickets to provide actionable recommendations on priority, complexity, and dependencies.

## Input

Arguments: `$ARGUMENTS`

Parse the arguments:
- **Single ticket:** just a ticket ID (e.g., `ENG-123`)
- **Batch mode:** multiple ticket IDs (e.g., `ENG-123 ENG-124 ENG-125`) or `--batch ENG-123 ENG-124`
- **Sprint mode:** `--sprint` flag — fetch all tickets in the current sprint/cycle

Determine the mode from the arguments.

## Tracker Detection

For each ticket ID, determine the tracker.
<!-- Note: $0 is used instead of $ARGUMENTS because $ARGUMENTS may contain flags like --batch or --sprint -->

First, run the tracker detection script using the Bash tool:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-tracker.sh "$0"
```
This outputs `github`, `ambiguous`, or `unknown`.

Follow the same detection logic as explore:
1. Check `.claude/ticket-pilot.json`
2. Check available MCP servers
3. Use identifier format
4. Ask user if ambiguous

Verify prerequisites (same as explore skill):
- **Linear:** Verify the Linear MCP server is available. If not, tell the user: "Add the Linear MCP server: `claude mcp add --transport http linear https://mcp.linear.app/mcp`"
- **GitHub:** Verify `gh` is installed and authenticated. Run `gh auth status`. If it fails, tell the user: "Install GitHub CLI: `brew install gh && gh auth login`"
- **Jira:** Verify the Atlassian MCP server is available. If not, tell the user: "Add the Atlassian MCP server and configure it for your instance"

## Single Ticket Mode

### Fetch
Read the ticket details:
- **Linear:** Use `get_issue` with the ticket identifier. Then use `list_comments` to get comments.
- **GitHub:** Run `gh issue view <number> --json title,body,comments,labels,assignees,state,milestone`
- **Jira:** Use `getJiraIssue` with the ticket identifier.

### Analyze

Evaluate the ticket across these dimensions:

**Complexity (T-shirt size):**
- **S** — isolated change, single file, clear requirements
- **M** — multiple files, some design decisions needed
- **L** — cross-cutting change, needs careful planning
- **XL** — architectural change, high risk, should be broken down

**Impacted components:**
Search the codebase to identify which modules, services, or layers are affected.

**Risks:**
- Breaking changes?
- Performance implications?
- Security considerations?
- Missing test coverage?

**Dependencies:**
- Does this block or depend on other work?
- Are there external dependencies (APIs, libraries)?

### Present Report

```
## Triage Report: [TICKET-ID]

**Title:** [title]
**Complexity:** [S/M/L/XL] — [brief justification]
**Suggested priority:** [urgent/high/medium/low] — [brief justification]

### Impacted components
- [component] — [how it's affected]

### Risks
- [risk description]

### Dependencies
- [dependency description]

### Suggested labels
- [label suggestions based on analysis]

### Questions to clarify
- [questions that should be answered before implementation]
```

### Optional: Update Ticket

Ask the user if they want to update the ticket with the triage results (add labels, set priority, add a comment with the analysis).

## Batch Mode

**Important:** For batch and sprint mode, use the Agent tool to dispatch the `triager` subagent. This provides isolation for the heavy analysis work while keeping single-ticket mode interactive in the main context.

For each ticket in the batch:
1. Fetch and analyze (same as single ticket)
2. After analyzing all tickets, produce a combined report:

```
## Batch Triage Report

### Priority Ranking
1. [TICKET-ID] — [title] — Priority: [X], Complexity: [Y]
2. ...

### Dependency Graph
- [TICKET-A] blocks [TICKET-B] (reason)
- ...

### Recommended Order
1. [TICKET-ID] — [reason to do first]
2. ...
```

## Sprint Mode

Fetch all tickets in the current sprint:
- **Linear:** use `list_issues` and filter by the active cycle. Use `list_teams` to identify the team if needed.
- **GitHub:** run `gh issue list --milestone <current-milestone> --state open --json number,title,labels,assignees`
- **Jira:** use `searchJiraIssuesUsingJql` with the JQL query `sprint in openSprints() AND status != Done`

Then process all fetched tickets using the Batch Mode flow above.
