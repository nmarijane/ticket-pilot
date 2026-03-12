---
name: explore
description: Browse recent tickets or read a specific ticket and analyze the codebase. Without arguments, lists recent open tickets to pick from. With a ticket ID, provides a structured summary.
argument-hint: [TICKET-ID]
---

# Explore Ticket

You are analyzing a ticket to provide a structured summary. **Do not modify any code or ticket.**

## Input

Arguments: `$ARGUMENTS`

## Pre-flight: Check Configuration

**Before anything else**, check if `.claude/ticket-pilot.json` exists in the project root.

If the file **does not exist**, tell the user:

> It looks like ticket-pilot hasn't been configured for this project yet. Let me set it up quickly — which issue tracker do you use?
> 1. **GitHub Issues**
> 2. **Linear**
> 3. **Jira**

Once the user answers, create `.claude/ticket-pilot.json` with at minimum `{ "tracker": "<choice>" }`. Then continue with the command they originally ran.

If the file **exists**, read it and use the `tracker` field for all tracker decisions below.

---

## Step 0: Browse Mode (no arguments)

If `$ARGUMENTS` is empty (the user just typed `/ticket-pilot:explore` with nothing after):

### List Recent Tickets

Use the tracker from `.claude/ticket-pilot.json` to fetch recent tickets.

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

## Step 1: Fetch Ticket

Use the tracker from `.claude/ticket-pilot.json` (already verified in pre-flight).

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
