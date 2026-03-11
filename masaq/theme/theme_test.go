package theme_test

import (
	"testing"

	"github.com/mistakeknot/masaq/theme"
)

func TestTokyoNightHasRequiredColors(t *testing.T) {
	th := theme.TokyoNight
	if th.Name == "" {
		t.Fatal("theme name must not be empty")
	}
	sem := th.Semantic()
	if sem.Primary.Dark == "" {
		t.Fatal("semantic Primary.Dark must not be empty")
	}
	if sem.Success.Dark == "" {
		t.Fatal("semantic Success.Dark must not be empty")
	}
	if sem.Error.Dark == "" {
		t.Fatal("semantic Error.Dark must not be empty")
	}
}

func TestCurrentReturnsDefault(t *testing.T) {
	th := theme.Current()
	if th.Name != theme.TokyoNight.Name {
		t.Errorf("Current() = %q, want %q", th.Name, theme.TokyoNight.Name)
	}
}

func TestSemanticDiffColors(t *testing.T) {
	sem := theme.TokyoNight.Semantic()
	if sem.DiffAdd.Dark == "" || sem.DiffRemove.Dark == "" {
		t.Fatal("diff colors must be defined")
	}
}

func TestSetCurrent(t *testing.T) {
	original := theme.Current()
	defer theme.SetCurrent(original)

	custom := theme.Theme{Name: "Custom"}
	theme.SetCurrent(custom)
	if theme.Current().Name != "Custom" {
		t.Errorf("SetCurrent failed, got %q", theme.Current().Name)
	}
}

func TestColorPairColor(t *testing.T) {
	cp := theme.ColorPair{Dark: "#ff0000", Light: "#00ff00"}
	c := cp.Color()
	if string(c) != "#ff0000" {
		t.Errorf("Color() = %q, want #ff0000", string(c))
	}
}
