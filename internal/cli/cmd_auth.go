// Optional OAuth2 device-authorization flow (RFC 8628).
//
// Auth is NOT mandatory: a static token from config / .env.local /
// RABBITCLI_TOKEN works without it. To enable `auth login`, configure:
//
//	rabbitcli config set authDeviceUrl  https://auth.example.com/device/code
//	rabbitcli config set authTokenUrl   https://auth.example.com/token
//	rabbitcli config set authClientId   your-client-id
package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"time"
)

const authHelp = `Usage: rabbitcli auth <subcommand>

Optional OAuth2 device-flow login. Not required: static tokens via
config / .env.local / env vars work without it.

Subcommands:
  login [--no-wait] [--device-code CODE]   Device-flow login
  status                                   Show credential presence and source
  logout                                   Remove stored token

Requires config keys: authDeviceUrl, authTokenUrl, authClientId.`

type deviceCodeResponse struct {
	DeviceCode      string `json:"device_code"`
	UserCode        string `json:"user_code"`
	VerificationURI string `json:"verification_uri"`
	Interval        int    `json:"interval"`
	ExpiresIn       int    `json:"expires_in"`
}

// RunAuth implements the auth command group.
func RunAuth(a *Args) error {
	format, err := a.OutputFormat()
	if err != nil {
		return err
	}
	if a.Bool("help") || len(a.Pos) == 0 {
		fmt.Println(authHelp)
		return nil
	}
	switch a.Pos[0] {
	case "login":
		return authLogin(a, format)
	case "status":
		return authStatus(format)
	case "logout":
		return authLogout(format)
	default:
		return usageError(fmt.Sprintf("Unknown auth subcommand %q", a.Pos[0]), authHelp)
	}
}

func authEndpoints() (deviceURL, tokenURL, clientID string, err *CliError) {
	cfg, e := LoadConfig()
	if e != nil {
		return "", "", "", &CliError{Type: "config", Message: e.Error()}
	}
	deviceURL, _ = cfg["authDeviceUrl"].(string)
	tokenURL, _ = cfg["authTokenUrl"].(string)
	clientID, _ = cfg["authClientId"].(string)
	if deviceURL == "" || tokenURL == "" || clientID == "" {
		return "", "", "", &CliError{
			Type:    "config",
			Message: "OAuth not configured (authDeviceUrl / authTokenUrl / authClientId missing)",
			Hint:    "Auth is optional — a static token works without it. To enable: rabbitcli config set authDeviceUrl/authTokenUrl/authClientId.",
		}
	}
	return deviceURL, tokenURL, clientID, nil
}

func authLogin(a *Args, format string) error {
	deviceURL, tokenURL, clientID, cerr := authEndpoints()
	if cerr != nil {
		return cerr
	}

	dc := a.Str("device-code")
	if dc == "" {
		res, err := http.PostForm(deviceURL, url.Values{"client_id": {clientID}})
		if err != nil {
			return &CliError{Type: "network", Message: err.Error()}
		}
		defer res.Body.Close()
		if res.StatusCode != 200 {
			return &CliError{Type: "api", Code: res.StatusCode, Message: fmt.Sprintf("Device endpoint returned HTTP %d", res.StatusCode)}
		}
		var dr deviceCodeResponse
		if err := json.NewDecoder(res.Body).Decode(&dr); err != nil {
			return &CliError{Type: "api", Message: "Invalid device-code response: " + err.Error()}
		}
		dc = dr.DeviceCode
		info := map[string]any{
			"verification_uri": dr.VerificationURI,
			"user_code":        dr.UserCode,
			"device_code":      dc,
			"expires_in":       dr.ExpiresIn,
		}
		fmt.Fprintf(os.Stderr, "Open %s and enter code %s\n", dr.VerificationURI, dr.UserCode)
		if a.Bool("no-wait") {
			info["status"] = "pending"
			info["hint"] = "Resume later: rabbitcli auth login --device-code " + dc
			EmitSuccess(info, format, nil)
			return nil
		}
		EmitSuccess(info, format, nil) // Agent can relay the URL/code to the user
	}

	// Poll the token endpoint
	interval := 5 * time.Second
	deadline := time.Now().Add(10 * time.Minute)
	for {
		res, err := http.PostForm(tokenURL, url.Values{
			"grant_type":  {"urn:ietf:params:oauth:grant-type:device_code"},
			"device_code": {dc},
			"client_id":   {clientID},
		})
		if err != nil {
			return &CliError{Type: "network", Message: err.Error()}
		}
		var body map[string]any
		json.NewDecoder(res.Body).Decode(&body)
		res.Body.Close()

		if tok, _ := body["access_token"].(string); tok != "" {
			cfg, err := LoadConfig()
			if err != nil {
				return err
			}
			cfg["token"] = tok
			cfg["auth"] = map[string]any{"method": "oauth_device", "obtained_at": time.Now().UTC().Format(time.RFC3339)}
			if err := SaveConfig(cfg); err != nil {
				return err
			}
			Log(context.Background(), slog.LevelInfo, "auth login succeeded")
			EmitSuccess(map[string]any{"authenticated": true}, format, nil)
			return nil
		}
		errCode, _ := body["error"].(string)
		switch errCode {
		case "authorization_pending", "":
			// keep polling
		case "slow_down":
			interval += 5 * time.Second
		default:
			return &CliError{Type: "api", Message: "OAuth error: " + errCode, Hint: str(body["error_description"])}
		}
		if time.Now().After(deadline) {
			return &CliError{Type: "api", Message: "Device flow timed out", Hint: "Run `rabbitcli auth login` again."}
		}
		time.Sleep(interval)
	}
}

func authStatus(format string) error {
	source := "none"
	masked := any(nil)
	cfg, err := LoadConfig()
	if err != nil {
		return err
	}
	eff, err := EffectiveConfig()
	if err != nil {
		return err
	}
	if tok, _ := eff["token"].(string); tok != "" {
		masked = "****" + tok[max(0, len(tok)-4):]
		switch {
		case os.Getenv(EnvVar("TOKEN")) != "":
			source = "env (incl. .env.local)"
		default:
			source = "config file"
			if a, ok := cfg["auth"].(map[string]any); ok {
				if m, _ := a["method"].(string); m != "" {
					source = "oauth (" + m + ")"
				}
			}
		}
	}
	EmitSuccess(map[string]any{
		"authenticated": source != "none",
		"token_source":  source,
		"token":         masked,
		"env":           CurrentEnv(cfg),
	}, format, nil)
	return nil
}

func authLogout(format string) error {
	cfg, err := LoadConfig()
	if err != nil {
		return err
	}
	delete(cfg, "token")
	delete(cfg, "auth")
	if err := SaveConfig(cfg); err != nil {
		return err
	}
	EmitSuccess(map[string]any{"logged_out": true}, format, nil)
	return nil
}
