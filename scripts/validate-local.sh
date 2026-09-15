#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

jq empty package.json .releaserc.json package-lock.json
python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/ci.yml")); yaml.safe_load(open(".github/dependabot.yml"))'
terraform fmt -check -recursive -diff
bash -n scripts/*.sh

echo "Local static validation passed."
