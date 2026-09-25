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

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
