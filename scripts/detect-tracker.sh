#!/bin/bash
# Detect issue tracker type from ticket identifier format.
# Input: ticket identifier string (e.g., "ENG-123", "#456", "owner/repo#789")
# Output (stdout): github | ambiguous | unknown
# Exit codes: 0 = detection succeeded, 1 = error
#
# Note: "ambiguous" means the format matches both Linear and Jira (PREFIX-NUMBER).
# The calling skill should check .claude/ticket-pilot.json or ask the user to resolve.

ID="$1"

if [[ -z "$ID" ]]; then
  echo "unknown"
  exit 1
fi

# GitHub: #123 or owner/repo#123
if [[ "$ID" =~ ^#[0-9]+$ ]] || [[ "$ID" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+#[0-9]+$ ]]; then
  echo "github"
# Linear or Jira: PREFIX-NUMBER (2-5 uppercase letters, dash, digits)
elif [[ "$ID" =~ ^[A-Z]{2,5}-[0-9]+$ ]]; then
  echo "ambiguous"
else
  echo "unknown"
fi
