#!/bin/bash
# One-time GCP setup for GitHub Actions deploys (no service-account keys needed).
# Uses Workload Identity Federation so GitHub can impersonate a service account.
#
# Usage:  PROJECT_ID=your-gcp-project-id ./scripts/setup-wif.sh
# Requires: gcloud authenticated as a project owner
#           (gcloud auth login)
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID, e.g. PROJECT_ID=my-project-123 ./scripts/setup-wif.sh}"

POOL_ID="github-pool"
PROVIDER_ID="github-provider"
SA_NAME="terraform"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
REPO="binaychap/ops-trade-idea-gcp"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"

echo "==> Creating service account ${SA_EMAIL}"
gcloud iam service-accounts create "${SA_NAME}" \
  --project="${PROJECT_ID}" \
  --display-name="Terraform GitHub Actions" 2>/dev/null || true

echo "==> Granting Editor role on the project"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/editor" \
  --condition=None >/dev/null

echo "==> Creating Workload Identity Pool"
gcloud iam workload-identity-pools create "${POOL_ID}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions pool" 2>/dev/null || true

echo "==> Creating OIDC provider for GitHub"
gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="${POOL_ID}" \
  --display-name="GitHub provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == 'binaychap'" \
  --issuer-uri="https://token.actions.githubusercontent.com" 2>/dev/null || true

echo "==> Allowing this repo to impersonate the service account"
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${REPO}" >/dev/null

echo "==> Creating Terraform state bucket (free tier: 5 GB)"
gcloud storage buckets create "gs://ops-trade-idea-tfstate" \
  --project="${PROJECT_ID}" \
  --location="us-central1" \
  --uniform-bucket-level-access 2>/dev/null || true

WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

echo
echo "Done. Add these as GitHub repo secrets"
echo "(https://github.com/${REPO}/settings/secrets/actions):"
echo
echo "  GCP_PROJECT_ID       = ${PROJECT_ID}"
echo "  GCP_WIF_PROVIDER     = ${WIF_PROVIDER}"
echo "  GCP_SERVICE_ACCOUNT  = ${SA_EMAIL}"
echo
echo "Optional bot secrets (empty = feature disabled):"
echo "  OPTIONOMICS_API_KEY, OPTIONOMICS_EMAIL,"
echo "  WEBULL_APP_KEY, WEBULL_APP_SECRET, IOS_API_KEY"
