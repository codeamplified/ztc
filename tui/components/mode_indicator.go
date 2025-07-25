package components

import (
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
	"ztc-tui/utils"
)

// ModeIndicator represents a visual indicator for the current configuration mode
type ModeIndicator struct {
	mode   utils.ConfigurationMode
	width  int
	height int
}

// ModeIndicatorStyles defines the styling for mode indicators
var modeIndicatorStyles = struct {
	SimpleMode   lipgloss.Style
	AdvancedMode lipgloss.Style
	Container    lipgloss.Style
	Label        lipgloss.Style
	Shortcut     lipgloss.Style
}{
	SimpleMode: lipgloss.NewStyle().
		Background(colors.ZtcGreen).
		Foreground(colors.ZtcWhite).
		Padding(0, 1).
		Margin(0, 1).
		Bold(true),

	AdvancedMode: lipgloss.NewStyle().
		Background(colors.ZtcOrange).
		Foreground(colors.ZtcWhite).
		Padding(0, 1).
		Margin(0, 1).
		Bold(true),

	Container: lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(colors.ZtcLightGray).
		Padding(0, 1).
		Margin(0, 0),

	Label: lipgloss.NewStyle().
		Foreground(colors.ZtcWhite).
		Bold(true),

	Shortcut: lipgloss.NewStyle().
		Foreground(colors.ZtcMutedGray).
		Italic(true),
}

// NewModeIndicator creates a new mode indicator
func NewModeIndicator(mode utils.ConfigurationMode) *ModeIndicator {
	return &ModeIndicator{
		mode:   mode,
		width:  40,
		height: 3,
	}
}

// SetMode updates the current mode
func (m *ModeIndicator) SetMode(mode utils.ConfigurationMode) {
	m.mode = mode
}

// View renders the mode indicator
func (m *ModeIndicator) View() string {
	var modeDisplay string
	var description string

	switch m.mode {
	case utils.ConfigModeSimple:
		modeDisplay = modeIndicatorStyles.SimpleMode.Render("🚀 SIMPLE")
		description = "Essential settings only"
	case utils.ConfigModeAdvanced:
		modeDisplay = modeIndicatorStyles.AdvancedMode.Render("⚙️  ADVANCED")
		description = "Full configuration control"
	default:
		modeDisplay = modeIndicatorStyles.SimpleMode.Render("UNKNOWN")
		description = "Unknown mode"
	}

	// Combine mode badge with description
	content := lipgloss.JoinHorizontal(
		lipgloss.Center,
		modeDisplay,
		modeIndicatorStyles.Label.Render(description),
	)

	// Add keyboard shortcut hint
	shortcutHint := modeIndicatorStyles.Shortcut.Render("Press 'M' to switch modes")
	
	// Stack vertically with shortcut hint
	fullContent := lipgloss.JoinVertical(
		lipgloss.Left,
		content,
		shortcutHint,
	)

	return modeIndicatorStyles.Container.Render(fullContent)
}

// Compact renders a compact version of the mode indicator
func (m *ModeIndicator) Compact() string {
	switch m.mode {
	case utils.ConfigModeSimple:
		return modeIndicatorStyles.SimpleMode.Render("🚀 SIMPLE")
	case utils.ConfigModeAdvanced:
		return modeIndicatorStyles.AdvancedMode.Render("⚙️  ADVANCED")
	default:
		return modeIndicatorStyles.SimpleMode.Render("UNKNOWN")
	}
}