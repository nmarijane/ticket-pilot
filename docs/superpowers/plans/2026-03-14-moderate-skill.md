# `/ticket-pilot:moderate` Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an issue moderation skill that evaluates incoming issues on quality, relevance, feasibility, and value, then recommends or executes actions (accept, request info, close).

**Architecture:** New skill `moderate` with a companion `moderator` agent for batch processing. The skill runs inline for single issues and dispatches parallel moderator agents for batch. The moderator agent delegates technical analysis to the existing `triager` agent.

**Tech Stack:** Pure Markdown (SKILL.md, agent .md), `gh` CLI for GitHub, MCP for Linear/Jira. No build step.

**Spec:** `docs/superpowers/specs/2026-03-14-moderate-skill-design.md`

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `agents/moderator.md` | Batch agent — analyzes one issue, delegates to triager, produces verdict |
| Create | `skills/moderate/SKILL.md` | Main skill — argument parsing, pre-flight, single/batch orchestration, report formatting, action execution |
| Modify | `.claude-plugin/plugin.json` | Register moderator agent |
| Modify | `scripts/pick.sh` | Add `moderate` to action parser and picker |
| Modify | `README.md` | Document new skill |

---

## Chunk 1: Core Files

### Task 1: Create the moderator agent

**Files:**
- Create: `agents/moderator.md`

**Convention reference:** Follow the pattern of `agents/triager.md` (frontmatter with name, description, tools) and `agents/resolver.md`.

- [ ] **Step 1: Create `agents/moderator.md`**

```markdown
---
name: moderator
description: Analyzes a single issue for quality, relevance, feasibility, and value. Produces a moderation verdict with recommended action. Used for batch moderation.
tools: Read, Grep, Glob, Bash(gh *), Agent
---

# Moderator Agent

You are a specialized moderation agent. Your job is to evaluate a single issue and produce a structured moderation verdict.

## Core Principles

- Be fair and constructive — contributors are volunteers
- Base assessments on evidence (codebase state, existing issues), not assumptions
- When in doubt, recommend asking for info rather than closing
- Always thank the contributor in draft comments

## Evaluation Axes

Score each axis as **good**, **fair**, or **insufficient**:

### 1. Writing Quality
- Descriptive title (not just "bug" or "help")
- Sufficient description to understand the problem/request
- Bugs: repro steps, expected vs observed behavior, version/environment
- Features: use case, motivation
- **No body at all** → automatic "insufficient"

### 2. Relevance
- Issue concerns this project (not a third-party dependency)
- Not a duplicate — search open and recently closed issues for similar content
- Not already resolved — check recent branches, commits, changelog

### 3. Feasibility
- Delegate to the **triager** agent via the Agent tool for codebase analysis and complexity estimate (S/M/L/XL)
- Additionally check **architectural coherence**: does the request make sense given the project's current structure? (e.g., requesting PostgreSQL support when there is no database layer)

### 4. Value
- Benefits the project and its users?
- Aligned with project direction? Check README, CONTRIBUTING.md, roadmap if available
- Effort/impact ratio

## Verdict Logic

Apply in this order:
1. Insufficient quality → **Request info**
2. Duplicate detected → **Close (duplicate)** with link to original
3. Low relevance (out of scope, already resolved) → **Close** with reason
4. All axes good → **Accept** with suggested labels
5. XL feasibility or questionable value → **Accept but flag** for maintainer discussion

A verdict is **ambiguous** when any axis scores "fair". Flag this in your output.

## Engagement Check

Before recommending closure, check engagement:
- **GitHub**: count reactions (via `gh api`) and comments
- **Linear**: comment count, subscriber count
- **Jira**: votes, watchers, comment count

If 5+ reactions/votes/subscribers OR 3+ comments → mark as **high engagement**. High-engagement issues must never be auto-closed.

## Draft Comments

When drafting comments (for request-info or close verdicts):
- Professional and kind tone
- Always thank the contributor
- Clearly explain the reason
- For duplicates, include a link to the original issue
- Language: use the language specified in the task prompt (default: English)

## Output Format

Return a structured verdict:

```
## Moderation Verdict: [ISSUE-ID]

**Title:** [title]
**Quality:** [good/fair/insufficient] — [brief justification]
**Relevance:** [good/fair/insufficient] — [brief justification]
**Feasibility:** [S/M/L/XL] — [brief justification]
**Value:** [good/fair/insufficient] — [brief justification]
**Engagement:** [low/high] — [X reactions, Y comments]
**Ambiguous:** [yes/no]

**Verdict:** [ACCEPT / REQUEST INFO / CLOSE / CLOSE (DUPLICATE) / ACCEPT BUT FLAG]
**Reason:** [one-line explanation]

**Suggested labels:** [if accepting]
**Draft comment:** [if requesting info or closing]
**Duplicate of:** [ISSUE-ID if duplicate]
```
```

- [ ] **Step 2: Verify file exists and frontmatter is valid**

Run: `head -5 agents/moderator.md`
Expected: YAML frontmatter with `name: moderator`, `tools: Read, Grep, Glob, Bash(gh *), Agent`

- [ ] **Step 3: Commit**

```bash
git add agents/moderator.md
git commit -m "feat: add moderator agent for issue moderation"
```

---

### Task 2: Create the moderate skill

**Files:**
- Create: `skills/moderate/SKILL.md`

**Convention reference:** Follow the exact pattern of `skills/triage/SKILL.md` — frontmatter, pre-flight config check, argument parsing, tracker detection, single mode, batch mode.

- [ ] **Step 1: Create `skills/moderate/SKILL.md`**

```markdown
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
```

- [ ] **Step 2: Verify the skill file exists and frontmatter is valid**

Run: `head -5 skills/moderate/SKILL.md`
Expected: YAML frontmatter with `name: moderate`

- [ ] **Step 3: Commit**

```bash
git add skills/moderate/SKILL.md
git commit -m "feat: add /ticket-pilot:moderate skill for issue moderation"
```

---

### Task 3: Register agent in plugin.json

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Add moderator agent to the agents array**

In `.claude-plugin/plugin.json`, find:

```json
  "agents": ["./agents/resolver.md", "./agents/triager.md"]
```

Replace with:

```json
  "agents": ["./agents/resolver.md", "./agents/triager.md", "./agents/moderator.md"]
```

- [ ] **Step 2: Update the plugin description**

In `.claude-plugin/plugin.json`, find:

```json
  "description": "Issue tracker integration for Claude Code — resolve, triage, explore, and create tickets from your terminal",
```

Replace with:

```json
  "description": "Issue tracker integration for Claude Code — resolve, triage, explore, create, and moderate tickets from your terminal",
```

- [ ] **Step 3: Verify**

Run: `cat .claude-plugin/plugin.json`
Expected: `agents` array contains 3 entries including `./agents/moderator.md`, description includes "moderate"

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat: register moderator agent in plugin manifest"
```

---

## Chunk 2: Integration Files

### Task 4: Update pick.sh

**Files:**
- Modify: `scripts/pick.sh`

Two changes needed: the argument parser and the action picker.

- [ ] **Step 1: Update the `parse_args` case pattern**

In `scripts/pick.sh`, change line 62 from:

```bash
      resolve|explore|triage)
```

to:

```bash
      resolve|explore|triage|moderate)
```

- [ ] **Step 2: Update the usage message**

In `scripts/pick.sh`, change line 68 from:

```bash
        echo "Usage: ./pick.sh [resolve|explore|triage] [--tracker github|linear|jira] [--all|--sprint]"
```

to:

```bash
        echo "Usage: ./pick.sh [resolve|explore|triage|moderate] [--tracker github|linear|jira] [--all|--sprint]"
```

- [ ] **Step 3: Update the `pick_action` function**

In `scripts/pick.sh`, change the `gum choose` block (lines 270-273) from:

```bash
  choice=$(gum choose \
    "resolve  — Implement the solution and create a PR" \
    "explore  — Read-only analysis of the ticket" \
    "triage   — Analyze priority, complexity, and dependencies" || true)
```

to:

```bash
  choice=$(gum choose \
    "resolve  — Implement the solution and create a PR" \
    "explore  — Read-only analysis of the ticket" \
    "triage   — Analyze priority, complexity, and dependencies" \
    "moderate — Evaluate issue quality and recommend accept/request-info/close" || true)
```

- [ ] **Step 4: Verify**

Run: `grep -n "moderate" scripts/pick.sh`
Expected: 3 matches — in parse_args case, usage string, and gum choose

- [ ] **Step 5: Commit**

```bash
git add scripts/pick.sh
git commit -m "feat: add moderate action to interactive picker"
```

---

### Task 5: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add moderate skill documentation**

In `README.md`, find the line:

```
Analyzes the codebase to generate structured tickets with title, description, acceptance criteria, and suggested labels. Previews before creating.
```

After that paragraph (and its blank line), insert before the `### Interactive Picker` heading:

```markdown
### `/ticket-pilot:moderate` — Evaluate and moderate incoming issues

```
/ticket-pilot:moderate #42                 # analyze a single issue
/ticket-pilot:moderate --batch             # analyze all untriaged issues
/ticket-pilot:moderate --batch --yolo      # analyze and act on all untriaged issues
```

Evaluates issues on quality, relevance, feasibility, and value. Recommends accepting, requesting more info, or closing — with drafted comments ready to post. In `--yolo` mode, executes actions directly (with safeguards: ambiguous verdicts and popular issues always require confirmation).
```

- [ ] **Step 2: Update the architecture tree**

In `README.md`, find the architecture tree section. Change from:

```
  skills/
    setup/SKILL.md                 # Project configuration wizard
    resolve/SKILL.md               # Ticket -> PR workflow
    triage/SKILL.md                # Priority & complexity analysis
    explore/SKILL.md               # Read-only ticket summary + browse
    create/SKILL.md                # Structured ticket creation
  agents/
    resolver.md                    # Subagent: implementation
    triager.md                     # Subagent: batch analysis
```

to:

```
  skills/
    setup/SKILL.md                 # Project configuration wizard
    resolve/SKILL.md               # Ticket -> PR workflow
    triage/SKILL.md                # Priority & complexity analysis
    explore/SKILL.md               # Read-only ticket summary + browse
    create/SKILL.md                # Structured ticket creation
    moderate/SKILL.md              # Issue moderation & evaluation
  agents/
    resolver.md                    # Subagent: implementation
    triager.md                     # Subagent: batch analysis
    moderator.md                   # Subagent: issue moderation
```

- [ ] **Step 3: Update the Supported Trackers table**

In `README.md`, find the Supported Trackers table. After the row `| Branch name from ticket | Yes | — | — |`, add:

```markdown
| Moderate issues | Yes | Yes | Yes |
```

- [ ] **Step 4: Update the Configuration table**

In `README.md`, find the Configuration table. After the row `| `defaultMode` | `guided` or `auto` for `/resolve` | `guided` |`, add:

```markdown
| `triagedLabels` | Labels that mark an issue as triaged (GitHub) | `["bug","enhancement",...]` |
| `triagedStatuses` | Statuses that mark an issue as triaged (Linear/Jira) | `["In Progress",...]` |
| `language` | Language for generated comments | `en` |
```

- [ ] **Step 5: Verify**

Run: `grep -c "moderate" README.md`
Expected: at least 5 matches

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: document /ticket-pilot:moderate in README"
```

---

## Manual Verification

After all tasks are complete, verify the plugin works end-to-end:

- [ ] **Load the plugin:** `claude --plugin-dir ./ticket-pilot`
- [ ] **Check skill appears:** type `/ticket-pilot:` and verify `moderate` shows in autocomplete
- [ ] **Test single issue mode:** `/ticket-pilot:moderate #<real-issue-number>`
- [ ] **Test batch mode:** `/ticket-pilot:moderate --batch`
- [ ] **Test pick.sh:** `./scripts/pick.sh moderate`
