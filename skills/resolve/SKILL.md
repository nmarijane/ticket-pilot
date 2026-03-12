---
name: resolve
description: Resolve an issue tracker ticket by reading it, implementing the solution, and creating a PR. Use when you want to go from ticket to working code.
argument-hint: [TICKET-ID] [--auto|--guided]
context: fork
agent: resolver
---

# Resolve Ticket

You are resolving an issue tracker ticket end-to-end: reading it, implementing the solution, testing, committing, and optionally creating a PR.

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

If the file **exists**, read it and use the `tracker` field for all tracker decisions below (skip detection script, skip ambiguity prompts).

---

Parse the arguments:
- **Ticket ID:** the first argument that is not a flag (e.g., `ENG-123`, `#456`)
- **Mode flag:** `--auto` for fully autonomous, `--guided` for step-by-step with user approval.
- **Default mode:** If no flag is provided, check the config for a `defaultMode` field (`"auto"` or `"guided"`). If not configured, default to `guided`.

## Step 1: Fetch Ticket

Use the tracker from `.claude/ticket-pilot.json`.

Follow the same detection logic as other skills:
1. Check `.claude/ticket-pilot.json`
2. Check available MCP servers
3. Use identifier format
4. Ask user if ambiguous

Verify prerequisites:
- **Linear:** Verify Linear MCP server is available. If not: "Add the Linear MCP server: `claude mcp add --transport http linear https://mcp.linear.app/mcp`"
- **GitHub:** Run `gh auth status`. If it fails: "Install GitHub CLI: `brew install gh && gh auth login`"
- **Jira:** Verify Atlassian MCP server is available. If not: "Add the Atlassian MCP server and configure it for your instance"

Fetch the full ticket:
- **Linear:** use `get_issue` with the identifier, then `list_comments` for comments
- **GitHub:** run `gh issue view <number> --json title,body,comments,labels,assignees,state,milestone`
- **Jira:** use `getJiraIssue` with the identifier

## Step 2: Present Summary

Present a structured summary of the ticket:

```
## Ticket: [TICKET-ID] — [Title]

**Status:** [status]
**Assignee:** [assignee or "unassigned"]
**Labels:** [labels]

### Description
[ticket description]

### Comments
[relevant comments, summarized if lengthy]

### Acceptance Criteria
[extracted from description, or "none specified"]
```

**If guided mode:** Ask the user to confirm they want to proceed before continuing.

## Step 3: Analyze Codebase and Plan

1. Search the codebase for files related to the ticket
2. Read relevant files to understand the current implementation
3. Propose an action plan:

```
## Action Plan

### Changes needed:
1. [file path] — [what to change and why]
2. ...

### Tests to add/modify:
1. [test file path] — [what to test]

### Estimated complexity: [S/M/L/XL]
```

**If guided mode:** Ask the user to approve the plan before continuing. If they suggest changes, adjust the plan.

## Step 4: Create Branch

Follow the branch naming rules from your agent instructions:
- Detect default branch
- Create `feat/<TICKET-ID>-<title-slug>`
- Handle existing branches and dirty working trees

## Step 5: Implement

Make the changes according to the plan:
- Follow existing code patterns and conventions
- Write clean, focused code
- Add or update tests

## Step 6: Run Tests

Run the project's test suite:
- Detect the test runner (look for `package.json` scripts, `pytest.ini`, `Makefile`, etc.)
- Run tests
- **GATE: Tests MUST pass.** If tests fail:
  - In **guided mode:** report failures, ask user for guidance
  - In **auto mode:** attempt to fix. If still failing after one retry, stop and report failures. Do NOT commit or create a PR with failing tests.

## Step 7: Commit

Create a commit with a conventional commit message referencing the ticket:
```
<type>(<TICKET-ID>): <concise description>

<optional body with more details>
```

## Step 8: Offer PR and Status Update

**If guided mode:** Ask the user if they want to:
1. Create a pull request
2. Update the ticket status (e.g., move to "In Review")
3. Both
4. Neither (just keep the local commit)

**If auto mode:** Create the PR and update the ticket status automatically.

### Creating a PR

```bash
gh pr create --title "<type>(<TICKET-ID>): <title>" --body "## Summary\n\nResolves <TICKET-ID>: <title>\n\n## Changes\n\n<list of changes>\n\n## Test plan\n\n<how this was tested>"
```

### Updating Ticket Status

- **Linear:** use `update_issue` to change the state. Use `list_issue_statuses` to find the "In Review" or equivalent state ID.
- **GitHub:** handled by PR (linked via "Resolves #N" in PR body)
- **Jira:** use `transitionJiraIssue`. Use `getTransitionsForJiraIssue` to find the appropriate transition.

Optionally add a comment to the ticket linking to the PR:
- **Linear:** use `create_comment`
- **Jira:** use `addCommentToJiraIssue`
