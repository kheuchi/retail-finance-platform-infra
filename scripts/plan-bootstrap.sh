#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap_dir="${repo_root}/bootstrap"

export AWS_PROFILE="${AWS_PROFILE:-retail-platform-admin}"
export AWS_REGION="${AWS_REGION:-eu-west-3}"
export AWS_PAGER=""

credential_exports="$(
  aws configure export-credentials \
    --profile "${AWS_PROFILE}" \
    --format env
)"
eval "${credential_exports}"
unset credential_exports

cleanup_credentials() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_CREDENTIAL_EXPIRATION
}
trap cleanup_credentials EXIT

budget_email="$(
  aws account get-contact-information \
    --query ContactInformation.EmailAddress \
    --output text 2>/dev/null || true
)"

if [[ "${budget_email}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  export TF_VAR_budget_alert_email="${budget_email}"
else
  unset TF_VAR_budget_alert_email || true
  echo "No retrievable budget email; planning the budget without notifications."
fi

cd "${bootstrap_dir}"
terraform fmt -check
terraform validate
terraform plan -input=false -out=bootstrap.tfplan

echo "Bootstrap plan saved. No contact data was printed or written to Git."
