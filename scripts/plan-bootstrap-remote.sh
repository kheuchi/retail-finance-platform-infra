#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"
export AWS_PAGER=""

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${AWS_PROFILE:-retail-platform-admin}"

credential_exports="$(
  aws configure export-credentials --profile "${profile}" --format env
)"
eval "${credential_exports}"
unset credential_exports

cleanup_credentials() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_CREDENTIAL_EXPIRATION
}
trap cleanup_credentials EXIT

cd "${repo_root}/bootstrap"
terraform plan -input=false -lock-timeout=5m -out=bootstrap.tfplan
