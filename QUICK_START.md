# Phase 04 — Quick start (Cloud Shell Bash)

Open **Azure Portal → Cloud Shell → Bash → Manage files → Upload**, select the downloaded zip, then:

```bash
mountpoint -q "$HOME/clouddrive" || { echo "STOP: persistent drive missing"; exit 1; }
mkdir -p ~/clouddrive/cloudguard360
unzip -n ~/CloudGuard360_Phase04_Automated_Finalization.zip -d ~/clouddrive/cloudguard360
cd ~/clouddrive/cloudguard360/CloudGuard360_Phase04_Automated_Finalization
```

Create empty `cloudguard360-phase04` repo on GitHub; install/authenticate gh CLI.

```bash
bash automation/finalize.sh all --repo OWNER/cloudguard360-phase04
```

If blocked, rerun individual subcommands listed in `README.md`. Identity/role and deployment require manual approval; neither is performed blindly.
