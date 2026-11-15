#!/usr/bin/env bash
# CloudGuard360 Phase 04 complete automation — staged, explicit human approval at side-effect boundaries.
set -Eeuo pipefail
umask 077
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AZ_RG="rg-cg360-app"
AZ_APP="ca-cg360-voting"
GITHUB_ENV="cloudguard360-lab"
WORKSPACE="${HOME}/clouddrive/cloudguard360"
TF_DIR="$ROOT/terraform/oidc-identity"
SCRIPT_NAME="$(basename "$0")"
REPO=""
COMMAND=""
ASSUME_YES=0
log() { printf '\n[CG360] %s\n' "$*"; }
fail() { echo "STOP: $*" >&2; exit 1; }
usage() {
cat <<'HELP'
CloudGuard 360 — Automated Phase 04 Finalisation

Commands (all run in Bash, from persistent Cloud Shell):
  bash automation/finalize.sh doctor --repo OWNER/REPO       # read-only checks
  bash automation/finalize.sh prepare --repo OWNER/REPO      # repo clone, copy sources, interactive push approval
  bash automation/finalize.sh ci --repo OWNER/REPO           # run and watch CI
  bash automation/finalize.sh oidc --repo OWNER/REPO         # Terraform OIDC + scoped RBAC; explicit approval
  bash automation/finalize.sh publish --repo OWNER/REPO      # build GHCR image only
  bash automation/finalize.sh deploy --repo OWNER/REPO       # manual GitHub workflow with explicit approval
  bash automation/finalize.sh verify --repo OWNER/REPO       # produce evidence and reconciliation preview
  bash automation/finalize.sh all --repo OWNER/REPO          # staged automation end to end

No Azure resource is created or modified by 'doctor'. No deletion command is used.
No Terraform apply, Git push or Azure deploy occurs without explicit interaction.
GitHub CLI 'gh' must be installed and authenticated. Account must have necessary permissions.
Existing Phase 03 Container App is required for oidc, deploy and verify.
HELP
}
[[ $# -gt 0 ]] || { usage; exit 0; }
COMMAND="$1"; shift
while (( $# > 0 )); do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || fail 'Missing --repo value'; REPO="$2"; shift 2;;
    --help|-h) usage; exit 0;;
    *) fail "Unknown argument: $1";;
  esac
done
[[ "$COMMAND" =~ ^(doctor|prepare|ci|oidc|publish|deploy|verify|all)$ ]] || fail "Unsupported command: $COMMAND"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail 'Supply --repo OWNER/REPO (case-sensitive).'
require() { command -v "$1" >/dev/null || fail "Missing executable: $1. Install using the official instructions."; }
confirm() { local ans; read -r -p "${1} Type YES to continue: " ans || return 1; [[ "$ans" == 'YES' ]] || fail 'Operator declined; no further changes.'; }
check_local() {
  require az; require python3; require git; require terraform; require gh
  mountpoint -q "$HOME/clouddrive" || fail 'Cloud Shell clouddrive is not mounted. Stop: Terraform state must persist.'
  gh auth status >/dev/null 2>&1 || fail 'Authenticate GitHub CLI using gh auth login.'
  az account show >/dev/null 2>&1 || fail 'Azure CLI not authenticated in Cloud Shell.'
  export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
  export ARM_TENANT_ID="$(az account show --query tenantId -o tsv)"
  [[ -n "$ARM_SUBSCRIPTION_ID" ]] || fail 'ARM_SUBSCRIPTION_ID could not be populated.'
  gh repo view "$REPO" --json nameWithOwner --jq .nameWithOwner >/dev/null || fail "GitHub repo $REPO is not accessible. Create it first."
}
read_azure() {
  AZ_JSON="$(az containerapp show -g "$AZ_RG" -n "$AZ_APP" -o json)" || fail 'Phase 03 Container App not found. Complete Phase 03 first.'
  printf '%s' "$AZ_JSON" | python3 -c 'import json,sys; app=json.load(sys.stdin); xs=app["properties"]["template"]["containers"]; names={c["name"] for c in xs}; assert names=={"vote-frontend","redis"},"Wrong container list: "+str(names); print("PASS: existing frontend + redis found")' || fail 'Unexpected Container App layout.'
}
repo_dir() { printf '%s/cloudguard360-phase04-repo\n' "$WORKSPACE"; }
get_image() { az containerapp show -g "$AZ_RG" -n "$AZ_APP" --query "properties.template.containers[?name=='vote-frontend'].image | [0]" -o tsv; }
get_redis() { az containerapp show -g "$AZ_RG" -n "$AZ_APP" --query "properties.template.containers[?name=='redis'].image | [0]" -o tsv; }
get_sha() { git -C "$(repo_dir)" rev-parse HEAD; }
read_repo() {
  local d; d="$(repo_dir)"
  [[ -d "$d/.git" ]] || fail "Git clone missing at $d. Run prepare first."
  [[ -f "$d/vendor/azure-vote/main.py" ]] || fail 'Vendor source missing; run prepare first.'
  [[ -d "$d/vendor/azure-vote/templates" ]] || fail 'Vendor templates missing.'
  (cd "$d" && python3 scripts/validate_repo.py)
}
doctor() {
  check_local
  log 'Subscribed Azure context:'
  az account show --query '{Name:name,State:state}' -o table
  log 'Existing Phase 03 app (no modification):'
  read_azure
  az containerapp show -g "$AZ_RG" -n "$AZ_APP" --query 'properties.template.containers[].{Name:name,Image:image}' -o table
  log 'GitHub repository:'
  gh repo view "$REPO" --json nameWithOwner,isPrivate,defaultBranchRef --jq '{repo:.nameWithOwner,private:.isPrivate,branch:.defaultBranchRef.name}'
  log 'Storage & cost: mounted Azure Files may generate fees; check Azure portal credits manually.'
}
prepare() {
  check_local; require unzip
  mkdir -p "$WORKSPACE"
  local d="$(repo_dir)" upstream="$WORKSPACE/azure-voting-app-redis-upstream"
  if [[ ! -d "$d/.git" ]]; then
    [[ ! -e "$d" ]] || fail "Path $d exists but is not a Git repository. Move it manually first."
    log "Cloning YOUR GitHub repository at $d"
    git clone "https://github.com/$REPO.git" "$d"
  fi
  if [[ ! -f "$d/vendor/azure-vote/main.py" ]]; then
    log 'Copying checked-out official Microsoft sample source (not inventing a new app)'
    if [[ ! -d "$upstream/.git" ]]; then
      git clone --depth 1 https://github.com/Azure-Samples/azure-voting-app-redis.git "$upstream"
    fi
    [[ -f "$upstream/azure-vote/main.py" ]] || fail 'Expected official sample main.py not found; upstream changed.'
    [[ -d "$upstream/azure-vote/templates" ]] || fail 'Expected official sample templates not found; upstream changed.'
    mkdir -p "$d/vendor/azure-vote" "$d/docs"
    cp -a "$upstream/azure-vote/." "$d/vendor/azure-vote/"
    git -C "$upstream" rev-parse HEAD > "$d/docs/upstream-commit.txt"
    cp "$upstream/LICENSE" "$d/docs/UPSTREAM-LICENSE.txt" || fail 'Expected MIT licence not found'
  fi
  if [[ ! -f "$d/.github/workflows/01-ci.yml" || ! -f "$d/.github/workflows/02-release.yml" ]]; then
    [[ ! -f "$d/.github/workflows/01-ci.yml" && ! -f "$d/.github/workflows/02-release.yml" ]] || fail 'Some workflows already exist; review manually (no overwriting).'
    bash "$ROOT/scripts/04-copy-to-repo.sh" "$d"
  else
    log 'CI/CD workflows already present. Leaving them untouched.'
  fi
  (cd "$d" && python3 scripts/validate_repo.py)
  grep -q 'FROM python:3.12-slim' "$d/Dockerfile" || fail 'Old or incompatible Dockerfile detected. Review and upgrade before CI.'
  log 'Proposed local Git changes:'
  git -C "$d" status --short | head -60
  if [[ -z "$(git -C "$d" status --porcelain)" ]]; then log 'Nothing to commit'; return; fi
  confirm "Review changed files above. Commit and push to $REPO?"
  git -C "$d" add Dockerfile .dockerignore .gitignore .github/ scripts/validate_repo.py docs/ vendor/
  git -C "$d" diff --cached --quiet && { log 'No staged changes'; return; }
  git -C "$d" commit -m 'CloudGuard 360 Phase04: auditable CI CD and official Azure voting sample'
  [[ "$(git -C "$d" branch --show-current)" == main ]] || fail 'Expected main branch. Resolve safely before pushing.'
  git -C "$d" push -u origin main
  log 'Code pushed. GitHub Actions should run CI automatically.'
}
last_run_id() { gh run list -R "$REPO" -w "$1" -c "$2" -L 1 --json databaseId --jq '(.[0].databaseId // "")' 2>/dev/null || true; }
wait_run() {
  local wf="$1" sha="$2" previous="${3:-}" id="" retry
  for retry in $(seq 1 24); do
    id="$(gh run list -R "$REPO" -w "$wf" -c "$sha" -L 4 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
    [[ "$id" =~ ^[0-9]+$ && "$id" != "$previous" ]] && break
    sleep 5
  done
  [[ "$id" =~ ^[0-9]+$ ]] || fail "No GitHub run found for $wf at commit $sha. Check Actions tab."
  log "Watching run ID $id for $wf"
  gh run watch "$id" -R "$REPO" --exit-status || fail "Workflow failed: $wf; investigate at https://github.com/$REPO/actions/runs/$id"
  printf 'PASS: %s https://github.com/%s/actions/runs/%s\n' "$wf" "$REPO" "$id"
}
ci() {
  check_local; read_repo
  local sha before; sha="$(get_sha)"
  [[ "$(git -C "$(repo_dir)" status --porcelain)" == '' ]] || fail 'Uncommitted changes in repository. Commit before CI.'
  before="$(last_run_id 01-ci.yml "$sha")"
  gh workflow run 01-ci.yml -R "$REPO" -r main || fail 'Could not trigger CI; verify Actions permissions.'
  wait_run 01-ci.yml "$sha" "$before"
}
oidc() {
  check_local; read_azure
  [[ -d "$TF_DIR" ]] || fail 'Missing Terraform OIDC files'
  log 'Checking Microsoft.ManagedIdentity registration'
  local status; status="$(az provider show --namespace Microsoft.ManagedIdentity --query registrationState -o tsv)"
  [[ "$status" == Registered ]] || fail "Microsoft.ManagedIdentity status=$status; register it only if authorized."
  local tfvars="$TF_DIR/terraform.tfvars"
  if [[ ! -f "$tfvars" ]]; then
    cp "$TF_DIR/terraform.tfvars.example" "$tfvars"
    python3 - "$tfvars" "$REPO" <<'PY_SETUP'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text().replace('YOUR_ACCOUNT/cloudguard360-phase04',sys.argv[2]);s=s.replace('enable_deployment_role  = false','enable_deployment_role  = true'); p.write_text(s)
PY_SETUP
  fi
  # Check the root's current settings to prevent accidental OIDC trust for a different repo.
  grep -Fq "\"$REPO\"" "$tfvars" || fail 'Terraform github_repository differs from --repo. Review terraform.tfvars.'
  log 'Terraform identity state stored separately from Phase 01/02/03.'
  (cd "$TF_DIR" && terraform init -input=false && terraform validate && terraform plan -out=phase04-oidc.tfplan -input=false && terraform show -json phase04-oidc.tfplan | python3 "$ROOT/scripts/05-check-oidc-plan.py")
  log 'Review the plan and confirm that role scope is the EXISTING Container App.'
  (cd "$TF_DIR" && terraform show -no-color phase04-oidc.tfplan | grep -E 'will be created|scope |subject |Plan:' || true)
  confirm 'Create/update this OIDC identity, trust and restricted Container App role via Terraform?'
  (cd "$TF_DIR" && terraform apply -input=false phase04-oidc.tfplan)
  log 'Creating/using GitHub deployment Environment for scoped secrets.'
  gh api -X PUT "repos/$REPO/environments/$GITHUB_ENV" >/dev/null || fail 'Could not create GitHub environment; check repository administration rights.'
  local client tenant sub
  client="$(cd "$TF_DIR" && terraform output -raw github_azure_client_id)"
  tenant="$(az account show --query tenantId -o tsv)"
  sub="$(az account show --query id -o tsv)"
  printf '%s' "$client" | gh secret set AZURE_CLIENT_ID -e "$GITHUB_ENV" -R "$REPO"
  printf '%s' "$tenant" | gh secret set AZURE_TENANT_ID -e "$GITHUB_ENV" -R "$REPO"
  printf '%s' "$sub" | gh secret set AZURE_SUBSCRIPTION_ID -e "$GITHUB_ENV" -R "$REPO"
  log 'GitHub Environment secrets populated; no client secret was created.'
  log 'Protect the Environment with reviewers and main-branch restrictions, if your GitHub plan supports it.'
}
publish() {
  check_local; read_repo
  local sha before; sha="$(get_sha)"
  confirm 'Trigger GHCR image publishing workflow (no Azure deployment)?'
  before="$(last_run_id 02-release.yml "$sha")"
  gh workflow run 02-release.yml -R "$REPO" -r main -f deploy_to_azure=false
  wait_run 02-release.yml "$sha" "$before"
  log "Expected GHCR image: ghcr.io/${REPO%%/*}/cloudguard360-vote:$sha (owner normalized lowercase)."
}
deploy() {
  check_local; read_repo; read_azure
  local id image previous_redis before
  id="$(get_sha)"
  image="ghcr.io/${REPO%%/*}/cloudguard360-vote:$id"
  image="$(printf '%s' "$image" | tr '[:upper:]' '[:lower:]')"
  previous_redis="$(get_redis)"
  log "Planned frontend image: $image"
  log "Redis image to preserve: $previous_redis"
  log 'PREREQUISITE: GHCR package visibility set to PUBLIC in GitHub; package is a training demo.'
  log 'PREREQUISITE: OIDC identity and GitHub environment secrets configured and allowed to deploy.'
  log 'IMPORTANT: Container Apps Contributor can delete the scoped app. Manual approval is required.'
  confirm 'I verified public GHCR, OIDC credentials and reviewed the exact image. Deploy to existing Azure Container App?'
  before="$(last_run_id 02-release.yml "$id")"
  gh workflow run 02-release.yml -R "$REPO" -r main -f deploy_to_azure=true
  wait_run 02-release.yml "$id" "$before"
  read_azure
  local current;current="$(get_image)"
  [[ "$current" == "$image" ]] || fail "Azure current frontend differs: $current"
  [[ "$(get_redis)" == "$previous_redis" ]] || fail 'Redis sidecar image changed! Investigate.'
  log 'PASS: frontend image updated and redis sidecar image unchanged.'
}
verify() {
  check_local; read_azure
  local dir="$WORKSPACE/phase04-evidence/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$dir"
  az account show --query '{Name:name,State:state}' -o json > "$dir/azure-context.json"
  az containerapp show -g "$AZ_RG" -n "$AZ_APP" --query 'properties.template.containers[].{Name:name,Image:image}' -o json > "$dir/container-images.json"
  az containerapp show -g "$AZ_RG" -n "$AZ_APP" --query 'properties.latestRevisionName' -o tsv > "$dir/current-revision.txt"
  gh run list -R "$REPO" -L 10 --json databaseId,headSha,conclusion,workflowName,url > "$dir/github-runs.json"
  local url http=""; url="$(az containerapp show -g "$AZ_RG" -n "$AZ_APP" --query properties.configuration.ingress.fqdn -o tsv)"
  if [[ -n "$url" ]]; then
    http="$(curl -L -sS -o /dev/null --max-time 30 -w '%{http_code}' "https://$url/" || true)"
  fi
  printf 'HTTP_CHECK=%s\n' "$http" > "$dir/http-status.txt"
  local phase3="$WORKSPACE/CloudGuard360_Phase03_Docker_Application/terraform"
  if [[ -d "$phase3" ]]; then
    (cd "$phase3" && terraform plan -no-color -detailed-exitcode -input=false > "$dir/phase03-drift-review.txt" 2>&1) || rc=$?
    printf 'TERRAFORM_PHASE03_EXIT_CODE=%s\n' "${rc:-0}" > "$dir/phase03-drift-exit.txt"
  else
    printf 'Phase 03 Terraform not found at usual folder. Manual reconciliation required.\n' > "$dir/phase03-drift-review.txt"
  fi
  local frontend redis
  frontend="$(get_image)"; redis="$(get_redis)"
  cat > "$dir/PHASE04_FINAL_REPORT.md" <<EOF_REPORT
# CloudGuard 360 — Phase 04 Finalisation Evidence

- Date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Repository: https://github.com/$REPO
- Azure Container App: $AZ_RG / $AZ_APP
- Frontend image: $frontend
- Redis image (must remain unchanged): $redis
- HTTPS check: $http
- GitHub run details: github-runs.json
- Terraform Phase 03 drift report: phase03-drift-review.txt

## Closure criteria (operator review)
- [ ] Latest CI workflow completed successfully
- [ ] Secret/IaC checks passed
- [ ] SBOM artifact exists in GitHub Actions
- [ ] High/critical image findings reviewed (image vulnerability scan is report-only)
- [ ] GHCR image is appropriately visible and published by commit SHA
- [ ] OIDC login and scoped permissions passed if Azure deploy enabled
- [ ] Redis image unchanged
- [ ] Endpoint returned HTTP 200 (or documented failure)
- [ ] Phase 03 Terraform drift addressed before next apply
- [ ] Azure costs and resource usage reviewed

Do not mark the Phase 04 project complete solely on the basis of this report.
EOF_REPORT
  log "Evidence saved: $dir"
  cat "$dir/http-status.txt"
  [[ "$http" == '200' ]] || log 'WARNING: HTTP test did not return 200. Review deployment logs.'
  log 'Review the evidence checklist and Terraform drift file before signing off.'
}
case "$COMMAND" in
  doctor) doctor;;
  prepare) prepare;;
  ci) ci;;
  oidc) oidc;;
  publish) publish;;
  deploy) deploy;;
  verify) verify;;
  all)
    doctor; prepare; ci; oidc; publish
    log 'Pause: Set the GHCR demo package to PUBLIC in GitHub Packages (operator action).'
    confirm 'GHCR is public and GitHub Environment protection rules are reviewed. Proceed with Azure deploy?'
    deploy; verify;;
esac
