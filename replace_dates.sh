#!/bin/bash

set -euo pipefail

# Replace placeholder dates in posts

PLACEHOLDER_REGEX='^date = "3000-01-01T00:00:00+00:00"$'
PLACEHOLDER_DATE_FILES=($(grep -rl "${PLACEHOLDER_REGEX}" content))
if [[ -z "${PLACEHOLDER_DATE_FILES[@]}" ]]; then
  # No placeholders to process
  exit 0
fi

DATE=$(date -Iseconds)

echo "Found placeholder date in $PLACEHOLDER_DATE_FILES"

for FILE in $PLACEHOLDER_DATE_FILES; do
  sed -i.swp -e "s/${PLACEHOLDER_REGEX}/date = \"${DATE}\"/" "${FILE}" && rm "${FILE}.swp"
done
