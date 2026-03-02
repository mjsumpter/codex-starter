#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_src_root="$(cd "$script_dir/.." && pwd)"
repo_url="${CODEX_STARTER_REPO_URL:-https://github.com/Skarian/codex-starter}"
branch="${CODEX_STARTER_BRANCH:-main}"
archive_url="${repo_url}/archive/refs/heads/${branch}.tar.gz"
exclude_paths=("README.md" ".gitignore" "notes/" "scripts/" ".git/" "AGENTS.override.md")
tmp_dir=""
src_root=""
using_local_source=0

cleanup() {
  if [[ -n "$tmp_dir" && -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

if [[ -f "$local_src_root/AGENTS.md" && -d "$local_src_root/.agent" && -d "$local_src_root/scripts" ]]; then
  src_root="$local_src_root"
  using_local_source=1
else
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required." >&2
    exit 1
  fi

  if ! command -v tar >/dev/null 2>&1; then
    echo "Error: tar is required." >&2
    exit 1
  fi

  tmp_dir="$(mktemp -d)"
  curl -fsSL "$archive_url" -o "$tmp_dir/archive.tar.gz"
  tar -xzf "$tmp_dir/archive.tar.gz" -C "$tmp_dir"

  src_root="$(find "$tmp_dir" -maxdepth 1 -type d -name "codex-starter-*" -print -quit)"
  if [[ -z "$src_root" || ! -d "$src_root" ]]; then
    echo "Error: could not locate extracted repository." >&2
    exit 1
  fi
fi

mkdir -p .agent/execplans/active .agent/execplans/archive

should_skip() {
  local rel_path="$1"
  for excluded in "${exclude_paths[@]}"; do
    if [[ "$excluded" == */ ]]; then
      if [[ "$rel_path" == "$excluded"* ]]; then
        return 0
      fi
    elif [[ "$rel_path" == "$excluded" ]]; then
      return 0
    fi
  done
  return 1
}

confirm_overwrite() {
  local target="$1"
  printf "Overwrite %s? [y/N] " "$target"
  local reply=""
  if [[ -r /dev/tty ]]; then
    read -r reply </dev/tty
  else
    echo
    return 1
  fi
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

sync_file() {
  local rel_path="$1"
  local file="$2"

  if should_skip "$rel_path"; then
    return 0
  fi

  if [[ -e "$rel_path" ]]; then
    if ! confirm_overwrite "$rel_path"; then
      return 0
    fi
  else
    mkdir -p "$(dirname "$rel_path")"
  fi

  cp -p "$file" "$rel_path"
}

if [[ "$using_local_source" -eq 1 ]] && command -v git >/dev/null 2>&1 && git -C "$src_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r -d '' rel_path; do
    sync_file "$rel_path" "$src_root/$rel_path"
  done < <(git -C "$src_root" ls-files -z)
else
  while IFS= read -r -d '' file; do
    rel_path="${file#"$src_root"/}"
    sync_file "$rel_path" "$file"
  done < <(find "$src_root" -type f -print0)
fi

echo "Sync complete."
