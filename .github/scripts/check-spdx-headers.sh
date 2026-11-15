#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# check-spdx-headers.sh — every shell script this repository owns declares its licence.
#
# The repository is Apache 2.0, but a script copied out of it carries no licence unless it says
# so itself. A script passes when one of its first three lines is exactly
#
#   # SPDX-License-Identifier: Apache-2.0
#
# (usually the line under the shebang).
#
# Usage: check-spdx-headers.sh [DIR...]
#   With no argument it checks resources/ and .github/scripts/. The scripts the template ships
#   (scripts/, .githooks/, .claude/, .specify/) are generated elsewhere and are not checked here.
#
# Exit status: 0 every script has the header, 1 at least one lacks it, 2 a DIR does not exist.

set -euo pipefail

HEADER='# SPDX-License-Identifier: Apache-2.0'
ROOT="$(CDPATH='' cd "$(dirname "$0")/../.." && pwd)"

if [ "$#" -gt 0 ]; then
  dirs=("$@")
else
  dirs=("${ROOT}/resources" "${ROOT}/.github/scripts")
fi

checked=0
missing=0
for dir in "${dirs[@]}"; do
  if [ ! -d "${dir}" ]; then
    printf 'error: no such directory: %s\n' "${dir}" >&2
    exit 2
  fi
  while IFS= read -r -d '' file; do
    checked=$((checked + 1))
    # Read the lines first: with pipefail, `head | grep -q` can fail on a closed pipe.
    top="$(head -n 3 "${file}" || true)"
    if ! grep -qxF -- "${HEADER}" <<<"${top}"; then
      printf 'missing SPDX header: %s\n' "${file}" >&2
      missing=$((missing + 1))
    fi
  done < <(find "${dir}" -type f -name '*.sh' -print0)
done

if [ "${missing}" -gt 0 ]; then
  printf 'error: %d of %d shell scripts lack "%s" in their first three lines\n' "${missing}" "${checked}" "${HEADER}" >&2
  exit 1
fi

printf 'ok: %d shell scripts carry the SPDX header\n' "${checked}"
