#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./launch.sh dev
#   ./launch.sh prod emulator-5554
PROFILE="${1:-dev}"
DEVICE="${2:-}"
PROFILE_FILE="config/profiles/${PROFILE}.json"

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
# Use the Flutter China mirror for engine Maven artifacts. Some university
# mirrors can lag new engine hashes and fail resolving flutter_embedding_debug.
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
flutter pub get
dart run build_runner build
flutter run \
	-d "${DEVICE}" \
	--dart-define-from-file="${PROFILE_FILE}"
