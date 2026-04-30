#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./tool/prepare_ios_profile.sh dev debug
#   ./tool/prepare_ios_profile.sh prod release

PROFILE="${1:-dev}"
BUILD_MODE="${2:-debug}"

case "${BUILD_MODE}" in
  debug|profile|release) ;;
  *)
    echo "Invalid build mode: ${BUILD_MODE}. Use debug|profile|release."
    exit 1
    ;;
esac

# When invoked from Xcode Pre-action, SRCROOT points to ios/.
if [[ -n "${SRCROOT:-}" ]]; then
  APP_ROOT="$(cd "${SRCROOT}/.." && pwd)"
else
  APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

PROFILE_FILE="${APP_ROOT}/config/profiles/${PROFILE}.json"
if [[ ! -f "${PROFILE_FILE}" ]]; then
  echo "Profile file not found: ${PROFILE_FILE}"
  echo "Create it from template: ${APP_ROOT}/config/profiles/dev.example.json"
  exit 1
fi

echo "Preparing iOS Flutter config"
echo "- app root : ${APP_ROOT}"
echo "- profile  : ${PROFILE}"
echo "- mode     : ${BUILD_MODE}"

cd "${APP_ROOT}"
flutter build ios \
  --"${BUILD_MODE}" \
  --config-only \
  --dart-define-from-file="${PROFILE_FILE}"

echo "Done. Generated config updated at ios/Flutter/Generated.xcconfig"
