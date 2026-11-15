#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/scripts/check-spdx-headers.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

# run <dir...>: sets $status and $output (stdout and stderr together).
run() {
  set +e
  output="$(bash "${SCRIPT}" "$@" 2>&1)"
  status=$?
  set -e
}

assert_status() {
  [ "${status}" -eq "$1" ] || fail "$2: expected exit $1, got ${status}: ${output}"
}

assert_output_contains() {
  printf '%s' "${output}" | grep -F -- "$1" >/dev/null 2>&1 || fail "$2: expected '$1' in: ${output}"
}

assert_output_lacks() {
  if printf '%s' "${output}" | grep -F -- "$1" >/dev/null 2>&1; then
    fail "$2: did not expect '$1' in: ${output}"
  fi
}

# A script with the header on its second line, below the shebang: the usual shape.
mkdir -p "${tmpdir}/good"
printf '#!/usr/bin/env bash\n# SPDX-License-Identifier: Apache-2.0\n\nset -euo pipefail\n' > "${tmpdir}/good/a.sh"
# ... and one without a shebang, header on the first line, found in a subdirectory.
mkdir -p "${tmpdir}/good/nested"
printf '# SPDX-License-Identifier: Apache-2.0\n:\n' > "${tmpdir}/good/nested/b.sh"
# Files that are not shell scripts are not checked.
printf 'no header here\n' > "${tmpdir}/good/notes.txt"

run "${tmpdir}/good"
assert_status 0 'scripts with the header'
assert_output_contains 'ok: 2 shell scripts' 'scripts with the header'
printf 'PASS: scripts with the header pass\n'

# No header at all.
mkdir -p "${tmpdir}/missing"
printf '#!/usr/bin/env bash\nset -euo pipefail\n' > "${tmpdir}/missing/c.sh"
run "${tmpdir}/missing"
assert_status 1 'script without the header'
assert_output_contains "${tmpdir}/missing/c.sh" 'script without the header'
printf 'PASS: a script without the header fails and is named\n'

# Another licence is not the repository's licence.
mkdir -p "${tmpdir}/other"
printf '#!/usr/bin/env bash\n# SPDX-License-Identifier: MIT\n' > "${tmpdir}/other/d.sh"
run "${tmpdir}/other"
assert_status 1 'script with another licence'
assert_output_contains "${tmpdir}/other/d.sh" 'script with another licence'
printf 'PASS: a different licence identifier fails\n'

# The header must sit at the top, not somewhere in the body.
mkdir -p "${tmpdir}/late"
printf '#!/usr/bin/env bash\nset -euo pipefail\n\necho hi\n# SPDX-License-Identifier: Apache-2.0\n' > "${tmpdir}/late/e.sh"
run "${tmpdir}/late"
assert_status 1 'header below the first lines'
assert_output_contains "${tmpdir}/late/e.sh" 'header below the first lines'
printf 'PASS: a header below the first three lines fails\n'

# Only the scripts that miss it are named, and the exit stays 1 for a mixed set.
mkdir -p "${tmpdir}/mixed"
cp "${tmpdir}/good/a.sh" "${tmpdir}/mixed/ok.sh"
cp "${tmpdir}/missing/c.sh" "${tmpdir}/mixed/bad.sh"
run "${tmpdir}/mixed"
assert_status 1 'mixed directory'
assert_output_contains "${tmpdir}/mixed/bad.sh" 'mixed directory'
assert_output_lacks "${tmpdir}/mixed/ok.sh" 'mixed directory'
printf 'PASS: only the scripts that miss the header are named\n'

# Several directories at once; a directory with no scripts is not an error.
mkdir -p "${tmpdir}/empty"
run "${tmpdir}/good" "${tmpdir}/empty"
assert_status 0 'a directory with no scripts'
printf 'PASS: a directory with no scripts passes\n'

# A directory that does not exist is a usage error, not a pass.
run "${tmpdir}/does-not-exist"
assert_status 2 'missing directory'
assert_output_contains 'no such directory' 'missing directory'
printf 'PASS: a missing directory is an error\n'

# The repository itself: every script of resources/ and .github/scripts/ carries the header.
run
assert_status 0 'the repository'
printf 'PASS: the repository'"'"'s own scripts carry the header\n'
