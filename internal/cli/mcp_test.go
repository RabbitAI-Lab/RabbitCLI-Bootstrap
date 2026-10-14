package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"
)

func TestBuildMCPTools(t *testing.T) {
	tools, err := BuildMCPTools("", nil)
	if err != nil {
		t.Fatal(err)
	}
	names := map[string]bool{}
	for _, tl := range tools {
		names[tl.Name] = true
		if tl.Name != tl.Group {
			t.Errorf("name/group mismatch without prefix: %q vs %q", tl.Name, tl.Group)
		}
		if !mcpToolNameRe.MatchString(tl.Name) {
			t.Errorf("tool name %q fails MCP name rules", tl.Name)
		}
		if tl.InputSchema["type"] != "object" {
			t.Errorf("tool %s: inputSchema must be an object", tl.Name)
		}
	}
	for _, want := range []string{"config", "env", "api", "demo", "schema", "skills", "auth", "update"} {
		if !names[want] {
			t.Errorf("missing tool %q", want)
		}
	}
	if names["mcp"] {
		t.Error("mcp must not register itself as a tool (recursion guard)")
	}
	// Sorted?
	for i := 1; i < len(tools); i++ {
		if tools[i-1].Name >= tools[i].Name {
			t.Errorf("tools not sorted: %q before %q", tools[i-1].Name, tools[i].Name)
		}
	}

	// Prefix + whitelist.
	tools, err = BuildMCPTools("rb_", map[string]bool{"api": true, "demo": true})
	if err != nil {
		t.Fatal(err)
	}
	if len(tools) != 2 || tools[0].Name != "rb_api" || tools[0].Group != "api" || tools[1].Name != "rb_demo" {
		t.Errorf("prefix/whitelist filtering wrong: %+v", tools)
	}

	// Invalid prefix must fail fast.
	if _, err := BuildMCPTools("bad prefix!", nil); err == nil {
		t.Error("invalid prefix should be rejected")
	}

	// Description carries schema details.
	if !strings.Contains(tools[1].Description, "Run `") || !strings.Contains(tools[1].Description, `"args"`) {
		t.Errorf("demo tool description missing usage/input hint:\n%s", tools[1].Description)
	}
}

// newTestServer returns a server whose exec is replaced by fn.
func newTestServer(t *testing.T, fn func(ctx context.Context, argv []string) mcpExecResult) *mcpServer {
	t.Helper()
	tools, err := BuildMCPTools("", nil)
	if err != nil {
		t.Fatal(err)
	}
	return &mcpServer{tools: tools, exec: fn}
}

// testResp mirrors jsonRPCResponse with a RawMessage result for easy
// re-unmarshaling in assertions.
type testResp struct {
	ID     json.RawMessage `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  *jsonRPCError   `json:"error"`
}

func runMCP(t *testing.T, srv *mcpServer, input string) map[string]testResp {
	t.Helper()
	var out strings.Builder
	if err := serveMCP(strings.NewReader(input), &out, srv); err != nil {
		t.Fatal(err)
	}
	// Requests are handled concurrently, so responses may arrive out of
	// order (legal per JSON-RPC) — key them by id.
	resps := map[string]testResp{}
	for _, line := range strings.Split(strings.TrimSpace(out.String()), "\n") {
		if line == "" {
			continue
		}
		var r testResp
		if err := json.Unmarshal([]byte(line), &r); err != nil {
			t.Fatalf("non-JSON response line: %q", line)
		}
		resps[string(r.ID)] = r
	}
	return resps
}

func TestMCPServeHandshakeAndList(t *testing.T) {
	srv := newTestServer(t, func(ctx context.Context, argv []string) mcpExecResult {
		return mcpExecResult{Stdout: "{}\n"}
	})
	input := strings.Join([]string{
		`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}`,
		`{"jsonrpc":"2.0","method":"notifications/initialized"}`,
		`{"jsonrpc":"2.0","id":2,"method":"ping"}`,
		`{"jsonrpc":"2.0","id":3,"method":"tools/list"}`,
	}, "\n") + "\n"

	resps := runMCP(t, srv, input)
	if len(resps) != 3 { // the notification must not produce a response
		t.Fatalf("want 3 responses, got %d: %+v", len(resps), resps)
	}

	var init struct {
		ProtocolVersion string `json:"protocolVersion"`
		ServerInfo      struct {
			Name string `json:"name"`
		} `json:"serverInfo"`
	}
	if err := json.Unmarshal(resps["1"].Result, &init); err != nil {
		t.Fatal(err)
	}
	if init.ProtocolVersion != "2025-03-26" { // echo the client's known version
		t.Errorf("protocol version = %q, want 2025-03-26", init.ProtocolVersion)
	}
	if init.ServerInfo.Name != Name {
		t.Errorf("serverInfo.name = %q, want %q", init.ServerInfo.Name, Name)
	}
	if resps["2"].Result == nil || string(resps["2"].Result) == "null" {
		t.Errorf("ping must return an (empty) result, got %s", resps["2"].Result)
	}

	var list struct {
		Tools []MCPTool `json:"tools"`
	}
	if err := json.Unmarshal(resps["3"].Result, &list); err != nil {
		t.Fatal(err)
	}
	if len(list.Tools) < 5 {
		t.Errorf("tools/list returned too few tools: %d", len(list.Tools))
	}
	for _, tl := range list.Tools {
		if tl.Group != "" {
			t.Error("group field must be hidden from tools/list output")
		}
	}
}

func TestMCPCallTool(t *testing.T) {
	var mu sync.Mutex
	var calls [][]string
	srv := newTestServer(t, func(ctx context.Context, argv []string) mcpExecResult {
		mu.Lock()
		calls = append(calls, argv)
		mu.Unlock()
		if argv[0] == "api" {
			return mcpExecResult{Stdout: "{\n  \"ok\": true,\n  \"data\": []\n}\n"}
		}
		return mcpExecResult{ExitCode: 2, Stderr: "{\n  \"ok\": false,\n  \"error\": {\"type\": \"usage\", \"message\": \"boom\"}\n}\n"}
	})
	srv.globalArgs = []string{"--env", "dev"}

	input := strings.Join([]string{
		`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"api","arguments":{"args":["GET","/v1/items"]}}}`,
		`{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"demo","arguments":{"args":["nope"]}}}`,
		`{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ghost","arguments":{}}}`,
	}, "\n") + "\n"

	resps := runMCP(t, srv, input)
	if len(resps) != 3 {
		t.Fatalf("want 3 responses, got %d", len(resps))
	}

	var call struct {
		IsError bool `json:"isError"`
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}

	if err := json.Unmarshal(resps["1"].Result, &call); err != nil {
		t.Fatal(err)
	}
	want := []string{"api", "--env", "dev", "GET", "/v1/items"}
	mu.Lock()
	found := false
	for _, c := range calls {
		if fmt.Sprint(c) == fmt.Sprint(want) {
			found = true
			break
		}
	}
	mu.Unlock()
	if !found {
		t.Errorf("no subprocess ran with argv %v; calls were %v", want, calls)
	}
	if call.IsError || len(call.Content) != 1 || call.Content[0].Type != "text" || !strings.Contains(call.Content[0].Text, `"ok": true`) {
		t.Errorf("success call result wrong: %+v", call)
	}

	if err := json.Unmarshal(resps["2"].Result, &call); err != nil {
		t.Fatal(err)
	}
	if !call.IsError || !strings.Contains(call.Content[0].Text, `"ok": false`) {
		t.Errorf("failing call must surface the stderr envelope with isError=true: %+v", call)
	}

	if resps["3"].Error == nil || resps["3"].Error.Code != -32602 {
		t.Errorf("unknown tool must be a -32602 JSON-RPC error, got %+v", resps["3"].Error)
	}
}

func TestMCPCallToolTimeoutAndSpawnError(t *testing.T) {
	srv := newTestServer(t, func(ctx context.Context, argv []string) mcpExecResult {
		if argv[0] == "api" {
			return mcpExecResult{Err: fmt.Errorf("command timed out after 1s")}
		}
		return mcpExecResult{Err: fmt.Errorf("fork: no such file")}
	})
	input := strings.Join([]string{
		`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"api","arguments":{"args":["GET","/v1/items"]}}}`,
		`{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"demo","arguments":{}}}`,
	}, "\n") + "\n"
	resps := runMCP(t, srv, input)

	var call struct {
		IsError bool `json:"isError"`
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
	}
	for id, want := range map[string]string{"1": "timed out", "2": "fork: no such file"} {
		if err := json.Unmarshal(resps[id].Result, &call); err != nil {
			t.Fatal(err)
		}
		if !call.IsError || !strings.Contains(call.Content[0].Text, want) {
			t.Errorf("resp %s: want isError with %q, got %+v", id, want, call)
		}
	}
}

func TestMCPServeMalformedAndUnknownMethod(t *testing.T) {
	srv := newTestServer(t, func(ctx context.Context, argv []string) mcpExecResult { return mcpExecResult{} })
	input := "not json at all\n" +
		`{"jsonrpc":"2.0","id":7,"method":"resources/list"}` + "\n"
	resps := runMCP(t, srv, input)
	if len(resps) != 2 {
		t.Fatalf("want 2 responses, got %d", len(resps))
	}
	if r := resps["null"]; r.Error == nil || r.Error.Code != -32700 {
		t.Errorf("malformed line must yield -32700 with null id, got %+v", r)
	}
	if r := resps["7"]; r.Error == nil || r.Error.Code != -32601 {
		t.Errorf("unknown method must yield -32601, got %+v", r)
	}
}
