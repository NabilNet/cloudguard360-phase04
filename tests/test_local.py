#!/usr/bin/env python3
from pathlib import Path
import ast, json, subprocess, sys, re
root=Path(__file__).resolve().parents[1]
files=['README.md','index.html','Dockerfile','automation/finalize.sh','.github/workflows/01-ci.yml','.github/workflows/02-release.yml','terraform/oidc-identity/main.tf','scripts/05-check-oidc-plan.py']
assert all((root/f).is_file() for f in files)
subprocess.run(['bash','-n',str(root/'automation/finalize.sh')], check=True)
subprocess.run(['bash','-n',str(root/'scripts/04-copy-to-repo.sh')], check=True)
ast.parse((root/'scripts/validate_repo.py').read_text())
assert 'FROM mcr.microsoft.com/azuredocs/azure-vote-front:v1' not in (root/'Dockerfile').read_text()
assert 'vote-frontend' in (root/'.github/workflows/02-release.yml').read_text()
assert 'docker/build-push-action' in (root/'.github/workflows/01-ci.yml').read_text()
assert 'container-name vote-frontend' in (root/'.github/workflows/02-release.yml').read_text()
assert 'webStorage' not in (root/'index.html').read_text()
assert all(f in (root/'index.html').read_text() for f in ['GitHub','OIDC','PHASE 04'])
print('PASS: structure, Bash syntax, Python syntax and essential safety checks')
