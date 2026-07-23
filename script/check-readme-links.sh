#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
readme="$repo_root/README.md"
invalid_count=0

readme_link_tokens() {
  grep -oE '\]\([^)]+\)' "$readme" || true
  sed -nE \
    's/^[[:space:]]{0,3}\[[^]]+\]:[[:space:]]*(<[^>]+>|[^[:space:]]+).*/](\1)/p' \
    "$readme"
}

while IFS= read -r markdown_link; do
  target="${markdown_link#](}"
  target="${target%)}"
  target="${target#<}"
  target="${target%>}"

  case "$target" in
    http://*|https://*|mailto:*|'#'*) continue ;;
  esac

  target="${target%%#*}"
  [[ -n "$target" ]] || continue

  if [[ ! -e "$repo_root/$target" ]]; then
    printf 'README link target does not exist: %s\n' "$target" >&2
    ((invalid_count += 1))
    continue
  fi

  resolved_target="$(realpath "$repo_root/$target")"
  case "$resolved_target" in
    "$repo_root"|"$repo_root"/*) ;;
    *)
      printf 'README link target resolves outside repository: %s\n' "$target" >&2
      ((invalid_count += 1))
      ;;
  esac
done < <(readme_link_tokens)

if ((invalid_count > 0)); then
  printf 'README link check failed with %d invalid target(s).\n' "$invalid_count" >&2
  exit 1
fi

printf 'Validated local README link targets.\n'
