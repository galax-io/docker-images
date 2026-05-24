#!/usr/bin/env bash
# Updates README.md with current image sizes and version badges.
# Expects RELEASE_VERSION env var to be set.

set -euo pipefail

RELEASE_VERSION="${RELEASE_VERSION:-latest}"
README="README.md"

image_size() {
  local image="${1}"
  local tag="${2}"

  size="$(docker manifest inspect "${image}:${tag}" 2>/dev/null \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
total = sum(l.get('size', 0) for m in data.get('manifests', [data]) for l in m.get('layers', []))
if total == 0:
    total = sum(l.get('size', 0) for l in data.get('layers', []))
mb = total / (1024 * 1024)
print(f'{mb:.0f}MB')
" 2>/dev/null || printf 'N/A')"

  printf '%s' "${size}"
}

IMAGES=(
  "galaxioteam/galaxio-cli:${RELEASE_VERSION}"
  "galaxioteam/base-jdk:17-${RELEASE_VERSION}"
  "galaxioteam/base-jdk:21-${RELEASE_VERSION}"
  "galaxioteam/gatling-sbt-builder:17-${RELEASE_VERSION}"
  "galaxioteam/gatling-sbt-builder:21-${RELEASE_VERSION}"
  "galaxioteam/gatling-maven-builder:17-${RELEASE_VERSION}"
  "galaxioteam/gatling-maven-builder:21-${RELEASE_VERSION}"
  "galaxioteam/gatling-gradle-builder:17-${RELEASE_VERSION}"
  "galaxioteam/gatling-gradle-builder:21-${RELEASE_VERSION}"
  "galaxioteam/gatling-sbt-runtime:17-${RELEASE_VERSION}"
  "galaxioteam/gatling-sbt-runtime:21-${RELEASE_VERSION}"
  "galaxioteam/gatling-maven-runtime:17-${RELEASE_VERSION}"
  "galaxioteam/gatling-maven-runtime:21-${RELEASE_VERSION}"
  "galaxioteam/gatling-gradle-runtime:17-${RELEASE_VERSION}"
  "galaxioteam/gatling-gradle-runtime:21-${RELEASE_VERSION}"
  "galaxioteam/gatling-sbt-debug:17-${RELEASE_VERSION}"
  "galaxioteam/gatling-sbt-debug:21-${RELEASE_VERSION}"
  "galaxioteam/gatling-maven-debug:17-${RELEASE_VERSION}"
  "galaxioteam/gatling-maven-debug:21-${RELEASE_VERSION}"
  "galaxioteam/gatling-gradle-debug:17-${RELEASE_VERSION}"
  "galaxioteam/gatling-gradle-debug:21-${RELEASE_VERSION}"
)

printf 'Collecting image sizes...\n'

TABLE="| Image | Tag | Size |\n|-------|-----|------|\n"
for image_tag in "${IMAGES[@]}"; do
  image="${image_tag%%:*}"
  tag="${image_tag#*:}"
  size="$(image_size "${image}" "${tag}")"
  short_name="${image#galaxioteam/}"
  TABLE+="| \`${short_name}\` | \`${tag}\` | ${size} |\n"
  printf '  %s:%s → %s\n' "${image}" "${tag}" "${size}"
done

# Replace content between markers in README
IMAGE_TABLE="${TABLE}" python3 - "${README}" <<'PYEOF'
import os, sys, re

readme_path = sys.argv[1]
table = os.environ["IMAGE_TABLE"]

with open(readme_path, 'r') as f:
    content = f.read()

# Replace between <!-- IMAGE-SIZES-START --> and <!-- IMAGE-SIZES-END -->
pattern = r'(<!-- IMAGE-SIZES-START -->).*?(<!-- IMAGE-SIZES-END -->)'
replacement = r'\1\n\n' + table.rstrip() + r'\n\n\2'
new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

if new_content == content:
    # Markers not found — append section
    new_content += '\n\n<!-- IMAGE-SIZES-START -->\n\n' + table.rstrip() + '\n\n<!-- IMAGE-SIZES-END -->\n'

tmp_path = readme_path + '.tmp'
with open(tmp_path, 'w') as f:
    f.write(new_content)
os.replace(tmp_path, readme_path)

print('README updated.')
PYEOF
