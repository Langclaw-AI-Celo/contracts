#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'vendored dependency check failed: %s\n' "$*" >&2
  exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
manifest_path="vendor.lock"

[[ ! -e "$repo_root/.gitmodules" && ! -L "$repo_root/.gitmodules" ]] || fail ".gitmodules is incompatible with vendored dependencies"
[[ ! -e "$repo_root/foundry.lock" && ! -L "$repo_root/foundry.lock" ]] || fail "foundry.lock is stale submodule metadata"

if grep -Fq 'git submodule update --init' "$repo_root/README.md"; then
  fail "README.md still instructs users to initialize submodules"
fi

dependabot="$repo_root/.github/dependabot.yml"
if [[ -f "$dependabot" ]] && grep -Eq "^[[:space:]]*package-ecosystem:[[:space:]]*['\"]?gitsubmodule['\"]?[[:space:]]*$" "$dependabot"; then
  fail "Dependabot still configures the gitsubmodule ecosystem"
fi

candidate_root="$(git -C "$repo_root" write-tree)" || fail "cannot write the staged candidate tree"
git -C "$repo_root" diff --quiet -- "$manifest_path" || fail "vendor.lock has unstaged changes"
manifest_entry="$(git -C "$repo_root" ls-tree "$candidate_root" -- "$manifest_path")"
[[ -n "$manifest_entry" ]] || fail "vendor.lock is missing from the staged candidate"
read -r manifest_mode manifest_type manifest_oid manifest_listed_path <<< "$manifest_entry"
[[ "$manifest_mode" == 100644 && "$manifest_type" == blob && "$manifest_listed_path" == "$manifest_path" ]] || fail "vendor.lock is not a regular staged file"

dependency_names=()
dependency_paths=()
row_count=0
while IFS= read -r row || [[ -n "$row" ]]; do
  row="${row%$'\r'}"
  case "$row" in
    ''|'#'*) continue ;;
  esac

  delimiters="${row//[^|]/}"
  [[ ${#delimiters} -eq 4 ]] || fail "malformed vendor.lock row: $row"
  IFS='|' read -r name path package_version upstream_revision tree_oid <<< "$row"
  [[ -n "$name" && -n "$path" && -n "$package_version" ]] || fail "vendor.lock contains an empty required field"
  [[ "$upstream_revision" =~ ^[0-9a-f]{40}$ ]] || fail "$name has an invalid upstream revision"
  [[ "$tree_oid" =~ ^[0-9a-f]{40}$ ]] || fail "$name has an invalid tree OID"
  [[ "$path" != /* && "$path" =~ ^[A-Za-z0-9._/-]+$ ]] || fail "$name has an unsafe path"
  case "/$path/" in
    *'/../'*|*'/./'*|*'//'*) fail "$name has an unsafe path" ;;
  esac
  case "$path" in
    lib/*) ;;
    *) fail "$name path must begin with lib/" ;;
  esac
  dependency_leaf="${path#lib/}"
  [[ -n "$dependency_leaf" && "$dependency_leaf" != */* ]] || fail "$name path must be a direct child of lib"

  for ((seen_index = 0; seen_index < row_count; seen_index += 1)); do
    [[ "${dependency_names[$seen_index]}" != "$name" ]] || fail "vendor.lock contains duplicate dependency name: $name"
    [[ "${dependency_paths[$seen_index]}" != "$path" ]] || fail "vendor.lock contains duplicate dependency path: $path"
  done
  dependency_names[$row_count]="$name"
  dependency_paths[$row_count]="$path"

  dependency_dir="$repo_root/$path"
  [[ -d "$dependency_dir" && ! -L "$dependency_dir" ]] || fail "$path is not a checked-out directory"
  if find "$dependency_dir" -name .git -print -quit | grep -q .; then
    fail "$path contains nested .git metadata"
  fi
  git -C "$repo_root" diff --quiet -- "$path" || fail "$path has unstaged tracked changes"
  if [[ -n "$(git -C "$repo_root" ls-files --others --exclude-standard -- "$path")" ]]; then
    fail "$path has untracked nonignored files"
  fi

  entry="$(git -C "$repo_root" ls-tree "$candidate_root" -- "$path")"
  [[ -n "$entry" ]] || fail "$path is not present in the staged candidate"
  read -r mode type listed_oid listed_path <<< "$entry"
  [[ "$mode" != 160000 ]] || fail "$path is a gitlink, not a vendored tree"
  [[ "$mode" == 040000 && "$type" == tree && "$listed_path" == "$path" ]] || fail "$path is not a regular staged tree"

  candidate_tree="$(git -C "$repo_root" rev-parse "${candidate_root}:$path")"
  [[ "$candidate_tree" == "$tree_oid" && "$listed_oid" == "$tree_oid" ]] || fail "$path staged tree OID does not match vendor.lock"

  package_json="$dependency_dir/package.json"
  [[ -f "$package_json" && ! -L "$package_json" ]] || fail "$path/package.json is missing"
  actual_version="$(sed -nE 's/^  "version"[[:space:]]*:[[:space:]]*"([^\"]+)"[[:space:]]*,?[[:space:]]*$/\1/p' "$package_json")"
  [[ -n "$actual_version" && "$actual_version" != *$'\n'* ]] || fail "$path/package.json has no unique top-level version"
  [[ "$actual_version" == "$package_version" ]] || fail "$path/package.json version does not match vendor.lock"

  ((row_count += 1))
done < <(git -C "$repo_root" cat-file blob "$manifest_oid")

((row_count > 0)) || fail "vendor.lock contains no dependency rows"

candidate_lib_tree="$(git -C "$repo_root" rev-parse "${candidate_root}:lib" 2>/dev/null)" || fail "lib is missing from the staged candidate"
[[ "$(git -C "$repo_root" cat-file -t "$candidate_lib_tree")" == tree ]] || fail "lib is not a regular staged tree"
while IFS= read -r -d '' candidate_lib_entry; do
  [[ "$candidate_lib_entry" == *$'\t'* ]] || fail "lib contains a malformed staged entry"
  entry_metadata="${candidate_lib_entry%%$'\t'*}"
  dependency_leaf="${candidate_lib_entry#*$'\t'}"
  read -r dependency_mode dependency_type dependency_oid dependency_extra <<< "$entry_metadata"
  [[ -z "${dependency_extra:-}" && "$dependency_mode" == 040000 && "$dependency_type" == tree ]] || fail "lib/$dependency_leaf is not a regular staged tree"

  dependency_listed=0
  for ((seen_index = 0; seen_index < row_count; seen_index += 1)); do
    if [[ "${dependency_paths[$seen_index]}" == "lib/$dependency_leaf" ]]; then
      dependency_listed=1
      break
    fi
  done
  ((dependency_listed == 1)) || fail "lib/$dependency_leaf is missing from vendor.lock"
done < <(git -C "$repo_root" ls-tree -z "$candidate_lib_tree")

printf 'Validated %d vendored dependencies.\n' "$row_count"
