#!/usr/bin/env python3
"""Validate the GitHub deployment repository shape without accessing Azure."""
from pathlib import Path
import sys
root=Path(__file__).resolve().parent.parent
required=['Dockerfile','.github/workflows/01-ci.yml','.github/workflows/02-release.yml','vendor/azure-vote/main.py','vendor/azure-vote/templates']
missing=[x for x in required if not (root/x).exists()]
if missing:
    print('FAIL: required files missing:',', '.join(missing)); sys.exit(1)
text=(root/'Dockerfile').read_text()
if 'mcr.microsoft.com/azuredocs/azure-vote-front:v1' in text:
    print('FAIL: retired base image is still configured');sys.exit(1)
print('PASS: official Azure Vote source and CI/CD files are present')
