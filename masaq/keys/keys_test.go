package keys_test

import (
	"testing"

	"github.com/mistakeknot/Masaq/keys"
)

func TestDefaultMapHasQuit(t *testing.T) {
	km := keys.NewDefault()
	if len(km.Quit.Keys()) == 0 {
		t.Fatal("Quit binding must have at least one key")
	}
}

func TestVimModeAddsJK(t *testing.T) {
	km := keys.NewDefault(keys.WithVim())
	found := false
	for _, k := range km.NavDown.Keys() {
		if k == "j" {
			found = true
		}
	}
	if !found {
		t.Fatal("vim mode should bind j to NavDown")
	}
}

func TestDefaultBindings(t *testing.T) {
	km := keys.NewDefault()
	bindings := []struct {
		name    string
		binding keys.Map
		field   func(keys.Map) []string
	}{
		{"Help", km, func(m keys.Map) []string { return m.Help.Keys() }},
		{"NavUp", km, func(m keys.Map) []string { return m.NavUp.Keys() }},
		{"NavDown", km, func(m keys.Map) []string { return m.NavDown.Keys() }},
		{"Accept", km, func(m keys.Map) []string { return m.Accept.Keys() }},
		{"Reject", km, func(m keys.Map) []string { return m.Reject.Keys() }},
		{"Back", km, func(m keys.Map) []string { return m.Back.Keys() }},
		{"Search", km, func(m keys.Map) []string { return m.Search.Keys() }},
	}
	for _, b := range bindings {
		if len(b.field(b.binding)) == 0 {
			t.Errorf("%s binding must have at least one key", b.name)
		}
	}
}
