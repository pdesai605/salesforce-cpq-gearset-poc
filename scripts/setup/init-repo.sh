#!/usr/bin/env bash
# Creates the Git history the pipeline expects:
#   main / uat / qa / dev  -> environment branches, all at the same baseline (no app code yet)
#   feature/DD-101-...     -> the Deal Desk app, which will travel Dev -> QA -> UAT -> Prod through Gearset
#
# Usage: bash scripts/setup/init-repo.sh https://github.com/<you>/salesforce-cpq-gearset-poc.git
set -euo pipefail
REMOTE_URL="${1:?Pass the GitHub repo URL, e.g. https://github.com/you/salesforce-cpq-gearset-poc.git}"
FEATURE=feature/DD-101-deal-desk-governance

if [ -d .git ]; then
    echo "This folder is already a Git repo. Run this only once, on a fresh copy." >&2
    exit 1
fi

git init -b main
git remote add origin "$REMOTE_URL"

# 1) Baseline: project structure, quality gates and scripts. No Salesforce components yet,
#    which matches the four empty orgs, so every environment starts in sync.
mkdir -p force-app/main/default
touch force-app/main/default/.gitkeep
git add --all -- . ':!force-app/main/default/*'
git add --force force-app/main/default/.gitkeep
git commit -m "chore: baseline Salesforce DX project, quality gates and release scripts"

# 2) Environment branches, all from the baseline
for branch in uat qa dev; do
    git branch "$branch"
done

# 3) Feature branch with the Deal Desk app
git checkout -b "$FEATURE"
git add force-app
git commit -m "feat(DD-101): Deal Desk governance for CPQ quotes

- Risk score, discount tier and approval status on every quote
- Floor price and margin checks on every quote line
- Discount thresholds as custom metadata (configurable per environment)
- Approval guardrail validation rule and review-task flow
- Deal Desk Lightning panel with approve/reject for approvers
- Unit and integration tests"

git push -u origin main uat qa dev "$FEATURE"
git checkout "$FEATURE"
echo ""
echo "Pushed: main, uat, qa, dev and $FEATURE"
