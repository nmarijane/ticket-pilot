---
name: explore
description: Read an issue tracker ticket and analyze the codebase to provide a structured summary. Use when you want to understand a ticket before working on it.
argument-hint: [TICKET-ID]
---

# Explore Ticket

You are analyzing a ticket to provide a structured summary. **Do not modify any code or ticket.**

## Input

Ticket identifier: `$ARGUMENTS`

## Step 1: Detect Tracker

<!-- Note: $ARGUMENTS is safe here because explore only takes a single ticket ID with no flags -->
Tracker format hint: !`${CLAUDE_PLUGIN_ROOT}/scripts/detect-tracker.sh $ARGUMENTS`

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
