---
name: create
description: Create a new issue tracker ticket with structured title, description, labels, and acceptance criteria. Use when you want to create a ticket from a conversation or code context.
argument-hint: [--tracker linear|github|jira] [description]
---

# Create Ticket

You are creating a well-structured ticket in an issue tracker.

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

Parse the arguments:
- If `--tracker` flag is present, it overrides the config for this invocation.
- Any remaining text is the initial description of the issue.

## Step 1: Gather Information

If the user provided a description in the arguments, use it as a starting point. Otherwise, ask the user to describe the problem or feature they want to track.

Ask follow-up questions if needed to clarify:
- Is this a bug, feature, or task?
- What is the expected behavior vs actual behavior (for bugs)?
- What are the acceptance criteria?

## Step 2: Analyze Codebase

Search the codebase for context related to the described issue:
- Identify relevant files, modules, or components
- Find related code patterns or existing implementations
- Note any technical constraints or dependencies

## Step 3: Generate Ticket

Compose a structured ticket with:

**All trackers:**
- **Title:** concise, actionable (imperative form, e.g., "Add rate limiting to API endpoints")
- **Description:** structured with context, expected behavior, and technical notes from codebase analysis
- **Acceptance criteria:** specific, testable bullet points

**Tracker-specific fields:**

### Linear
- **Team:** use `defaultPrefix` from `.claude/ticket-pilot.json`, or ask the user. Use `list_teams` to show available teams if needed.
- **Labels:** suggest from `list_issue_labels`. Let the user confirm.
- **Priority:** suggest based on analysis (1=urgent, 2=high, 3=medium, 4=low)

### GitHub
- **Repository:** use current git repository
- **Labels:** suggest from `gh label list`. Let the user confirm.

### Jira
- **Project:** use config or ask. Use `getVisibleJiraProjects` to show options if needed.
- **Issue type:** use `getJiraIssueTypeMetaWithFields` to get available types. Default to "Task" for features, "Bug" for bugs.

## Step 4: Preview and Confirm

Present the full ticket to the user in a readable format. Ask for confirmation before creating.

If the user wants changes, adjust and preview again.

## Step 5: Create Ticket

Once confirmed:
- **Linear:** use `create_issue` with title, description, teamId, priority, labelIds
- **GitHub:** run `gh issue create --title "..." --body "..." --label "..."`
- **Jira:** use `createJiraIssue` with project, issuetype, summary, description

After creation, display the ticket URL/identifier to the user.
