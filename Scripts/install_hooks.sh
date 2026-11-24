#!/bin/bash
# Installs the pre-push hook (tests + security check before every push).
set -e
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
install -m 755 "$root/Scripts/pre-push" "$root/.git/hooks/pre-push"
echo "pre-push hook installed"
