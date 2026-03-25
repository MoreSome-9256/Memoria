#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./launch.sh dev
#   ./launch.sh prod emulator-5554
PROFILE="${1:-dev}"
DEVICE="${2:-}"
PROFILE_FILE="config/profiles/${PROFILE}.json"

ensure_isar_generated() {
	local entity_dir="lib/models/entity"
	if [[ ! -d "${entity_dir}" ]]; then
		return
	fi

	local missing=()
	local file
	for file in "${entity_dir}"/*.dart; do
		[[ -f "${file}" ]] || continue
		if [[ "${file}" == *.g.dart ]]; then
			continue
		fi

		local generated="${file%.dart}.g.dart"
		if [[ ! -f "${generated}" ]]; then
			missing+=("${generated}")
		fi
	done

	if [[ ${#missing[@]} -eq 0 ]]; then
		return
	fi

	echo "Detected missing generated files:"
	for file in "${missing[@]}"; do
		echo "  - ${file}"
	done

	echo "Running build_runner to generate Isar code..."
	dart run build_runner build --delete-conflicting-outputs
}

if [[ ! -f "${PROFILE_FILE}" ]]; then
	echo "Profile file not found: ${PROFILE_FILE}"
	echo "Create it from template: config/profiles/dev.example.json"
	exit 1
fi

if [[ -z "${DEVICE}" ]]; then
	DEVICE=$(adb devices -l | grep -v "List of devices" | grep -v "offline" | grep -v "unauthorized" | awk '{print $1}' | head -n1 || true)
fi

if [[ -z "${DEVICE}" ]]; then
	echo "No online device found. Please connect a device or pass one as 2nd arg."
	exit 1
fi

echo "Using profile: ${PROFILE}"
echo "Using device : ${DEVICE}"

ensure_isar_generated

flutter run \
	-d "${DEVICE}" \
	--no-enable-impeller \
	--dart-define-from-file="${PROFILE_FILE}"