#!/bin/bash
for filename in "$@"; do
    if [[ "${filename}" =~ values.ya?ml$ ]] || [[ "${filename}" =~ secrets?.ya?ml$ ]] || [[ "${filename}" =~ .env$ ]]; then
        # Skip files that are already SOPS-encrypted: sops -e -i refuses files
        # containing a top-level 'sops' metadata block (YAML) or '#sops'
        # comments (dotenv), and double-encrypting would corrupt them anyway.
        # Makes the hook idempotent for encrypted-at-rest working trees.
        if grep -qE '^(sops:|#sops)' "${filename}" 2>/dev/null; then
            continue
        fi
        sops -e -i "${filename}"
        git add "${filename}"
    fi
done
