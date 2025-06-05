#!/bin/bash

# Create .github directory if needed
if [ ! -d .github ]; then
    mkdir -p .github
fi

tmpfile=$(mktemp)

# Make sure to cleanup our temp file on any kind of exit
trap 'rm -f "$tmpfile"' EXIT

# dependabot.yml header
cat > "$tmpfile" <<'YAML'
version: 2
updates:
  - package-ecosystem: "docker-compose"
    schedule:
      interval: weekly
    directories:
YAML

# Find and sort all docker-compose.yml directories
find docker -name 'docker-compose.yml' -print0 \
  | xargs -0 -n1 dirname \
  | sed 's|^\./||' \
  | sort \
  | while read -r dir; do
      echo "      - \"/$dir\"" >> "$tmpfile"
    done

# Overwrite file on change
if ! [ -f .github/dependabot.yml ] || ! cmp -s "$tmpfile" .github/dependabot.yml; then
  mv "$tmpfile" .github/dependabot.yml
  echo "Updated .github/dependabot.yml!"
else
  echo "No changes to .github/dependabot.yml."
fi