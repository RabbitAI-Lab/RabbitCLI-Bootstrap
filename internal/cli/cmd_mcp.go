// mcp command group: expose the whole CLI as an MCP server over stdio
// for local agents (ZCode, Claude Desktop, Cursor, ...).
package cli

import (
	"fmt"
	"os"
	"strings"
	"time"
)

const mcpHelp = `Usage: rabbitcli mcp [flags]

Starts a stdio MCP (Model Context Protocol) server that registers every
command group (built-ins + services) as one MCP tool. Each tool call
re-executes this binary as ` + "`rabbitcli <group> <args...>`" + ` and returns the
JSON envelope, so tool behavior is identical to interactive CLI use.

Agents configure it as a stdio MCP server (command: rabbitcli, args: mcp).

Flags:
  --tools <a,b,c>   Whitelist of command groups to expose (default: all)
  --prefix <p_>     Prefix for tool names, e.g. "rabbitcli_" (default: none)
  --timeout <sec>   Per-call subprocess timeout (default: 300; 0 = none)
  --list            Print the tool inventory and exit (no server)
  --env, --config-dir are passed through to every tool-call subprocess`

// RunMCP implements the mcp command group.
func RunMCP(a *Args) error {
	if a.Bool("help") || a.Bool("h") {
		fmt.Println(mcpHelp)
		return nil
	}

	prefix := a.Str("prefix")
	var only map[string]bool // nil = expose every group
	if v := a.Str("tools"); v != "" {
		only = map[string]bool{}
		for _, t := range strings.Split(v, ",") {
			if t = strings.TrimSpace(t); t != "" {
				only[t] = true
			}
		}
	}
	tools, err := BuildMCPTools(prefix, only)
	if err != nil {
		return err
	}
	if len(only) > 0 && len(tools) == 0 {
		return usageError("No matching command groups in --tools",
			"Run `rabbitcli mcp --list` to see all groups.")
	}

	if a.Bool("list") {
		format, err := a.OutputFormat()
		if err != nil {
			return err
		}
		EmitSuccess(tools, format, nil)
		return nil
	}

	timeout := 300 * time.Second
	if n, present, err := a.Int("timeout"); err != nil {
		return err
	} else if present {
		timeout = time.Duration(n) * time.Second
	}

	self, err := os.Executable()
	if err != nil {
		return &CliError{Type: "internal", Message: "cannot locate own executable: " + err.Error()}
	}

	// Propagate server-level --env / --config-dir to every subprocess.
	var globalArgs []string
	if v := a.Str("config-dir"); v != "" {
		globalArgs = append(globalArgs, "--config-dir", v)
	}
	if v := a.Str("env"); v != "" {
		globalArgs = append(globalArgs, "--env", v)
	}

	srv := &mcpServer{
		tools:      tools,
		self:       self,
		globalArgs: globalArgs,
		timeout:    timeout,
	}
	srv.exec = srv.execSelf

	fmt.Fprintf(os.Stderr, "%s mcp: serving %d tools over stdio (timeout %s)\n", Name, len(tools), timeout)
	return serveMCP(os.Stdin, os.Stdout, srv)
}
