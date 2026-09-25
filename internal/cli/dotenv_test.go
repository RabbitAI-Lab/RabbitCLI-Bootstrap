package cli

import (
	"os"
	"testing"
)

func TestLoadDotenv(t *testing.T) {
	dir := t.TempDir()
	content := EnvVar("TOKEN") + "=tok123\n" + EnvVar("BASE_URL") + "=\"https://x.example.com\"\n"
	os.WriteFile(dir+"/.env.local", []byte(content), 0o600)
	cwd, _ := os.Getwd()
	defer os.Chdir(cwd)
	os.Chdir(dir)
	LoadDotenv()
	if os.Getenv(EnvVar("TOKEN")) != "tok123" {
		t.Fatalf("token not loaded: %q", os.Getenv(EnvVar("TOKEN")))
	}
	if os.Getenv(EnvVar("BASE_URL")) != "https://x.example.com" {
		t.Fatalf("base url not loaded: %q", os.Getenv(EnvVar("BASE_URL")))
	}
}
