#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap_dir="${repo_root}/bootstrap"
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

account_id="$(aws sts get-caller-identity --query Account --output text)"
old_bucket="retail-finance-platform-tfstate-${account_id}-eu-west-3"
new_bucket="retail-finance-platform-tfstate-${account_id}-eu-central-1"
state_key="bootstrap/terraform.tfstate"
backup_key="migration-backup/bootstrap-$(date -u +%Y%m%dT%H%M%SZ).tfstate"

aws s3api head-bucket --bucket "${old_bucket}"

if aws s3api head-bucket --bucket "${new_bucket}" 2>/dev/null; then
  echo "Destination bucket already exists: ${new_bucket}"
else
  aws s3api create-bucket \
    --bucket "${new_bucket}" \
    --region eu-central-1 \
    --create-bucket-configuration LocationConstraint=eu-central-1
fi

# Establish minimum backend protection before any state is copied.
aws s3api put-public-access-block \
  --bucket "${new_bucket}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning \
  --bucket "${new_bucket}" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption \
  --bucket "${new_bucket}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Preserve a separately named server-side copy in the old versioned bucket.
aws s3api copy-object \
  --bucket "${old_bucket}" \
  --copy-source "${old_bucket}/${state_key}" \
  --key "${backup_key}" >/dev/null

cd "${bootstrap_dir}"
terraform init \
  -migrate-state \
  -force-copy \
  -input=false \
  -backend-config="bucket=${new_bucket}" \
  -backend-config="key=${state_key}" \
  -backend-config="region=eu-central-1" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"

# The old bucket remains physically intact. Rebind the logical Terraform resource
# to the destination; child configurations are recreated by the reviewed apply.
terraform state rm \
  aws_s3_bucket_policy.terraform_state \
  aws_s3_bucket_lifecycle_configuration.terraform_state \
  aws_s3_bucket_server_side_encryption_configuration.terraform_state \
  aws_s3_bucket_versioning.terraform_state \
  aws_s3_bucket_public_access_block.terraform_state \
  aws_s3_bucket_ownership_controls.terraform_state \
  aws_s3_bucket.terraform_state
terraform import aws_s3_bucket.terraform_state "${new_bucket}"

echo "State is now hosted in Frankfurt and the Frankfurt bucket is imported."
echo "Paris remains untouched pending a reviewed zero-delete plan and apply."
