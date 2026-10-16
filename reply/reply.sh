#!/usr/bin/env bash
# x-cmd-action/ai/reply — react + reply on keyword match
#
# IMPORTANT: NO `set -e` / `set -u` / `set -o pipefail` anywhere in this
# script. Reasoning:
#
#   * x-cmd source-loads `x` as a SHELL FUNCTION; on error paths those
#     functions run `exit 1` instead of `return 1`. `set -e` does NOT
#     rescue the parent shell from an internal `exit` — it kills the
#     script the moment any sourced-in x-cmd function bails.
#
#   * `set -u` trips on every probed unset var — X's own opening lines
#     do `$var` checks; alias and function bodies inside x-cmd do too.
#
#   * `set -o pipefail` makes `cmd | grep` exit 1 when grep finds no
#     match, which is a normal case (it means "no match", not failure).
#
# We instead rely on:
#   * explicit `if [ -n "$var" ]; then x || true; fi` blocks
#   * explicit `${VAR:-default}` for any possibly-unset variable
#   * explicit `: "${INPUT:?required}"` parameter-required patterns
#
# This trades a small amount of early-failure speed for not being
# killed by a sourced function that exits.

# Resolve action dir robustly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${ACTION_PATH:=$SCRIPT_DIR}"

# The x-cmd-action/x-cmd step only installs x-cmd onto disk. Each `run`
# step is a fresh non-interactive shell, so the `x` function must be
# sourced in here. Everything below depends on it — fail fast if absent.
if [ ! -f "$HOME/.x-cmd.root/X" ]; then
  echo "reply: ERROR — x-cmd not installed at $HOME/.x-cmd.root/X" >&2
  echo "reply: the x-cmd-action/x-cmd step must run before this action" >&2
  exit 1
fi
if ! . "$HOME/.x-cmd.root/X"; then
  echo "reply: ERROR — failed to source $HOME/.x-cmd.root/X" >&2
  exit 1
fi
if ! command -v x >/dev/null 2>&1; then
  echo "reply: ERROR — 'x' command unavailable after sourcing x-cmd" >&2
  exit 1
fi

: "${INPUT_KEYWORD:=@x}"
: "${INPUT_REACTION:=eyes}"
: "${INPUT_COMMENT:=👀 on it}"
: "${ISSUE_NUM:=}"   # only required when the keyword actually triggers
: "${INPUT_USE_AI:=false}"
: "${GH_TOKEN:?GH_TOKEN required}"

# ── Strict keyword match (word boundary) ──
KEYWORD_RE_ESCAPED=$(printf '%s' "$INPUT_KEYWORD" | sed 's/[][\.*^$()+?{|/]/\\&/g')
PATTERN="(^|[^a-zA-Z0-9_-])${KEYWORD_RE_ESCAPED}([^a-zA-Z0-9_-]|$)"

SHOULD_TRIGGER=false

case "${GITHUB_EVENT_NAME:-}" in
  issue_comment)
    if printf '%s' "${COMMENT_BODY:-}" | grep -qE "$PATTERN"; then
      SHOULD_TRIGGER=true
    fi
    ;;
  issues)
    if printf '%s' "${ISSUE_BODY:-}" | grep -qE "$PATTERN"; then
      SHOULD_TRIGGER=true
    fi
    ;;
esac

if [ "$SHOULD_TRIGGER" = false ]; then
  echo "reply: keyword '$INPUT_KEYWORD' not found (strict match), skipping"
  exit 0
fi

: "${ISSUE_NUM:?ISSUE_NUM required}"

echo "reply: triggered on $GITHUB_EVENT_NAME for issue #$ISSUE_NUM"

TARGET_DESC="issue #$ISSUE_NUM"
REACTION_PATH="repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUM/reactions"

if [ -n "${COMMENT_ID:-}" ] && [ "${GITHUB_EVENT_NAME}" = "issue_comment" ]; then
  REACTION_PATH="repos/$GITHUB_REPOSITORY/issues/comments/$COMMENT_ID/reactions"
  TARGET_DESC="comment #$COMMENT_ID"
fi

echo "reply: target=$TARGET_DESC"

# ── Build reply body (static or AI-generated) ──
if [ "${INPUT_USE_AI:-false}" = "true" ]; then
  # AI generation is delegated to `x ai reply`, which has the issue-safety
  # rules (untrusted input, no secrets, no guessing APIs) built into its
  # prompt. x-cmd picks the provider and credentials itself (e.g. from the
  # MINIMAX_API_KEY env var), so no provider/apikey/model setup happens
  # here — we only assemble the repo/issue context to reply to.

  # Pull repo context (owner/name + description) so the AI doesn't
  # guess — it's already running inside this repo and can be referenced.
  REPO_INFO=$(gh repo view --json nameWithOwner,description 2>/dev/null || echo '{}')
  REPO_NAME=$(printf '%s' "$REPO_INFO" | jq -r '.nameWithOwner // empty' 2>/dev/null || printf '')
  REPO_DESC=$(printf '%s' "$REPO_INFO" | jq -r '.description // empty' 2>/dev/null || printf '')

  COMBINED_TEXT="${ISSUE_TITLE:-}${ISSUE_BODY:-}${COMMENT_BODY:-}"
  if printf '%s' "$COMBINED_TEXT" | grep -qE '[一-龥]'; then
    REPLY_LANG="zh-CN"
  else
    REPLY_LANG="en"
  fi

  if [ "$GITHUB_EVENT_NAME" = "issue_comment" ]; then
    CONTEXT="Repository: ${REPO_NAME:-unknown}
Repository description: ${REPO_DESC:-n/a}

Issue #$ISSUE_NUM${ISSUE_TITLE:+: $ISSUE_TITLE}

${ISSUE_BODY:-}

Comment by the user:
${COMMENT_BODY:-}"
  else
    CONTEXT="Repository: ${REPO_NAME:-unknown}
Repository description: ${REPO_DESC:-n/a}

Issue #$ISSUE_NUM${ISSUE_TITLE:+: $ISSUE_TITLE}

${ISSUE_BODY:-}"
  fi

  # Optional extra guidance (inputs.prompt / inputs.prompt-file) is
  # prepended to the context; the built-in issue-safety rules in `x ai
  # reply` always apply regardless.
  EXTRA_PROMPT=""
  if [ -n "${INPUT_PROMPT:-}" ]; then
    EXTRA_PROMPT="$INPUT_PROMPT"
    echo "reply: using inline extra guidance from inputs.prompt"
  elif [ -n "${INPUT_PROMPT_FILE:-}" ]; then
    # Try resolving relative to cwd (workflow checkout dir) first, then to action dir.
    if [ -f "$INPUT_PROMPT_FILE" ]; then
      EXTRA_PROMPT=$(cat "$INPUT_PROMPT_FILE")
      echo "reply: loaded extra guidance from $INPUT_PROMPT_FILE (cwd)"
    elif [ -f "$ACTION_PATH/$INPUT_PROMPT_FILE" ]; then
      EXTRA_PROMPT=$(cat "$ACTION_PATH/$INPUT_PROMPT_FILE")
      echo "reply: loaded extra guidance from $ACTION_PATH/$INPUT_PROMPT_FILE (action dir)"
    else
      echo "reply: WARNING — prompt-file '$INPUT_PROMPT_FILE' not found, ignoring"
    fi
  fi

  PROMPT="User language: $REPLY_LANG

$CONTEXT"
  if [ -n "$EXTRA_PROMPT" ]; then
    PROMPT="$EXTRA_PROMPT

$PROMPT"
  fi

  # `x ai reply` prints the drafted reply on stdout; stderr (progress,
  # harness logs) is left untouched so it shows up in the Actions log
  # for debugging. It resolves the provider + credentials (MINIMAX_API_KEY
  # etc.) internally.
  echo "reply: calling x ai reply..."
  RC=0
  RESPONSE=$(x ai reply "$PROMPT") || RC=$?
  if [ "$RC" != "0" ]; then
    echo "reply: AI call failed (rc=$RC) — see stderr output above"
  fi

  # Defensive: drop any stray progress/log lines that leak onto stdout.
  # grep -vE returns 1 when nothing matches, hence the `||` fallback.
  RESPONSE=$(printf '%s' "$RESPONSE" | grep -vE '^-[[:space:]]*[✓✗WIE]\||exitcode:' 2>/dev/null || printf '%s' "$RESPONSE")

  # Trim leading/trailing whitespace.
  REPLY_TEXT=$(printf '%s' "$RESPONSE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' 2>/dev/null || printf '%s' "$RESPONSE")

  # Guard against empty / broken AI responses.
  # `___ASK_FAILED___:` is x-cmd's internal failure marker.
  case "$REPLY_TEXT" in
    ""|___ASK_FAILED___*)
      echo "reply: AI returned empty/failed response, falling back to static comment"
      REPLY_TEXT="$INPUT_COMMENT"
      ;;
  esac
else
  REPLY_TEXT="$INPUT_COMMENT"
fi

EXISTING=$(gh api "$REACTION_PATH" --jq "[.[] | select(.content == \"$INPUT_REACTION\")] | length" 2>/dev/null || echo 0)

if [ "${EXISTING:-0}" -gt 0 ]; then
  echo "reply: $TARGET_DESC already has :$INPUT_REACTION: (count=$EXISTING), skipping"
  exit 0
fi

REACTION_ERR=$(mktemp)
if gh api -X POST "$REACTION_PATH" \
  -f content="$INPUT_REACTION" 2>"$REACTION_ERR"; then
  echo "reply: added :$INPUT_REACTION: on $TARGET_DESC"
else
  # Surface the real error — a 403 here usually means the workflow token
  # lacks write permission on the target (e.g. PR conversations need
  # pull-requests: write, not just issues: write), NOT a dedupe hit.
  echo "reply: WARNING — failed to add reaction on $TARGET_DESC:" >&2
  cat "$REACTION_ERR" >&2
fi
rm -f "$REACTION_ERR"

COMMENT_BODY="$REPLY_TEXT

<sub>Replied by [x-cmd-action/ai](https://github.com/x-cmd-action/ai)</sub>"

if gh issue comment "$ISSUE_NUM" --body "$COMMENT_BODY"; then
  echo "reply: posted reply"
else
  echo "reply: WARNING — failed to post reply on issue #$ISSUE_NUM (GH_TOKEN permissions?)" >&2
fi

echo "reply: done"
