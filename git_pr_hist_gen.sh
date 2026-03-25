#!/bin/bash

###############################################################################
# Stable PR Miner
#
# Fixes included:
# • Correct line-count parsing (handles insert-only / delete-only)
# • Works for squash / merge / rebase
# • Uses synthetic merge when available
# • Falls back to mergeCommit correctly
# • No subshell loop issues
# • Allows small PRs (like smolagents#1900)
###############################################################################

set -e

OUTPUT="task_prs.csv"
MAX=20
count=0

# -------- Validate repo --------
if [ ! -d ".git" ]; then
  echo "ERROR: Run inside a git repository"
  exit 1
fi

REPO=$(git remote get-url origin 2>/dev/null)
REPO=$(echo "$REPO" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')

echo "Using repo: $REPO"

command -v gh >/dev/null || { echo "gh CLI required"; exit 1; }
command -v jq >/dev/null || { echo "jq required"; exit 1; }

# -------- Fetch full history --------
echo "Fetching origin..."
git fetch origin --prune --depth=0 >/dev/null 2>&1 || true

echo "Fetching PR refs..."
git fetch origin \
  '+refs/pull/*/head:refs/remotes/origin/pr/*' \
  '+refs/pull/*/merge:refs/remotes/origin/pr-merge/*' \
  >/dev/null 2>&1 || true

# -------- CSV --------
echo "pr_number,title,files_changed,lines_changed,start_sha,end_sha,created_at,merged_at" > "$OUTPUT"

echo "Scanning merged PRs..."

while read -r pr; do

  [ "$count" -ge "$MAX" ] && break

  number=$(echo "$pr" | jq -r '.number')
  title=$(echo "$pr" | jq -r '.title' | tr ',' ' ')
  created=$(echo "$pr" | jq -r '.createdAt')
  merged=$(echo "$pr" | jq -r '.mergedAt')
  head_sha=$(echo "$pr" | jq -r '.headRefOid')
  base_sha=$(echo "$pr" | jq -r '.baseRefOid')
  merge_commit=$(echo "$pr" | jq -r '.mergeCommit.oid')

  #########################################
  # Determine start_sha and end_sha
  #########################################

  end_sha=""
  start_sha=""

  # --- Strategy 1: synthetic merge ---
  if git rev-parse --verify "origin/pr-merge/$number" >/dev/null 2>&1; then
    end_sha=$(git rev-parse "origin/pr-merge/$number")
    start_sha=$(git rev-parse "${end_sha}^1" 2>/dev/null || true)
  fi

  # --- Strategy 2: mergeCommit fallback (works for squash) ---
  if [ -z "$end_sha" ] && [ "$merge_commit" != "null" ]; then
    if git cat-file -e "$merge_commit" 2>/dev/null; then
      end_sha="$merge_commit"
      start_sha=$(git rev-parse "${end_sha}^" 2>/dev/null || true)
    fi
  fi

  # Skip if still unresolved
  [ -z "$start_sha" ] && continue
  [ -z "$end_sha" ] && continue

  #########################################
  # File count
  #########################################

  files=$(git diff --name-only "$start_sha" "$end_sha" | wc -l | tr -d ' ')
  [ "$files" -lt 5 ] && continue
  [ "$files" -gt 7 ] && continue

  #########################################
  # Code file filter
  #########################################

  code_files=$(git diff --name-only "$start_sha" "$end_sha" \
    | grep -E '\.(py|js|ts|java|go|rb|rs|cpp|c|cs|php|sh|yaml|yml)$' \
    | wc -l | tr -d ' ')

  [ "$code_files" -eq 0 ] && continue

  #########################################
  # Precise line count (FIXED)
  #########################################

  stats=$(git diff --shortstat "$start_sha" "$end_sha")

  insertions=$(echo "$stats" | grep -o '[0-9]\+ insertion' | grep -o '[0-9]\+' || echo 0)
  deletions=$(echo "$stats" | grep -o '[0-9]\+ deletion' | grep -o '[0-9]\+' || echo 0)

  lines=$((insertions + deletions))

  # Optional upper bound
  [ "$lines" -gt 200 ] && continue

  #########################################

  echo "✔ PR #$number  files=$files  lines=$lines"

  echo "$number,\"$title\",$files,$lines,$start_sha,$end_sha,$created,$merged" >> "$OUTPUT"

  count=$((count+1))

done < <(
  gh pr list \
    --repo "$REPO" \
    --state merged \
    --limit 200 \
    --json number,title,headRefOid,baseRefOid,mergeCommit,createdAt,mergedAt \
  | jq -c '.[]'
)

echo "Done. Collected $count PRs"
echo "Saved: $OUTPUT"
