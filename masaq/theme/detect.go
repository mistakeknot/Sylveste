package theme

import (
	"os"
	"strings"

	"github.com/muesli/termenv"
)

// DetectMode determines the color mode from the environment.
// Priority: MASAQ_COLOR_MODE env var > terminal background detection > default Dark.
func DetectMode() Mode {
	if v := os.Getenv("MASAQ_COLOR_MODE"); v != "" {
		if strings.EqualFold(v, "light") {
			return Light
		}
		return Dark
	}
	if !termenv.HasDarkBackground() {
		return Light
	}
	return Dark
}
