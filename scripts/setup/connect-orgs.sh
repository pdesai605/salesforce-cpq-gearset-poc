#!/usr/bin/env bash
# Logs the Salesforce CLI into all four POC orgs, one browser login each.
# Usage: bash scripts/setup/connect-orgs.sh
set -euo pipefail

for env in dev qa uat prod; do
    echo ""
    echo ">>> Log in to the ${env} org in the browser window that opens"
    sf org login web --alias "poc-${env}" --instance-url https://login.salesforce.com
done

sf config set target-org poc-dev
echo ""
sf org list
