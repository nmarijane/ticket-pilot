# Design: `/ticket-pilot:moderate` — Issue Moderation Skill

## Summary

A new skill for open source maintainers to analyze, evaluate, and act on incoming issues. It judges issues on quality, relevance, feasibility, and value, then recommends actions (accept, request info, close). Operates in guided mode by default, with a `--yolo` mode for direct execution.

## Motivation

Open source maintainers receive issues of varying quality and relevance. Currently there's no structured way to triage incoming issues from a maintainer's perspective — evaluating not just technical complexity (which `triage` handles) but also issue quality, relevance to the project, and whether the issue should even be worked on.

## Interface

```
/ticket-pilot:moderate [ISSUE-ID] [--batch] [--yolo]
```

- `ISSUE-ID` — analyze a single issue
- `--batch` — analyze all open untriaged issues (no action labels)
- `--yolo` — execute actions directly without confirmation

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

### 2. Relevance
- Issue concerns this project (not a third-party dependency)
- Not a duplicate (similarity search across open + recently closed issues)
- Not already resolved (check recent branches, commits, changelog)

### 3. Feasibility
- Delegated to triager agent: codebase analysis for realism
- Coherence with existing architecture (e.g., requesting PostgreSQL on a project with no DB layer)
- Complexity estimate (S/M/L/XL)

### 4. Value
- Benefits the project and its users?
- Aligned with project direction? (uses README/CONTRIBUTING.md/roadmap if available)
- Effort/impact ratio

### Verdict Logic

- Insufficient quality → request info
- Low relevance → close with reason
- All good → accept + suggested labels
- XL feasibility or questionable value → accept but flag for discussion

## Actions

| Verdict | Normal mode | `--yolo` mode |
|---|---|---|
| Accept | Suggest labels | Add labels, comment "Triaged ✓" |
| Request info | Display draft comment | Post comment, add `needs-info` label |
| Close | Display reason and draft | Post comment, close issue |

### Labels
- Uses existing repo labels only — never creates new labels
- If no suitable label exists, mentions it in the report and suggests creating one

### Comments
- Professional and kind tone (open source contributors are volunteers)
- Always thank the contributor
- Clearly explain the reason when closing
- English by default (project language), unless project is explicitly in another language

### Safeguards in `--yolo` mode
- Ambiguous scores (e.g., borderline relevance) → ask for confirmation even in `--yolo`
- Issues with high engagement (many 👍, many comments) → never auto-closed, always escalated to maintainer

## Batch Mode

### Issue Selection
- `--batch`: all open issues without action labels (no `bug`, `enhancement`, `needs-info`, etc.)
- Detects "untriaged" issues by absence of labels — no special `untriaged` label required

### Execution
- Each issue dispatched to a moderator agent in parallel
- Moderator agent delegates to triager agent for technical analysis
- Max 10 issues in parallel, remainder queued

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
- `agents/moderator.md` — batch agent (one per issue), access: Read, Grep, Glob, Bash + triager delegation

### Modified
- `scripts/pick.sh` — add `moderate` as available action
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
