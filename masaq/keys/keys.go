package keys

import "github.com/charmbracelet/bubbles/key"

// Map holds all keybindings for Masaq-powered TUIs.
type Map struct {
	Quit     key.Binding
	Help     key.Binding
	NavUp    key.Binding
	NavDown  key.Binding
	Top      key.Binding
	Bottom   key.Binding
	PageUp   key.Binding
	PageDown key.Binding
	Accept   key.Binding
	Reject   key.Binding
	Expand   key.Binding
	Back     key.Binding
	Submit   key.Binding
	Search   key.Binding
}

// Option configures a Map.
type Option func(*Map)

// WithVim adds j/k/g/G vim-style navigation bindings.
func WithVim() Option {
	return func(m *Map) {
		m.NavDown = key.NewBinding(
			key.WithKeys("down", "j"),
			key.WithHelp("↓/j", "down"),
		)
		m.NavUp = key.NewBinding(
			key.WithKeys("up", "k"),
			key.WithHelp("↑/k", "up"),
		)
		m.Top = key.NewBinding(
			key.WithKeys("home", "g"),
			key.WithHelp("home/g", "top"),
		)
		m.Bottom = key.NewBinding(
			key.WithKeys("end", "G"),
			key.WithHelp("end/G", "bottom"),
		)
	}
}

// NewDefault returns a Map with standard bindings.
func NewDefault(opts ...Option) Map {
	m := Map{
		Quit: key.NewBinding(
			key.WithKeys("ctrl+c"),
			key.WithHelp("ctrl+c", "quit"),
		),
		Help: key.NewBinding(
			key.WithKeys("?"),
			key.WithHelp("?", "help"),
		),
		NavUp: key.NewBinding(
			key.WithKeys("up"),
			key.WithHelp("↑", "up"),
		),
		NavDown: key.NewBinding(
			key.WithKeys("down"),
			key.WithHelp("↓", "down"),
		),
		Top: key.NewBinding(
			key.WithKeys("home"),
			key.WithHelp("home", "top"),
		),
		Bottom: key.NewBinding(
			key.WithKeys("end"),
			key.WithHelp("end", "bottom"),
		),
		PageUp: key.NewBinding(
			key.WithKeys("pgup"),
			key.WithHelp("pgup", "page up"),
		),
		PageDown: key.NewBinding(
			key.WithKeys("pgdown"),
			key.WithHelp("pgdn", "page down"),
		),
		Accept: key.NewBinding(
			key.WithKeys("y"),
			key.WithHelp("y", "accept"),
		),
		Reject: key.NewBinding(
			key.WithKeys("n"),
			key.WithHelp("n", "reject"),
		),
		Expand: key.NewBinding(
			key.WithKeys("d", "enter"),
			key.WithHelp("d/enter", "expand"),
		),
		Back: key.NewBinding(
			key.WithKeys("esc"),
			key.WithHelp("esc", "back"),
		),
		Submit: key.NewBinding(
			key.WithKeys("enter"),
			key.WithHelp("enter", "submit"),
		),
		Search: key.NewBinding(
			key.WithKeys("ctrl+f"),
			key.WithHelp("ctrl+f", "search"),
		),
	}
	for _, opt := range opts {
		opt(&m)
	}
	return m
}
