package components

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
)

// SpinnerMsg is a common message type for spinner animations
type SpinnerMsg struct{}

// Spinner represents a reusable spinner component
type Spinner struct {
	frame    int
	frames   []string
	style    lipgloss.Style
	active   bool
	interval time.Duration
}

// NewSpinner creates a new spinner with default configuration
func NewSpinner() *Spinner {
	return &Spinner{
		frame:    0,
		frames:   []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"},
		style:    lipgloss.NewStyle().Foreground(colors.ZtcOrange),
		active:   false,
		interval: 100 * time.Millisecond,
	}
}

// NewDotsSpinner creates a spinner with dots animation
func NewDotsSpinner() *Spinner {
	return &Spinner{
		frame:    0,
		frames:   []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"},
		style:    lipgloss.NewStyle().Foreground(colors.ZtcOrange),
		active:   false,
		interval: 100 * time.Millisecond,
	}
}

// NewSimpleSpinner creates a simple rotating spinner
func NewSimpleSpinner() *Spinner {
	return &Spinner{
		frame:    0,
		frames:   []string{"|", "/", "-", "\\"},
		style:    lipgloss.NewStyle().Foreground(colors.ZtcOrange),
		active:   false,
		interval: 200 * time.Millisecond,
	}
}

// Start activates the spinner
func (s *Spinner) Start() {
	s.active = true
	s.frame = 0
}

// Stop deactivates the spinner
func (s *Spinner) Stop() {
	s.active = false
}

// IsActive returns whether the spinner is currently active
func (s *Spinner) IsActive() bool {
	return s.active
}

// Update advances the spinner frame
func (s *Spinner) Update(msg tea.Msg) tea.Cmd {
	switch msg.(type) {
	case SpinnerMsg:
		if s.active {
			s.frame = (s.frame + 1) % len(s.frames)
			return s.Tick()
		}
	}
	return nil
}

// Tick returns a command that will send a SpinnerMsg after the interval
func (s *Spinner) Tick() tea.Cmd {
	if !s.active {
		return nil
	}
	return tea.Tick(s.interval, func(t time.Time) tea.Msg {
		return SpinnerMsg{}
	})
}

// View renders the current spinner frame
func (s *Spinner) View() string {
	if !s.active {
		return ""
	}

	if s.frame < len(s.frames) {
		return s.style.Render(s.frames[s.frame])
	}
	return ""
}

// SetStyle sets the spinner style
func (s *Spinner) SetStyle(style lipgloss.Style) {
	s.style = style
}

// SetFrames sets custom animation frames
func (s *Spinner) SetFrames(frames []string) {
	s.frames = frames
	s.frame = 0
}

// SetInterval sets the animation interval
func (s *Spinner) SetInterval(interval time.Duration) {
	s.interval = interval
}
