#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
run_dir="$(mktemp -d "${TMPDIR:-/tmp}/huddlz-tests.XXXXXX")"
workers="${HUDDLZ_TEST_WORKERS:-4}"
destination="${HUDDLZ_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
derived_data="${HUDDLZ_TEST_DERIVED_DATA:-${TMPDIR:-/tmp}/huddlz-behavior-tests}"

printf 'Results: %s\nSimulator workers: %s\n' "$run_dir" "$workers"
started=$SECONDS
status=0
caffeinate -i xcodebuild test \
  -project Huddlz/Huddlz.xcodeproj -scheme Huddlz \
  -destination "$destination" \
  -parallel-testing-enabled YES -parallel-testing-worker-count "$workers" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$run_dir/HuddlzTests.xcresult" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  "$@" > "$run_dir/xcodebuild.log" 2>&1 || status=$?
printf 'Elapsed: %dm %ds\nLog: %s/xcodebuild.log\n' "$(((SECONDS-started)/60))" "$(((SECONDS-started)%60))" "$run_dir"
if [[ -d "$run_dir/HuddlzTests.xcresult" ]]; then
  xcrun xcresulttool get test-results summary --path "$run_dir/HuddlzTests.xcresult" \
    > "$run_dir/summary.json" || true
  python3 - "$run_dir/summary.json" <<'PYREPORT' || status=1
import json
import sys
with open(sys.argv[1]) as result_file:
    result = json.load(result_file)
count = result["totalTestCount"]
print(f'{result["result"]}: {count} tests, {result["failedTests"]} failed, {result["skippedTests"]} skipped')
if count == 0 or result["result"] != "Passed":
    sys.exit(1)
PYREPORT
fi
if [[ "$status" -ne 0 ]]; then tail -60 "$run_dir/xcodebuild.log"; fi
exit "$status"
