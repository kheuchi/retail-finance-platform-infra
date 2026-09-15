#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${AWS_PROFILE:-retail-platform-admin}"

credential_exports="$(
  aws configure export-credentials --profile "${profile}" --format env
)"
eval "${credential_exports}"
unset credential_exports

delete_manifest="$(mktemp)"
cleanup() {
  rm -f "${delete_manifest}"
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_CREDENTIAL_EXPIRATION
}
trap cleanup EXIT

account_id="$(aws sts get-caller-identity --query Account --output text)"
old_bucket="retail-finance-platform-tfstate-${account_id}-eu-west-3"
new_bucket="retail-finance-platform-tfstate-${account_id}-eu-central-1"
state_key="bootstrap/terraform.tfstate"

# Refuse cleanup unless the active local backend and remote state both point to Frankfurt.
backend_bucket="$(jq -r '.backend.config.bucket' "${repo_root}/bootstrap/.terraform/terraform.tfstate")"
backend_region="$(jq -r '.backend.config.region' "${repo_root}/bootstrap/.terraform/terraform.tfstate")"
if [[ "${backend_bucket}" != "${new_bucket}" || "${backend_region}" != "eu-central-1" ]]; then
  echo "Refusing cleanup: the active Terraform backend is not Frankfurt." >&2
  exit 1
fi
aws s3api head-object --bucket "${new_bucket}" --key "${state_key}" >/dev/null
aws s3api head-bucket --bucket "${old_bucket}" >/dev/null

aws s3api list-object-versions --bucket "${old_bucket}" --output json |
  jq '{Objects: (((.Versions // []) + (.DeleteMarkers // [])) | map({Key, VersionId})), Quiet: true}' \
    >"${delete_manifest}"

object_count="$(jq '.Objects | length' "${delete_manifest}")"
if [[ "${object_count}" -gt 0 ]]; then
  aws s3api delete-objects \
    --bucket "${old_bucket}" \
    --delete "file://${delete_manifest}" >/dev/null
fi

remaining="$(aws s3api list-object-versions --bucket "${old_bucket}" --output json |
  jq '((.Versions // []) + (.DeleteMarkers // [])) | length')"
if [[ "${remaining}" -ne 0 ]]; then
  echo "Refusing bucket deletion: ${remaining} object versions remain." >&2
  exit 1
fi

aws s3api delete-bucket --bucket "${old_bucket}" --region eu-west-3
echo "Retired empty Paris backend bucket after verifying active Frankfurt state."
