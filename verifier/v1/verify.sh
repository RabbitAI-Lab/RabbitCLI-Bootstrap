#!/usr/bin/env bash
# Verifier v1 for cli-scaffold. Run from the project root.
set -u
cd "$(dirname "$0")/../.."
PASS=0; FAIL=0

check() { # name, condition-exit-code
  if [ "$2" -eq 0 ]; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi
}

# 1. build
npm run build >/tmp/v_build.log 2>&1
check "build succeeds (tsc exit 0)" $?
[ -f dist/cli.js ]; check "dist/cli.js exists" $?

CLI="node dist/cli.js"
export MYCLI_CONFIG_DIR=/tmp/mycli-verify-config

# 2. smoke tests
$CLI --help >/tmp/v_help.out 2>&1
check "--help exit 0" $?

$CLI demo +hello >/tmp/v_hello.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"ok": *true' /tmp/v_hello.out
check "demo +hello ok:true envelope" $?

$CLI api GET /v1/items --dry-run >/tmp/v_dry.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"dry_run": *true' /tmp/v_dry.out
check "api --dry-run previews request" $?

$CLI badcmd >/dev/null 2>&1
[ $? -eq 2 ]
check "unknown command exits 2" $?

$CLI demo items list >/tmp/v_items.out 2>&1
rc=$?; [ $rc -ne 0 ] && grep -q '"ok": *false' /tmp/v_items.out
check "items list without network yields structured error envelope" $?

# 3. no Feishu/Lark references (excluding node_modules, lockfile, verifier itself)
if grep -riE 'feishu|lark|飞书' . --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=verifier --exclude=package-lock.json >/tmp/v_grep.out 2>&1; then
  check "no Feishu/Lark references" 1
else
  check "no Feishu/Lark references" 0
fi

# 4. three-layer architecture present
grep -q '+hello' src/commands/demo.ts && grep -q 'items' src/commands/demo.ts && [ -f src/commands/api.ts ]
check "three command layers present (shortcut/resource/raw-api)" $?

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
