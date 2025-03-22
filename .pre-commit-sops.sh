#!/bin/bash
for filename in "$@"; do
    if [[ "${filename}" =~ values.ya?ml$ ]] || [[ "${filename}" =~ secrets?.ya?ml$ ]]; then
        sops -e -i "${filename}"
        git add "${filename}"
    fi
done
