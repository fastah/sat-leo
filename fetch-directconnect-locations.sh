#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="aws"
ACCOUNT_REGION="${ACCOUNT_REGION:-us-east-1}"

usage() {
  cat <<'EOF'
Usage: ./fetch-directconnect-locations.sh [--profile PROFILE] [--all-regions]

Lists enabled AWS account regions, then writes Direct Connect locations for
each region to aws/directconnect-<region>.json.

Environment:
  AWS_PROFILE     AWS CLI profile to use, unless --profile is provided.
  ACCOUNT_REGION  Region for aws account list-regions. Defaults to us-east-1.
EOF
}

PROFILE_ARGS=()
REGION_FILTER='map(select(.RegionOptStatus == "ENABLED" or .RegionOptStatus == "ENABLED_BY_DEFAULT"))'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --profile requires a value" >&2
        exit 2
      fi
      PROFILE_ARGS=(--profile "$2")
      shift 2
      ;;
    --all-regions)
      REGION_FILTER='.'
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v aws >/dev/null 2>&1; then
  echo "error: aws CLI is not installed or not in PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is not installed or not in PATH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "Listing AWS account regions..."
REGIONS_JSON="$(
  aws "${PROFILE_ARGS[@]}" account list-regions \
    --no-cli-pager \
    --region "$ACCOUNT_REGION" \
    --output json
)"

TOTAL_AWS_REGIONS="$(jq '.Regions | map(select(.RegionName != null)) | length' <<< "$REGIONS_JSON")"

mapfile -t REGION_ROWS < <(
  jq -r ".Regions | ${REGION_FILTER} | .[] | [.RegionName, .RegionOptStatus] | @tsv" <<< "$REGIONS_JSON" |
    sed '/^$/d' |
    sort
)

if [[ ${#REGION_ROWS[@]} -eq 0 ]]; then
  echo "error: no AWS regions returned by aws account list-regions" >&2
  exit 1
fi

for region_row in "${REGION_ROWS[@]}"; do
  read -r region_code opt_in_status <<< "$region_row"
  output_file="$OUT_DIR/directconnect-${region_code}.json"
  temp_file="${output_file}.tmp"
  echo "Writing AWS ${region_code} (${opt_in_status}) to ${output_file}..."
  aws "${PROFILE_ARGS[@]}" directconnect \
    --no-cli-pager \
    --region="$region_code" \
    describe-locations \
    --output json > "$temp_file"
  mv "$temp_file" "$output_file"
done

echo "Done. Wrote ${#REGION_ROWS[@]} Direct Connect location file(s) to ${OUT_DIR}/. Total AWS regions: ${TOTAL_AWS_REGIONS}."
