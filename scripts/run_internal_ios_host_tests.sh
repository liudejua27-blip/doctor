#!/usr/bin/env bash
# Run the internal-only iOS App Host smoke suite on an available iPhone Simulator.
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
project_path="$repository_root/ios/BodyCompanion/AppHost/BodyCompanionInternal.xcodeproj"
simulator_udid="${BODY_COMPANION_SIMULATOR_UDID:-}"

if [[ -z "$simulator_udid" ]]; then
  simulator_udid="$({
    xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json
import sys

devices = json.load(sys.stdin).get("devices", {})
candidates = []
for runtime, entries in devices.items():
    for device in entries:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            candidates.append((device.get("state") != "Booted", runtime, device["name"], device["udid"]))

if not candidates:
    raise SystemExit("No available iPhone Simulator found. Set BODY_COMPANION_SIMULATOR_UDID to an available device.")

print(sorted(candidates)[0][3])
'
  } )"
fi

result_directory="$(mktemp -d)"
result_bundle="$result_directory/body-companion-host-smoke.xcresult"
trap 'rm -rf "$result_directory"' EXIT

set +e
xcodebuild -quiet \
  -project "$project_path" \
  -scheme BodyCompanionInternal \
  -configuration DebugInternal \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  test \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ONLY_ACTIVE_ARCH=YES \
  -resultBundlePath "$result_bundle"
test_status=$?
set -e

if [[ "$test_status" -ne 0 ]]; then
  echo "Internal Host smoke xcresult summary:"
  xcrun xcresulttool get test-results summary --path "$result_bundle" --compact || true
fi

exit "$test_status"
