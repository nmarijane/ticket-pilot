---
name: explore
description: Browse recent tickets or read a specific ticket and analyze the codebase. Without arguments, lists recent open tickets to pick from. With a ticket ID, provides a structured summary.
argument-hint: [TICKET-ID]
---

# Explore Ticket

You are analyzing a ticket to provide a structured summary. **Do not modify any code or ticket.**

## Input

Arguments: `$ARGUMENTS`

## Step 0: Browse Mode (no arguments)

If `$ARGUMENTS` is empty (the user just typed `/ticket-pilot:explore` with nothing after):

### Detect Tracker

Since there is no ticket ID to detect format from, determine the tracker by:
1. Check `.claude/ticket-pilot.json` for a `tracker` field
2. Check which MCP servers are available (Linear MCP, Atlassian MCP) or if `gh` CLI is authenticated
3. If multiple trackers are available, ask the user which one to browse

### List Recent Tickets

Fetch the most recent open tickets (up to 20):

- **GitHub:** Run `gh issue list --state open --json number,title,labels,assignees,state --limit 20`
- **Linear:** Use `list_my_issues` to get tickets assigned to the user. If no results, use `list_issues` for recent open tickets.
- **Jira:** Use `searchJiraIssuesUsingJql` with JQL: `status != Done ORDER BY updated DESC` (max 20 results)

### Present List

Display the tickets in a numbered list:

```
## Recent Open Tickets

| # | ID | Title | Status | Assignee |
|---|-----|-------|--------|----------|
| 1 | ENG-123 | Add rate limiting | In Progress | @user |
| 2 | ENG-124 | Fix login timeout | Todo | — |
| ... | ... | ... | ... | ... |

Which ticket do you want to explore? (enter a number or ticket ID)
```

Wait for the user to pick a ticket, then continue with Step 1 below using that ticket ID.

---

## Step 1: Detect Tracker

If a ticket ID was provided (via `$ARGUMENTS` or picked from browse mode):

Run the tracker detection script using the Bash tool:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-tracker.sh "<ticket-id>"
```
This outputs `github`, `ambiguous`, or `unknown`.

Use this detection result to determine which tracker to query:

- **If `github`:** Use the `gh` CLI to read the issue. Run: `gh issue view <number> --json title,body,comments,labels,assignees,state,milestone`
- **If `ambiguous`:** Check if `.claude/ticket-pilot.json` exists in the project root. If it specifies a `tracker` field, use that. Otherwise, check which MCP servers are available. If only one tracker MCP is configured, use it. If still ambiguous, ask the user which tracker to use and offer to save the choice to `.claude/ticket-pilot.json`.
- **If `unknown`:** Ask the user to clarify the ticket identifier format.

### Prerequisites

Before querying, verify the tracker is accessible:
- **Linear:** Verify the Linear MCP server is available. If not, tell the user: "Add the Linear MCP server: `claude mcp add --transport http linear https://mcp.linear.app/mcp`"
- **GitHub:** Verify `gh` is installed and authenticated. Run `gh auth status`. If it fails, tell the user: "Install GitHub CLI: `brew install gh && gh auth login`"
- **Jira:** Verify the Atlassian MCP server is available. If not, tell the user: "Add the Atlassian MCP server and configure it for your instance"

## Step 2: Fetch Ticket

Read the full ticket details:

- **Linear:** Use `get_issue` with the ticket identifier. Then use `list_comments` to get comments.
- **GitHub:** Run `gh issue view <number> --json title,body,comments,labels,assignees,state,milestone`
- **Jira:** Use `getJiraIssue` with the ticket identifier.

## Step 3: Analyze Codebase

Based on the ticket content, search the codebase:
1. Identify keywords, file names, function names, or module names mentioned in the ticket
2. Use Grep and Glob to find related files
3. Read the most relevant files to understand the current state

## Step 4: Present Summary

Present a structured summary in this format:

### Ticket Summary
- **Title:** [ticket title]
- **Status:** [current status]
- **Assignee:** [if any]
- **Labels:** [if any]

### What the ticket asks for
[Clear description of the requirement or bug]

### Likely impacted files
- `path/to/file.ext` — [why this file is relevant]
- ...

### Relevant technical context
[Key information about the current implementation that relates to this ticket]

### Open questions
- [Any ambiguities or missing information in the ticket]
- [Questions that should be clarified before implementation]
