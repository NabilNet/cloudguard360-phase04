# CloudGuard 360 — Phase 04 Automated Finalisation

**Scope:** GitHub Actions CI/CD → security scans → Docker build → CycloneDX SBOM → GitHub Container Registry → Microsoft Entra OIDC → existing Azure Container App → evidence.

**Status:** Toolkit tested locally for syntax, file structure, safety checks and packaging. Actual Azure/GitHub deployment has **not** been performed from this environment.

## Critical change compared with the earlier Phase 04 ZIP
The original package wrapped `mcr.microsoft.com/azuredocs/azure-vote-front:v1`. Microsoft has confirmed that image was removed. This revised toolkit **snapshots the source code of the existing Microsoft Azure Voting App** into your repository and builds it on `python:3.12-slim` with Flask, Redis client and Gunicorn. This remains a prebuilt *application project* (no new app to design), but we do **not** claim production hardening. CI must actually prove Docker builds and the app starts.

## Requirements
- Phases 01–03 existing, especially `rg-cg360-app/ca-cg360-voting` with **both** `vote-frontend` and `redis` containers.
- Cloud Shell **Bash**, persistent `~/clouddrive`, Azure CLI authenticated, Terraform and Git available.
- GitHub CLI `gh` installed and authenticated; GitHub repo `OWNER/cloudguard360-phase04` already created (empty is preferred).
- Azure permission to create a user-assigned identity, federated credential and **scope-limited** role assignment on the existing Container App. Without `roleAssignments/write`, complete CI and GHCR first, then have an authorised admin configure OIDC/RBAC.
- Credit and actual Container Apps costs reviewed; GitHub Actions billing depends on repository visibility/plan.

## Download, upload and extract — exact clicks
1. Download **CloudGuard360_Phase04_Automated_Finalization.zip** in ChatGPT to your computer.
2. Open https://portal.azure.com → Cloud Shell icon in the top toolbar → **Bash**.
3. Choose **Manage files → Upload** and select the downloaded ZIP. Cloud Shell normally puts it in `~/`.
4. In Cloud Shell, run:

```bash
mountpoint -q "$HOME/clouddrive" && echo 'PERSISTENT STORAGE OK'
mkdir -p "$HOME/clouddrive/cloudguard360"
unzip -n "$HOME/CloudGuard360_Phase04_Automated_Finalization.zip" -d "$HOME/clouddrive/cloudguard360"
cd "$HOME/clouddrive/cloudguard360/CloudGuard360_Phase04_Automated_Finalization"
ls -la
```

## Create the GitHub repository — exact clicks
1. Open https://github.com/new.
2. Set name `cloudguard360-phase04`; use Public **only** for synthetic demo code.
3. Create repo under your own account and note `OWNER/REPO` with exact **case**. Prefer empty repo without starter README.
4. Sign into GitHub CLI: `gh auth login`. Confirm with `gh auth status`. Do not put tokens into Terraform or this chat.

## Run the whole process (with checkpoints)

```bash
cd "$HOME/clouddrive/cloudguard360/CloudGuard360_Phase04_Automated_Finalization"
bash automation/finalize.sh all --repo OWNER/cloudguard360-phase04
```

The script performs the stages below **in order**, pauses for explicit approval of side effects and fails closed:

1. **Doctor** — verifies Azure account, Cloud Shell persistence, GitHub CLI, target repo and the existing frontend/Redis containers.
2. **Prepare** — clones your GitHub repo; clones Microsoft's existing Azure Vote sample and snapshots `azure-vote/` into `vendor/`; installs the improved Dockerfile and Actions workflows; prompts before Git commit/push.
3. **CI** — triggers `.github/workflows/01-ci.yml`; validates layout, runs blocking secret/IaC scan, builds a Docker image and publishes a CycloneDX SBOM artifact; waits for a successful GitHub run.
4. **OIDC** — plans a **separate Terraform root** (user-assigned identity, GitHub federated identity and one role scoped to the *existing* Container App). Safety checker runs; `terraform apply` needs explicit confirmation. The script then creates GitHub Environment `cloudguard360-lab` and stores the client/tenant/subscription IDs as **Environment secrets** using `gh secret set`.
5. **Publish** — triggers GHCR publish **without touching Azure**; tags the image with full commit SHA.
6. **Human GHCR gate** — GitHub profile → **Packages → cloudguard360-vote → Package settings → Change visibility → Public**, for this synthetic demo only. Exact UI can differ. Confirm it is public; do not expose other packages or any secrets.
7. **Deploy** — explicitly approve the release; GitHub Actions uses OIDC, updates `vote-frontend` only and performs HTTP smoke test; redis image verified unchanged.
8. **Verify** — snapshots Azure images, revision name, latest GitHub runs, HTTPS result, Phase 03 Terraform drift preview into persistent Cloud Shell evidence. Final report contains checkboxes requiring *actual* confirmation.

### Run one step at a time if an error occurs

```bash
bash automation/finalize.sh doctor  --repo OWNER/cloudguard360-phase04
bash automation/finalize.sh prepare --repo OWNER/cloudguard360-phase04
bash automation/finalize.sh ci      --repo OWNER/cloudguard360-phase04
bash automation/finalize.sh oidc    --repo OWNER/cloudguard360-phase04
bash automation/finalize.sh publish --repo OWNER/cloudguard360-phase04
bash automation/finalize.sh deploy  --repo OWNER/cloudguard360-phase04
bash automation/finalize.sh verify  --repo OWNER/cloudguard360-phase04
```

## GitHub Environment security — required review
After `oidc` stage, open your repository → **Settings → Environments → cloudguard360-lab**. Inspect the environment secrets and, when supported, configure required reviewers and restrict allowed deployment branches to `main`. Without supported required reviewers, **the script's terminal confirmation is a local safety gate only**; it does not prevent someone with sufficient GitHub permissions from running the deployment workflow independently.

The user-assigned managed identity is federated to the **exact** repository/environment token subject `repo:OWNER/REPO:environment:cloudguard360-lab`, case-sensitive. An Entra application client secret is **not** needed. The built-in `Container Apps Contributor` can **delete** the scoped Container App, so it must be scoped to the specific app, not to the entire subscription.

## Image, security and accuracy notes
- The original Microsoft sample is a **demo**, not hardened financial software.
- We build from **existing Microsoft sample source**, not from the removed MCR image.
- App build compatibility is verified by CI, **not assumed**. If GitHub CI fails, stop and read logs; do not disable secret/IaC scanning.
- Trivy image vulnerabilities are reported but do not block the lab by default; **this does not constitute a production quality gate**.
- GitHub Container Registry is often private by default. The publication job and the actual Azure deployment are deliberately separate.
- The Azure Container App remains managed by **Phase 03 Terraform**. When GitHub deploys a different image, Phase 03 `terraform plan` will detect configuration drift. Update its `frontend_image` variable to the exact GHCR image and *review* the plan; do not blindly `terraform apply` or delete resources.
- Network and Redis data remain unchanged by the script. Redis is ephemeral, so data can disappear on a restart.
- During final verification, the code reads Azure resource metadata and makes an HTTPS request; it does not delete anything.

## Recovery decisions
| Error | What to do |
|---|---|
| `gh: command not found` | Install GitHub CLI using https://cli.github.com/manual/installation, then `gh auth login` |
| Cloud Shell `clouddrive` not mounted | Reconfigure mounted storage; no Terraform state should be created in an ephemeral session |
| Existing GitHub workflows present | Compare them manually; automation will not overwrite existing workflows |
| Docker build error | Inspect GitHub Actions logs; verify upstream source snapshot, `main.py`, `templates` and Python compatibility |
| Secret/IaC scan blocks | Correct the finding; do not suppress the security gate |
| Microsoft.ManagedIdentity not registered | Register with authorised Azure role if available; repeat preflight |
| RBAC assignment forbidden | Request `roleAssignments/write` at the Container App scope; stop OIDC deploy path |
| OIDC AADSTS700213 | Inspect exact GitHub repo case, environment and federated token subject |
| GHCR 401/403 | Check visibility of **this** demo package and registered `ghcr.io` endpoint |
| Azure update fails | Review Container App revision and logs; do not rerun repeatedly or delete Phase 03 RG |
| Terraform drift appears | Review and reconcile Phase 03 `frontend_image` and any registry config; no blind apply |
| No trial credits | Complete GitHub CI/GHCR only, stop Azure deployment |

## Official references
- Azure GitHub OIDC: https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect
- Container Apps + GHCR: https://learn.microsoft.com/en-us/azure/container-apps/github-actions
- Azure RBAC Container Apps Contributor: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/containers
- GitHub CLI workflow: https://cli.github.com/manual/gh_workflow_run
- GitHub CLI secrets: https://cli.github.com/manual/gh_secret_set
- Microsoft Azure Voting App: https://github.com/Azure-Samples/azure-voting-app-redis
