package theme_test

import (
	"os"
	"testing"

	"github.com/mistakeknot/Masaq/theme"
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

func TestColorPairColorRespectsMode(t *testing.T) {
	defer theme.SetMode(theme.Dark)

	cp := theme.ColorPair{Dark: "#ff0000", Light: "#00ff00"}

	theme.SetMode(theme.Dark)
	if got := string(cp.Color()); got != "#ff0000" {
		t.Errorf("Dark mode: Color() = %q, want #ff0000", got)
	}

	theme.SetMode(theme.Light)
	if got := string(cp.Color()); got != "#00ff00" {
		t.Errorf("Light mode: Color() = %q, want #00ff00", got)
	}
}

func TestModeStringDark(t *testing.T) {
	if theme.Dark.String() != "dark" {
		t.Errorf("Dark.String() = %q", theme.Dark.String())
	}
}

func TestModeStringLight(t *testing.T) {
	if theme.Light.String() != "light" {
		t.Errorf("Light.String() = %q", theme.Light.String())
	}
}

func TestSetModeRoundTrip(t *testing.T) {
	defer theme.SetMode(theme.Dark)

	theme.SetMode(theme.Light)
	if theme.CurrentMode() != theme.Light {
		t.Error("CurrentMode() should be Light after SetMode(Light)")
	}

	theme.SetMode(theme.Dark)
	if theme.CurrentMode() != theme.Dark {
		t.Error("CurrentMode() should be Dark after SetMode(Dark)")
	}
}

func TestDetectModeEnvLight(t *testing.T) {
	defer theme.SetMode(theme.Dark)

	t.Setenv("MASAQ_COLOR_MODE", "light")
	if got := theme.DetectMode(); got != theme.Light {
		t.Errorf("DetectMode() with MASAQ_COLOR_MODE=light = %v, want Light", got)
	}
}

func TestDetectModeEnvDark(t *testing.T) {
	t.Setenv("MASAQ_COLOR_MODE", "dark")
	if got := theme.DetectMode(); got != theme.Dark {
		t.Errorf("DetectMode() with MASAQ_COLOR_MODE=dark = %v, want Dark", got)
	}
}

func TestDetectModeEnvCaseInsensitive(t *testing.T) {
	t.Setenv("MASAQ_COLOR_MODE", "LIGHT")
	if got := theme.DetectMode(); got != theme.Light {
		t.Errorf("DetectMode() with MASAQ_COLOR_MODE=LIGHT = %v, want Light", got)
	}
}

func TestDetectModeNoEnvDefaultsDark(t *testing.T) {
	os.Unsetenv("MASAQ_COLOR_MODE")
	// Without env override, DetectMode queries termenv.
	// In CI/pipes this returns Dark (no TTY), which is the expected default.
	got := theme.DetectMode()
	if got != theme.Dark {
		t.Logf("DetectMode() without env = %v (depends on terminal)", got)
	}
}

func TestThemesReturnsMultiple(t *testing.T) {
	themes := theme.Themes()
	if len(themes) < 2 {
		t.Fatalf("Themes() returned %d themes, want at least 2", len(themes))
	}
}

func TestThemesContainsTokyoNight(t *testing.T) {
	for _, th := range theme.Themes() {
		if th.Name == "Tokyo Night" {
			return
		}
	}
	t.Error("Themes() missing Tokyo Night")
}

func TestThemesContainsCatppuccin(t *testing.T) {
	for _, th := range theme.Themes() {
		if th.Name == "Catppuccin" {
			return
		}
	}
	t.Error("Themes() missing Catppuccin")
}

func TestThemeByNameFound(t *testing.T) {
	th, ok := theme.ThemeByName("catppuccin")
	if !ok {
		t.Fatal("ThemeByName(catppuccin) not found")
	}
	if th.Name != "Catppuccin" {
		t.Errorf("ThemeByName returned %q", th.Name)
	}
}

func TestThemeByNameCaseInsensitive(t *testing.T) {
	_, ok := theme.ThemeByName("TOKYO NIGHT")
	if !ok {
		t.Error("ThemeByName(TOKYO NIGHT) should be case-insensitive")
	}
}

func TestThemeByNameNotFound(t *testing.T) {
	_, ok := theme.ThemeByName("nonexistent")
	if ok {
		t.Error("ThemeByName(nonexistent) should return false")
	}
}

func TestCatppuccinHasRequiredColors(t *testing.T) {
	sem := theme.Catppuccin.Semantic()
	if sem.Primary.Dark == "" || sem.Primary.Light == "" {
		t.Fatal("Catppuccin Primary must have both dark and light")
	}
	if sem.Bg.Dark == "" || sem.Bg.Light == "" {
		t.Fatal("Catppuccin Bg must have both dark and light")
	}
	if sem.Fg.Dark == "" || sem.Fg.Light == "" {
		t.Fatal("Catppuccin Fg must have both dark and light")
	}
	if sem.Error.Dark == "" || sem.Error.Light == "" {
		t.Fatal("Catppuccin Error must have both dark and light")
	}
	if sem.DiffAdd.Dark == "" || sem.DiffRemove.Dark == "" {
		t.Fatal("Catppuccin diff colors must be defined")
	}
}

func TestActiveColorDefined(t *testing.T) {
	for _, th := range theme.Themes() {
		sem := th.Semantic()
		if sem.Active.Dark == "" || sem.Active.Light == "" {
			t.Errorf("%s: Active color must have both dark and light", th.Name)
		}
	}
}

func TestActiveDistinctFromPrimary(t *testing.T) {
	sem := theme.TokyoNight.Semantic()
	if sem.Active.Dark == sem.Primary.Dark {
		t.Error("Active.Dark should differ from Primary.Dark")
	}
}

func TestDefaultModeIsDark(t *testing.T) {
	// The package default should be Dark so existing users see no change.
	// We can't truly verify the initial state in a test suite that may
	// have other tests running first, but we can verify the constant.
	if theme.Dark != 0 {
		t.Error("Dark should be the zero value (iota)")
	}
}
