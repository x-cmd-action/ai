#!/usr/bin/env bash
# x-cmd-action/ai/triage — AI issue triage
#
# NO set -e / set -u / pipefail: x-cmd source-loads `x` as a shell
# function that may `exit 1` internally — strict modes get the script
# killed by sourced functions instead of surfacing errors. Explicit
# checks and ${VAR:-defaults} are used instead.

# Resolve action dir robustly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${ACTION_PATH:=$SCRIPT_DIR}"

# The x-cmd-action/x-cmd step only installs x-cmd onto disk; each `run`
# step is a fresh shell, so the `x` function must be sourced here.
if [ ! -f "$HOME/.x-cmd.root/X" ]; then
  echo "triage: ERROR — x-cmd not installed at $HOME/.x-cmd.root/X" >&2
  exit 1
fi
. "$HOME/.x-cmd.root/X" || { echo "triage: ERROR — failed to source x-cmd" >&2; exit 1; }
command -v x >/dev/null 2>&1 || { echo "triage: ERROR — 'x' unavailable" >&2; exit 1; }

: "${INPUT_APPLY_LABELS:=true}"
: "${ISSUE_NUM:?ISSUE_NUM required}"

echo "triage: issue #$ISSUE_NUM"

# ── Fetch issue title/body when not provided by the event payload ──
# (workflow_dispatch has no github.event.issue — fetch it ourselves).
if [ -z "${ISSUE_TITLE:-}" ] || [ -z "${ISSUE_BODY:-}" ]; then
  ISSUE_JSON=$(gh api "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUM" \
    --jq '{title: .title, body: .body}' 2>/dev/null || echo '{}')
  [ -z "${ISSUE_TITLE:-}" ] && ISSUE_TITLE=$(printf '%s' "$ISSUE_JSON" | jq -r '.title // ""' 2>/dev/null || echo "")
  [ -z "${ISSUE_BODY:-}" ]  && ISSUE_BODY=$(printf '%s' "$ISSUE_JSON"  | jq -r '.body // ""'  2>/dev/null || echo "")
fi

# ── Fetch comments ──
COMMENTS=$(gh api "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUM/comments?per_page=10" \
  --jq '[.[] | {user: .user.login, body: .body}]' 2>/dev/null || echo '[]')

# ── Compose the source material and delegate to `x ai triage` ──
# (priority/area/labels/blocking prompt is built into x ai triage)
SOURCE="Issue #$ISSUE_NUM: ${ISSUE_TITLE:-}

${ISSUE_BODY:-}

Comments:
$COMMENTS"

echo "triage: calling x ai triage..."
RC=0
RESPONSE=$(printf '%s' "$SOURCE" | x ai triage --json) || RC=$?
if [ "$RC" != "0" ] || [ -z "$RESPONSE" ]; then
  echo "triage: AI call failed (rc=$RC) — see stderr output above"
  exit 1
fi

PRIORITY=$(printf '%s' "$RESPONSE" | jq -r '.priority // "unknown"' 2>/dev/null || echo "unknown")
AREA=$(printf '%s' "$RESPONSE" | jq -r '.area // "unknown"' 2>/dev/null || echo "unknown")
LABELS=$(printf '%s' "$RESPONSE" | jq -r '.labels // ""' 2>/dev/null || echo "")
TLDR=$(printf '%s' "$RESPONSE" | jq -r '.tldr // ""' 2>/dev/null || echo "")

COMMENT_BODY="🤖 **ai triage**

**Priority:** $PRIORITY · **Area:** $AREA

**TL;DR:** ${TLDR:-n/a}

**Suggested labels:** ${LABELS:-none}

<sub>Triaged by [x-cmd-action/ai](https://github.com/x-cmd-action/ai)</sub>"

if gh issue comment "$ISSUE_NUM" --body "$COMMENT_BODY"; then
  echo "triage: posted comment"
else
  echo "triage: WARNING — gh issue comment failed (GH_TOKEN permissions?) — writing to job summary" >&2
  printf '%s\n' "$COMMENT_BODY" >> "${GITHUB_STEP_SUMMARY:-/dev/null}" 2>/dev/null || true
fi

if [ "$INPUT_APPLY_LABELS" = "true" ] && [ -n "$LABELS" ]; then
  LABEL_ARGS=""
  IFS=',' read -ra PARTS <<< "$LABELS"
  for l in "${PARTS[@]}"; do
    l_trim=$(printf '%s' "$l" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$l_trim" ] && continue
    # Create the label if the repo doesn't have it yet, then apply it.
    gh label create "$l_trim" --force >/dev/null 2>&1 || \
      echo "triage: WARNING — could not create label '$l_trim'"
    LABEL_ARGS="$LABEL_ARGS --add-label $l_trim"
  done
  # shellcheck disable=SC2086
  gh issue edit "$ISSUE_NUM" $LABEL_ARGS || \
    echo "triage: WARNING — gh issue edit failed (permissions?)"
fi

echo "triage: done"
