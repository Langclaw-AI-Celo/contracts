#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
readme="$repo_root/README.md"
missing_count=0

while IFS= read -r markdown_link; do
  target="${markdown_link#](}"
  target="${target%)}"

  case "$target" in
    http://*|https://*|mailto:*|'#'*) continue ;;
  esac

  target="${target%%#*}"
  [[ -n "$target" ]] || continue

  if [[ ! -e "$repo_root/$target" ]]; then
    printf 'README link target does not exist: %s\n' "$target" >&2
    ((missing_count += 1))
  fi
done < <(grep -oE '\]\([^)]+\)' "$readme" || true)

if ((missing_count > 0)); then
  printf 'README link check failed with %d missing target(s).\n' "$missing_count" >&2
  exit 1
fi

printf 'Validated local README link targets.\n'
