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
grep -q '+hello' internal/services/demo.go && grep -q 'items' internal/services/demo.go && [ -f internal/cli/cmd_api.go ]
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

# --- v8: .env.local loading ---
rm -rf /tmp/de-cwd /tmp/de-cfg
mkdir -p /tmp/de-cwd
printf '# comment\nexport RABBITCLI_BASE_URL="https://dotenv-api.example.com"\nRABBITCLI_TOKEN='"'"'tok_from_dotenv'"'"'\n' > /tmp/de-cwd/.env.local
(
  cd /tmp/de-cwd
  /"$PWD"/bin/rabbitcli api GET /v1/items --config-dir /tmp/de-cfg --dry-run > /tmp/v8_de.out 2>&1
)
BIN="$PWD/bin/rabbitcli"
(cd /tmp/de-cwd && "$BIN" api GET /v1/items --config-dir /tmp/de-cfg --dry-run > /tmp/v8_de.out 2>&1)
grep -q 'https://dotenv-api.example.com/v1/items' /tmp/v8_de.out && grep -q 'Bearer tok_from_dotenv' /tmp/v8_de.out
check ".env.local in cwd sets baseUrl and token (comments/export/quotes)" $?

(cd /tmp/de-cwd && RABBITCLI_BASE_URL=https://realenv.example.com "$BIN" api GET /v1/items --config-dir /tmp/de-cfg --dry-run > /tmp/v8_real.out 2>&1)
grep -q 'https://realenv.example.com/v1/items' /tmp/v8_real.out
check "real env var wins over .env.local" $?

rm -rf /tmp/de-cwd2 /tmp/de-cfg2 && mkdir -p /tmp/de-cwd2 /tmp/de-cfg2
printf 'RABBITCLI_BASE_URL=https://cfgdir.example.com\n' > /tmp/de-cfg2/.env.local
(cd /tmp/de-cwd2 && "$BIN" api GET /v1/items --config-dir /tmp/de-cfg2 --dry-run 2>/dev/null | grep -q 'https://cfgdir.example.com/v1/items')
check ".env.local in config dir works" $?

# config file has a baseUrl, no active env: dotenv still overrides it
"$BIN" config --config-dir /tmp/de-cfg set baseUrl https://config-file.example.com >/dev/null 2>&1
(cd /tmp/de-cwd && "$BIN" api GET /v1/items --config-dir /tmp/de-cfg --dry-run 2>/dev/null | grep -q 'https://dotenv-api.example.com/v1/items')
check ".env.local overrides config-file baseUrl (no active env)" $?

grep -q '^\.env\.local$' .gitignore
check ".gitignore excludes .env.local" $?

# --- v9: name is the single source of truth ---
PKG=github.com/RabbitAI-Lab/RabbitCLI-Bootstrap/internal/cli
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X $PKG.Version=0.1.0 -X $PKG.Name=acmecli" -o bin/acmecli ./cmd/rabbitcli >/dev/null 2>&1
[ -x bin/acmecli ]
check "build with -X Name=acmecli produces bin/acmecli (no source change)" $?

rm -rf /tmp/v9-cfg
ACMECLI_BASE_URL=https://acme.example.com ACMECLI_TOKEN=actok ./bin/acmecli api GET /v1/items --config-dir /tmp/v9-cfg --dry-run >/tmp/v9_acme.out 2>&1
grep -q 'https://acme.example.com/v1/items' /tmp/v9_acme.out && grep -q 'Bearer actok' /tmp/v9_acme.out
check "renamed binary honors ACMECLI_* env vars" $?

RABBITCLI_BASE_URL=https://should-not-apply.example.com ./bin/acmecli api GET /v1/items --config-dir /tmp/v9-cfg --dry-run 2>/dev/null | grep -q 'should-not-apply'
[ $? -ne 0 ]
check "renamed binary ignores RABBITCLI_* env vars" $?

rm -rf /tmp/v9-logs
ACMECLI_LOG_DIR=/tmp/v9-logs ACMECLI_LOG_LEVEL=info ./bin/acmecli demo +hello >/dev/null 2>&1
ls /tmp/v9-logs/acmecli-*.log >/dev/null 2>&1
check "log file name derives from binary name (acmecli-*.log)" $?

rm -rf /tmp/v9-home
HOME=/tmp/v9-home ACMECLI_LOG_LEVEL=warn ./bin/acmecli config set k v >/dev/null 2>&1
[ -f /tmp/v9-home/.config/acmecli/config.json ]
check "default config dir derives from binary name (~/.config/acmecli)" $?

if grep -rn 'os.Getenv("RABBITCLI_' internal/cli/ >/dev/null 2>&1; then
  check "no hardcoded RABBITCLI_ os.Getenv calls (all via EnvVar)" 1
else
  check "no hardcoded RABBITCLI_ os.Getenv calls (all via EnvVar)" 0
fi

# --- v10: skills / schema / auth / sanitization ---
$CLI schema >/tmp/v10_schema.out 2>&1
rc=$?
groups_ok=0
for g in config env demo api update schema skills auth; do grep -q "\"$g\"" /tmp/v10_schema.out || groups_ok=1; done
[ $rc -eq 0 ] && [ $groups_ok -eq 0 ]
check "schema lists all 8 command groups" $?

$CLI schema api >/tmp/v10_schema_api.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"params"' /tmp/v10_schema_api.out && grep -q '"dry-run"' /tmp/v10_schema_api.out
check "schema api returns flag definitions" $?

$CLI schema nope >/tmp/v10_schema_nope.out 2>&1
rc=$?; [ $rc -eq 2 ] && grep -q '"type": "usage"' /tmp/v10_schema_nope.out
check "schema unknown group yields usage error (exit 2)" $?

$CLI skills list >/tmp/v10_skills.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q 'rabbitcli-shared' /tmp/v10_skills.out && grep -q 'rabbitcli-demo' /tmp/v10_skills.out
check "skills list shows bundled skills" $?

rm -rf /tmp/v10-skilldir
$CLI skills install --dir /tmp/v10-skilldir >/dev/null 2>&1
[ -f /tmp/v10-skilldir/rabbitcli-shared/SKILL.md ] && [ -f /tmp/v10-skilldir/rabbitcli-demo/SKILL.md ]
check "skills install copies SKILL.md files" $?

rm -rf /tmp/v10-newskill && mkdir -p /tmp/v10-newskill
(cd /tmp/v10-newskill && "$OLDPWD/bin/rabbitcli" skills new my-svc >/dev/null 2>&1)
[ -f /tmp/v10-newskill/skills/my-svc/SKILL.md ] && grep -q 'name: my-svc' /tmp/v10-newskill/skills/my-svc/SKILL.md
check "skills new scaffolds from template" $?

rm -rf /tmp/v10-auth
$CLI auth login --config-dir /tmp/v10-auth >/tmp/v10_auth.out 2>&1
rc=$?; [ $rc -ne 0 ] && grep -q '"type": "config"' /tmp/v10_auth.out && grep -qi 'optional' /tmp/v10_auth.out
check "auth login without OAuth config yields structured error (optional hint)" $?

$CLI auth status --config-dir /tmp/v10-auth >/tmp/v10_status.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"token_source": "none"' /tmp/v10_status.out
check "auth status reports credential source" $?

go test ./internal/cli/ >/tmp/v10_test.log 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q 'ok' /tmp/v10_test.log
check "go test: sanitize + auth device flow + versions + dotenv" $?

# --- v11: service registry auto-discovery ---
[ ! -f internal/cli/cmd_demo.go ] && [ -f internal/services/demo.go ]
check "demo migrated to internal/services/ (registry-based)" $?

grep -q 'duplicate service registration' internal/cli/registry.go
check "registry panics on duplicate service names" $?

cat > internal/services/probe_v11.go <<'EOF'
package services

import "github.com/RabbitAI-Lab/RabbitCLI-Bootstrap/internal/cli"

func init() {
	cli.RegisterService(&cli.Service{
		Name:        "probe",
		Description: "Verifier probe service",
		Handler: func(a *cli.Args) error {
			cli.EmitSuccess(map[string]any{"pong": true}, "json", nil)
			return nil
		},
		Schema: cli.CommandSchema{Name: "probe", Description: "Verifier probe service", Usage: "rabbitcli probe +ping"},
	})
}
EOF

CGO_ENABLED=0 go build -trimpath -o bin/rabbitcli ./cmd/rabbitcli >/tmp/v11_build.log 2>&1
check "rebuild with dropped-in probe file (no router edits)" $?

./bin/rabbitcli probe +ping >/tmp/v11_probe.out 2>&1
rc=$?; [ $rc -eq 0 ] && grep -q '"ok": true' /tmp/v11_probe.out && grep -q '"pong": true' /tmp/v11_probe.out
check "probe +ping works immediately after dropping the file" $?

./bin/rabbitcli schema 2>/dev/null | grep -q '"probe"'
check "schema lists the auto-registered service" $?

./bin/rabbitcli --help 2>/dev/null | grep -q 'probe'
check "--help Registered services lists the probe" $?

rm internal/services/probe_v11.go
CGO_ENABLED=0 go build -trimpath -o bin/rabbitcli ./cmd/rabbitcli >/dev/null 2>&1
./bin/rabbitcli probe +ping >/dev/null 2>&1
[ $? -eq 2 ]
check "removing the file removes the command (exit 2)" $?

echo "-----"
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
