#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Native environment requires macOS'; exit 2; }
[[ -x /usr/bin/sandbox-exec ]] || { echo 'Required process network sandbox unavailable'; exit 2; }
command -v brew >/dev/null
command -v go >/dev/null
command -v python3 >/dev/null
python3 -c 'import sys; assert sys.version_info[:2] == (3, 12), "Use Python3.12 for pinned native trial dependencies"'
native_tools="${NIDAA_NATIVE_TOOLS:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nidaa-native-tools}"
mkdir -p "$native_tools"
chmod 700 "$native_tools"
# Acquire dependencies before runtime isolation; never start a shared brew service.
if ! brew list --versions postgresql@17 >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install postgresql@17
fi
brew --prefix postgresql@17 > "$native_tools/postgresql-prefix.txt"
python3 -m venv "$native_tools/venv"
"$native_tools/venv/bin/python" -m pip install -r Integration/requirements.txt -c Integration/requirements-lock.txt
[[ ! -e "$native_tools/auth-source" ]] || { echo 'Native tools already contain Auth source; use a fresh tools directory'; exit 2; }
git clone --depth 1 --branch v2.196.0 https://github.com/supabase/auth.git "$native_tools/auth-source"
[[ "$(git -C "$native_tools/auth-source" rev-parse HEAD)" == 0204331ca41a5b49f076b6fa3dc6c0d20b996590 ]] || { echo 'Auth tag no longer matches inspected source'; exit 2; }
(
  cd "$native_tools/auth-source"
  GOTOOLCHAIN=go1.26.5 go mod download
  GOTOOLCHAIN=go1.26.5 go mod verify
  GOTOOLCHAIN=go1.26.5 CGO_ENABLED=0 go build -buildvcs=false \
    -ldflags '-X github.com/supabase/auth/internal/utilities.Version=v2.196.0' -o "$native_tools/auth" .
)
"$native_tools/venv/bin/python" Integration/native/prepare_assets.py "$native_tools"
echo 'Native dependency preparation completed; runtime isolation and execution still require verification.'
