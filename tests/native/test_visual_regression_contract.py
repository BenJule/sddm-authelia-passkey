#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
VISUAL = ROOT / "tests/native/visual"

manifest = json.loads(
    (VISUAL / "baselines/manifest.json").read_text(encoding="utf-8")
)

if manifest["state_count"] != 16:
    raise SystemExit("visual state count != 16")

if manifest["case_count"] != 24:
    raise SystemExit("visual case count != 24")

pngs = list((VISUAL / "baselines").rglob("*.png"))

if len(pngs) != 24:
    raise SystemExit(f"baseline PNG count != 24: {len(pngs)}")

for case in manifest["cases"]:
    path = VISUAL / "baselines" / case["file"]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != case["sha256"]:
        raise SystemExit(f"baseline SHA mismatch: {case['file']}")

runner = (VISUAL / "run_visual_regression.sh").read_text(encoding="utf-8")
harness = (VISUAL / "harness/Main.qml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/native-theme.yml").read_text(
    encoding="utf-8"
)

required = (
    'render_case "$STATE" 1280 720 1.00',
    'render_case "$STATE" 1920 1080 "$SCALE"',
    'for SCALE in 1.00 1.25',
    'MAX_CHANGED_RATIO=1_PERCENT',
    'NotoSans-Regular.ttf',
    'QT_FONT_DPI=96',
    '--update-baselines',
)

for token in required:
    if token not in runner:
        raise SystemExit(f"runner contract missing: {token}")

if "sddm.login" in harness:
    raise SystemExit("visual harness contains authentication call")

for token in (
    "visual-regression:",
    "run_visual_regression.sh",
    "native-visual-regression-diagnostics",
    "fonts-noto-core",
):
    if token not in workflow:
        raise SystemExit(f"workflow contract missing: {token}")

print("VISUAL_REGRESSION_CONTRACT=GREEN")
print("VISUAL_STATES=16")
print("VISUAL_CASES=24")
print("AUTHORITY_IN_HARNESS=NO")
