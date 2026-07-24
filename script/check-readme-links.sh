#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
readme="$repo_root/README.md"
invalid_count=0

readme_without_fenced_code() {
  awk '
    function marker_run_length(value, marker, run_count) {
      if (marker == "") {
        return 0
      }

      run_count = 0
      while (substr(value, run_count + 1, 1) == marker) {
        run_count += 1
      }
      return run_count
    }

    {
      candidate = $0
      indent = 0
      while (indent < 3 && (substr(candidate, 1, 1) == " " || substr(candidate, 1, 1) == "\t")) {
        candidate = substr(candidate, 2)
        indent += 1
      }

      marker = substr(candidate, 1, 1)
      marker_length = marker_run_length(candidate, marker)

      if (!in_fence) {
        if ((marker == "`" || marker == "~") && marker_length >= 3 && !(marker == "`" && index(substr(candidate, marker_length + 1), "`") > 0)) {
          in_fence = 1
          fence_marker = marker
          fence_length = marker_length
          next
        }

        print
        next
      }

      remainder = substr(candidate, marker_length + 1)
      if (marker == fence_marker && marker_length >= fence_length && remainder ~ /^[ \t]*$/) {
        in_fence = 0
      }
    }
  ' "$readme"
}

mask_inline_code_spans() {
  awk '
    function backtick_run_length(value, start, run_count) {
      run_count = 0
      while (substr(value, start + run_count, 1) == "`") {
        run_count += 1
      }
      return run_count
    }

    function opening_is_escaped(value, start, slash_count, cursor) {
      slash_count = 0
      cursor = start - 1
      while (cursor > 0 && substr(value, cursor, 1) == "\\") {
        slash_count += 1
        cursor -= 1
      }
      return slash_count % 2 == 1
    }

    function has_matching_delimiter(value, start, delimiter_length, cursor, run_length) {
      cursor = start + delimiter_length
      while (cursor <= length(value)) {
        if (substr(value, cursor, 1) != "`") {
          cursor += 1
          continue
        }

        run_length = backtick_run_length(value, cursor)
        if (run_length == delimiter_length) {
          return 1
        }
        cursor += run_length
      }
      return 0
    }

    {
      contents = contents $0 ORS
    }

    END {
      output = ""
      in_code = 0
      delimiter_length = 0
      cursor = 1

      while (cursor <= length(contents)) {
        character = substr(contents, cursor, 1)
        if (character != "`") {
          output = output (in_code && character != "\n" ? " " : character)
          cursor += 1
          continue
        }

        run_length = backtick_run_length(contents, cursor)
        if (!in_code) {
          if (!opening_is_escaped(contents, cursor) &&
              has_matching_delimiter(contents, cursor, run_length)) {
            in_code = 1
            delimiter_length = run_length
            output = output sprintf("%*s", run_length, "")
          } else {
            output = output substr(contents, cursor, run_length)
          }
        } else {
          output = output sprintf("%*s", run_length, "")
          if (run_length == delimiter_length) {
            in_code = 0
            delimiter_length = 0
          }
        }
        cursor += run_length
      }

      printf "%s", output
    }
  '
}

visible_readme="$(mktemp)"
cleanup() {
  rm -f -- "$visible_readme"
}
trap cleanup EXIT
readme_without_fenced_code | mask_inline_code_spans > "$visible_readme"

readme_link_tokens() {
  while IFS= read -r markdown_link; do
    target="${markdown_link#](}"
    target="${target%)}"

    case "$target" in
      \<*)
        target="${target#<}"
        target="${target%%>*}"
        ;;
      *)
        target="${target%%[[:space:]]*}"
        ;;
    esac

    printf '](%s)\n' "$target"
  done < <(grep -oE '\]\([^)]+\)' "$visible_readme" || true)

  sed -nE \
    's/^[[:space:]]{0,3}\[[^]]+\]:[[:space:]]*(<[^>]+>|[^[:space:]]+).*/](\1)/p' \
    "$visible_readme"
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
