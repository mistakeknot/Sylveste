package theme

// Catppuccin theme using the official Mocha (dark) and Latte (light) palettes.
// Colors from https://github.com/catppuccin/catppuccin
var Catppuccin = Theme{
	Name: "Catppuccin",
	semantic: SemanticColors{
		Primary:     ColorPair{Dark: "#89b4fa", Light: "#1e66f5"}, // Blue
		Secondary:   ColorPair{Dark: "#cba6f7", Light: "#8839ef"}, // Mauve
		Success:     ColorPair{Dark: "#a6e3a1", Light: "#40a02b"}, // Green
		Warning:     ColorPair{Dark: "#f9e2af", Light: "#df8e1d"}, // Yellow
		Error:       ColorPair{Dark: "#f38ba8", Light: "#d20f39"}, // Red
		Info:        ColorPair{Dark: "#89dceb", Light: "#209fb5"}, // Sky
		Active:      ColorPair{Dark: "#89dceb", Light: "#04a5e5"}, // Sky
		Muted:       ColorPair{Dark: "#6c7086", Light: "#9ca0b0"}, // Overlay0
		Bg:          ColorPair{Dark: "#1e1e2e", Light: "#eff1f5"}, // Base
		BgDark:      ColorPair{Dark: "#181825", Light: "#e6e9ef"}, // Mantle
		BgLight:     ColorPair{Dark: "#313244", Light: "#ccd0da"}, // Surface0
		Fg:          ColorPair{Dark: "#cdd6f4", Light: "#4c4f69"}, // Text
		FgDim:       ColorPair{Dark: "#a6adc8", Light: "#6c6f85"}, // Subtext0
		Border:      ColorPair{Dark: "#45475a", Light: "#bcc0cc"}, // Surface1
		DiffAdd:     ColorPair{Dark: "#a6e3a1", Light: "#40a02b"}, // Green
		DiffRemove:  ColorPair{Dark: "#f38ba8", Light: "#d20f39"}, // Red
		DiffContext: ColorPair{Dark: "#6c7086", Light: "#9ca0b0"}, // Overlay0
	},
}
