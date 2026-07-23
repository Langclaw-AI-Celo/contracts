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

printf '[Guide][guide]\n\n[guide]: missing-guide.md\n' > "$repo/README.md"

if bash "$repo/script/check-readme-links.sh" >"$test_root/stdout" 2>"$test_root/stderr"; then
  printf 'expected a broken reference-style link target to fail\n' >&2
  exit 1
fi

grep -Fq \
  'README link target does not exist: missing-guide.md' \
  "$test_root/stderr"

printf '%s\n' \
  '```markdown' \
  '[Example](missing-example.md)' \
  '[Guide][guide]' \
  '[guide]: missing-fenced-guide.md' \
  '```' \
  '~~~~markdown' \
  '[Tilde example](missing-tilde-example.md)' \
  '~~~' \
  '[Still fenced](missing-after-short-close.md)' \
  '~~~~' \
  > "$repo/README.md"

if ! bash "$repo/script/check-readme-links.sh" >"$test_root/stdout" 2>"$test_root/stderr"; then
  printf 'expected links inside fenced code blocks to be ignored\n' >&2
  cat "$test_root/stderr" >&2
  exit 1
fi

printf 'Validated README link checker regressions.\n'
