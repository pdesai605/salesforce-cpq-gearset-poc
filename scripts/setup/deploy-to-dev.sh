#!/usr/bin/env bash
# Deploys the Deal Desk app to the DEV org only, runs the Apex tests,
# assigns permission sets and seeds the Nimbus CPQ catalogue.
# QA, UAT and Prod are NOT touched: they only ever receive changes through Gearset.
# Usage: bash scripts/setup/deploy-to-dev.sh
set -euo pipefail
ORG=poc-dev

echo ">>> Deploying force-app to ${ORG}"
sf project deploy start --source-dir force-app --target-org "$ORG" --wait 30

echo ">>> Running Apex tests with coverage"
sf apex run test --target-org "$ORG" \
    --class-names DealDeskServiceTest --class-names DealDeskIntegrationTest \
    --code-coverage --result-format human --wait 15

echo ">>> Assigning permission sets"
sf org assign permset --name Deal_Desk_User --name Deal_Desk_Approver --target-org "$ORG"

echo ">>> Seeding the Nimbus CPQ catalogue"
sf apex run --file scripts/apex/seed-cpq-catalog.apex --target-org "$ORG"

echo ""
echo "Done. Open the org with:  sf org open --target-org $ORG"
