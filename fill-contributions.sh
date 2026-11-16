#!/usr/bin/env bash
#
# fill-contributions.sh — fill the GitHub contribution graph with backdated commits.
#
# How it works: GitHub places each commit on the graph by its author date.
# This script creates small commits in a target repo with GIT_AUTHOR_DATE /
# GIT_COMMITTER_DATE set to days in the past, then (optionally) pushes them.
#
# Requirements for the squares to show up:
#   * The commit email must be one verified on your GitHub account
#     (check with: git config user.email).
#   * Commits must land on the repo's default branch (main) on GitHub.
#   * For a private repo, enable "Private contributions" in your profile settings.
#
# Usage:
#   ./fill-contributions.sh [options]
#
# Options:
#   -r, --repo PATH       Repo to commit into (default: ./contrib-art, created if missing)
#   -d, --days N          How many days back to fill (default: 365)
#   -m, --max N           Max commits per day; each day gets 1..N (default: 4)
#   -s, --skip-chance P   % chance to leave a day empty, looks more natural (default: 20)
#   -w, --no-weekends     Don't commit on Saturdays/Sundays
#   -p, --push            Push to the repo's remote after committing
#   -n, --dry-run         Show what would be done, change nothing
#   -h, --help            Show this help
#
# Examples:
#   ./fill-contributions.sh -n                          # preview
#   ./fill-contributions.sh -d 365 -m 6 -s 0 -p         # every day for a year, then push
#   ./fill-contributions.sh -r ~/code/graph -w -p       # weekdays only, custom repo

set -euo pipefail

REPO="./contrib-art"
DAYS=365
MAX=4
SKIP=20
NO_WEEKENDS=0
PUSH=0
DRY_RUN=0

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--repo)        REPO="$2"; shift 2 ;;
    -d|--days)        DAYS="$2"; shift 2 ;;
    -m|--max)         MAX="$2"; shift 2 ;;
    -s|--skip-chance) SKIP="$2"; shift 2 ;;
    -w|--no-weekends) NO_WEEKENDS=1; shift ;;
    -p|--push)        PUSH=1; shift ;;
    -n|--dry-run)     DRY_RUN=1; shift ;;
    -h|--help)        usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

for v in DAYS MAX SKIP; do
  [[ "${!v}" =~ ^[0-9]+$ ]] || { echo "Error: --$(echo "$v" | tr A-Z a-z) must be a non-negative integer" >&2; exit 1; }
done
(( MAX >= 1 )) || { echo "Error: --max must be at least 1" >&2; exit 1; }

# Portable "N days ago" -> prints "YYYY-MM-DD <weekday 1-7, Mon=1>"
if date -v-1d +%F >/dev/null 2>&1; then
  day_ago() { date -v-"$1"d +"%F %u"; }          # macOS / BSD
else
  day_ago() { date -d "$1 days ago" +"%F %u"; }  # GNU / Linux
fi

# Prepare repo
if [[ $DRY_RUN -eq 0 ]]; then
  if [[ ! -d "$REPO/.git" ]]; then
    echo "Creating new repo at $REPO"
    mkdir -p "$REPO"
    git -C "$REPO" init -q -b main
  fi
  cd "$REPO"
  email="$(git config user.email || true)"
  if [[ -z "$email" ]]; then
    echo "Error: git user.email is not set. Run: git config --global user.email you@example.com" >&2
    exit 1
  fi
  echo "Committing as: $(git config user.name) <$email>"
  echo "(this email must be verified on your GitHub account for squares to appear)"
fi

total=0
for (( i = DAYS; i >= 1; i-- )); do
  read -r day weekday <<<"$(day_ago "$i")"

  if [[ $NO_WEEKENDS -eq 1 && $weekday -ge 6 ]]; then continue; fi
  if (( RANDOM % 100 < SKIP )); then continue; fi

  count=$(( RANDOM % MAX + 1 ))
  for (( c = 0; c < count; c++ )); do
    # Spread commits across working hours: 09:00–18:59
    stamp="$(printf '%sT%02d:%02d:%02d' "$day" $((9 + RANDOM % 10)) $((RANDOM % 60)) $((RANDOM % 60)))"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "would commit at $stamp"
    else
      echo "$stamp" >> contributions.txt
      git add contributions.txt
      GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" \
        git commit -q -m "update $day ($((c + 1))/$count)"
    fi
    total=$(( total + 1 ))
  done
done

echo "Done: $total commits over the last $DAYS days."

if [[ $DRY_RUN -eq 0 && $PUSH -eq 1 ]]; then
  if git remote get-url origin >/dev/null 2>&1; then
    git push -u origin main
  else
    echo "No 'origin' remote. Create an empty repo on GitHub, then run:"
    echo "  cd $REPO && git remote add origin git@github.com:<you>/<repo>.git && git push -u origin main"
  fi
elif [[ $DRY_RUN -eq 0 ]]; then
  echo "Not pushed. When ready: cd $REPO && git push -u origin main"
fi
