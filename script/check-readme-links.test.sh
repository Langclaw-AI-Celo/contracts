#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
checker="$script_dir/check-readme-links.sh"
test_root="$(mktemp -d)"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

repo="$test_root/repo"
mkdir -p "$repo/script"
cp "$checker" "$repo/script/check-readme-links.sh"
git -C "$repo" init --quiet

printf 'Outside fixture.\n' > "$test_root/outside.md"
printf '[Outside](../outside.md)\n' > "$repo/README.md"

if bash "$repo/script/check-readme-links.sh" >"$test_root/stdout" 2>"$test_root/stderr"; then
  printf 'expected a link resolving outside the repository to fail\n' >&2
  exit 1
fi

grep -Fq \
  'README link target resolves outside repository: ../outside.md' \
  "$test_root/stderr"

printf 'Validated README link checker regressions.\n'
