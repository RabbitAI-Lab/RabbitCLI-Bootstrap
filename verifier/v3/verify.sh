#!/usr/bin/env bash
# Verifier v3 for cli-scaffold: v2 checks + customizable config dir (--config-dir).
set -u
cd "$(dirname "$0")/../.."
PASS=0; FAIL=0

check() {
  if [ "$2" -eq 0 ]; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi
}

npm run build >/tmp/v2_build.log 2>&1
check "build succeeds (tsc exit 0)" $?
[ -f dist/cli.js ]; check "dist/cli.js exists" $?

CLI="node dist/cli.js"
export MYCLI_CONFIG_DIR=/tmp/mycli-verify-config

$CLI --help >/tmp/v2_help.out 2>&1
check "--help exit 0" $?

$CLI demo +hello >/tmp/v2_hello.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"ok": *true' /tmp/v2_hello.out
check "demo +hello ok:true envelope" $?

$CLI api GET /v1/items --dry-run >/tmp/v2_dry.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"dry_run": *true' /tmp/v2_dry.out
check "api --dry-run previews request" $?

$CLI badcmd >/dev/null 2>&1
[ $? -eq 2 ]
check "unknown command exits 2" $?

$CLI demo items list >/tmp/v2_items.out 2>&1
rc=$?; [ $rc -ne 0 ] && grep -q '"ok": *false' /tmp/v2_items.out
check "items list without network yields structured error envelope" $?

if grep -riE 'feishu|lark|飞书' . --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=verifier --exclude=package-lock.json >/dev/null 2>&1; then
  check "no Feishu/Lark references" 1
else
  check "no Feishu/Lark references" 0
fi

grep -q '+hello' src/commands/demo.ts && grep -q 'items' src/commands/demo.ts && [ -f src/commands/api.ts ]
check "three command layers present (shortcut/resource/raw-api)" $?

# --- v2: self-update ---
$CLI update --help >/tmp/v2_uhelp.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q -- '--check' /tmp/v2_uhelp.out && grep -q -- '--registry' /tmp/v2_uhelp.out
check "update command registered with --check/--registry" $?

node --input-type=module -e "
import { compareVersions } from './dist/lib/update.js';
const ok =
  compareVersions('1.2.0','1.1.9') > 0 &&
  compareVersions('0.1.0','0.1.0') === 0 &&
  compareVersions('0.9.9','0.10.0') < 0 &&
  compareVersions('v1.0.1','1.0.0') > 0;
process.exit(ok ? 0 : 1);
"
check "compareVersions unit assertions" $?

node --input-type=module -e "
import { fetchLatestVersion } from './dist/lib/update.js';
const v = await fetchLatestVersion('typescript');
if (!/^\d+\.\d+\.\d+/.test(v)) process.exit(1);
console.error('typescript latest = ' + v);
" 2>/tmp/v2_tsver.txt
check "fetchLatestVersion('typescript') returns a version" $?
echo "  (typescript latest: $(cat /tmp/v2_tsver.txt))"

$CLI update --check --package typescript >/tmp/v2_ucheck.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q 'update_available' /tmp/v2_ucheck.out
check "update --check end-to-end" $?

# --- v3: customizable config dir ---
rm -rf /tmp/mycli-cfg-custom
$CLI config --config-dir /tmp/mycli-cfg-custom set foo bar >/tmp/v3_set.out 2>&1
rc=$?; [ $rc -eq 0 ] && [ -f /tmp/mycli-cfg-custom/config.json ] && grep -q '"foo": *"bar"' /tmp/mycli-cfg-custom/config.json
check "--config-dir writes config to the given directory" $?

$CLI config --config-dir /tmp/mycli-cfg-custom show >/tmp/v3_show.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"foo": *"bar"' /tmp/v3_show.out && grep -q '/tmp/mycli-cfg-custom' /tmp/v3_show.out
check "config show reads from --config-dir and reports _dir" $?

rm -rf /tmp/mycli-cfg-env
MYCLI_CONFIG_DIR=/tmp/mycli-cfg-env $CLI config set baz qux >/dev/null 2>&1
[ -f /tmp/mycli-cfg-env/config.json ] && grep -q '"baz": *"qux"' /tmp/mycli-cfg-env/config.json
check "MYCLI_CONFIG_DIR env var works" $?

MYCLI_CONFIG_DIR=/tmp/mycli-cfg-env $CLI config --config-dir /tmp/mycli-cfg-custom get foo >/tmp/v3_pri.out 2>&1
grep -q '"value": *"bar"' /tmp/v3_pri.out
check "--config-dir takes precedence over MYCLI_CONFIG_DIR" $?

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
