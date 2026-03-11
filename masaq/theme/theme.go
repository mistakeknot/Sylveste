package theme

import "github.com/charmbracelet/lipgloss"

// ColorPair holds hex colors for dark and light mode.
type ColorPair struct {
	Dark  string
	Light string
}

// Color returns the lipgloss.Color for dark mode.
func (cp ColorPair) Color() lipgloss.Color {
	return lipgloss.Color(cp.Dark)
}

// SemanticColors maps UI roles to color pairs.
type SemanticColors struct {
	Primary     ColorPair
	Secondary   ColorPair
	Success     ColorPair
	Warning     ColorPair
	Error       ColorPair
	Info        ColorPair
	Muted       ColorPair
	Bg          ColorPair
	BgDark      ColorPair
	BgLight     ColorPair
	Fg          ColorPair
	FgDim       ColorPair
	Border      ColorPair
	DiffAdd     ColorPair
	DiffRemove  ColorPair
	DiffContext ColorPair
}

// Theme is a named color palette.
type Theme struct {
	Name     string
	semantic SemanticColors
}

// Semantic returns the semantic color mapping for this theme.
func (t Theme) Semantic() SemanticColors {
	return t.semantic
}

// TokyoNight is the default Demarch theme based on Tokyo Night.
var TokyoNight = Theme{
	Name: "Tokyo Night",
	semantic: SemanticColors{
		Primary:     ColorPair{Dark: "#7aa2f7", Light: "#3760bf"},
		Secondary:   ColorPair{Dark: "#bb9af7", Light: "#7847bd"},
		Success:     ColorPair{Dark: "#9ece6a", Light: "#587539"},
		Warning:     ColorPair{Dark: "#e0af68", Light: "#8c6c3e"},
		Error:       ColorPair{Dark: "#f7768e", Light: "#c64343"},
		Info:        ColorPair{Dark: "#7dcfff", Light: "#2e7de9"},
		Muted:       ColorPair{Dark: "#565f89", Light: "#8990b3"},
		Bg:          ColorPair{Dark: "#1a1b26", Light: "#d5d6db"},
		BgDark:      ColorPair{Dark: "#16161e", Light: "#e9e9ec"},
		BgLight:     ColorPair{Dark: "#24283b", Light: "#c4c8da"},
		Fg:          ColorPair{Dark: "#c0caf5", Light: "#3760bf"},
		FgDim:       ColorPair{Dark: "#a9b1d6", Light: "#6172b0"},
		Border:      ColorPair{Dark: "#3b4261", Light: "#a8aecb"},
		DiffAdd:     ColorPair{Dark: "#9ece6a", Light: "#587539"},
		DiffRemove:  ColorPair{Dark: "#f7768e", Light: "#c64343"},
		DiffContext: ColorPair{Dark: "#565f89", Light: "#8990b3"},
	},
}

var current = TokyoNight

// Current returns the active theme.
func Current() Theme {
	return current
}

// SetCurrent changes the active theme.
func SetCurrent(t Theme) {
	current = t
}
