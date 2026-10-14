// Minimal MCP (Model Context Protocol) server over stdio — pure stdlib.
//
// The transport is newline-delimited JSON-RPC 2.0 on stdin/stdout, the
// standard way local agents (ZCode, Claude Desktop, Cursor, ...) talk to
// child-process MCP servers. Every registered CLI command group becomes
// one MCP tool; a tool call re-execs this binary as
//
//	rabbitcli <group> [global flags] [args...]
//
// and returns the subprocess stdout (the JSON envelope) as the tool
// result. Running handlers as subprocesses keeps the server loop safe
// from code that prints to stdout or calls os.Exit, and picks up config
// and .env.local exactly like interactive use. stdout belongs to the
// protocol here — the slog framework already writes log files only.
package cli

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

// MCP protocol versions this server speaks (oldest → newest). On
// initialize the client's requested version is echoed when known,
// otherwise the newest supported one is returned.
var mcpVersions = []string{"2024-11-05", "2025-03-26", "2025-06-18"}

// mcpToolNameRe is the safe tool-name charset shared by MCP clients.
var mcpToolNameRe = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// MCPTool is one CLI command group exposed as an MCP tool.
type MCPTool struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Group       string         `json:"-"` // CLI command group executed by this tool
	InputSchema map[string]any `json:"inputSchema"`
}

// BuildMCPTools turns every registered command group (built-ins plus
// self-registered services, except mcp itself) into MCP tools, sorted by
// name. prefix is prepended to tool names ("" for none). only, when not
// nil, restricts the set to the listed command groups.
func BuildMCPTools(prefix string, only map[string]bool) ([]MCPTool, error) {
	type entry struct {
		group  string
		schema CommandSchema
	}
	byName := map[string]entry{}
	for _, s := range ListServices() {
		byName[s.Name] = entry{s.Name, s.Schema} // services win over same-name built-ins
	}
	for name, sch := range schemas {
		if _, ok := byName[name]; !ok {
			byName[name] = entry{name, sch}
		}
	}
	delete(byName, "mcp") // never expose the server itself (recursion guard)

	names := make([]string, 0, len(byName))
	for n := range byName {
		names = append(names, n)
	}
	sort.Strings(names)

	tools := make([]MCPTool, 0, len(names))
	for _, n := range names {
		if only != nil && !only[n] {
			continue
		}
		e := byName[n]
		full := prefix + n
		if !mcpToolNameRe.MatchString(full) {
			return nil, usageError(fmt.Sprintf("Invalid MCP tool name %q (from prefix %q + group %q)", full, prefix, n),
				"Tool names may only use letters, digits, '-' and '_'.")
		}
		tools = append(tools, MCPTool{
			Name:        full,
			Group:       e.group,
			Description: mcpDescribe(e.schema),
			InputSchema: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"args": map[string]any{
						"type":        "array",
						"items":       map[string]any{"type": "string"},
						"description": "Command-line tokens after the group name (subcommand, flags, values)",
					},
				},
			},
		})
	}
	return tools, nil
}

// mcpDescribe flattens a CommandSchema into a tool description.
func mcpDescribe(s CommandSchema) string {
	var b strings.Builder
	if s.Usage != "" {
		b.WriteString("Run `" + s.Usage + "`")
		if s.Description != "" {
			b.WriteString(" — " + s.Description)
		}
		b.WriteString("\n")
	} else if s.Description != "" {
		b.WriteString(s.Description + "\n")
	}
	if len(s.Positionals) > 0 {
		b.WriteString("Positionals: " + strings.Join(s.Positionals, " ") + "\n")
	}
	if len(s.Subcommands) > 0 {
		b.WriteString("Subcommands:\n")
		for _, sc := range s.Subcommands {
			b.WriteString("  - " + sc + "\n")
		}
	}
	if len(s.Flags) > 0 {
		b.WriteString("Flags:\n")
		for _, f := range s.Flags {
			req := ""
			if f.Required {
				req = " (required)"
			}
			fmt.Fprintf(&b, "  - --%s (%s)%s: %s\n", f.Name, f.Type, req, f.Desc)
		}
	}
	if len(s.Examples) > 0 {
		b.WriteString("Examples:\n")
		for _, e := range s.Examples {
			b.WriteString("  " + e + "\n")
		}
	}
	b.WriteString(`Input: pass the subcommand tokens and flags as the "args" string array (without the group name), e.g. {"args":["items","list","--format","table"]}.`)
	return b.String()
}

// mcpExecResult is the outcome of one tool-call subprocess.
type mcpExecResult struct {
	Stdout   string
	Stderr   string
	ExitCode int
	Err      error // spawn failure or timeout (no exit code)
}

// mcpServer serves one stdio connection.
type mcpServer struct {
	tools      []MCPTool
	self       string        // path to this binary
	globalArgs []string      // global flags injected into every exec (--env dev ...)
	timeout    time.Duration // per-call subprocess timeout (0 = none)
	exec       func(ctx context.Context, argv []string) mcpExecResult

	mu sync.Mutex
	w  io.Writer
}

// execSelf runs this binary as a subprocess and captures both streams.
func (s *mcpServer) execSelf(ctx context.Context, argv []string) mcpExecResult {
	cmd := exec.CommandContext(ctx, s.self, argv...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	cmd.Env = os.Environ()
	err := cmd.Run()
	if ctx.Err() != nil {
		return mcpExecResult{Stderr: stderr.String(), Err: fmt.Errorf("command timed out after %s", s.timeout)}
	}
	res := mcpExecResult{Stdout: stdout.String(), Stderr: stderr.String()}
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			res.ExitCode = ee.ExitCode()
		} else {
			res.Err = err
		}
	}
	return res
}

// --- JSON-RPC 2.0 plumbing ---

type jsonRPCRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type jsonRPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

type jsonRPCResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  any             `json:"result,omitempty"`
	Error   *jsonRPCError   `json:"error,omitempty"`
}

// serveMCP reads newline-delimited JSON-RPC messages from r until EOF,
// writing responses to w. Requests with an id run in goroutines so a
// slow tools/call cannot block a concurrent ping; writes are
// serialized under mu.
func serveMCP(r io.Reader, w io.Writer, s *mcpServer) error {
	s.w = w
	br := bufio.NewReader(r)
	var wg sync.WaitGroup
	for {
		line, err := br.ReadString('\n')
		if msg := strings.TrimSpace(line); msg != "" {
			var req jsonRPCRequest
			if jerr := json.Unmarshal([]byte(msg), &req); jerr != nil {
				s.send(&jsonRPCResponse{
					JSONRPC: "2.0",
					ID:      json.RawMessage("null"),
					Error:   &jsonRPCError{Code: -32700, Message: "parse error: " + jerr.Error()},
				})
			} else if len(req.ID) == 0 || string(req.ID) == "null" {
				// Notification: no response expected.
			} else {
				wg.Add(1)
				go func(req jsonRPCRequest) {
					defer wg.Done()
					if resp := s.handle(req); resp != nil {
						s.send(resp)
					}
				}(req)
			}
		}
		if err != nil {
			break // EOF (client closed stdin) or read error: shut down
		}
	}
	wg.Wait()
	return nil
}

func (s *mcpServer) send(resp *jsonRPCResponse) {
	b, err := json.Marshal(resp)
	if err != nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.w.Write(append(b, '\n'))
}

func (s *mcpServer) handle(req jsonRPCRequest) *jsonRPCResponse {
	ok := func(result any) *jsonRPCResponse {
		return &jsonRPCResponse{JSONRPC: "2.0", ID: req.ID, Result: result}
	}
	fail := func(code int, msg string) *jsonRPCResponse {
		return &jsonRPCResponse{JSONRPC: "2.0", ID: req.ID, Error: &jsonRPCError{Code: code, Message: msg}}
	}

	switch req.Method {
	case "initialize":
		var p struct {
			ProtocolVersion string `json:"protocolVersion"`
		}
		_ = json.Unmarshal(req.Params, &p)
		ver := mcpVersions[len(mcpVersions)-1]
		for _, v := range mcpVersions {
			if v == p.ProtocolVersion {
				ver = v
				break
			}
		}
		return ok(map[string]any{
			"protocolVersion": ver,
			"capabilities":    map[string]any{"tools": map[string]any{"listChanged": false}},
			"serverInfo":      map[string]any{"name": Name, "version": Version},
			"instructions": fmt.Sprintf(
				"Every tool wraps one %s command group; the CLI output contract is preserved: "+
					`{"ok":true,"data":...} on success, {"ok":false,"error":{...}} with isError=true on failure. `+
					"Call the `schema` tool with {\"args\":[\"<group>\"]} to inspect any group's flags and examples.",
				Name),
		})

	case "ping":
		return ok(map[string]any{})

	case "tools/list":
		return ok(map[string]any{"tools": s.tools})

	case "tools/call":
		var p struct {
			Name      string `json:"name"`
			Arguments struct {
				Args []string `json:"args"`
			} `json:"arguments"`
		}
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return fail(-32602, "invalid tools/call params: "+err.Error())
		}
		var tool *MCPTool
		for i := range s.tools {
			if s.tools[i].Name == p.Name {
				tool = &s.tools[i]
				break
			}
		}
		if tool == nil {
			return fail(-32602, fmt.Sprintf("unknown tool: %s", p.Name))
		}
		return ok(s.callTool(tool, p.Arguments.Args))

	default:
		return fail(-32601, "method not found: "+req.Method)
	}
}

// callTool runs one command group as a subprocess and shapes the MCP result.
func (s *mcpServer) callTool(tool *MCPTool, args []string) map[string]any {
	argv := make([]string, 0, 1+len(s.globalArgs)+len(args))
	argv = append(argv, tool.Group)
	argv = append(argv, s.globalArgs...)
	argv = append(argv, args...)

	ctx := context.Background()
	if s.timeout > 0 {
		c, cancel := context.WithTimeout(ctx, s.timeout)
		defer cancel()
		ctx = c
	}
	res := s.exec(ctx, argv)

	text := strings.TrimSpace(res.Stdout)
	if res.Err != nil {
		text = firstNonEmpty(text, strings.TrimSpace(res.Stderr), res.Err.Error())
		return mcpToolResult(text, true)
	}
	if res.ExitCode != 0 {
		text = firstNonEmpty(strings.TrimSpace(res.Stderr), text, fmt.Sprintf("exit status %d", res.ExitCode))
		return mcpToolResult(text, true)
	}
	// Success: prefer the stdout envelope; fall back to stderr for
	// handlers that report via stderr without failing.
	text = firstNonEmpty(text, strings.TrimSpace(res.Stderr), "(no output)")
	return mcpToolResult(text, false)
}

func mcpToolResult(text string, isErr bool) map[string]any {
	return map[string]any{
		"content": []any{map[string]any{"type": "text", "text": text}},
		"isError": isErr,
	}
}

func firstNonEmpty(ss ...string) string {
	for _, s := range ss {
		if s != "" {
			return s
		}
	}
	return ""
}
