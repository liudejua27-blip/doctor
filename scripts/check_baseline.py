#!/usr/bin/env python3
"""Fail-closed documentation, contract, and prohibited-reference checks."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

import yaml
from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = ROOT / "docs" / "contracts"
EXPECTED_SCHEMAS = {
    "agent-context.schema.json",
    "agent-handoff-result.schema.json",
    "agent-turn-application-result.schema.json",
    "agent-turn.schema.json",
    "approval-decision-application-result.schema.json",
    "body-asset-manifest.schema.json",
    "body-location.schema.json",
    "body-signal-event.schema.json",
    "confirmation-intent-application-result.schema.json",
    "confirmation-transaction-receipt.schema.json",
    "ios-draft-envelope.schema.json",
    "ios-signal-intake-adapter-result.schema.json",
    "ios-signal-intake-application-handoff.schema.json",
    "ios-signal-intake.schema.json",
    "p1c-ux-research-record.schema.json",
    "session-turn-projection-result.schema.json",
}
IGNORED_PARTS = {".git", ".venv", ".venv311", ".build", ".swiftpm", "__pycache__"}
LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
STALE_OPEN_PATTERN = re.compile(r"\bOPEN-P[1-4][A-Z0-9-]*\b")
PROHIBITED_SOURCE_PATTERNS = {
    "RehabMate body.glb": re.compile(r"body\.glb", re.IGNORECASE),
    "Three.js runtime": re.compile(r"three(?:\.js|js)", re.IGNORECASE),
    "GSAP runtime": re.compile(r"\bgsap\b", re.IGNORECASE),
    "WKWebView wrapper": re.compile(r"\bwkwebview\b", re.IGNORECASE),
    "face.a partition": re.compile(r"\bface\.a\b", re.IGNORECASE),
    "world-coordinate marker": re.compile(r"world coordinates?", re.IGNORECASE),
    "RehabMate muscles.js": re.compile(r"muscles\.js", re.IGNORECASE),
}
PINNED_ACTION_PATTERN = re.compile(r"^\s*uses:\s*[^\s@]+@([0-9a-f]{40})(?:\s+#.*)?$", re.MULTILINE)


def _project_files(suffixes: set[str]) -> list[Path]:
    return sorted(
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and path.suffix.lower() in suffixes
        and not any(part in IGNORED_PARTS for part in path.parts)
    )


def _check_markdown(errors: list[str]) -> tuple[int, int]:
    markdown_files = _project_files({".md"})
    checked_links = 0
    for path in markdown_files:
        text = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            if line.endswith((" ", "\t")):
                errors.append(f"{path.relative_to(ROOT)}:{line_number}: trailing whitespace")
        for match in LINK_PATTERN.finditer(text):
            target = match.group(1).strip().strip("<>").split(maxsplit=1)[0]
            if not target or target.startswith(("#", "http://", "https://", "mailto:", "chatgpt-conversation://", "plugin://", "app://")):
                continue
            local_target = unquote(target.split("#", 1)[0])
            if not local_target:
                continue
            checked_links += 1
            resolved = (ROOT / local_target.lstrip("/")) if local_target.startswith("/") else (path.parent / local_target)
            if not resolved.exists():
                errors.append(f"{path.relative_to(ROOT)}: missing link target {target}")
    return len(markdown_files), checked_links


def _check_contracts(errors: list[str]) -> tuple[int, int, int]:
    actual_schemas = {path.name for path in CONTRACTS.glob("*.schema.json")}
    if actual_schemas != EXPECTED_SCHEMAS:
        missing = sorted(EXPECTED_SCHEMAS - actual_schemas)
        unexpected = sorted(actual_schemas - EXPECTED_SCHEMAS)
        errors.append(f"JSON Schema inventory changed; missing={missing} unexpected={unexpected}")
    for path in sorted(CONTRACTS.glob("*.schema.json")):
        try:
            Draft202012Validator.check_schema(json.loads(path.read_text(encoding="utf-8")))
        except Exception as exc:  # noqa: BLE001 - report every contract parse failure together
            errors.append(f"{path.relative_to(ROOT)}: invalid Draft 2020-12 schema: {exc}")

    openapi_path = CONTRACTS / "openapi-v1.yaml"
    try:
        openapi = yaml.safe_load(openapi_path.read_text(encoding="utf-8"))
        if not isinstance(openapi, dict) or not str(openapi.get("openapi", "")).startswith("3."):
            errors.append("docs/contracts/openapi-v1.yaml: expected OpenAPI 3.x document")
            return len(actual_schemas), 0, 0
        paths = openapi.get("paths")
        schemas = openapi.get("components", {}).get("schemas")
        if not isinstance(paths, dict) or not isinstance(schemas, dict):
            errors.append("docs/contracts/openapi-v1.yaml: paths/components.schemas must be mappings")
            return len(actual_schemas), 0, 0
        return len(actual_schemas), len(paths), len(schemas)
    except Exception as exc:  # noqa: BLE001 - normalized CI error
        errors.append(f"docs/contracts/openapi-v1.yaml: invalid YAML/OpenAPI: {exc}")
        return len(actual_schemas), 0, 0


def _check_retired_material(errors: list[str]) -> None:
    for retired in (ROOT / "docs" / "features", ROOT / "docs" / "plans"):
        if retired.exists():
            errors.append(f"retired process directory must remain absent: {retired.relative_to(ROOT)}")
    baseline = ROOT / "docs" / "18_IMPLEMENTED_PROTOTYPE_BASELINE.md"
    for path in _project_files({".md"}):
        text = path.read_text(encoding="utf-8")
        if path != baseline and STALE_OPEN_PATTERN.search(text):
            errors.append(f"{path.relative_to(ROOT)}: stale historical OPEN-P* process ID")
        for target in LINK_PATTERN.findall(text):
            normalized = target.replace("\\", "/")
            if "docs/features/" in normalized or "docs/plans/" in normalized or normalized.startswith(("features/", "plans/")):
                errors.append(f"{path.relative_to(ROOT)}: link to retired process document: {target}")


def _check_prohibited_sources(errors: list[str]) -> None:
    source_roots = (ROOT / "backend" / "src", ROOT / "ios" / "BodyCompanion" / "Sources")
    for source_root in source_roots:
        for path in sorted(source_root.rglob("*")):
            if not path.is_file() or path.suffix.lower() not in {".py", ".swift"}:
                continue
            text = path.read_text(encoding="utf-8")
            for label, pattern in PROHIBITED_SOURCE_PATTERNS.items():
                if pattern.search(text):
                    errors.append(f"{path.relative_to(ROOT)}: prohibited production reference: {label}")


def _check_pydantic_ai_pin(errors: list[str]) -> None:
    pyproject = (ROOT / "backend" / "pyproject.toml").read_text(encoding="utf-8")
    if '"pydantic-ai-slim==2.23.0"' not in pyproject:
        errors.append("backend/pyproject.toml: pydantic-ai-slim must remain pinned to 2.23.0")


def _check_ci_baseline(errors: list[str]) -> None:
    workflow_path = ROOT / ".github" / "workflows" / "ci.yml"
    constraints_path = ROOT / "backend" / "constraints-test.txt"
    try:
        workflow_text = workflow_path.read_text(encoding="utf-8")
        workflow = yaml.safe_load(workflow_text)
    except Exception as exc:  # noqa: BLE001 - normalized CI error
        errors.append(f".github/workflows/ci.yml: invalid YAML: {exc}")
        return
    if not isinstance(workflow, dict) or not isinstance(workflow.get("jobs"), dict):
        errors.append(".github/workflows/ci.yml: jobs must be a mapping")
        return
    if workflow.get("permissions") != {"contents": "read"}:
        errors.append(".github/workflows/ci.yml: top-level permissions must be contents: read only")
    required_fragments = (
        "runs-on: ubuntu-24.04",
        "runs-on: macos-15",
        "python-version: \"3.11\"",
        "python scripts/check_baseline.py",
        "python -m pytest backend/tests --tb=short",
        "swift test",
        "--triple arm64-apple-ios17.0",
        "-c backend/constraints-test.txt",
    )
    for fragment in required_fragments:
        if fragment not in workflow_text:
            errors.append(f".github/workflows/ci.yml: missing baseline fragment: {fragment}")
    uses_lines = [line for line in workflow_text.splitlines() if line.lstrip().startswith("uses:")]
    if len(PINNED_ACTION_PATTERN.findall(workflow_text)) != len(uses_lines):
        errors.append(".github/workflows/ci.yml: every Action must be pinned to a full 40-character SHA")

    try:
        constraints = constraints_path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        errors.append(f"backend/constraints-test.txt: cannot read constraints: {exc}")
        return
    active_constraints = {line for line in constraints if line and not line.startswith("#")}
    for requirement in (
        "pydantic-ai-slim==2.23.0",
        "fastapi==0.116.1",
        "httpx==0.28.1",
        "pytest==8.4.1",
        "jsonschema==4.25.1",
        "PyYAML==6.0.3",
    ):
        if requirement not in active_constraints:
            errors.append(f"backend/constraints-test.txt: missing direct dependency pin {requirement}")
    if any(" @ " in line or line.startswith(("-e ", "--editable")) for line in active_constraints):
        errors.append("backend/constraints-test.txt: URLs and editable requirements are not allowed")


def main() -> int:
    errors: list[str] = []
    markdown_count, checked_links = _check_markdown(errors)
    schema_count, path_count, openapi_schema_count = _check_contracts(errors)
    _check_retired_material(errors)
    _check_prohibited_sources(errors)
    _check_pydantic_ai_pin(errors)
    _check_ci_baseline(errors)

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"baseline_checks=failed errors={len(errors)}", file=sys.stderr)
        return 1

    print(
        "baseline_checks=passed "
        f"markdown_files={markdown_count} checked_links={checked_links} "
        f"json_schemas={schema_count} openapi_paths={path_count} "
        f"openapi_schemas={openapi_schema_count} prohibited_source_matches=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
