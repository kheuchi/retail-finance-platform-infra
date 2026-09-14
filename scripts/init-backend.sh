#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap_dir="${repo_root}/bootstrap"
profile="${AWS_PROFILE:-retail-platform-admin}"

# Terraform 1.14's S3 backend does not yet understand AWS CLI `login_session`.
# Convert the existing short-lived browser session to process-only environment
# variables. Nothing is written to the credentials file or repository.
credential_exports="$(
  aws configure export-credentials \
    --profile "${profile}" \
    --format env
)"
eval "${credential_exports}"
unset credential_exports

cleanup_credentials() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_CREDENTIAL_EXPIRATION
}
trap cleanup_credentials EXIT

cd "${bootstrap_dir}"
terraform init \
  -migrate-state \
  -force-copy \
  -input=false \
  -backend-config="bucket=retail-finance-platform-tfstate-729088687627-eu-west-3" \
  -backend-config="key=bootstrap/terraform.tfstate" \
  -backend-config="region=eu-west-3" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"

echo "Terraform state backend initialized with temporary process credentials."
