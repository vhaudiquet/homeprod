#!/bin/bash
readarray f < <(git diff-tree --no-commit-id --name-only HEAD -r)
for filepath in "${f[@]}"; do
    filepath=$(echo "${filepath}" | tr -d '\n')
    filename=$(basename ${filepath})
    if [[ "${filename}" =~ values.ya?ml$ ]] || [[ "${filename}" =~ secrets?.ya?ml$ ]]; then
        sops -d -i "${filepath}"
    fi
done
