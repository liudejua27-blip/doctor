#!/usr/bin/env python3
"""Static boundary checks for the internal Simulator-only iOS App Host."""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / "ios" / "BodyCompanion" / "AppHost"
PROJECT = HOST / "BodyCompanionInternal.xcodeproj"
APP_SOURCE = HOST / "BodyCompanionInternal"
HOST_RESOURCES = APP_SOURCE / "Resources"
PACKAGE_RESOURCES = ROOT / "ios" / "BodyCompanion" / "Sources" / "BodyCompanionIOS" / "Resources"
UI_TEST_SOURCE = HOST / "BodyCompanionInternalUITests" / "BodyCompanionInternalUITests.swift"
BODY_MAP_SCREEN_SOURCE = ROOT / "ios" / "BodyCompanion" / "Sources" / "BodyCompanionIOS" / "BodyMapScreen.swift"
SIGNAL_INTAKE_SCREEN_SOURCE = ROOT / "ios" / "BodyCompanion" / "Sources" / "BodyCompanionIOS" / "SignalIntakeScreen.swift"
SIGNAL_INTAKE_CORE_SOURCE = ROOT / "ios" / "BodyCompanion" / "Sources" / "BodyCompanionCore" / "SignalIntake.swift"


def fail(message: str) -> None:
    print(f"internal_ios_host_checks=failed reason={message}")
    raise SystemExit(1)


def require_file(path: Path) -> None:
    if not path.is_file():
        fail(f"missing_file:{path.relative_to(ROOT)}")


def require_text(path: Path, expected: str) -> str:
    text = path.read_text(encoding="utf-8")
    if expected not in text:
        fail(f"missing_text:{path.relative_to(ROOT)}:{expected}")
    return text


def main() -> int:
    required_files = [
        PROJECT / "project.pbxproj",
        PROJECT / "xcshareddata" / "xcschemes" / "BodyCompanionInternal.xcscheme",
        APP_SOURCE / "BodyCompanionInternalApp.swift",
        APP_SOURCE / "InternalHostLaunchOptions.swift",
        APP_SOURCE / "Info.plist",
        HOST_RESOURCES / "BodyNeutralPrototype.usdz",
        HOST_RESOURCES / "BodyNeutralPrototypeCollision.usdz",
        HOST_RESOURCES / "body-neutral-procedural-v1.camera_presets.json",
        HOST_RESOURCES / "body-neutral-procedural-v1.region_map.json",
        HOST_RESOURCES / "body-neutral-procedural-v1.surface_correspondence.json",
        UI_TEST_SOURCE,
        BODY_MAP_SCREEN_SOURCE,
        SIGNAL_INTAKE_SCREEN_SOURCE,
        SIGNAL_INTAKE_CORE_SOURCE,
        HOST / "Config" / "Base.xcconfig",
        HOST / "Config" / "DebugInternal.xcconfig",
        HOST / "Config" / "ReleaseInternal.xcconfig",
        ROOT / "scripts" / "run_internal_ios_host_tests.sh",
    ]
    for path in required_files:
        require_file(path)

    project = require_text(PROJECT / "project.pbxproj", "relativePath = ..;")
    for expected in (
        "productName = BodyCompanionIOS;",
        "BodyCompanionIOS in Frameworks",
        "com.apple.product-type.application",
        "com.apple.product-type.bundle.ui-testing",
        "TEST_TARGET_NAME = BodyCompanionInternal;",
        "BodyNeutralPrototype.usdz in Resources",
        "BodyNeutralPrototypeCollision.usdz in Resources",
        "body-neutral-procedural-v1.region_map.json in Resources",
        "body-neutral-procedural-v1.surface_correspondence.json in Resources",
    ):
        if expected not in project:
            fail(f"invalid_project_wiring:{expected}")
    if "BodyCompanionPrototype" in project:
        fail("prototype_executable_must_not_be_host_dependency")
    if "SystemCapabilities" in project or ".entitlements" in project:
        fail("unexpected_capability_or_entitlements")
    if PACKAGE_RESOURCES.exists() and any(PACKAGE_RESOURCES.iterdir()):
        fail("candidate_resources_must_not_live_in_reusable_swift_package")

    scheme = (PROJECT / "xcshareddata" / "xcschemes" / "BodyCompanionInternal.xcscheme").read_text(encoding="utf-8")
    for expected in ("BodyCompanionInternalUITests.xctest", "DebugInternal", "BodyCompanionInternal.app"):
        if expected not in scheme:
            fail(f"invalid_scheme:{expected}")

    app_entry = require_text(
        APP_SOURCE / "BodyCompanionInternalApp.swift",
        "AppShell(runtimeConfiguration: InternalHostLaunchOptions.runtimeConfiguration)",
    )
    if "BodyCompanionPrototype" in app_entry:
        fail("app_entry_must_not_import_prototype")

    launch_options = require_text(
        APP_SOURCE / "InternalHostLaunchOptions.swift",
        "candidate3DEnabled: candidateRequested && !isUISmoke",
    )
    if "UserDefaults" in launch_options:
        fail("launch_options_must_not_persist")

    for source in APP_SOURCE.glob("*.swift"):
        text = source.read_text(encoding="utf-8")
        for forbidden in (
            "URLSession",
            "URLRequest",
            "UserDefaults",
            "FileManager",
            "Keychain",
            "HKHealthStore",
            "HealthKit",
            "AVCapture",
            "UNUserNotification",
            "PHPhoto",
            "CLLocation",
            "Sentry",
            "Analytics",
        ):
            if forbidden in text:
                fail(f"forbidden_host_source:{source.name}:{forbidden}")

    ui_test = UI_TEST_SOURCE.read_text(encoding="utf-8")
    for expected in (
        '"BODY_COMPANION_UI_SMOKE"',
        '"BODY_COMPANION_ENABLE_CANDIDATE_3D"',
        '"body-map.text-picker-open"',
        '"body-map.text-picker.search"',
        '"body-map.text-picker.option-body.knee.general-left-lateral"',
        '"body-map.text-picker.selection-notice"',
        '"body-map.pending-mark-summary"',
        '"body-map.continuation-unavailable"',
        '"body-map.marker-count-empty"',
        '"body-map.fallback-notice"',
        '"body-map.candidate-3d-ready"',
        '"body-map.candidate-3d-fallback-notice"',
        '"body-map.candidate-3d-load-attempted"',
        '"screen.records"',
        '"analysis.standard-chat-unavailable"',
        '"sensation-picker.more-open"',
        '"麻木"',
        '"sensation-picker.per-location-unknown"',
        '"这些位置的感觉都说不清"',
        "testMoreSensationsKeepsStructuredInternalDraftFlow",
        "testMultipleLocationsKeepPerLocationUnknownDistinctFromGroupUnknown",
        "failure-accessibility-hierarchy",
        "launchCandidateThreeDProbe",
    ):
        if expected not in ui_test:
            fail(f"missing_ui_smoke_assertion:{expected}")

    body_map_screen = require_text(BODY_MAP_SCREEN_SOURCE, '"body-map.candidate-3d-ready"')
    for expected in (
        '"body-map.candidate-3d-loading"',
        '"body-map.candidate-3d-fallback-notice"',
        '"body-map.candidate-3d-load-attempted"',
        '"body-map.text-picker-open"',
        '"body-map.3d-scene"',
        "allowsPrototypeCandidate: true",
        "identifierPrefix).selection-notice",
        "identifierPrefix).empty",
        '"body-map.pending-mark-summary"',
        '"body-map.continuation-unavailable"',
        "Button(action: onContinue)",
    ):
        if expected not in body_map_screen:
            fail(f"missing_candidate_probe_boundary:{expected}")

    signal_intake_screen = require_text(SIGNAL_INTAKE_SCREEN_SOURCE, '"sensation-picker.more-open"')
    for expected in (
        '"sensation-picker.safety-editing-locked"',
        "SignalSensationCode.additionalCases",
        "displayedCommonSensationCodes",
        "model.isSensationEditingBlockedBySafetyAction",
    ):
        if expected not in signal_intake_screen:
            fail(f"missing_sensation_entry_boundary:{expected}")

    signal_intake_core = require_text(SIGNAL_INTAKE_CORE_SOURCE, "sensationRevisionRequiresServer")
    for expected in (
        "public static var additionalCases",
        "commonCases(forLocationCount",
        "prepareSemanticSensationMutation",
        "isSensationEditingBlockedBySafetyAction",
    ):
        if expected not in signal_intake_core:
            fail(f"missing_sensation_core_boundary:{expected}")

    info = plistlib.loads((APP_SOURCE / "Info.plist").read_bytes())
    restricted_info_keys = {
        "NSAppleMusicUsageDescription",
        "NSBluetoothAlwaysUsageDescription",
        "NSCameraUsageDescription",
        "NSHealthClinicalHealthRecordsShareUsageDescription",
        "NSHealthShareUsageDescription",
        "NSHealthUpdateUsageDescription",
        "NSLocationAlwaysAndWhenInUseUsageDescription",
        "NSLocationWhenInUseUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSPhotoLibraryAddUsageDescription",
        "NSPhotoLibraryUsageDescription",
    }
    unexpected_keys = sorted(restricted_info_keys.intersection(info))
    if unexpected_keys:
        fail(f"restricted_info_keys:{','.join(unexpected_keys)}")

    entitlements = list(HOST.rglob("*.entitlements"))
    if entitlements:
        fail("unexpected_entitlements")

    for config in (HOST / "Config").glob("*.xcconfig"):
        content = config.read_text(encoding="utf-8")
        if re.search(r"^[ \t]*DEVELOPMENT_TEAM[ \t]*=[ \t]*[A-Za-z0-9]{5,}[ \t]*$", content, flags=re.MULTILINE):
            fail(f"committed_development_team:{config.name}")
        if re.search(r"^[ \t]*PRODUCT_BUNDLE_IDENTIFIER[ \t]*=[ \t]*(?!com\.example\.)\S+", content, flags=re.MULTILINE):
            fail(f"non_placeholder_bundle_id:{config.name}")

    print("internal_ios_host_checks=passed host_sources=2 ui_smoke_sources=1 entitlements=0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
