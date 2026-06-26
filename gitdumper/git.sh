#!/usr/bin/env bash
# gittools-kit.sh
# Reusable wrapper for authorized GitTools Finder, Dumper, Extractor and safe export/report workflows.
#
# Only use against systems you own or have written authorization to test.
# This wrapper intentionally adds scope checks, logs, config loading, redaction, and first-run setup.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_CONFIG="${SCRIPT_DIR}/gittools-kit.config"
CONFIG_FILE="${GITTOOLS_KIT_CONFIG:-$DEFAULT_CONFIG}"

# -----------------------------
# Defaults; override in config
# -----------------------------
GITTOOLS_REPO_URL="${GITTOOLS_REPO_URL:-https://github.com/internetwache/GitTools.git}"
GITTOOLS_DIR="${GITTOOLS_DIR:-$HOME/tools/GitTools}"
WORK_DIR="${WORK_DIR:-$PWD/gittools-work}"
LOG_DIR="${LOG_DIR:-$WORK_DIR/logs}"
REPORT_DIR="${REPORT_DIR:-$WORK_DIR/reports}"
FINDER_THREADS="${FINDER_THREADS:-10}"
REQUEST_SLEEP="${REQUEST_SLEEP:-0}"
REQUIRE_AUTH_CONFIRM="${REQUIRE_AUTH_CONFIRM:-true}"
ALLOW_PRIVATE_IPS="${ALLOW_PRIVATE_IPS:-true}"
ALLOWED_HOST_REGEX="${ALLOWED_HOST_REGEX:-}"
HTTP_PROXY_URL="${HTTP_PROXY_URL:-}"
HTTPS_PROXY_URL="${HTTPS_PROXY_URL:-}"
REDACT_OUTPUT="${REDACT_OUTPUT:-true}"
EXPORT_TAR="${EXPORT_TAR:-true}"
OPEN_AFTER_DUMP="${OPEN_AFTER_DUMP:-false}"
DEFAULT_GIT_DIR_NAME="${DEFAULT_GIT_DIR_NAME:-.git}"

# Secret/risk scan patterns used in report mode.
RISK_REGEX="${RISK_REGEX:-eval\(|new Function|innerHTML|dangerouslySetInnerHTML|localStorage|sessionStorage|document\.cookie|fetch\(|XMLHttpRequest|crypto|AES|RSA|PBKDF2|argon2|bcrypt|jsonwebtoken|jwt|password|passwd|secret|token|api[_-]?key|private[_-]?key|client[_-]?secret|process\.env|env\.|CSP|Content-Security-Policy|iframe|clipboard|window\.location|redirect|cors|csrf|xss|sql injection|nosql}"

ACTION=""
TARGET_URL=""
TARGETS_FILE=""
FINDER_INPUT=""
FINDER_OUTPUT=""
DUMP_DIR=""
EXTRACT_OUT=""
EXPORT_OUT=""
REPORT_INPUT=""
GIT_DIR_NAME="$DEFAULT_GIT_DIR_NAME"
AUTH_OK="false"
FORCE="false"
NO_REDACT="false"
EXTRA_ARGS=()

ts() { date +"%Y-%m-%dT%H:%M:%S%z"; }

log() {
  mkdir -p "$LOG_DIR"
  printf '[%s] %s\n' "$(ts)" "$*" | tee -a "$LOG_DIR/gittools-kit.log" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
gittools-kit.sh - authorized GitTools workflow wrapper

USAGE:
  ./gittools-kit.sh init [--config FILE]
  ./gittools-kit.sh finder  --input targets.txt [--output found.txt] [--threads 20] --i-have-authorization
  ./gittools-kit.sh dump    --url https://example.com/.git/ [--dump-dir ./work/dumps/example] --i-have-authorization
  ./gittools-kit.sh extract --dump-dir ./work/dumps/example [--out ./work/extracted/example] --i-have-authorization
  ./gittools-kit.sh export  --input ./work/extracted/example [--out ./work/export/example] --i-have-authorization
  ./gittools-kit.sh report  --input ./work/export/example
  ./gittools-kit.sh all     --url https://example.com/.git/ --i-have-authorization
  ./gittools-kit.sh show-config

ACTIONS:
  init        First-run setup: clone/update GitTools and create config example if missing.
  finder      Run GitTools Finder against a file of authorized targets.
  dump        Run GitTools Dumper against one exposed .git URL.
  extract     Run GitTools Extractor against a dumped repository.
  exporter    Alias for export.
  export      Copy recovered source into an export folder, remove .git, create manifest and optional tar.gz.
  report      Scan exported/recovered repo for risky files and patterns.
  all         dump -> extract -> export -> report for one authorized .git URL.
  show-config Print effective configuration.
  clean       Remove work directory after confirmation.

IMPORTANT:
  This script is for authorized security assessment only.
  Use --i-have-authorization or set REQUIRE_AUTH_CONFIRM=false in config.
  Use ALLOWED_HOST_REGEX in config to restrict allowed target hostnames.

COMMON OPTIONS:
  --config FILE               Load config file.
  --url URL                   Target .git URL for dumper, e.g. https://example.com/.git/
  --input PATH                Input path for finder/report/export, depending on action.
  --targets-file PATH         Same as --input for finder.
  --output PATH               Output file for finder.
  --dump-dir PATH             Dumper output directory or extractor input directory.
  --out PATH                  Output directory for extract/export.
  --git-dir NAME              Git directory name; default .git.
  --threads N                 Finder threads.
  --proxy URL                 Sets HTTP_PROXY and HTTPS_PROXY for tools.
  --no-redact                 Do not redact secrets in report snippets.
  --force                     Overwrite output folders where supported.
  --i-have-authorization      Confirm you are authorized to test the target(s).
  -h, --help                  Show help.

EXAMPLES:
  ./gittools-kit.sh init

  ./gittools-kit.sh finder \
    --input authorized-domains.txt \
    --output found-git.txt \
    --threads 20 \
    --i-have-authorization

  ./gittools-kit.sh all \
    --url https://example.com/.git/ \
    --i-have-authorization

  ./gittools-kit.sh report \
    --input ./gittools-work/export/example.com

FILES:
  Config search default:
    ./gittools-kit.config
  Override:
    GITTOOLS_KIT_CONFIG=/path/config ./gittools-kit.sh show-config
    ./gittools-kit.sh --config /path/config show-config

REDACTION:
  Report output redacts common secret-like values by default. Review before sharing:
  passwords, tokens, API keys, private keys, cookies, authorization headers,
  database URLs, cloud keys, JWTs, and internal hostnames/IPs if present in paths/content.
EOF
}

load_config() {
  # First parse --config early without consuming main options.
  local i
  for ((i=1; i <= $#; i++)); do
    if [[ "${!i}" == "--config" ]]; then
      local j=$((i+1))
      [[ -n "${!j:-}" ]] || die "--config requires a file"
      CONFIG_FILE="${!j}"
    fi
  done

  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi

  GITTOOLS_DIR="${GITTOOLS_DIR/#\~/$HOME}"
  WORK_DIR="${WORK_DIR/#\~/$HOME}"
  LOG_DIR="${LOG_DIR/#\~/$HOME}"
  REPORT_DIR="${REPORT_DIR/#\~/$HOME}"

  if [[ -n "$HTTP_PROXY_URL" ]]; then
    export HTTP_PROXY="$HTTP_PROXY_URL"
    export http_proxy="$HTTP_PROXY_URL"
  fi
  if [[ -n "$HTTPS_PROXY_URL" ]]; then
    export HTTPS_PROXY="$HTTPS_PROXY_URL"
    export https_proxy="$HTTPS_PROXY_URL"
  fi
}

parse_args() {
  [[ $# -gt 0 ]] || { usage; exit 1; }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      init|finder|dump|dumper|extract|extractor|export|exporter|report|all|show-config|clean)
        ACTION="$1"
        shift
        ;;
      --config)
        shift 2
        ;;
      --url)
        TARGET_URL="${2:-}"; shift 2
        ;;
      --input)
        FINDER_INPUT="${2:-}"
        REPORT_INPUT="${2:-}"
        EXPORT_OUT="${EXPORT_OUT:-}"
        shift 2
        ;;
      --targets-file)
        TARGETS_FILE="${2:-}"
        FINDER_INPUT="$TARGETS_FILE"
        shift 2
        ;;
      --output)
        FINDER_OUTPUT="${2:-}"; shift 2
        ;;
      --dump-dir)
        DUMP_DIR="${2:-}"; shift 2
        ;;
      --out)
        EXTRACT_OUT="${2:-}"
        EXPORT_OUT="${2:-}"
        shift 2
        ;;
      --git-dir)
        GIT_DIR_NAME="${2:-}"; shift 2
        ;;
      --threads)
        FINDER_THREADS="${2:-}"; shift 2
        ;;
      --sleep)
        REQUEST_SLEEP="${2:-}"; shift 2
        ;;
      --proxy)
        HTTP_PROXY_URL="${2:-}"
        HTTPS_PROXY_URL="${2:-}"
        export HTTP_PROXY="$HTTP_PROXY_URL" HTTPS_PROXY="$HTTPS_PROXY_URL"
        export http_proxy="$HTTP_PROXY_URL" https_proxy="$HTTPS_PROXY_URL"
        shift 2
        ;;
      --no-redact)
        NO_REDACT="true"; REDACT_OUTPUT="false"; shift
        ;;
      --force)
        FORCE="true"; shift
        ;;
      --i-have-authorization|--authorized)
        AUTH_OK="true"; shift
        ;;
      -h|--help)
        usage; exit 0
        ;;
      --)
        shift; EXTRA_ARGS+=("$@"); break
        ;;
      *)
        die "Unknown option/action: $1"
        ;;
    esac
  done

  [[ -n "$ACTION" ]] || die "No action provided. Use --help."
  [[ "$ACTION" == "dumper" ]] && ACTION="dump"
  [[ "$ACTION" == "extractor" ]] && ACTION="extract"
  [[ "$ACTION" == "exporter" ]] && ACTION="export"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

check_deps() {
  need_cmd bash
  need_cmd git
  need_cmd curl
  need_cmd sed
  need_cmd grep
  need_cmd awk
  need_cmd find
  need_cmd tar
  need_cmd python3
  if ! command -v strings >/dev/null 2>&1; then
    log "WARNING: 'strings' not found. Install binutils for full GitTools compatibility."
  fi
}

init_dirs() {
  mkdir -p "$WORK_DIR" "$LOG_DIR" "$REPORT_DIR"
}

write_config_example() {
  local example="${SCRIPT_DIR}/gittools-kit.config.example"
  if [[ -f "$example" && "$FORCE" != "true" ]]; then
    log "Config example already exists: $example"
    return
  fi

  cat > "$example" <<'EOF'
# gittools-kit.config.example
# Copy to gittools-kit.config and edit.

# Where upstream GitTools will be cloned/updated
GITTOOLS_REPO_URL="https://github.com/internetwache/GitTools.git"
GITTOOLS_DIR="$HOME/tools/GitTools"

# Workspace
WORK_DIR="$PWD/gittools-work"
LOG_DIR="$WORK_DIR/logs"
REPORT_DIR="$WORK_DIR/reports"

# Safety controls
REQUIRE_AUTH_CONFIRM="true"

# Optional hostname allowlist regex.
# Examples:
#   ALLOWED_HOST_REGEX="(^|\.)example\.com$"
#   ALLOWED_HOST_REGEX="^(app1|app2)\.example\.com$"
ALLOWED_HOST_REGEX=""

# Finder settings
FINDER_THREADS="10"

# Proxy support; leave blank if not needed.
HTTP_PROXY_URL=""
HTTPS_PROXY_URL=""

# Dumper / extractor settings
DEFAULT_GIT_DIR_NAME=".git"
OPEN_AFTER_DUMP="false"

# Export/report
REDACT_OUTPUT="true"
EXPORT_TAR="true"

# Pattern list for report mode.
# Keep it broad for first triage, then manually verify results.
RISK_REGEX="eval\(|new Function|innerHTML|dangerouslySetInnerHTML|localStorage|sessionStorage|document\.cookie|fetch\(|XMLHttpRequest|crypto|AES|RSA|PBKDF2|argon2|bcrypt|jsonwebtoken|jwt|password|passwd|secret|token|api[_-]?key|private[_-]?key|client[_-]?secret|process\.env|env\.|CSP|Content-Security-Policy|iframe|clipboard|window\.location|redirect|cors|csrf|xss|sql injection|nosql"
EOF
  log "Wrote config example: $example"
}

init_gittools() {
  check_deps
  init_dirs
  write_config_example

  if [[ -d "$GITTOOLS_DIR/.git" ]]; then
    log "GitTools exists. Updating: $GITTOOLS_DIR"
    git -C "$GITTOOLS_DIR" pull --ff-only | tee -a "$LOG_DIR/gittools-kit.log"
  else
    log "Cloning GitTools to: $GITTOOLS_DIR"
    mkdir -p "$(dirname "$GITTOOLS_DIR")"
    git clone "$GITTOOLS_REPO_URL" "$GITTOOLS_DIR" | tee -a "$LOG_DIR/gittools-kit.log"
  fi

  [[ -x "$GITTOOLS_DIR/Dumper/gitdumper.sh" ]] || chmod +x "$GITTOOLS_DIR/Dumper/gitdumper.sh" 2>/dev/null || true
  [[ -x "$GITTOOLS_DIR/Extractor/extractor.sh" ]] || chmod +x "$GITTOOLS_DIR/Extractor/extractor.sh" 2>/dev/null || true
  [[ -x "$GITTOOLS_DIR/Finder/gitfinder.py" ]] || chmod +x "$GITTOOLS_DIR/Finder/gitfinder.py" 2>/dev/null || true

  log "Init complete."
}

require_gittools() {
  [[ -d "$GITTOOLS_DIR" ]] || die "GitTools not found at $GITTOOLS_DIR. Run: ./$SCRIPT_NAME init"
  [[ -f "$GITTOOLS_DIR/Finder/gitfinder.py" ]] || die "Missing Finder/gitfinder.py. Run init."
  [[ -f "$GITTOOLS_DIR/Dumper/gitdumper.sh" ]] || die "Missing Dumper/gitdumper.sh. Run init."
  [[ -f "$GITTOOLS_DIR/Extractor/extractor.sh" ]] || die "Missing Extractor/extractor.sh. Run init."
}

require_authorized() {
  if [[ "$REQUIRE_AUTH_CONFIRM" == "true" && "$AUTH_OK" != "true" ]]; then
    die "Authorization confirmation required. Re-run with --i-have-authorization, or set REQUIRE_AUTH_CONFIRM=false in config."
  fi
}

url_host() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlparse
u = urlparse(sys.argv[1])
print(u.hostname or "")
PY
}

sanitize_name() {
  sed -E 's#^https?://##; s#/.git/?$##; s#[^A-Za-z0-9._-]+#_#g; s#_+$##' <<<"$1"
}

validate_url() {
  local url="$1"
  [[ "$url" =~ ^https?:// ]] || die "URL must start with http:// or https://"
  [[ "$url" =~ /\.git/?$ ]] || die "URL should point to exposed .git path, e.g. https://example.com/.git/"

  local host
  host="$(url_host "$url")"
  [[ -n "$host" ]] || die "Could not parse target host from URL: $url"

  if [[ -n "$ALLOWED_HOST_REGEX" ]]; then
    if ! grep -Eiq "$ALLOWED_HOST_REGEX" <<<"$host"; then
      die "Host '$host' is outside ALLOWED_HOST_REGEX='$ALLOWED_HOST_REGEX'"
    fi
  fi
}

validate_targets_file() {
  local file="$1"
  [[ -f "$file" ]] || die "Targets file not found: $file"

  if [[ -n "$ALLOWED_HOST_REGEX" ]]; then
    local bad
    bad="$(awk 'NF && $0 !~ /^#/ {print $1}' "$file" | while read -r t; do
      local h="$t"
      if [[ "$t" =~ ^https?:// ]]; then
        h="$(url_host "$t")"
      fi
      if ! grep -Eiq "$ALLOWED_HOST_REGEX" <<<"$h"; then
        printf '%s\n' "$t"
      fi
    done | head -20)"
    [[ -z "$bad" ]] || die "Targets outside ALLOWED_HOST_REGEX detected:\n$bad"
  fi
}

redact_stream() {
  if [[ "$REDACT_OUTPUT" != "true" || "$NO_REDACT" == "true" ]]; then
    cat
    return
  fi

  sed -E \
    -e 's#(Authorization:[[:space:]]*Bearer[[:space:]]+)[A-Za-z0-9._~+/=-]+#\1[REDACTED]#Ig' \
    -e 's#(password|passwd|pwd|secret|token|api[_-]?key|client[_-]?secret|private[_-]?key)(["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?)[^"'"'"' ,;}]+#\1\2[REDACTED]#Ig' \
    -e 's#-----BEGIN [A-Z ]*PRIVATE KEY-----.*#-----BEGIN PRIVATE KEY-----[REDACTED]#Ig' \
    -e 's#([A-Za-z0-9_-]+\.){2}[A-Za-z0-9_-]+#[JWT-LIKE-REDACTED]#g' \
    -e 's#(mongodb|mysql|postgres|postgresql|redis)://[^[:space:]'"'"'"]+#\1://[REDACTED]#Ig' \
    -e 's#AKIA[0-9A-Z]{16}#AWS_ACCESS_KEY_ID_REDACTED#g'
}

run_finder() {
  require_authorized
  require_gittools
  check_deps

  [[ -n "$FINDER_INPUT" ]] || die "finder requires --input targets.txt"
  validate_targets_file "$FINDER_INPUT"

  [[ -n "$FINDER_OUTPUT" ]] || FINDER_OUTPUT="$WORK_DIR/found-git-$(date +%Y%m%d-%H%M%S).txt"
  mkdir -p "$(dirname "$FINDER_OUTPUT")"

  log "Running Finder with $FINDER_THREADS threads."
  (
    cd "$GITTOOLS_DIR/Finder"
    python3 ./gitfinder.py -i "$FINDER_INPUT" -o "$FINDER_OUTPUT" -t "$FINDER_THREADS"
  ) 2>&1 | tee -a "$LOG_DIR/finder.log"

  log "Finder output: $FINDER_OUTPUT"
}

run_dump() {
  require_authorized
  require_gittools
  check_deps

  [[ -n "$TARGET_URL" ]] || die "dump requires --url https://target/.git/"
  validate_url "$TARGET_URL"

  if [[ -z "$DUMP_DIR" ]]; then
    DUMP_DIR="$WORK_DIR/dumps/$(sanitize_name "$TARGET_URL")"
  fi

  if [[ -e "$DUMP_DIR" && "$FORCE" != "true" ]]; then
    die "Dump directory already exists: $DUMP_DIR. Use --force or choose another --dump-dir."
  fi

  mkdir -p "$DUMP_DIR"
  log "Running Dumper. Output: $DUMP_DIR"
  log "Note: recovery may be incomplete if the remote repository uses pack files or missing objects."

  "$GITTOOLS_DIR/Dumper/gitdumper.sh" "$TARGET_URL" "$DUMP_DIR" "--git-dir=$GIT_DIR_NAME" \
    2>&1 | tee -a "$LOG_DIR/dumper.log"

  if [[ "$OPEN_AFTER_DUMP" == "true" && -d "$DUMP_DIR/.git" ]]; then
    log "Running git status after dump."
    git -C "$DUMP_DIR" status --short 2>&1 | tee -a "$LOG_DIR/dumper.log" || true
  fi

  log "Dump complete: $DUMP_DIR"
}

run_extract() {
  require_authorized
  require_gittools
  check_deps

  [[ -n "$DUMP_DIR" ]] || die "extract requires --dump-dir"
  [[ -d "$DUMP_DIR" ]] || die "Dump directory not found: $DUMP_DIR"

  if [[ -z "$EXTRACT_OUT" ]]; then
    EXTRACT_OUT="$WORK_DIR/extracted/$(basename "$DUMP_DIR")"
  fi

  if [[ -e "$EXTRACT_OUT" && "$FORCE" != "true" ]]; then
    die "Extract output exists: $EXTRACT_OUT. Use --force or choose another --out."
  fi

  mkdir -p "$EXTRACT_OUT"
  log "Running Extractor. Input: $DUMP_DIR Output: $EXTRACT_OUT"

  "$GITTOOLS_DIR/Extractor/extractor.sh" "$DUMP_DIR" "$EXTRACT_OUT" \
    2>&1 | tee -a "$LOG_DIR/extractor.log"

  log "Extract complete: $EXTRACT_OUT"
}

copy_safe_export() {
  local src="$1"
  local dst="$2"

  mkdir -p "$dst"

  # Prefer rsync if present; fallback to tar pipeline.
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude '.git' \
      --exclude '.svn' \
      --exclude '.hg' \
      --exclude 'node_modules' \
      --exclude 'vendor' \
      --exclude '__pycache__' \
      "$src"/ "$dst"/
  else
    (
      cd "$src"
      tar --exclude='./.git' --exclude='./.svn' --exclude='./.hg' \
          --exclude='./node_modules' --exclude='./vendor' --exclude='./__pycache__' \
          -cf - .
    ) | (cd "$dst" && tar -xf -)
  fi
}

run_export() {
  require_authorized
  check_deps

  local src="$REPORT_INPUT"
  [[ -n "$src" ]] || src="$DUMP_DIR"
  [[ -n "$src" ]] || die "export requires --input recovered_dir or --dump-dir"
  [[ -d "$src" ]] || die "Export input directory not found: $src"

  if [[ -z "$EXPORT_OUT" || "$EXPORT_OUT" == "$src" ]]; then
    EXPORT_OUT="$WORK_DIR/export/$(basename "$src")"
  fi

  if [[ -e "$EXPORT_OUT" && "$FORCE" != "true" ]]; then
    die "Export output exists: $EXPORT_OUT. Use --force or choose another --out."
  fi

  log "Creating clean export: $EXPORT_OUT"
  copy_safe_export "$src" "$EXPORT_OUT"

  local manifest="$EXPORT_OUT/MANIFEST.gittools-kit.txt"
  {
    echo "gittools-kit export manifest"
    echo "created_at=$(ts)"
    echo "source=$src"
    echo "export=$EXPORT_OUT"
    echo
    echo "file_count=$(find "$EXPORT_OUT" -type f | wc -l | tr -d ' ')"
    echo "dir_count=$(find "$EXPORT_OUT" -type d | wc -l | tr -d ' ')"
    echo
    echo "sha256:"
    find "$EXPORT_OUT" -type f ! -name 'MANIFEST.gittools-kit.txt' -print0 \
      | sort -z \
      | xargs -0 sha256sum 2>/dev/null || true
  } > "$manifest"

  if [[ "$EXPORT_TAR" == "true" ]]; then
    local tarball="${EXPORT_OUT%/}.tar.gz"
    log "Creating tarball: $tarball"
    tar -czf "$tarball" -C "$(dirname "$EXPORT_OUT")" "$(basename "$EXPORT_OUT")"
  fi

  log "Export complete: $EXPORT_OUT"
}

run_report() {
  check_deps

  local src="$REPORT_INPUT"
  [[ -n "$src" ]] || src="$EXPORT_OUT"
  [[ -n "$src" ]] || src="$DUMP_DIR"
  [[ -n "$src" ]] || die "report requires --input directory"
  [[ -d "$src" ]] || die "Report input directory not found: $src"

  mkdir -p "$REPORT_DIR"
  local base
  base="$(basename "$src")"
  local report="$REPORT_DIR/${base}-security-report-$(date +%Y%m%d-%H%M%S).md"

  log "Generating report: $report"

  {
    echo "# GitTools Kit Security Report"
    echo
    echo "- Created: $(ts)"
    echo "- Input: \`$src\`"
    echo "- Redaction: \`$REDACT_OUTPUT\`"
    echo
    echo "## Before sharing this report"
    echo
    echo "Review and redact sensitive data such as passwords, tokens, API keys, private keys, cookies, authorization headers, database URLs, internal hostnames/IPs, customer data, and proprietary source paths."
    echo
    echo "## File summary"
    echo
    echo "\`\`\`"
    echo "files=$(find "$src" -type f | wc -l | tr -d ' ')"
    echo "directories=$(find "$src" -type d | wc -l | tr -d ' ')"
    echo "size=$(du -sh "$src" 2>/dev/null | awk '{print $1}')"
    echo "\`\`\`"
    echo
    echo "## High-risk filenames"
    echo
    echo "\`\`\`"
    find "$src" -type f \
      \( -iname '.env' -o -iname '*.env' -o -iname '*secret*' -o -iname '*password*' -o -iname '*credential*' -o -iname '*token*' -o -iname '*key*' -o -iname 'id_rsa' -o -iname '*.pem' -o -iname '*.p12' -o -iname '*.pfx' -o -iname 'database.json' -o -iname 'config.json' \) \
      | sort | redact_stream | head -300
    echo "\`\`\`"
    echo
    echo "## Risky code/config pattern matches"
    echo
    echo "\`\`\`"
    grep -RInE --binary-files=without-match "$RISK_REGEX" "$src" \
      --include='*.js' --include='*.jsx' --include='*.ts' --include='*.tsx' \
      --include='*.json' --include='*.md' --include='*.yml' --include='*.yaml' \
      --include='*.env' --include='*.php' --include='*.py' --include='*.rb' \
      2>/dev/null | redact_stream | head -500 || true
    echo "\`\`\`"
    echo
    echo "## Git metadata check"
    echo
    echo "\`\`\`"
    find "$src" -type d -name '.git' -print | sort | head -100
    echo "\`\`\`"
    echo
    echo "## Suggested manual verification"
    echo
    echo "1. Confirm whether any exposed secrets are active; rotate them if found."
    echo "2. Check commit history for removed secrets."
    echo "3. Verify web server blocks access to /.git/, /.svn/, /.hg/, backups, and dotfiles."
    echo "4. Add CI checks for secret scanning and exposed VCS directories."
    echo "5. Add WAF/web-server rule for denying /.git paths."
  } > "$report"

  log "Report complete: $report"
  printf '%s\n' "$report"
}

show_config() {
  cat <<EOF
Effective config:
  CONFIG_FILE=$CONFIG_FILE
  GITTOOLS_REPO_URL=$GITTOOLS_REPO_URL
  GITTOOLS_DIR=$GITTOOLS_DIR
  WORK_DIR=$WORK_DIR
  LOG_DIR=$LOG_DIR
  REPORT_DIR=$REPORT_DIR
  FINDER_THREADS=$FINDER_THREADS
  REQUIRE_AUTH_CONFIRM=$REQUIRE_AUTH_CONFIRM
  ALLOWED_HOST_REGEX=$ALLOWED_HOST_REGEX
  HTTP_PROXY_URL=$HTTP_PROXY_URL
  HTTPS_PROXY_URL=$HTTPS_PROXY_URL
  REDACT_OUTPUT=$REDACT_OUTPUT
  EXPORT_TAR=$EXPORT_TAR
  DEFAULT_GIT_DIR_NAME=$DEFAULT_GIT_DIR_NAME
EOF
}

run_all() {
  require_authorized
  [[ -n "$TARGET_URL" ]] || die "all requires --url https://target/.git/"
  validate_url "$TARGET_URL"

  local name
  name="$(sanitize_name "$TARGET_URL")"

  DUMP_DIR="${DUMP_DIR:-$WORK_DIR/dumps/$name}"
  EXTRACT_OUT="${EXTRACT_OUT:-$WORK_DIR/extracted/$name}"
  EXPORT_OUT="${EXPORT_OUT:-$WORK_DIR/export/$name}"

  run_dump
  run_extract

  REPORT_INPUT="$EXTRACT_OUT"
  run_export

  REPORT_INPUT="$EXPORT_OUT"
  run_report >/dev/null

  log "All workflow complete."
  log "Dump: $DUMP_DIR"
  log "Extracted: $EXTRACT_OUT"
  log "Export: $EXPORT_OUT"
}

run_clean() {
  [[ -d "$WORK_DIR" ]] || die "Work dir not found: $WORK_DIR"
  if [[ "$FORCE" != "true" ]]; then
    printf 'This will remove: %s\nType DELETE to continue: ' "$WORK_DIR" >&2
    read -r ans
    [[ "$ans" == "DELETE" ]] || die "Clean cancelled."
  fi
  rm -rf "$WORK_DIR"
  log "Removed work dir: $WORK_DIR"
}

main() {
  load_config "$@"
  parse_args "$@"
  init_dirs

  case "$ACTION" in
    init) init_gittools ;;
    finder) run_finder ;;
    dump) run_dump ;;
    extract) run_extract ;;
    export) run_export ;;
    report) run_report ;;
    all) run_all ;;
    show-config) show_config ;;
    clean) run_clean ;;
    *) die "Unhandled action: $ACTION" ;;
  esac
}

main "$@"
