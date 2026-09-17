package main

import "testing"

func TestReleaseDefaults(t *testing.T) {
	if defaultAdapterName != "slimevr" {
		t.Fatalf("default adapter = %q, want slimevr", defaultAdapterName)
	}
	if !shouldStartBackground([]string{"camesura-bridge"}, false, false, false) {
		t.Fatal("a no-argument launch should run in the background")
	}
}

func TestExplicitCLIStaysInForeground(t *testing.T) {
	if shouldStartBackground([]string{"camesura-bridge", "-listen", ":39500"}, false, false, false) {
		t.Fatal("an explicit CLI invocation should stay in the foreground")
	}
	if shouldStartBackground([]string{"camesura-bridge"}, false, false, true) {
		t.Fatal("the detached child must not start another child")
	}
}
