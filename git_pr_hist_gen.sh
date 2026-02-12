#!/bin/bash

#!/bin/bash

###############################################################################
# Script: taskgen.sh
#
# Purpose
# -------
# Extract a curated set of small, meaningful Pull Requests from a GitHub repo
# and generate a CSV describing the exact code changes introduced by each PR.
#
# The script:
#   • Reads repository information from the local git remote (origin)
#   • Fetches recently merged PRs using GitHub CLI (gh)
#   • Reconstructs the true lifecycle of each PR branch
#   • Filters for small, code-relevant changes
#   • Stops after collecting a fixed number of high-signal PRs
#
#
# What the script captures
# ------------------------
# For each selected PR:
#
#   start_sha  = commit where the PR branch diverged from base (branch creation)
#   end_sha    = commit that was merged into the base branch
#
# The actual change introduced by the branch can be obtained via:
#
#   git diff start_sha end_sha
#
#
# Selection criteria
# ------------------
# 1. Only merged PRs are considered
# 2. Up to the latest 100 merged PRs are scanned
# 3. PR title must NOT match noise patterns:
#      bump, release, version, prepare, docs-only, readme, changelog
#    (filters dependency updates, releases, documentation-only changes)
# 4. Actual files changed across branch lifetime must be:
#      2 to 5 files (inclusive)
#    Computed via:
#      git diff start_sha end_sha
#    (GitHub API counts are NOT trusted)
# 5. Processing stops after MAX valid PRs (default: 20)
#
#
# Output
# ------
# CSV file: filtered_prs.csv
#
# Columns:
#   pr_number
#   title
#   files_changed
#   start_sha   (branch divergence point)
#   end_sha     (merge commit)
#   created_at
#   merged_at
#
#
# Requirements
# ------------
# • Must be run inside a cloned Git repository
# • The repository must have a GitHub remote named "origin"
# • GitHub CLI installed and authenticated:
#       gh auth login
# • jq installed
#
#
# Repository detection
# --------------------
# The script automatically derives:
#   owner/repo
# from:
#   git remote get-url origin
#
# Supports:
#   git@github.com:owner/repo.git
#   https://github.com/owner/repo.git
#
#
# Git behavior
# ------------
# The script fetches:
#   • latest origin history
#   • PR head references
#
# Branch start is reconstructed using:
#   git merge-base headRefOid baseRefOid
#
# This approximates the commit where the PR branch was created.
#
#
# Notes / Limitations
# -------------------
# • Git does not store actual branch creation events; merge-base is used.
# • File count reflects total changes over branch lifetime, which may include
#   changes introduced by base branch movement during the PR.
# • Title filtering is heuristic and may exclude some legitimate PRs.
#
#
# Typical Use Cases
# -----------------
# • Building small-change datasets
# • Mining bug-fix or enhancement examples
# • LLM training / evaluation data preparation
# • Code review pattern analysis
#
###############################################################################


# Detect repo from origin URL (owner/repo)
REPO=$(git remote get-url origin 2>/dev/null)

# Convert SSH or HTTPS URL to owner/repo
REPO=$(echo "$REPO" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')

if [ -z "$REPO" ]; then
  echo "ERROR: Could not determine GitHub repo from origin"
  exit 1
fi

echo "Using repo: $REPO"

OUTPUT="task_prs.csv"
MAX=20
count=0

if [ ! -d ".git" ]; then
  echo "ERROR: Run inside cloned repository"
  exit 1
fi

echo "Fetching history..."
git fetch origin --prune >/dev/null 2>&1
git fetch origin '+refs/pull/*/head:refs/remotes/origin/pr/*' >/dev/null 2>&1

echo "pr_number,title,files_changed,start_sha,end_sha,created_at,merged_at" > "$OUTPUT"

gh pr list \
  --repo "$REPO" \
  --state merged \
  --limit 100 \
  --json number,title,headRefOid,baseRefOid,mergeCommit,createdAt,mergedAt \
| jq -c '.[]' \
| while read -r pr; do

  # Stop early if already collected enough
  if [ "$count" -ge "$MAX" ]; then
    break
  fi

  number=$(echo "$pr" | jq -r '.number')
  title=$(echo "$pr" | jq -r '.title' | tr ',' ' ')
  head_sha=$(echo "$pr" | jq -r '.headRefOid')
  base_sha=$(echo "$pr" | jq -r '.baseRefOid')
  end_sha=$(echo "$pr" | jq -r '.mergeCommit.oid')
  created=$(echo "$pr" | jq -r '.createdAt')
  merged=$(echo "$pr" | jq -r '.mergedAt')

  [ "$end_sha" = "null" ] && continue

  # ---- Filter noise PRs ----
  title_lower=$(echo "$title" | tr '[:upper:]' '[:lower:]')
  if echo "$title_lower" | grep -E -q 'bump|release|version|prepare|preparing|docs only|readme|changelog'; then
    continue
  fi

  # Ensure commits exist locally
  git cat-file -e "$head_sha" 2>/dev/null || continue
  git cat-file -e "$base_sha" 2>/dev/null || continue

  # Branch start (divergence)
  start_sha=$(git merge-base "$head_sha" "$base_sha")

  # Branch lifetime file count
  files=$(git diff --name-only "$start_sha" "$end_sha" | wc -l | tr -d ' ')

  [ "$files" -le 1 ] || [ "$files" -gt 5 ] && continue

  echo "Processing PR #$number (files=$files)"

  echo "$number,\"$title\",$files,$start_sha,$end_sha,$created,$merged" >> "$OUTPUT"

  count=$((count+1))

done

echo "Done. Collected $count PRs. CSV saved as $OUTPUT"
