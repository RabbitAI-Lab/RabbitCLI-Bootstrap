#!/usr/bin/env bash
# Verifier v4 for cli-scaffold (Go edition): static binary, smoke tests,
# config-dir precedence, semver unit tests, self-update check, Kylin targets.
set -u
cd "$(dirname "$0")/../.."
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi; }

# --- Go toolchain bootstrap ---
if ! command -v go >/dev/null 2>&1; then
  if [ -x /tmp/go/bin/go ]; then export PATH=/tmp/go/bin:$PATH;
  else
    echo "Go not found, downloading toolchain to /tmp/go ..."
    arch=$(uname -m); [ "$arch" = "x86_64" ] && arch=amd64 || arch=arm64
    curl -sL -o /tmp/go.tgz "https://go.dev/dl/go1.23.12.linux-${arch}.tar.gz" && tar -C /tmp -xzf /tmp/go.tgz
    export PATH=/tmp/go/bin:$PATH
  fi
fi
export GOPATH=${GOPATH:-/tmp/gopath} GOCACHE=${GOCACHE:-/tmp/gocache} GOFLAGS=-mod=mod
go version >/dev/null 2>&1
check "go toolchain available" $?

# --- 1. static binary ---
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X github.com/RabbitAI-Lab/RabbitCLI-Bootstrap/internal/cli.Version=0.1.0" -o bin/rabbitcli ./cmd/rabbitcli >/tmp/v4_build.log 2>&1
check "build succeeds (static binary)" $?
[ -x bin/rabbitcli ]; check "bin/rabbitcli is executable" $?
ldd bin/rabbitcli 2>&1 | grep -qE 'not a dynamic executable|statically linked'
check "binary is statically linked (ldd)" $?

CLI=./bin/rabbitcli
export RABBITCLI_CONFIG_DIR=/tmp/rabbitcli-v4-config

# --- 2. smoke tests ---
$CLI --help >/tmp/v4_help.out 2>&1
check "--help exit 0" $?

$CLI demo +hello >/tmp/v4_hello.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"ok": true' /tmp/v4_hello.out
check "demo +hello ok:true envelope" $?

$CLI api GET /v1/items --dry-run >/tmp/v4_dry.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"dry_run": true' /tmp/v4_dry.out
check "api --dry-run previews request" $?

$CLI badcmd >/dev/null 2>&1
[ $? -eq 2 ]
check "unknown command exits 2" $?

$CLI demo items list >/tmp/v4_items.out 2>&1
rc=$?; [ $rc -ne 0 ] && grep -q '"ok": false' /tmp/v4_items.out
check "items list without network yields structured error envelope" $?

# --- 3. no Feishu/Lark references ---
if grep -riE 'feishu|lark|飞书' . --exclude-dir=verifier --exclude-dir=bin --exclude-dir=dist --exclude-dir=.git >/dev/null 2>&1; then
  check "no Feishu/Lark references" 1
else
  check "no Feishu/Lark references" 0
fi

# --- 4. three-layer architecture ---
grep -q '+hello' internal/cli/cmd_demo.go && grep -q 'items' internal/cli/cmd_demo.go && [ -f internal/cli/cmd_api.go ]
check "three command layers present (shortcut/resource/raw-api)" $?

# --- 5. config dir precedence ---
rm -rf /tmp/rabbitcli-v4-custom /tmp/rabbitcli-v4-env
$CLI config --config-dir /tmp/rabbitcli-v4-custom set foo bar >/dev/null 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"foo": "bar"' /tmp/rabbitcli-v4-custom/config.json
check "--config-dir writes config to the given directory" $?

$CLI config --config-dir /tmp/rabbitcli-v4-custom show >/tmp/v4_show.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"foo": "bar"' /tmp/v4_show.out && grep -q '/tmp/rabbitcli-v4-custom' /tmp/v4_show.out
check "config show reads from --config-dir and reports _dir" $?

RABBITCLI_CONFIG_DIR=/tmp/rabbitcli-v4-env $CLI config set baz qux >/dev/null 2>&1
grep -q '"baz": "qux"' /tmp/rabbitcli-v4-env/config.json 2>/dev/null
check "RABBITCLI_CONFIG_DIR env var works" $?

RABBITCLI_CONFIG_DIR=/tmp/rabbitcli-v4-env $CLI config --config-dir /tmp/rabbitcli-v4-custom get foo >/tmp/v4_pri.out 2>&1
grep -q '"value": "bar"' /tmp/v4_pri.out
check "--config-dir takes precedence over RABBITCLI_CONFIG_DIR" $?

# --- 6. semver unit tests ---
go test ./internal/cli/ >/tmp/v4_test.log 2>&1
check "go test (CompareVersions assertions)" $?

# --- 7. self-update check end-to-end (real GitHub repo) ---
$CLI update --check --repo cli/cli >/tmp/v4_ucheck.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q 'update_available' /tmp/v4_ucheck.out
check "update --check --repo cli/cli end-to-end" $?
grep -o '"latest": "[^"]*"' /tmp/v4_ucheck.out | sed 's/^/  (gh latest: /;s/$/)/' || true

# --- 8. Kylin targets cross-compile ---
CGO_ENABLED=0 GOOS=linux GOARCH=arm64   go build -trimpath -o /tmp/rabbitcli-linux-arm64   ./cmd/rabbitcli >/dev/null 2>&1 \
&& CGO_ENABLED=0 GOOS=linux GOARCH=loong64 go build -trimpath -o /tmp/rabbitcli-linux-loong64 ./cmd/rabbitcli >/dev/null 2>&1
check "cross-compile linux/arm64 + linux/loong64 (Kylin)" $?

# --- v5: logging framework ---
rm -rf /tmp/rcfg-v5
$CLI config --config-dir /tmp/rcfg-v5 set token secrettoken123 >/dev/null 2>&1
$CLI api GET 'https://httpbin.org/get?access_token=secrettoken123' --debug --config-dir /tmp/rcfg-v5 >/tmp/v5_debug_stdout.out 2>/dev/null
rc=$?
LOGFILE=$(ls /tmp/rcfg-v5/logs/rabbitcli-*.log 2>/dev/null | head -1)
[ $rc -eq 0 ] && [ -n "$LOGFILE" ] && grep -q '"msg":"command start"' "$LOGFILE" && grep -q '"msg":"command done"' "$LOGFILE"
check "log file created with command start/done records" $?

[ -n "$LOGFILE" ] && grep -q '"msg":"http request"' "$LOGFILE" && grep -q '"elapsed_ms"' "$LOGFILE"
check "debug level logs http request (method/url/status/elapsed)" $?

if [ -n "$LOGFILE" ] && grep -q 'secrettoken123' "$LOGFILE"; then
  check "token never appears in logs (args + URL redacted)" 1
else
  check "token never appears in logs (args + URL redacted)" 0
fi

grep -q 'access_token=\*\*\*' "$LOGFILE" 2>/dev/null
check "sensitive query values redacted to ***" $?

grep -q '"ok": true' /tmp/v5_debug_stdout.out && ! grep -q '"msg":' /tmp/v5_debug_stdout.out
check "stdout stays a pure JSON envelope under --debug" $?

rm -rf /tmp/rcfg-v5b
$CLI demo +hello --config-dir /tmp/rcfg-v5b >/dev/null 2>&1
if ls /tmp/rcfg-v5b/logs/*.log >/dev/null 2>&1; then
  if grep -q '"level":"INFO"\|"level":"DEBUG"' /tmp/rcfg-v5b/logs/*.log; then
    check "default warn level suppresses info/debug records" 1
  else
    check "default warn level suppresses info/debug records" 0
  fi
else
  check "default warn level suppresses info/debug records" 0
fi

rm -rf /tmp/rlog-v5
RABBITCLI_LOG_DIR=/tmp/rlog-v5 $CLI demo +hello --config-dir /tmp/rcfg-v5b >/dev/null 2>&1
ls /tmp/rlog-v5/rabbitcli-*.log >/dev/null 2>&1
check "RABBITCLI_LOG_DIR overrides log location" $?

[ "$(go list -m all 2>/dev/null | wc -l)" -eq 1 ]
check "zero third-party module dependencies" $?

# --- v6: environment switcher ---
rm -rf /tmp/envtest-v6
ECFG="--config-dir /tmp/envtest-v6"
$CLI env $ECFG add dev --base-url https://dev-api.example.com >/dev/null 2>&1
rc1=$?
$CLI env $ECFG add prod --base-url https://api.example.com >/dev/null 2>&1
rc2=$?
$CLI env $ECFG use dev >/dev/null 2>&1
rc3=$?
[ $rc1 -eq 0 ] && [ $rc2 -eq 0 ] && [ $rc3 -eq 0 ]
check "env add x2 + env use succeed" $?

grep -q '"current_env": "dev"' /tmp/envtest-v6/config.json
check "env use persists current_env to config file" $?

$CLI env $ECFG list >/tmp/v6_list.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q 'dev-api.example.com' /tmp/v6_list.out && grep -q '"current": "dev"' /tmp/v6_list.out
check "env list shows both environments and active marker" $?

$CLI api GET /v1/items $ECFG --dry-run 2>/dev/null | grep -q 'https://dev-api.example.com/v1/items'
check "dry-run uses active env baseUrl (dev)" $?

$CLI api GET /v1/items $ECFG --env prod --dry-run 2>/dev/null | grep -q 'https://api.example.com/v1/items'
check "--env flag overrides persisted env" $?

RABBITCLI_ENV=prod $CLI api GET /v1/items $ECFG --dry-run 2>/dev/null | grep -q 'https://api.example.com/v1/items'
check "RABBITCLI_ENV env var works" $?

RABBITCLI_ENV=dev $CLI api GET /v1/items $ECFG --env prod --dry-run 2>/dev/null | grep -q 'https://api.example.com/v1/items'
check "--env flag takes precedence over RABBITCLI_ENV" $?

$CLI api GET /v1/items $ECFG --env nope --dry-run >/tmp/v6_nope.out 2>&1
rc=$?; [ $rc -ne 0 ] && grep -q '"type": "config"' /tmp/v6_nope.out
check "unknown environment yields structured config error" $?

$CLI config $ECFG show >/tmp/v6_show.out 2>&1
grep -q '"_env": "dev"' /tmp/v6_show.out
check "config show reports _env" $?

# --- v7: log rotation by size ---
rm -rf /tmp/rtest-v7
for i in $(seq 1 15); do
  RABBITCLI_LOG_MAX_SIZE=2048 $CLI api GET 'https://httpbin.org/get' --debug --config-dir /tmp/rtest-v7 >/dev/null 2>&1
done
BASE=$(ls /tmp/rtest-v7/logs/rabbitcli-*.log 2>/dev/null | head -1)
ROTATED=$(ls /tmp/rtest-v7/logs/rabbitcli-*.1.log 2>/dev/null | head -1)
[ -n "$BASE" ] && [ -n "$ROTATED" ]
check "size-based rotation produces rabbitcli-YYYYMMDD.N.log files" $?

oversized=0
for f in /tmp/rtest-v7/logs/rabbitcli-*.log; do
  sz=$(wc -c < "$f")
  # files other than the last-written one must be <= threshold + 1KB slack
  if [ "$f" != "$(ls -t /tmp/rtest-v7/logs/rabbitcli-*.log | head -1)" ] && [ "$sz" -gt 3072 ]; then oversized=1; fi
done
[ $oversized -eq 0 ]
check "rotated files stay within size threshold (+1KB slack)" $?

starts=$(cat /tmp/rtest-v7/logs/rabbitcli-*.log | grep -c '"msg":"command start"')
[ "$starts" -ge 10 ]
check "log content continuous across rotation boundaries" $?

grep -q 'return 10 \* 1024 \* 1024' internal/cli/logging.go
check "default max log size is 10MB" $?

grep -q 'strings.Cut(stem, ".")' internal/cli/logging.go
check "retention cleanup parses rotated file names" $?

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
