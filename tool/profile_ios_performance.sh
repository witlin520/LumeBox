#!/usr/bin/env bash
set -euo pipefail
# Run on the Mac connected to the iPhone; pass its `flutter devices` ID.
# Inspect cold-start marks and frame timing under Settings > 流畅度采集.
if [ "$#" -ne 1 ]; then
  echo "Usage: bash tool/profile_ios_performance.sh <iphone-device-id>" >&2
  exit 2
fi
flutter run --profile -d "$1" --dart-define=LUME_PROFILE_STARTUP=true
