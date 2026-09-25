package services

// demo.go — example service. Demonstrates the two upper command layers
// (shortcuts with "+", resource commands 1:1 to endpoints) and the
// self-registration pattern. Replace it with your own service.

import (
	"fmt"
	"net/url"
	"os"

	"github.com/RabbitAI-Lab/RabbitCLI-Bootstrap/internal/cli"
)

const demoHelp = `Usage: rabbitcli demo <command>

Shortcuts:
  +hello             Greeting shortcut (smart defaults, no API needed)

Resource commands:
  items list         GET /v1/items
  items get <id>     GET /v1/items/:id

Flags: --format, --page-all, --dry-run (see ` + "`rabbitcli api --help`" + `)`

func init() {
	cli.RegisterService(&cli.Service{
		Name:        "demo",
		Description: "Example service: shortcuts and resource commands (replace with yours)",
		Handler:     runDemo,
		Schema: cli.CommandSchema{
			Name: "demo", Description: "Example service (replace with yours)",
			Usage:       "rabbitcli demo <command>",
			Subcommands: []string{"+hello", "items list", "items get <id>"},
			Examples:    []string{"rabbitcli demo +hello", "rabbitcli demo items list --format table"},
		},
	})
}

func runDemo(a *cli.Args) error {
	format, err := a.OutputFormat()
	if err != nil {
		return err
	}
	if a.Bool("help") || len(a.Pos) == 0 {
		fmt.Println(demoHelp)
		return nil
	}
	cmd := a.Pos[0]

	// --- Shortcuts ---
	if cmd == "+hello" {
		cli.EmitSuccess(map[string]any{"message": "Hello from rabbitcli! Replace this shortcut with your own."}, format, nil)
		return nil
	}

	// --- Resource commands ---
	if cmd == "items" && len(a.Pos) >= 2 && a.Pos[1] == "list" {
		data, err := cli.Request(cli.RequestOpts{Method: "GET", Path: "/v1/items", DryRun: a.Bool("dry-run"), PageAll: a.Bool("page-all")})
		if err != nil {
			return err
		}
		cli.EmitSuccess(data, format, nil)
		return nil
	}
	if cmd == "items" && len(a.Pos) >= 3 && a.Pos[1] == "get" {
		data, err := cli.Request(cli.RequestOpts{Method: "GET", Path: "/v1/items/" + url.PathEscape(a.Pos[2]), DryRun: a.Bool("dry-run")})
		if err != nil {
			return err
		}
		cli.EmitSuccess(data, format, nil)
		return nil
	}

	fmt.Fprintln(os.Stderr, demoHelp)
	os.Exit(2)
	return nil
}
