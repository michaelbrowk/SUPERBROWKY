#!/usr/bin/env bash
# Shared, Bash 3.2-compatible helpers for the SUPERBROWKY runtime.

sb_bold() {
  printf '\033[1m%s\033[0m\n' "$1"
}

sb_ok() {
  printf '\033[0;32m✓ %s\033[0m\n' "$1"
}

sb_warn() {
  printf '\033[1;33m⚠ %s\033[0m\n' "$1" >&2
}

sb_error() {
  printf '\033[0;31m✗ %s\033[0m\n' "$1" >&2
}

sb_status() {
  printf 'STATUS: %s\n' "$1"
}

sb_lock_pin() {
  # $1=lock file, $2=key
  [ -f "$1" ] || return 0
  awk -F '=' -v wanted="$2" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $1 == wanted {
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$1"
}

sb_profile_selects() {
  # $1=requested profile, $2=manifest profile
  case "$1:$2" in
    core:core) return 0 ;;
    web-launch:core|web-launch:web-launch) return 0 ;;
    growth:core|growth:web-launch|growth:growth) return 0 ;;
    full:*) return 0 ;;
  esac
  return 1
}

sb_harness_home() {
  case "$1" in
    claude) printf '%s\n' "$CLAUDE_HOME" ;;
    codex) printf '%s\n' "$CODEX_HOME" ;;
    *) return 1 ;;
  esac
}

sb_skills_dir() {
  local harness_home
  harness_home="$(sb_harness_home "$1")" || return 1
  printf '%s/skills\n' "$harness_home"
}

sb_receipt_path() {
  # $1=state home, $2=harness, $3=name
  printf '%s/state/%s/%s.receipt.tsv\n' "$1" "$2" "$3"
}

sb_receipt_get() {
  # $1=receipt, $2=key
  [ -f "$1" ] || return 0
  awk -F '\t' -v wanted="$2" '
    $1 == wanted {
      sub(/^[^\t]*\t/, "")
      print
      exit
    }
  ' "$1"
}

sb_sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    sb_error "No SHA-256 tool found (need shasum, sha256sum, or openssl)."
    return 1
  fi
}

sb_validate_no_symlinks() {
  # Managed skill trees are copied and executed globally. Reject every symlink,
  # including a symlink used as the tree root, before reading or hashing files.
  local root="$1" links
  [ -d "$root" ] && [ ! -L "$root" ] || return 1
  links="$(find "$root" -type l -print)" || return 1
  [ -z "$links" ]
}

sb_safe_source_folder() {
  # Manifest folders use a deliberately small, portable relative-path subset.
  # "." means the repository root; backslashes and dot segments are rejected.
  local folder="$1" remaining segment
  [ "$folder" = "." ] && return 0
  case "$folder" in
    ''|/*|*/|*\\*) return 1 ;;
  esac
  remaining="$folder"
  while [ -n "$remaining" ]; do
    case "$remaining" in
      */*)
        segment="${remaining%%/*}"
        remaining="${remaining#*/}"
        ;;
      *)
        segment="$remaining"
        remaining=""
        ;;
    esac
    case "$segment" in
      ''|.|..|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
  done
  return 0
}

sb_validate_source_path_chain() {
  # $1=trusted repository root, $2=validated manifest-relative folder.
  # Validate every component, not only the final directory: Get-Item/test -d
  # follows symlinked parents and would otherwise hide an intermediate link.
  local root="$1" folder="$2" current remaining segment
  [ -d "$root" ] && [ ! -L "$root" ] || return 1
  sb_safe_source_folder "$folder" || return 1
  [ "$folder" = "." ] && return 0
  current="$root"
  remaining="$folder"
  while [ -n "$remaining" ]; do
    case "$remaining" in
      */*)
        segment="${remaining%%/*}"
        remaining="${remaining#*/}"
        ;;
      *)
        segment="$remaining"
        remaining=""
        ;;
    esac
    current="${current}/${segment}"
    [ -d "$current" ] && [ ! -L "$current" ] || return 1
  done
  return 0
}

sb_tree_hash() {
  # Stable over path names and file bytes. Symlinks are prohibited in every
  # staged and managed skill tree. Ignores mtimes.
  # Newlines in filenames are unsupported; skill packages must not use them.
  local root="$1" list aggregate rel item_hash
  sb_validate_no_symlinks "$root" || return 1
  list="$(mktemp "${TMPDIR:-/tmp}/superbrowky-hash-list.XXXXXX")" || return 1
  aggregate="$(mktemp "${TMPDIR:-/tmp}/superbrowky-hash-data.XXXXXX")" || {
    rm -f "$list"
    return 1
  }
  if ! find "$root" -mindepth 1 \( -type d -o -type f \) -print | LC_ALL=C sort > "$list"; then
    rm -f "$list" "$aggregate"
    return 1
  fi
  : > "$aggregate"
  # On hash-tool failure the early-return cleanup intentionally removes the
  # list currently being read.
  # shellcheck disable=SC2094
  while IFS= read -r item; do
    rel="${item#"$root"/}"
    if [ -d "$item" ] && [ ! -L "$item" ]; then
      printf 'D\t%s\n' "$rel" >> "$aggregate"
    elif [ -f "$item" ] && [ ! -L "$item" ]; then
      item_hash="$(sb_sha256_file "$item")" || {
        rm -f "$list" "$aggregate"
        return 1
      }
      printf 'F\t%s\t%s\n' "$rel" "$item_hash" >> "$aggregate"
    else
      rm -f "$list" "$aggregate"
      return 1
    fi
  done < "$list"
  if ! sb_validate_no_symlinks "$root"; then
    rm -f "$list" "$aggregate"
    return 1
  fi
  item_hash="$(sb_sha256_file "$aggregate")"
  rm -f "$list" "$aggregate"
  printf '%s\n' "$item_hash"
}

sb_unmanaged_tree_hash() {
  # Backup hashing must preserve the exact pre-existing object, including
  # symlink targets, without treating that object as a managed skill tree.
  local root="$1" list aggregate rel item_hash target
  [ -d "$root" ] && [ ! -L "$root" ] || return 1
  list="$(mktemp "${TMPDIR:-/tmp}/superbrowky-backup-list.XXXXXX")" || return 1
  aggregate="$(mktemp "${TMPDIR:-/tmp}/superbrowky-backup-data.XXXXXX")" || {
    rm -f "$list"
    return 1
  }
  if ! find "$root" -mindepth 1 \( -type d -o -type f -o -type l \) -print | LC_ALL=C sort > "$list"; then
    rm -f "$list" "$aggregate"
    return 1
  fi
  : > "$aggregate"
  # shellcheck disable=SC2094
  while IFS= read -r item; do
    rel="${item#"$root"/}"
    if [ -L "$item" ]; then
      target="$(readlink "$item")" || {
        rm -f "$list" "$aggregate"
        return 1
      }
      printf 'L\t%s\t%s\n' "$rel" "$target" >> "$aggregate"
    elif [ -d "$item" ]; then
      printf 'D\t%s\n' "$rel" >> "$aggregate"
    else
      item_hash="$(sb_sha256_file "$item")" || {
        rm -f "$list" "$aggregate"
        return 1
      }
      printf 'F\t%s\t%s\n' "$rel" "$item_hash" >> "$aggregate"
    fi
  done < "$list"
  item_hash="$(sb_sha256_file "$aggregate")"
  rm -f "$list" "$aggregate"
  printf '%s\n' "$item_hash"
}

sb_path_type() {
  # Prints the receipt-safe type of one existing backup candidate.
  if [ -L "$1" ]; then
    printf 'symlink\n'
  elif [ -f "$1" ]; then
    printf 'file\n'
  elif [ -d "$1" ]; then
    printf 'directory\n'
  else
    return 1
  fi
}

sb_path_hash() {
  # Hashes one pre-existing object according to its recorded type.
  local path="$1" type="${2:-}" target data
  [ -n "$type" ] || type="$(sb_path_type "$path")" || return 1
  case "$type" in
    file)
      [ -f "$path" ] && [ ! -L "$path" ] || return 1
      sb_sha256_file "$path"
      ;;
    directory)
      [ -d "$path" ] && [ ! -L "$path" ] || return 1
      sb_unmanaged_tree_hash "$path"
      ;;
    symlink)
      [ -L "$path" ] || return 1
      target="$(readlink "$path")" || return 1
      data="$(mktemp "${TMPDIR:-/tmp}/superbrowky-link-data.XXXXXX")" || return 1
      printf 'L\t%s\n' "$target" > "$data" || {
        rm -f "$data"
        return 1
      }
      target="$(sb_sha256_file "$data")"
      rm -f "$data"
      printf '%s\n' "$target"
      ;;
    *)
      return 1
      ;;
  esac
}

sb_path_is_within() {
  # $1=existing path (or path with an existing parent), $2=existing root.
  # Resolve parents physically so a receipt cannot escape through ../ or a
  # symlinked intermediate directory.
  local path="$1" root="$2" root_real parent_real base candidate
  case "$path:$root" in
    /*:/*) ;;
    *) return 1 ;;
  esac
  [ -d "$root" ] || return 1
  root_real="$(cd -P "$root" 2>/dev/null && pwd)" || return 1
  parent_real="$(cd -P "$(dirname "$path")" 2>/dev/null && pwd)" || return 1
  base="$(basename "$path")"
  case "$base" in ''|.|..) return 1 ;; esac
  candidate="${parent_real}/${base}"
  case "$candidate" in
    "$root_real"/*) return 0 ;;
    *) return 1 ;;
  esac
}

sb_frontmatter_value() {
  # Basic scalar reader used even when Python is unavailable.
  # Block markers count as present; scripts/validate-skills.py performs the
  # deeper parse when Python is available.
  awk -v wanted="$2" '
    NR == 1 {
      if ($0 != "---") exit
      in_frontmatter=1
      next
    }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter {
      line=$0
      key=line
      sub(/:.*/, "", key)
      if (key == wanted) {
        sub(/^[^:]*:[[:space:]]*/, "", line)
        gsub(/^["'"'"']|["'"'"']$/, "", line)
        print line
        exit
      }
    }
  ' "$1"
}

sb_validate_skill_basic() {
  # $1=skill directory, $2=expected install name
  local skill_dir="$1" expected="$2" skill_md name description file
  skill_md="${skill_dir}/SKILL.md"
  if [ ! -f "$skill_md" ]; then
    sb_error "${expected}: missing SKILL.md"
    return 1
  fi
  if [ "$(sed -n '1p' "$skill_md")" != "---" ]; then
    sb_error "${expected}: SKILL.md has no YAML frontmatter"
    return 1
  fi
  name="$(sb_frontmatter_value "$skill_md" name)"
  description="$(sb_frontmatter_value "$skill_md" description)"
  if [ -z "$name" ]; then
    sb_error "${expected}: frontmatter name is missing"
    return 1
  fi
  if [ "$name" != "$expected" ]; then
    sb_error "${expected}: frontmatter name is '${name}'"
    return 1
  fi
  if [ -z "$description" ]; then
    sb_error "${expected}: frontmatter description is missing"
    return 1
  fi
  while IFS= read -r file; do
    if LC_ALL=C grep -n '/Users/' "$file" >/dev/null 2>&1; then
      sb_error "${expected}: non-portable absolute /Users path in ${file#"$skill_dir"/}"
      return 1
    fi
  done <<EOF
$(find "$skill_dir" -type f \( -name '*.md' -o -name '*.markdown' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.ts' -o -name '*.tsx' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.txt' \) -print)
EOF
  return 0
}

sb_detect_harness() {
  # Prints claude, codex, both, or returns nonzero when neither can be inferred.
  local target="${1:-}" has_claude=0 has_codex=0
  if [ -n "$target" ]; then
    [ -f "${target}/CLAUDE.md" ] && has_claude=1
    [ -f "${target}/AGENTS.md" ] && has_codex=1
  fi
  if command -v claude >/dev/null 2>&1 || [ -d "$CLAUDE_HOME" ] || [ "${SB_CLAUDE_HOME_EXPLICIT:-0}" -eq 1 ]; then
    has_claude=1
  fi
  if command -v codex >/dev/null 2>&1 || [ -d "$CODEX_HOME" ] || [ "${SB_CODEX_HOME_EXPLICIT:-0}" -eq 1 ]; then
    has_codex=1
  fi
  if [ "$has_claude" -eq 1 ] && [ "$has_codex" -eq 1 ]; then
    printf 'both\n'
  elif [ "$has_claude" -eq 1 ]; then
    printf 'claude\n'
  elif [ "$has_codex" -eq 1 ]; then
    printf 'codex\n'
  else
    return 1
  fi
}

sb_harnesses() {
  case "$1" in
    claude) printf 'claude\n' ;;
    codex) printf 'codex\n' ;;
    both) printf 'claude\ncodex\n' ;;
    *) return 1 ;;
  esac
}

sb_short_ref() {
  case "$1" in
    [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*)
      printf '%.12s\n' "$1"
      ;;
    *) printf '%s\n' "$1" ;;
  esac
}

sb_redact_home() {
  local home path
  home="$(printf '%s' "$HOME" | sed 's://*:/:g; s:/$::')"
  path="$(printf '%s' "$1" | sed 's://*:/:g')"
  case "$path" in
    "$home") printf '~\n' ;;
    "$home"/*) printf '%s/%s\n' '~' "${path#"$home"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
