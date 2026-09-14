#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap_dir="${repo_root}/bootstrap"
profile="${AWS_PROFILE:-retail-platform-admin}"
plan_file="${bootstrap_dir}/bootstrap.tfplan"

if [[ ! -f "${plan_file}" ]]; then
  echo "No saved bootstrap plan exists. Run scripts/plan-bootstrap.sh first." >&2
  exit 1
fi

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
terraform apply -input=false bootstrap.tfplan
