#!/usr/bin/env bash
# Keyless identity for the CI plan job (.github/workflows/ci.yml): Workload Identity Federation for GitHub Actions.
#   pool/provider github  accepts tokens only from GITHUB_REPO on refs/heads/main
#   sa-terraform          read-only: viewer, iam.securityReviewer (IAM policies), bigquery.jobUser (SQL dry run)
# Then set in GitHub: variables WIF_PROVIDER and TERRAFORM_SA (printed at the end),
# secrets TF_ALERT_EMAIL and TF_FULL_READERS (JSON list), with the same values as terraform.tfvars. Idempotent.
# Usage: GITHUB_REPO=owner/repo infra/07_ci_identity.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
REPO="${GITHUB_REPO:?set GITHUB_REPO=owner/repo}"
NUM=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
POOL="projects/$NUM/locations/global/workloadIdentityPools/github"
SA="sa-terraform@$PROJECT_ID.iam.gserviceaccount.com"

gcloud services enable iamcredentials.googleapis.com sts.googleapis.com --project="$PROJECT_ID"

gcloud iam workload-identity-pools describe github --project="$PROJECT_ID" --location=global >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools create github --project="$PROJECT_ID" --location=global \
    --display-name="GitHub Actions"
gcloud iam workload-identity-pools providers describe github --project="$PROJECT_ID" --location=global \
    --workload-identity-pool=github >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools providers create-oidc github --project="$PROJECT_ID" --location=global \
    --workload-identity-pool=github --display-name="GitHub OIDC" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository=='$REPO' && assertion.ref=='refs/heads/main'"

gcloud iam service-accounts describe "$SA" --project="$PROJECT_ID" >/dev/null 2>&1 || \
  gcloud iam service-accounts create sa-terraform --project="$PROJECT_ID" \
    --display-name="Terraform plan desde GitHub Actions (solo lectura)"

for r in roles/viewer roles/iam.securityReviewer roles/bigquery.jobUser; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA" --role="$r" --condition=None --format=none
done
gcloud iam service-accounts add-iam-policy-binding "$SA" --project="$PROJECT_ID" \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/$POOL/attribute.repository/$REPO" --format=none

echo "WIF_PROVIDER=$POOL/providers/github"
echo "TERRAFORM_SA=$SA"
echo "Bindings can take a few minutes to propagate; the first CI run may fail with 403 meanwhile."
