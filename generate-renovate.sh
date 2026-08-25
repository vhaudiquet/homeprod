#!/bin/bash
set -euo pipefail

# Regenerate renovate.json from the on-disk docker/kubernetes layout.

tmpfile=$(mktemp)

# Make sure to cleanup our temp file on any kind of exit
trap 'rm -f "$tmpfile"' EXIT

python3 - "$tmpfile" <<'PY'
import json
import os
import subprocess
import sys


def discover(root, filename):
    """Sorted directories under root containing filename."""
    out = subprocess.run(
        ["find", root, "-name", filename],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return sorted(
        {os.path.dirname(line).removeprefix("./") for line in out.splitlines() if line}
    )


def file_match(directory, filename):
    return "^%s/%s$" % (directory, filename.replace(".", "[.]"))


docker_dirs = discover("docker", "docker-compose.yml")
helm_dirs = discover("kubernetes", "release.yaml")

renovate = {
    "$schema": "https://docs.renovatebot.com/renovate-schema.json",
    "schedule": ["every weekend"],
    "prConcurrentLimit": 15,
    "enabledManagers": ["docker-compose", "helm-requirements", "helm-values"],
    "packageRules": [
        {
            "description": "docker-compose updates",
            "matchManagers": ["docker-compose"],
            "commitMessage": "docker(deps): bump {{{depName}}} in {{{packageFile}}}",
        },
        {
            "description": "helm updates",
            "matchManagers": ["helm-requirements", "helm-values"],
            "commitMessage": "kube(deps): bump {{{depName}}} in {{{packageFile}}}",
        },
    ],
    "docker-compose": {
        "fileMatch": [file_match(d, "docker-compose.yml") for d in docker_dirs]
    },
    "helm-requirements": {"fileMatch": [file_match(d, "Chart.yaml") for d in helm_dirs]},
    "helm-values": {"fileMatch": [file_match(d, "values.yaml") for d in helm_dirs]},
}

with open(sys.argv[1], "w") as f:
    json.dump(renovate, f, indent=2)
    f.write("\n")
PY

# Overwrite file on change
if ! [ -f renovate.json ] || ! cmp -s "$tmpfile" renovate.json; then
  mv "$tmpfile" renovate.json
  echo "Updated renovate.json!"
  git add "renovate.json"
else
  echo "No changes to renovate.json."
fi
