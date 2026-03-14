# Design: `/ticket-pilot:moderate` — Issue Moderation Skill

## Summary

A new skill for open source maintainers to analyze, evaluate, and act on incoming issues. It judges issues on quality, relevance, feasibility, and value, then recommends actions (accept, request info, close). Operates in guided mode by default, with a `--yolo` mode for direct execution.

## Motivation

Open source maintainers receive issues of varying quality and relevance. Currently there's no structured way to triage incoming issues from a maintainer's perspective — evaluating not just technical complexity (which `triage` handles) but also issue quality, relevance to the project, and whether the issue should even be worked on.

## SKILL.md Frontmatter

```yaml
name: moderate
description: Analyze and moderate incoming issues — evaluate quality, relevance, feasibility, and recommend actions
argument-hint: "[ISSUE-ID] [--batch] [--yolo]"
```

No `context: fork` (moderate does not modify code). No `agent` field — single-issue mode runs inline, batch mode dispatches moderator agents explicitly via the Agent tool.

## Interface

```
/ticket-pilot:moderate [ISSUE-ID] [--batch] [--yolo]
```

- `ISSUE-ID` — analyze a single issue
- `--batch` — analyze all open untriaged issues
- `--yolo` — execute actions directly without confirmation

`$ARGUMENTS` is parsed for the issue ID and flags.

Prerequisites: same as other skills (`.claude/ticket-pilot.json` with tracker configured, auto-setup if absent).

## Architecture

Two-phase process per issue:

### Phase 1: Analysis

1. Fetch issue content (title, body, comments, existing labels)
2. Search for duplicates among open and recently closed issues
3. Delegate to triager agent for technical analysis (impacted files, complexity, feasibility)
4. Evaluate writing quality (repro steps, clarity, missing info)
5. Cross-reference with codebase context (does the request make sense architecturally?)

### Phase 2: Decision

Produce a verdict per issue:
- **Accept** — valid issue, ready to work on (+ suggested labels)
- **Request info** — draft comment asking for clarifications
- **Close** — with reason (duplicate, out of scope, not reproducible, already resolved)

## Evaluation Criteria

Each issue is scored on 4 axes (good / fair / insufficient):

### 1. Writing Quality
- Descriptive title (not just "bug" or "help")
- Sufficient description to understand the problem/request
- Bugs: repro steps, expected vs observed behavior, version/environment
- Features: use case, motivation
- **No body at all** → automatic "insufficient" score, verdict: request info

### 2. Relevance
- Issue concerns this project (not a third-party dependency)
- Not a duplicate (similarity search across open + recently closed issues)
- Not already resolved (check recent branches, commits, changelog)

### 3. Feasibility
- Delegated to triager agent: codebase analysis for realism + complexity estimate (S/M/L/XL)
- The moderator agent additionally checks **architectural coherence** on top of the triager's output (e.g., requesting PostgreSQL on a project with no DB layer) — this is not part of the triager's scope

### 4. Value
- Benefits the project and its users?
- Aligned with project direction? (uses README/CONTRIBUTING.md/roadmap if available)
- Effort/impact ratio

### Verdict Logic

- Insufficient quality → request info
- **Duplicate detected** → close with link to original issue
- Low relevance → close with reason
- All good → accept + suggested labels
- XL feasibility or questionable value → accept but flag for discussion

### Ambiguity Definition

A verdict is **ambiguous** when any axis scores "fair" (not clearly good or insufficient). In `--yolo` mode, ambiguous verdicts require maintainer confirmation instead of auto-executing.

## Actions

| Verdict | Normal mode | `--yolo` mode |
|---|---|---|
| Accept | Suggest labels | Add labels, comment "Triaged ✓" |
| Request info | Display draft comment | Post comment, add `needs-info` label |
| Close | Display reason and draft | Post comment, close issue |
| Close (duplicate) | Display reason, link to original | Post comment with link to original, close issue |

### Labels
- Uses existing repo labels only — never creates new labels
- If no suitable label exists, mentions it in the report and suggests creating one

### Comments
- Professional and kind tone (open source contributors are volunteers)
- Always thank the contributor
- Clearly explain the reason when closing
- English by default. Language detection: check for a `language` field in `ticket-pilot.json`, then fall back to README language. If undetectable, use English

### Safeguards in `--yolo` mode
- Ambiguous verdicts (any axis scored "fair") → ask for confirmation even in `--yolo`
- **High engagement threshold**: issues with 5+ reactions or 3+ comments → never auto-closed, always escalated to maintainer

## Batch Mode

### Issue Selection
- `--batch`: all open issues considered "untriaged"
- **Untriaged detection** varies by tracker:
  - **GitHub**: issues with no labels at all, or only informational labels (not action labels like `bug`, `enhancement`, `needs-info`, `wontfix`, `duplicate`)
  - **Linear/Jira**: issues in initial status only ("Triage", "Backlog", "To Do") — status-based, not label-based
- The set of "triaged labels" (GitHub) and "triaged statuses" (Linear/Jira) can be customized via an optional `moderateConfig.triagedLabels` / `moderateConfig.triagedStatuses` array in `ticket-pilot.json`
- **Zero issues found**: display "No untriaged issues found" and exit

### Execution
- Each issue dispatched to a moderator agent via the Agent tool
- Moderator agent delegates to triager agent for technical analysis
- Issues are dispatched in parallel where the Agent tool supports it; no explicit concurrency cap (platform-managed)

### Batch Report

```
## Moderation — 12 issues analyzed

| #  | Title                        | Quality | Relevance | Verdict     |
|----|------------------------------|---------|-----------|-------------|
| 42 | Add PostgreSQL support       | ⚠️      | ❌        | Close       |
| 43 | Crash on startup with v2.1   | ✅      | ✅        | Accept      |
| 44 | plz help                     | ❌      | ?         | Request info|
| 45 | Refactor auth module         | ✅      | ✅        | Accept      |

Summary: 5 to accept, 3 to close, 4 need info

View details? [All] [Closures only] [Apply all]
```

In `--yolo` batch mode, safeguards still apply (ambiguous/popular issues escalated).

## Tracker Integration

### GitHub Issues
- Read: `gh issue list` / `gh issue view`
- Duplicate search: `gh issue list --search`
- Comments: `gh issue comment`
- Close: `gh issue close`
- Labels: `gh issue edit --add-label`
- Popularity: count 👍 reactions and comments

### Linear
- Read: MCP Linear
- Duplicate search: MCP text search
- Comments and status changes: MCP
- Close: transition to "Cancelled" or "Won't Do" status
- Labels: use existing Linear labels or workflow status

### Jira
- Read: `getJiraIssue`, `searchJiraIssuesUsingJql`
- Duplicate search: JQL
- Comments: `addCommentToJiraIssue`
- Close: `transitionJiraIssue` to "Won't Do" / "Closed"
- Labels: `editJiraIssue`

## Files to Create/Modify

### New
- `skills/moderate/SKILL.md` — main skill with instructions, modes, criteria
- `agents/moderator.md` — batch agent (one per issue), `tools: Read, Grep, Glob, Bash, Agent` (uses Agent tool to delegate to triager)

### Modified
- `.claude-plugin/plugin.json` — add `./agents/moderator.md` to the agents array
- `scripts/pick.sh` — add `moderate` as available action (`"moderate — Evaluate issue quality and recommend accept/request-info/close"`)
- `README.md` — document new skill in features table

### Unchanged
- `skills/triage/SKILL.md`, `skills/resolve/SKILL.md`, `skills/explore/SKILL.md`, `skills/create/SKILL.md`, `skills/setup/SKILL.md` — no changes
- `agents/triager.md` — reused as-is via dispatch
- `scripts/detect-tracker.sh` — no changes needed

## Relationship with Existing Skills

- **triage**: `moderate` delegates technical analysis to the triager agent but adds maintainer-specific concerns (quality, relevance, value, actions)
- **resolve**: a moderated+accepted issue can then be resolved with `/ticket-pilot:resolve`
- **explore**: `moderate` does deeper analysis than explore (which is read-only discovery)
- **create**: orthogonal — create makes tickets, moderate evaluates incoming ones
- **setup**: `moderate` uses the same `ticket-pilot.json` config and follows the same auto-setup pattern
