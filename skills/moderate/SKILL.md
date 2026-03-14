---
name: moderate
description: Analyze and moderate incoming issues — evaluate quality, relevance, feasibility, and recommend actions
argument-hint: "[ISSUE-ID] [--batch] [--yolo]"
---

# Moderate Issues

You are evaluating incoming issues to help maintainers decide: accept, ask for more info, or close.

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
- **Single issue:** just an issue ID (e.g., `ENG-123`, `#42`)
- **Batch mode:** `--batch` flag — fetch all untriaged issues
- **Yolo mode:** `--yolo` flag — execute actions without confirmation

Flags can combine: `--batch --yolo` processes all untriaged issues and executes actions directly.

## Tracker Detection

Use the tracker from `.claude/ticket-pilot.json`.

Follow the same detection logic as other skills:
1. Check `.claude/ticket-pilot.json`
2. Check available MCP servers
3. Use identifier format
4. Ask user if ambiguous

Verify prerequisites:
- **Linear:** Verify the Linear MCP server is available. If not, tell the user: "Add the Linear MCP server: `claude mcp add --transport http linear https://mcp.linear.app/mcp`"
- **GitHub:** Verify `gh` is installed and authenticated. Run `gh auth status`. If it fails, tell the user: "Install GitHub CLI: `brew install gh && gh auth login`"
- **Jira:** Verify the Atlassian MCP server is available. If not, tell the user: "Add the Atlassian MCP server and configure it for your instance"

## Comment Language

Determine the language for draft comments:
1. Check for a `language` field in `ticket-pilot.json` → use it
2. Otherwise, check the README language
3. If undetectable, default to English

## Single Issue Mode

### Fetch

Read the issue details:
- **GitHub:** Run `gh issue view <number> --json number,title,body,comments,labels,assignees,state,reactionGroups`
- **Linear:** Use `get_issue` with the identifier. Then use `list_comments` to get comments.
- **Jira:** Use `getJiraIssue` with the identifier.

### Check Idempotency

Search the issue's comments for a previous moderation signature (a comment containing `<!-- ticket-pilot:moderated -->`). If found, tell the user:

> This issue was already moderated. Run again to re-evaluate? (y/n)

In `--batch` mode, silently skip already-moderated issues.

### Analyze

#### 1. Writing Quality

Evaluate the issue content:
- Is the title descriptive? (not just "bug", "help", "error", "issue")
- Does the body exist? **No body at all → automatic "insufficient"**
- For bugs: are repro steps, expected/observed behavior, and version present?
- For features: is there a use case and motivation?

Score: **good** / **fair** / **insufficient**

#### 2. Relevance

Search for duplicates:
- **GitHub:** `gh issue list --search "<title keywords>" --state all --json number,title,state --limit 10`
- **Linear:** Search via MCP with title keywords
- **Jira:** `searchJiraIssuesUsingJql` with text search

Also check:
- Is the issue about this project or a third-party dependency?
- Has this been fixed in recent commits? (search git log for related keywords)

Score: **good** / **fair** / **insufficient**
If duplicate found, note the original issue ID.

#### 3. Feasibility

Use the **Agent tool** to dispatch the `triager` agent with the issue details. The triager will:
- Search the codebase for impacted files
- Estimate complexity (S/M/L/XL)

On top of the triager's output, check **architectural coherence**: does the request make sense given the project structure? (e.g., requesting a database feature when there's no DB layer)

Size: **S** / **M** / **L** / **XL** (from triager). XL triggers "accept but flag".

#### 4. Value

Assess:
- Does this benefit the project and its users?
- Is it aligned with the project direction? (check README, CONTRIBUTING.md, roadmap)
- What's the effort/impact ratio?

Score: **good** / **fair** / **insufficient**

### Engagement Check

Before deciding on closure:
- **GitHub:** Use `gh api repos/{owner}/{repo}/issues/{number}/reactions` to count reactions. Count comments from the fetched issue data.
- **Linear:** Count comments and subscribers from MCP data.
- **Jira:** Check votes and watchers from issue data. Count comments.

**High engagement** = 5+ reactions/votes/subscribers OR 3+ comments.

### Verdict

Apply in this order:
1. Insufficient quality → **Request info**
2. Duplicate detected → **Close (duplicate)** with link to original
3. Low relevance → **Close** with reason
4. All axes good → **Accept** with suggested labels
5. XL feasibility or questionable value → **Accept but flag** for discussion

A verdict is **ambiguous** if any axis scored "fair".

### Draft Comment

If the verdict requires a comment (request info, close, or close-duplicate), draft it:
- Thank the contributor
- Explain the reason clearly
- For duplicates, link to the original issue
- Use the determined comment language
- End the comment with the hidden signature: `<!-- ticket-pilot:moderated -->`

If accepting in `--yolo` mode, draft a brief summary comment:
> "Reviewed — complexity [X], labeled as [labels]. Ready to work on. <!-- ticket-pilot:moderated -->"

### Present Report

```
## Moderation: [ISSUE-ID] — "[title]"

| Axis | Score | Detail |
|------|-------|--------|
| Quality | [good/fair/insufficient] | [justification] |
| Relevance | [good/fair/insufficient] | [justification] |
| Feasibility | [S/M/L/XL] | [justification] |
| Value | [good/fair/insufficient] | [justification] |

**Engagement:** [low/high] ([X] reactions, [Y] comments)
**Verdict:** [ACCEPT / REQUEST INFO / CLOSE / CLOSE (DUPLICATE)]
**Reason:** [explanation]
```

If accepting: show suggested labels.
If requesting info or closing: show the draft comment.
If duplicate: show link to original.

### Execute (or recommend)

**Normal mode (no `--yolo`):**
- Present the report and ask the user: `[Apply] [Modify] [Skip]`
- If **Apply**, execute the action (see action table below)
- If **Modify**, let the user edit the verdict/comment, then apply
- If **Skip**, do nothing

**`--yolo` mode:**
- If verdict is **ambiguous** → still ask for confirmation
- If issue has **high engagement** and verdict is close → still ask for confirmation
- Otherwise, execute immediately

### Action Table

| Verdict | Action |
|---------|--------|
| Accept | Add suggested labels. Post summary comment. |
| Request info | Post draft comment. Add `needs-info` label (if it exists). |
| Close | Post draft comment. Close the issue. |
| Close (duplicate) | Post draft comment with link to original. Close the issue. |

**Executing actions per tracker:**

**GitHub:**
- Labels: `gh issue edit <number> --add-label "<label>"`
- Comment: `gh issue comment <number> --body "<comment>"`
- Close: `gh issue close <number>`

**Linear:**
- Labels: update via MCP
- Comment: add comment via MCP
- Close: transition to "Cancelled" or "Won't Do" via MCP

**Jira:**
- Labels: `editJiraIssue` to add labels
- Comment: `addCommentToJiraIssue`
- Close: `transitionJiraIssue` to appropriate closed status

**Labels:** Only use labels that already exist in the repo. Never create new labels. If no suitable label exists, mention it in the report and suggest creating one.

## Batch Mode

### Fetch Untriaged Issues

Determine which issues are untriaged:

**GitHub:** Fetch open issues and filter:
- Default: issues with no labels at all, or only informational labels
- Action labels to exclude (issue is already triaged): `bug`, `enhancement`, `feature`, `needs-info`, `wontfix`, `duplicate`, `good first issue`, `help wanted`
- Custom: if `triagedLabels` array exists in `ticket-pilot.json`, use those instead

```bash
gh issue list --state open --json number,title,labels,comments,reactionGroups --limit 50
```

Then filter in analysis: keep issues where none of their labels match the triaged labels list.

**Linear:** Fetch issues in initial statuses:
- Default statuses: "Triage", "Backlog"
- Custom: if `triagedStatuses` array exists in `ticket-pilot.json`, use those instead
- Use MCP to list issues filtered by status

**Jira:** Fetch issues in initial statuses:
- Default: `searchJiraIssuesUsingJql` with `status in ("To Do", "Backlog", "Open") ORDER BY created DESC`
- Custom: if `triagedStatuses` array exists in `ticket-pilot.json`, use those instead

### Filter: Skip Already Moderated

For each fetched issue, check comments for the `<!-- ticket-pilot:moderated -->` signature. Skip issues that have it.

### Zero Issues

If no untriaged issues remain after filtering:
> No untriaged issues found.

Exit.

### Dispatch

For each untriaged issue, use the **Agent tool** to dispatch a `moderator` agent with:
- The issue details (title, body, comments, labels, reactions)
- The tracker type
- The comment language
- The project context (README summary, CONTRIBUTING.md if present)

Dispatch issues in parallel where the Agent tool supports it.

### Batch Report

Collect all verdicts and present:

```
## Moderation — [N] issues analyzed

| # | Title | Quality | Relevance | Verdict |
|---|-------|---------|-----------|---------|
| 42 | Add PostgreSQL support | fair | insufficient | Close |
| 43 | Crash on startup v2.1 | good | good | Accept |
| 44 | plz help | insufficient | ? | Request info |

Summary: [X] to accept, [Y] to close, [Z] need info

[View details: All] [View details: Closures only] [Apply all]
```

**Normal mode:** User chooses what to apply. Can view details of any issue before deciding.

**`--yolo` mode:** Execute all non-ambiguous, non-high-engagement verdicts. Present ambiguous/high-engagement ones for confirmation.
