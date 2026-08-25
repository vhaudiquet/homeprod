#!/bin/sh
#
# Renovate runner bootstrap / entrypoint.
#
# Renovate has NO preUpgradeTasks hook (schema only exposes postUpgradeTasks),
# and postUpgradeTasks runs AFTER Renovate has already edited the dependency
# files. That matters because these `values.yaml` files are SOPS documents:
# the `sops:` metadata block carries a `mac:` that authenticates the whole
# file, so ANY edit (even to a plaintext `image.tag`) invalidates it and makes
# `sops -d` fail with a MAC/data-integrity error. You cannot decrypt the file
# *after* Renovate has touched it.
#
# So we decrypt BEFORE Renovate extracts any dependency info:
#   1. clone the repo into the exact checkout path Renovate will reuse
#   2. `sops -d -i` every values.yaml in place (plaintext, no `sops:` block)
#   3. local-commit the decrypted working tree onto the local base branch
#      (NOT pushed -> encrypted blobs stay in remote git, no plaintext secrets
#      ever leave the runner)
#   4. run Renovate. It now reads plaintext tags and edits plaintext files.
#      postUpgradeTasks only needs `sops -e -i` (encrypt) to rebuild a valid
#      SOPS document containing the bumped tag.
#
# The local commit is important: step 3 makes `git checkout <base>` restore the
# decrypted content from the LOCAL branch rather than the encrypted remote blob,
# so Renovate's branch operations don't silently resurrect the encrypted file
# and re-introduce the MAC-mismatch problem.

set -eu

# SOPS PGP private key must be available to decrypt AND to re-encrypt.
if [ -f /etc/renovate/gpg/git-renovate-gpg.key ]; then
    gpg --batch --import /etc/renovate/gpg/git-renovate-gpg.key || true
fi

# Renovate stores repos under $RENOVATE_BASE_DIR/repos/<platform>/<org>/<repo>.
BASE_DIR="${RENOVATE_BASE_DIR:-/tmp/renovate}"
REPO_DIR="${BASE_DIR}/repos/github/vhaudiquet/homeprod"
REPO_URL="https://x-access-token:${RENOVATE_TOKEN}@github.com/vhaudiquet/homeprod.git"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

mkdir -p "$(dirname "$REPO_DIR")"

# 1. Ensure a fresh, valid checkout of the base branch exists.
if [ -d "${REPO_DIR}/.git" ]; then
    git -C "$REPO_DIR" fetch --all --prune
    git -C "$REPO_DIR" -c advice.detachedHead=false checkout "$DEFAULT_BRANCH" \
        && git -C "$REPO_DIR" reset --hard "origin/${DEFAULT_BRANCH}"
else
    git clone --no-tags --single-branch --branch "$DEFAULT_BRANCH" "$REPO_URL" "$REPO_DIR"
    git -C "$REPO_DIR" config user.name  renovate
    git -C "$REPO_DIR" config user.email renovate@localhost
fi

# 2. Decrypt every values.yaml still carrying SOPS metadata (in-place).
#    Skips files that are already plaintext (no `sops:` block) so the bootstrap
#    is idempotent across re-runs.
find "$REPO_DIR" -name 'values.yaml' -type f \
    -exec grep -l -m1 '^sops:' {} + 2>/dev/null \
    | xargs -r -n1 sops -d -i

# 3. Local commit (never pushed) so Renovate's checkout of the base branch
#    keeps working on decrypted files.
git -C "$REPO_DIR" add -A
if ! git -C "$REPO_DIR" diff --cached --quiet; then
    git -C "$REPO_DIR" commit -m "chore(renovate): decrypt values for update (local bootstrap)" --quiet
fi

# 4. Run Renovate itself.
exec renovate "$@"
