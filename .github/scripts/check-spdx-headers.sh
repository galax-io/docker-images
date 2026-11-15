#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Fails when a *.sh file under the given directories lacks the licence line within its first three lines.
# Usage: check-spdx-headers.sh [DIR...]   (default: resources/ and .github/scripts/ of this repository)
# Exit: 0 every script has the header, 1 at least one lacks it, 2 a DIR is missing or not a directory.

HEADER='# SPDX-License-Identifier: Apache-2.0'

if [[ "$#" -eq 0 ]]; then
  repo_root="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  set -- "${repo_root}/resources" "${repo_root}/.github/scripts"
fi

for dir in "$@"; do
  if [[ ! -d "${dir}" ]]; then
    echo "not a directory: ${dir}" >&2
    exit 2
  fi
done

has_header() {
  local line=''
  for _ in 1 2 3; do
    IFS= read -r line || [[ -n "${line}" ]] || return 1
    [[ "${line}" == "${HEADER}" ]] && return 0
    line=''
  done
  return 1
}

total=0
missing=0
for dir in "$@"; do
  while IFS= read -r -d '' file; do
    total=$((total + 1))
    if ! has_header < "${file}"; then
      missing=$((missing + 1))
      echo "missing SPDX header: ${file}" >&2
    fi
  done < <(find "${dir}" -type f -name '*.sh' -print0)
done

if [[ "${missing}" -gt 0 ]]; then
  echo "${missing} of ${total} shell scripts lack the line '${HEADER}' in their first three lines" >&2
  exit 1
fi

echo "ok: ${total} shell scripts carry the SPDX header"
