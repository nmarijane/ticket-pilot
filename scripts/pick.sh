#!/bin/bash
set -euo pipefail

# ticket-pilot pick.sh — Interactive ticket picker
# Runs in your terminal (not through Claude Code) to select a ticket
# with arrow-key navigation, then launches Claude Code with the chosen action.
#
# Usage:
#   ./pick.sh                          # my tickets → pick action
#   ./pick.sh resolve                  # my tickets → resolve selected
#   ./pick.sh explore --all            # all tickets → explore selected
#   ./pick.sh triage --sprint          # sprint tickets → triage selected
#   ./pick.sh --tracker github         # force GitHub tracker
#   ./pick.sh --tracker jira resolve   # force Jira + resolve action

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Dependency checks ---
check_deps() {
  if ! command -v gum &>/dev/null; then
    echo -e "${RED}Error:${NC} gum is required but not installed."
    echo -e "Install it with: ${CYAN}brew install gum${NC}"
    exit 1
  fi
  if ! command -v claude &>/dev/null; then
    echo -e "${RED}Error:${NC} claude CLI is required but not installed."
    echo -e "Install it with: ${CYAN}npm install -g @anthropic-ai/claude-code${NC}"
    exit 1
  fi
}

# --- Argument parsing ---
# First non-flag argument is the action. Flags can appear anywhere.
parse_args() {
  ACTION=""
  TRACKER=""
  SCOPE="mine"  # mine | all | sprint

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tracker)
        TRACKER="$2"
        shift 2
        ;;
      --all)
        SCOPE="all"
        shift
        ;;
      --sprint)
        SCOPE="sprint"
        shift
        ;;
      resolve|explore|triage|moderate)
        ACTION="$1"
        shift
        ;;
      *)
        echo -e "${RED}Error:${NC} Unknown argument: $1"
        echo "Usage: ./pick.sh [resolve|explore|triage|moderate] [--tracker github|linear|jira] [--all|--sprint]"
        exit 1
        ;;
    esac
  done

  # Validate --all and --sprint are not both set
  if [[ "$SCOPE" == "all" ]] && [[ "${*:-}" == *"--sprint"* ]]; then
    echo -e "${RED}Error:${NC} --all and --sprint are mutually exclusive."
    exit 1
  fi
}

# --- Tracker detection ---
detect_tracker() {
  # 1. Flag takes priority
  if [[ -n "$TRACKER" ]]; then
    echo "$TRACKER"
    return
  fi

  # 2. Config file (search from cwd up to git root)
  local config
  config=$(find_config)
  if [[ -n "$config" ]]; then
    local tracker
    tracker=$(jq -r '.tracker // empty' "$config" 2>/dev/null || true)
    if [[ -n "$tracker" ]]; then
      echo "$tracker"
      return
    fi
  fi

  # 3. Interactive picker
  echo -e "${BOLD}Which tracker do you use?${NC}" >&2
  local choice
  choice=$(gum choose "github" "linear" "jira" || true)
  if [[ -z "$choice" ]]; then
    echo -e "${RED}Cancelled.${NC}" >&2
    exit 0
  fi
  echo "$choice"
}

find_config() {
  local dir
  dir=$(pwd)
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.claude/ticket-pilot.json" ]]; then
      echo "$dir/.claude/ticket-pilot.json"
      return
    fi
    dir=$(dirname "$dir")
  done
}

# --- GitHub Issues ---
fetch_github() {
  local scope="$1"
  local cmd="gh issue list --state open --json number,title,labels,state --limit 50"

  case "$scope" in
    mine)
      cmd="$cmd --assignee @me"
      ;;
    all)
      # no filter
      ;;
    sprint)
      local milestone
      milestone=$(gh api "repos/{owner}/{repo}/milestones" --jq \
        '[.[] | select(.state=="open")] | sort_by(.due_on) | last | .title' 2>/dev/null || true)
      if [[ -z "$milestone" ]]; then
        echo -e "${YELLOW}No open milestone found. Showing all tickets.${NC}" >&2
        scope="all"
      else
        cmd="$cmd --milestone \"$milestone\""
      fi
      ;;
  esac

  eval "$cmd" | jq -r '.[] | "#\(.number)\t\(.title)\t\(.state)"'
}

# --- Linear ---
fetch_linear() {
  local scope="$1"

  if [[ -z "${LINEAR_API_KEY:-}" ]]; then
    echo -e "${RED}Error:${NC} LINEAR_API_KEY environment variable is required for Linear." >&2
    echo -e "Create one at: ${CYAN}Linear Settings > Security & Access > Personal API keys${NC}" >&2
    exit 1
  fi

  local query
  case "$scope" in
    mine)
      query='{ "query": "{ viewer { assignedIssues(first: 50, filter: { state: { type: { nin: [\"completed\",\"canceled\"] } } }) { nodes { identifier title state { name } } } } }" }'
      ;;
    all)
      query='{ "query": "{ issues(first: 50, filter: { state: { type: { nin: [\"completed\",\"canceled\"] } } }) { nodes { identifier title state { name } } } }" }'
      ;;
    sprint)
      query='{ "query": "{ cycles(filter: { isActive: { eq: true } }, first: 1) { nodes { issues(first: 50) { nodes { identifier title state { name } } } } } }" }'
      ;;
  esac

  local response
  response=$(curl -sf -X POST "https://api.linear.app/graphql" \
    -H "Content-Type: application/json" \
    -H "Authorization: $LINEAR_API_KEY" \
    -d "$query" 2>/dev/null)

  if [[ -z "$response" ]] || echo "$response" | jq -e '.errors' &>/dev/null; then
    local err
    err=$(echo "$response" | jq -r '.errors[0].message // "Unknown API error"' 2>/dev/null || echo "Connection failed")
    echo -e "${RED}Linear API error:${NC} $err" >&2
    exit 1
  fi

  case "$scope" in
    mine)
      echo "$response" | jq -r '.data.viewer.assignedIssues.nodes[] | "\(.identifier)\t\(.title)\t\(.state.name)"'
      ;;
    all)
      echo "$response" | jq -r '.data.issues.nodes[] | "\(.identifier)\t\(.title)\t\(.state.name)"'
      ;;
    sprint)
      echo "$response" | jq -r '.data.cycles.nodes[0].issues.nodes[] | "\(.identifier)\t\(.title)\t\(.state.name)"'
      ;;
  esac
}

# --- Jira ---
fetch_jira() {
  local scope="$1"

  if [[ -z "${JIRA_BASE_URL:-}" ]] || [[ -z "${JIRA_EMAIL:-}" ]] || [[ -z "${JIRA_API_TOKEN:-}" ]]; then
    echo -e "${RED}Error:${NC} Jira requires these environment variables:" >&2
    echo "  JIRA_BASE_URL  (e.g., https://your-org.atlassian.net)" >&2
    echo "  JIRA_EMAIL     (your Atlassian email)" >&2
    echo "  JIRA_API_TOKEN (create at https://id.atlassian.com/manage-profile/security/api-tokens)" >&2
    exit 1
  fi

  local jql
  case "$scope" in
    mine)
      jql="assignee = currentUser() AND status != Done ORDER BY updated DESC"
      ;;
    all)
      jql="status != Done ORDER BY updated DESC"
      ;;
    sprint)
      jql="sprint in openSprints() AND status != Done ORDER BY priority ASC"
      ;;
  esac

  local auth
  auth=$(echo -n "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64)
  local encoded_jql
  encoded_jql=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$jql'))")

  local response
  response=$(curl -sf "${JIRA_BASE_URL}/rest/api/3/search?jql=${encoded_jql}&fields=key,summary,status&maxResults=50" \
    -H "Authorization: Basic $auth" \
    -H "Content-Type: application/json" 2>/dev/null)

  if [[ -z "$response" ]] || echo "$response" | jq -e '.errorMessages' &>/dev/null; then
    local err
    err=$(echo "$response" | jq -r '.errorMessages[0] // "Unknown API error"' 2>/dev/null || echo "Connection failed")
    echo -e "${RED}Jira API error:${NC} $err" >&2
    exit 1
  fi

  echo "$response" | jq -r '.issues[] | "\(.key)\t\(.fields.summary)\t\(.fields.status.name)"'
}

# --- Display formatting ---
format_tickets() {
  local term_width
  term_width=$(tput cols 2>/dev/null || echo 100)
  # Reserve: ID (12) + padding (4) + status (18) + brackets (2) = 36
  local title_width=$(( term_width - 36 ))
  [[ $title_width -lt 30 ]] && title_width=30
  [[ $title_width -gt 80 ]] && title_width=80

  while IFS=$'\t' read -r id title status; do
    # Truncate title
    if [[ ${#title} -gt $title_width ]]; then
      title="${title:0:$((title_width - 3))}..."
    fi
    printf "%-12s %-${title_width}s [%s]\n" "$id" "$title" "$status"
  done
}

# --- Action picker ---
pick_action() {
  local ticket_id="$1"
  echo -e "\n${BOLD}What do you want to do with ${CYAN}${ticket_id}${NC}${BOLD}?${NC}\n" >&2

  local choice
  choice=$(gum choose \
    "resolve  — Implement the solution and create a PR" \
    "explore  — Read-only analysis of the ticket" \
    "triage   — Analyze priority, complexity, and dependencies" \
    "moderate — Evaluate issue quality and recommend accept/request-info/close" || true)

  if [[ -z "$choice" ]]; then
    echo -e "${RED}Cancelled.${NC}" >&2
    exit 0
  fi

  echo "$choice" | awk '{print $1}'
}

# --- Main ---
main() {
  check_deps
  parse_args "$@"

  local tracker
  tracker=$(detect_tracker)

  # Fetch tickets
  echo -e "${BOLD}Fetching tickets from ${CYAN}${tracker}${NC}${BOLD}...${NC}" >&2

  local raw_tickets
  case "$tracker" in
    github)  raw_tickets=$(fetch_github "$SCOPE") ;;
    linear)  raw_tickets=$(fetch_linear "$SCOPE") ;;
    jira)    raw_tickets=$(fetch_jira "$SCOPE") ;;
    *)
      echo -e "${RED}Error:${NC} Unknown tracker: $tracker"
      exit 1
      ;;
  esac

  if [[ -z "$raw_tickets" ]]; then
    echo -e "${YELLOW}No tickets found.${NC}"
    exit 0
  fi

  # Format for display
  local formatted
  formatted=$(echo "$raw_tickets" | format_tickets)

  # Ticket picker
  local ticket_count
  ticket_count=$(echo "$formatted" | wc -l | tr -d ' ')
  echo -e "${GREEN}Found ${ticket_count} ticket(s).${NC}\n" >&2

  local selected
  selected=$(echo "$formatted" | gum filter --placeholder "Type to search..." --height 20 || true)

  if [[ -z "$selected" ]]; then
    echo -e "${RED}Cancelled.${NC}" >&2
    exit 0
  fi

  # Extract ticket ID (first field)
  local ticket_id
  ticket_id=$(echo "$selected" | awk '{print $1}')

  # Pick action if not provided
  local action="$ACTION"
  if [[ -z "$action" ]]; then
    action=$(pick_action "$ticket_id")
  fi

  # Launch Claude Code
  echo -e "\n${BOLD}Launching:${NC} ${CYAN}/ticket-pilot:${action} ${ticket_id}${NC}\n"
  claude --plugin-dir "$PLUGIN_DIR" "/ticket-pilot:${action} ${ticket_id}"
}

main "$@"
