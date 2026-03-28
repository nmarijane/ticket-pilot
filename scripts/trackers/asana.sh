#!/bin/bash
# ticket-pilot — Asana tracker provider
#
# Implements the standard tracker API used by ticket-pilot skills:
#   get_ticket <task_gid>
#   list_tickets [mine|all|sprint] [limit]
#   update_ticket_status <task_gid> <status>
#
# Required environment variables:
#   ASANA_TOKEN          — Personal Access Token (https://app.asana.com/0/my-apps)
#   ASANA_WORKSPACE_ID   — Workspace GID (https://app.asana.com/api/1.0/workspaces)
#
# Optional:
#   ASANA_PROJECT_ID     — Narrow list_tickets to a specific project GID
#
# Dependencies: curl, jq (no other non-standard tools)
#
# Exit codes:
#   0  success
#   1  configuration or API error

set -euo pipefail

ASANA_API="https://app.asana.com/api/1.0"

# ---------------------------------------------------------------------------
# _asana_check_env — verify required env vars are set
# ---------------------------------------------------------------------------
_asana_check_env() {
  local missing=()
  [[ -z "${ASANA_TOKEN:-}" ]]        && missing+=("ASANA_TOKEN")
  [[ -z "${ASANA_WORKSPACE_ID:-}" ]] && missing+=("ASANA_WORKSPACE_ID")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: missing Asana environment variable(s): ${missing[*]}" >&2
    echo "Set them and retry." >&2
    echo "" >&2
    echo "  ASANA_TOKEN          — Personal Access Token" >&2
    echo "                         Create at: https://app.asana.com/0/my-apps" >&2
    echo "  ASANA_WORKSPACE_ID   — Workspace GID" >&2
    echo "                         List at: https://app.asana.com/api/1.0/workspaces" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# _asana_request <path> [extra curl args...]
# Makes an authenticated GET request to the Asana REST API.
# Prints the raw JSON response on stdout.
# ---------------------------------------------------------------------------
_asana_request() {
  local path="$1"
  shift
  local response
  response=$(curl -sf "${ASANA_API}${path}" \
    -H "Authorization: Bearer ${ASANA_TOKEN}" \
    -H "Accept: application/json" \
    "$@" 2>/dev/null) || {
    echo "Error: Asana API request failed for path: ${path}" >&2
    exit 1
  }

  # Surface API-level errors
  local api_error
  api_error=$(echo "$response" | jq -r '.errors[0].message // empty' 2>/dev/null || true)
  if [[ -n "$api_error" ]]; then
    echo "Error: Asana API error: $api_error" >&2
    exit 1
  fi

  echo "$response"
}

# ---------------------------------------------------------------------------
# get_ticket <task_gid>
#
# Fetches a single Asana task and prints a structured summary to stdout.
# Output format (tab-separated fields, one per line):
#   id      <gid>
#   title   <name>
#   status  <open|completed>
#   url     <permalink_url>
#   assignee <name or unassigned>
#   due     <due_on or none>
#   desc    <notes (first 500 chars)>
# ---------------------------------------------------------------------------
get_ticket() {
  local task_gid="$1"
  if [[ -z "$task_gid" ]]; then
    echo "Usage: get_ticket <task_gid>" >&2
    exit 1
  fi

  _asana_check_env

  local fields="gid,name,completed,notes,permalink_url,assignee,due_on,custom_fields,memberships"
  local response
  response=$(_asana_request "/tasks/${task_gid}?opt_fields=${fields}")

  local data
  data=$(echo "$response" | jq '.data')

  local status
  status=$(echo "$data" | jq -r 'if .completed then "completed" else "open" end')
  local assignee
  assignee=$(echo "$data" | jq -r '.assignee.name // "unassigned"')
  local due
  due=$(echo "$data" | jq -r '.due_on // "none"')
  local notes
  notes=$(echo "$data" | jq -r '.notes // ""' | head -c 500)

  echo "id	$(echo "$data" | jq -r '.gid')"
  echo "title	$(echo "$data" | jq -r '.name')"
  echo "status	${status}"
  echo "url	$(echo "$data" | jq -r '.permalink_url // "https://app.asana.com"')"
  echo "assignee	${assignee}"
  echo "due	${due}"
  echo "desc	${notes}"
}

# ---------------------------------------------------------------------------
# list_tickets [scope] [limit]
#
# scope: mine (default) | all | sprint
#   mine   — tasks assigned to the authenticated user
#   all    — all incomplete tasks in the workspace (or project if ASANA_PROJECT_ID set)
#   sprint — same as all, sorted by due date ascending (Asana has no native sprint concept)
#
# limit: max tasks to return (default 50)
#
# Output: tab-separated rows of: <gid> <name> <status>
# ---------------------------------------------------------------------------
list_tickets() {
  local scope="${1:-mine}"
  local limit="${2:-50}"

  _asana_check_env

  local fields="gid,name,completed,permalink_url,assignee"
  local params="opt_fields=${fields}&limit=${limit}"

  if [[ -n "${ASANA_PROJECT_ID:-}" ]]; then
    # Scope to a project
    local endpoint="/projects/${ASANA_PROJECT_ID}/tasks?${params}&completed_since=now"
    if [[ "$scope" == "sprint" ]]; then
      endpoint="${endpoint}&sort_by=due_date&sort_ascending=true"
    fi
    local response
    response=$(_asana_request "$endpoint")
    echo "$response" | jq -r \
      '.data[] | select(.completed == false) | "\(.gid)\t\(.name)\topen"'
    return
  fi

  case "$scope" in
    mine)
      # Get the current user's GID
      local me_resp me_id
      me_resp=$(_asana_request "/users/me?opt_fields=gid")
      me_id=$(echo "$me_resp" | jq -r '.data.gid')

      local response
      response=$(_asana_request \
        "/workspaces/${ASANA_WORKSPACE_ID}/tasks?${params}&completed_since=now&assignee=${me_id}")
      echo "$response" | jq -r \
        '.data[] | select(.completed == false) | "\(.gid)\t\(.name)\topen"'
      ;;

    all)
      local response
      response=$(_asana_request \
        "/workspaces/${ASANA_WORKSPACE_ID}/tasks?${params}&completed_since=now")
      echo "$response" | jq -r \
        '.data[] | select(.completed == false) | "\(.gid)\t\(.name)\topen"'
      ;;

    sprint)
      # Asana has no native sprints — return incomplete tasks sorted by due date
      local response
      response=$(_asana_request \
        "/workspaces/${ASANA_WORKSPACE_ID}/tasks?${params}&completed_since=now&sort_by=due_date&sort_ascending=true")
      echo "$response" | jq -r \
        '.data[] | select(.completed == false) | "\(.gid)\t\(.name)\topen"'
      ;;

    *)
      echo "Error: unknown scope '$scope'. Use: mine | all | sprint" >&2
      exit 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# update_ticket_status <task_gid> <status>
#
# status values:
#   open        — mark task as incomplete
#   completed   — mark task as complete
#   in_progress — add a comment (Asana uses sections/custom fields for in-progress)
#
# Prints a confirmation message to stdout on success.
# ---------------------------------------------------------------------------
update_ticket_status() {
  local task_gid="$1"
  local status="$2"

  if [[ -z "$task_gid" ]] || [[ -z "$status" ]]; then
    echo "Usage: update_ticket_status <task_gid> <status>" >&2
    echo "  status: open | completed | in_progress" >&2
    exit 1
  fi

  _asana_check_env

  case "$status" in
    open)
      curl -sf -X PUT "${ASANA_API}/tasks/${task_gid}" \
        -H "Authorization: Bearer ${ASANA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"data":{"completed":false}}' >/dev/null 2>&1 || {
        echo "Error: failed to update task ${task_gid}" >&2
        exit 1
      }
      echo "Task ${task_gid} marked as open."
      ;;

    completed)
      curl -sf -X PUT "${ASANA_API}/tasks/${task_gid}" \
        -H "Authorization: Bearer ${ASANA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"data":{"completed":true}}' >/dev/null 2>&1 || {
        echo "Error: failed to update task ${task_gid}" >&2
        exit 1
      }
      echo "Task ${task_gid} marked as completed."
      ;;

    in_progress)
      # Asana has no universal "in progress" state — we add a comment instead.
      # For teams using custom fields or sections, extend this function accordingly.
      local comment_payload
      comment_payload=$(printf '{"data":{"text":"Status updated to: in progress"}}')
      curl -sf -X POST "${ASANA_API}/tasks/${task_gid}/stories" \
        -H "Authorization: Bearer ${ASANA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$comment_payload" >/dev/null 2>&1 || {
        echo "Error: failed to add in_progress comment to task ${task_gid}" >&2
        exit 1
      }
      echo "Task ${task_gid} commented as in_progress (Asana has no native in-progress state; use sections or custom fields for workflow states)."
      ;;

    *)
      echo "Error: unknown status '$status'. Use: open | completed | in_progress" >&2
      exit 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# CLI entrypoint — allows using this script directly:
#   ./asana.sh get_ticket <gid>
#   ./asana.sh list_tickets [mine|all|sprint] [limit]
#   ./asana.sh update_ticket_status <gid> <status>
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -eq 0 ]]; then
    echo "Usage: asana.sh <command> [args]"
    echo ""
    echo "Commands:"
    echo "  get_ticket <task_gid>"
    echo "  list_tickets [mine|all|sprint] [limit]"
    echo "  update_ticket_status <task_gid> <status>"
    exit 0
  fi
  "$@"
fi
