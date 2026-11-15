#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"
CHECKER="${REPO_ROOT}/.github/scripts/check-spdx-headers.sh"
WORKFLOW="${REPO_ROOT}/.github/workflows/shellcheck.yml"
HEADER='# SPDX-License-Identifier: Apache-2.0'

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local what="$3"
  [[ "${actual}" == "${expected}" ]] || fail "expected ${what} to be '${expected}', got '${actual}'"
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  grep -F -- "$pattern" "$file" >/dev/null 2>&1 || fail "expected '$pattern' in $file: $(cat "$file")"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  ! grep -F -- "$pattern" "$file" >/dev/null 2>&1 || fail "did not expect '$pattern' in $file: $(cat "$file")"
}

assert_file_empty() {
  local file="$1"
  [[ ! -s "$file" ]] || fail "expected $file to be empty, got: $(cat "$file")"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

out_file="${tmpdir}/stdout"
err_file="${tmpdir}/stderr"
rc=0

# run_checker ARG...: runs the checker, leaves its exit code in rc, its output in out_file and err_file.
run_checker() {
  rc=0
  bash "${CHECKER}" "$@" >"${out_file}" 2>"${err_file}" || rc=$?
}

assert_passes() {
  local count="$1"
  [[ "${rc}" -eq 0 ]] || fail "expected exit 0, got ${rc}; stderr: $(cat "${err_file}")"
  assert_equals "ok: ${count} shell scripts carry the SPDX header" "$(cat "${out_file}")" "stdout"
  assert_file_empty "${err_file}"
}

assert_fails() {
  [[ "${rc}" -eq 1 ]] || fail "expected exit 1, got ${rc}; stdout: $(cat "${out_file}") stderr: $(cat "${err_file}")"
  assert_file_not_contains "${out_file}" "ok:"
}

new_dir() {
  local dir
  dir="$(mktemp -d "${tmpdir}/case.XXXXXX")"
  printf '%s\n' "${dir}"
}

# FR-001, FR-003, FR-004: the header on line 1, 2 or 3 passes, with and without a shebang, nested too.
dir="$(new_dir)"
printf '%s\n#!/usr/bin/env sh\necho one\n' "${HEADER}" > "${dir}/line1.sh"
printf '#!/usr/bin/env bash\n%s\necho two\n' "${HEADER}" > "${dir}/line2.sh"
printf '#!/usr/bin/env bash\n\n%s\necho three\n' "${HEADER}" > "${dir}/line3.sh"
mkdir -p "${dir}/nested/deeper"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${dir}/nested/deeper/inner.sh"
printf '%s' "${HEADER}" > "${dir}/no-newline.sh"
run_checker "${dir}"
assert_passes 5
printf 'PASS: FR-001: the header on line 1, 2 or 3, with or without a shebang, nested, passes\n'

# FR-001, FR-004: a script without the header is named on stderr and the exit code is 1.
dir="$(new_dir)"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho hi\n' > "${dir}/plain.sh"
run_checker "${dir}"
assert_fails
assert_file_contains "${err_file}" "${dir}/plain.sh"
printf 'PASS: FR-004: a script without the header is named on stderr, exit 1\n'

# FR-001: another licence identifier, trailing text, trailing space, a carriage return, a leading space.
dir="$(new_dir)"
printf '#!/usr/bin/env bash\n# SPDX-License-Identifier: MIT\n' > "${dir}/other-licence.sh"
printf '#!/usr/bin/env bash\n%s OR MIT\n' "${HEADER}" > "${dir}/trailing-text.sh"
printf '#!/usr/bin/env bash\n%s \n' "${HEADER}" > "${dir}/trailing-space.sh"
printf '#!/usr/bin/env bash\n%s\r\n' "${HEADER}" > "${dir}/carriage-return.sh"
printf '#!/usr/bin/env bash\n %s\n' "${HEADER}" > "${dir}/leading-space.sh"
run_checker "${dir}"
assert_fails
for name in other-licence trailing-text trailing-space carriage-return leading-space; do
  assert_file_contains "${err_file}" "${dir}/${name}.sh"
done
printf 'PASS: FR-001: another licence, trailing text, trailing space, carriage return and leading space do not count\n'

# FR-001: the header on line 4 or later does not count.
dir="$(new_dir)"
printf '#!/usr/bin/env bash\n\n\n%s\n' "${HEADER}" > "${dir}/line4.sh"
printf '#!/usr/bin/env bash\n\n\n\n\n%s\n' "${HEADER}" > "${dir}/line6.sh"
run_checker "${dir}"
assert_fails
assert_file_contains "${err_file}" "${dir}/line4.sh"
assert_file_contains "${err_file}" "${dir}/line6.sh"
printf 'PASS: FR-001: the header below the first three lines does not count\n'

# FR-001, edge cases: an empty script and a script of fewer than three lines lack the header and are named.
dir="$(new_dir)"
: > "${dir}/empty.sh"
printf '#!/usr/bin/env sh\n' > "${dir}/one-line.sh"
printf '#!/usr/bin/env sh\nexit 0\n' > "${dir}/two-lines.sh"
run_checker "${dir}"
assert_fails
for name in empty one-line two-lines; do
  assert_file_contains "${err_file}" "${dir}/${name}.sh"
done
printf 'PASS: FR-001: an empty or very short script is named, not a crash\n'

# FR-004: a mixed directory names only the offenders, once each, and exits 1.
dir="$(new_dir)"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${dir}/good-one.sh"
printf '#!/usr/bin/env sh\n%s\n' "${HEADER}" > "${dir}/good-two.sh"
printf '#!/usr/bin/env bash\necho bad\n' > "${dir}/bad-one.sh"
mkdir -p "${dir}/sub"
printf '#!/usr/bin/env bash\necho bad\n' > "${dir}/sub/bad-two.sh"
run_checker "${dir}"
assert_fails
assert_file_contains "${err_file}" "bad-one.sh"
assert_file_contains "${err_file}" "bad-two.sh"
assert_file_not_contains "${err_file}" "good-one.sh"
assert_file_not_contains "${err_file}" "good-two.sh"
assert_equals "1" "$(grep -c -F 'bad-one.sh' "${err_file}")" "the lines naming bad-one.sh"
assert_equals "1" "$(grep -c -F 'bad-two.sh' "${err_file}")" "the lines naming bad-two.sh"
assert_equals "3" "$(grep -c . "${err_file}")" "the non-empty stderr lines (two offenders and a summary)"
printf 'PASS: FR-004: a mixed directory names only the offenders, one line each, then a summary, exit 1\n'

# FR-003: files that are not *.sh are ignored.
dir="$(new_dir)"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${dir}/real.sh"
printf 'export X=1\n' > "${dir}/.sbtopts"
printf 'readme\n' > "${dir}/README.md"
printf '#!/usr/bin/env bash\necho x\n' > "${dir}/no-extension"
printf '#!/usr/bin/env bash\necho x\n' > "${dir}/other.bash"
printf '#!/usr/bin/env bash\necho x\n' > "${dir}/not-a-script.sh.txt"
run_checker "${dir}"
assert_passes 1
printf 'PASS: FR-003: files that are not *.sh are ignored\n'

# FR-005: a directory with no scripts passes and says 0.
dir="$(new_dir)"
run_checker "${dir}"
assert_passes 0
dir="$(new_dir)"
printf 'readme\n' > "${dir}/README.md"
run_checker "${dir}"
assert_passes 0
printf 'PASS: FR-005: a directory with no scripts passes with 0 shell scripts\n'

# FR-003, edge cases: names with spaces and newlines are handled without splitting.
dir="$(new_dir)"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${dir}/good name.sh"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${dir}/good"$'\n'"line.sh"
printf '#!/usr/bin/env bash\necho bad\n' > "${dir}/bad name.sh"
printf '#!/usr/bin/env bash\necho bad\n' > "${dir}/bad"$'\n'"line.sh"
run_checker "${dir}"
assert_fails
assert_file_contains "${err_file}" "bad name.sh"
assert_file_not_contains "${err_file}" "good name.sh"
dir="$(new_dir)"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${dir}/good name.sh"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${dir}/good"$'\n'"line.sh"
run_checker "${dir}"
assert_passes 2
printf 'PASS: FR-003: file names with spaces and newlines are handled\n'

# FR-003, edge cases: a symbolic link named *.sh is not followed and not counted.
dir="$(new_dir)"
target_dir="$(new_dir)"
printf '#!/usr/bin/env bash\necho bad\n' > "${target_dir}/target.txt"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${dir}/real.sh"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${dir}/second.sh"
ln -s "${target_dir}/target.txt" "${dir}/link.sh"
run_checker "${dir}"
assert_passes 2
printf 'PASS: FR-003: a symbolic link named *.sh is neither followed nor counted\n'

# FR-003: several directories at once, counts add up, offenders of each are named.
first="$(new_dir)"
second="$(new_dir)"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${first}/a.sh"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${first}/b.sh"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${second}/c.sh"
run_checker "${first}" "${second}"
assert_passes 3
printf '#!/usr/bin/env bash\necho bad\n' > "${first}/bad-first.sh"
printf '#!/usr/bin/env bash\necho bad\n' > "${second}/bad-second.sh"
run_checker "${first}" "${second}"
assert_fails
assert_file_contains "${err_file}" "bad-first.sh"
assert_file_contains "${err_file}" "bad-second.sh"
assert_file_not_contains "${err_file}" "${first}/a.sh"
printf 'PASS: FR-003: several directories at once\n'

# FR-004: a missing directory, or a file in place of one, exits 2 and does not pass.
missing="${tmpdir}/does-not-exist"
run_checker "${missing}"
[[ "${rc}" -eq 2 ]] || fail "expected exit 2 for a missing directory, got ${rc}"
assert_file_contains "${err_file}" "${missing}"
assert_file_not_contains "${out_file}" "ok:"
dir="$(new_dir)"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${dir}/good.sh"
run_checker "${dir}" "${missing}"
[[ "${rc}" -eq 2 ]] || fail "expected exit 2 when one of the directories is missing, got ${rc}"
assert_file_not_contains "${out_file}" "ok:"
run_checker "${dir}/good.sh"
[[ "${rc}" -eq 2 ]] || fail "expected exit 2 for a file in place of a directory, got ${rc}"
assert_file_not_contains "${out_file}" "ok:"
printf 'PASS: FR-004: a missing directory or a non-directory exits 2\n'

# FR-005: the same answer on the same files, from any working directory, in a directory that is not a git repository.
dir="$(new_dir)"
printf '#!/usr/bin/env bash\n%s\n' "${HEADER}" > "${dir}/good.sh"
printf '#!/usr/bin/env bash\necho bad\n' > "${dir}/bad.sh"
run_checker "${dir}"
first_rc="${rc}"
first_err="$(cat "${err_file}")"
(
  cd /
  rc=0
  bash "${CHECKER}" "${dir}" >"${out_file}" 2>"${err_file}" || rc=$?
  [[ "${rc}" -eq "${first_rc}" ]] || fail "exit code changed with the working directory: ${first_rc} then ${rc}"
  [[ "$(cat "${err_file}")" == "${first_err}" ]] || fail "stderr changed with the working directory"
)
run_checker "${dir}"
assert_equals "${first_rc}" "${rc}" "the exit code of a second run"
assert_equals "${first_err}" "$(cat "${err_file}")" "stderr of a second run"
printf 'PASS: FR-005: the same answer on the same files from any working directory\n'

# FR-006: the checker is a bash script with set -euo pipefail, carries the header and is ShellCheck-clean.
[[ -f "${CHECKER}" ]] || fail "expected the checker at ${CHECKER}"
assert_equals "#!/usr/bin/env bash" "$(sed -n 1p "${CHECKER}")" "the first line of the checker"
assert_equals "${HEADER}" "$(sed -n 2p "${CHECKER}")" "the second line of the checker"
assert_file_contains "${CHECKER}" "set -euo pipefail"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --severity=warning "${CHECKER}" || fail "ShellCheck found warnings in the checker"
  shellcheck --severity=warning "$0" || fail "ShellCheck found warnings in this test"
else
  printf 'SKIP: shellcheck is not installed\n'
fi
printf 'PASS: FR-006: the checker is bash with set -euo pipefail, carries its own header and is ShellCheck-clean\n'

# FR-003: with no argument the checker looks at resources/ and .github/scripts/ found from its own location,
# whatever the working directory, and leaves the other directories alone (FR-002).
fake_repo="$(new_dir)"
mkdir -p "${fake_repo}/.github/scripts" "${fake_repo}/resources/nested" "${fake_repo}/scripts" "${fake_repo}/.githooks" \
  "${fake_repo}/.claude" "${fake_repo}/.specify" "${fake_repo}/tests"
cp "${CHECKER}" "${fake_repo}/.github/scripts/check-spdx-headers.sh"
printf '#!/usr/bin/env sh\n%s\n' "${HEADER}" > "${fake_repo}/resources/good.sh"
printf '#!/usr/bin/env sh\n%s\n' "${HEADER}" > "${fake_repo}/resources/nested/inner.sh"
for out_of_scope in scripts .githooks .claude .specify tests; do
  printf '#!/usr/bin/env bash\necho no header\n' > "${fake_repo}/${out_of_scope}/headerless.sh"
done
run_default() {
  rc=0
  (cd "$1" && bash "${fake_repo}/.github/scripts/check-spdx-headers.sh") >"${out_file}" 2>"${err_file}" || rc=$?
}
run_default "${tmpdir}"
assert_passes 3
run_default "${fake_repo}/tests"
assert_passes 3
printf '#!/usr/bin/env bash\necho no header\n' > "${fake_repo}/.github/scripts/another.sh"
run_default "${tmpdir}"
assert_fails
assert_file_contains "${err_file}" "another.sh"
rm "${fake_repo}/.github/scripts/another.sh"
printf '#!/usr/bin/env bash\necho no header\n' > "${fake_repo}/resources/nested/headerless.sh"
run_default "${tmpdir}"
assert_fails
assert_file_contains "${err_file}" "resources/nested/headerless.sh"
printf 'PASS: FR-003: with no argument the checker covers resources/ and .github/scripts/ from its own location, nothing else\n'

# FR-002, FR-009, SC-001, SC-002: the repository's own scripts pass, and removing the header from either of the two
# existing scripts turns the checker red on a scratch copy and names that file.
(cd "${REPO_ROOT}" && bash "${CHECKER}") >"${out_file}" 2>"${err_file}" || fail "the repository's own scripts fail: $(cat "${err_file}")"
assert_equals "ok: 3 shell scripts carry the SPDX header" "$(cat "${out_file}")" "stdout on the repository"
assert_file_empty "${err_file}"
for script in resources/sbt-warmup.sh .github/scripts/buildkit-build.sh; do
  scratch="$(new_dir)"
  mkdir -p "${scratch}/.github" "${scratch}/resources"
  cp -R "${REPO_ROOT}/.github/scripts" "${scratch}/.github/scripts"
  cp -R "${REPO_ROOT}/resources/." "${scratch}/resources/"
  grep -v -x -F -- "${HEADER}" "${scratch}/${script}" > "${scratch}/stripped" || true
  cp "${scratch}/stripped" "${scratch}/${script}"
  rc=0
  (cd "${scratch}" && bash .github/scripts/check-spdx-headers.sh) >"${out_file}" 2>"${err_file}" || rc=$?
  assert_fails
  assert_file_contains "${err_file}" "${script}"
done
printf 'PASS: FR-009: the repository'"'"'s own scripts pass; removing the header from either existing script turns the checker red\n'

# FR-010: the workflow has a job named `SPDX headers` that runs this test, then the checker, and the ShellCheck job stays.
[[ -f "${WORKFLOW}" ]] || fail "expected ${WORKFLOW}"
job_block="$(awk '
  /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { if (found) exit; block = "" }
  { block = block $0 "\n" }
  /name: SPDX headers[[:space:]]*$/ { found = 1 }
  END { if (found) printf "%s", block }
' "${WORKFLOW}")"
[[ -n "${job_block}" ]] || fail "expected a job named 'SPDX headers' in ${WORKFLOW}"
job_file="${tmpdir}/job-block"
printf '%s' "${job_block}" > "${job_file}"
assert_file_contains "${job_file}" "runs-on: ubuntu-24.04"
assert_file_contains "${job_file}" "contents: read"
assert_file_contains "${job_file}" "uses: actions/checkout@v7"
assert_file_contains "${job_file}" "bash tests/test_check_spdx_headers.sh"
assert_file_contains "${job_file}" "bash .github/scripts/check-spdx-headers.sh"
test_line="$(grep -n -F 'bash tests/test_check_spdx_headers.sh' "${job_file}" | head -1 | cut -d: -f1)"
checker_line="$(grep -n -F 'bash .github/scripts/check-spdx-headers.sh' "${job_file}" | head -1 | cut -d: -f1)"
[[ "${test_line}" -lt "${checker_line}" ]] || fail "expected the checker's test before the checker in the SPDX headers job"
assert_file_contains "${WORKFLOW}" "name: ShellCheck"
assert_file_contains "${WORKFLOW}" "uses: ludeeus/action-shellcheck@2.0.0"
assert_file_contains "${WORKFLOW}" "severity: warning"
assert_file_contains "${WORKFLOW}" "- '**/*.sh'"
printf 'PASS: FR-010: the SPDX headers job runs the checker'"'"'s test, then the checker, beside the unchanged ShellCheck job\n'
