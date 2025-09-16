#!/bin/bash

# Create .swarmcd directory if needed
if [ ! -d .swarmcd ]; then
    mkdir -p .swarmcd
fi

tmpfile=$(mktemp)

# Make sure to cleanup our temp file on any kind of exit
trap 'rm -f "$tmpfile"' EXIT

# Find and sort all docker-compose.yml directories
find docker -name 'docker-compose.yml' -print0 \
  | xargs -0 -n1 dirname \
  | sed 's|^\./||' \
  | sort \
  | while read -r dir; do
      file="$dir/docker-compose.yml"
      name=$(basename "$dir")
      echo -e "$name:\n  repo: homeprod\n  branch: main\n  compose_file: $file\n" >> "$tmpfile"
    done

# Overwrite file on change
if ! [ -f .swarmcd/stacks.yaml ] || ! cmp -s "$tmpfile" .swarmcd/stacks.yaml; then
  mv "$tmpfile" .swarmcd/stacks.yaml
  echo "Updated .swarmcd/stacks.yaml!"
else
  echo "No changes to .swarmcd/stacks.yaml."
fi