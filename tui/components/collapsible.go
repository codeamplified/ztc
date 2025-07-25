package components

import (
	"strings"
	
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
)

// CollapsibleSection represents a collapsible group of content
type CollapsibleSection struct {
	title     string
	content   string
	expanded  bool
	focused   bool
	width     int
}

// CollapsibleStyles defines the styling for collapsible sections
var collapsibleStyles = struct {
	Header        lipgloss.Style
	HeaderFocused lipgloss.Style
	Content       lipgloss.Style
	Container     lipgloss.Style
	Arrow         lipgloss.Style
	ArrowFocused  lipgloss.Style
}{
	Header: lipgloss.NewStyle().
		Foreground(colors.ZtcWhite).
		Bold(true).
		Padding(0, 1),

	HeaderFocused: lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Padding(0, 1).
		Background(lipgloss.Color("#2A2A2A")),

	Content: lipgloss.NewStyle().
		Padding(1, 2).
		MarginLeft(2),

	Container: lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(colors.ZtcLightGray).
		Margin(1, 0),

	Arrow: lipgloss.NewStyle().
		Foreground(colors.ZtcMutedGray),

	ArrowFocused: lipgloss.NewStyle().
		Foreground(colors.ZtcOrange),
}

// NewCollapsibleSection creates a new collapsible section
func NewCollapsibleSection(title, content string, expanded bool) *CollapsibleSection {
	return &CollapsibleSection{
		title:    title,
		content:  content,
		expanded: expanded,
		focused:  false,
		width:    80,
	}
}

// SetFocused updates the focused state
func (c *CollapsibleSection) SetFocused(focused bool) {
	c.focused = focused
}

// IsFocused returns the current focused state
func (c *CollapsibleSection) IsFocused() bool {
	return c.focused
}

// Toggle toggles the expanded state
func (c *CollapsibleSection) Toggle() {
	c.expanded = !c.expanded
}

// IsExpanded returns whether the section is expanded
func (c *CollapsibleSection) IsExpanded() bool {
	return c.expanded
}

// SetContent updates the section content
func (c *CollapsibleSection) SetContent(content string) {
	c.content = content
}

// View renders the collapsible section
func (c *CollapsibleSection) View() string {
	// Choose arrow and header styles based on state
	var arrow string
	var headerStyle lipgloss.Style
	var arrowStyle lipgloss.Style

	if c.expanded {
		arrow = "▼"
	} else {
		arrow = "▶"
	}

	if c.focused {
		headerStyle = collapsibleStyles.HeaderFocused
		arrowStyle = collapsibleStyles.ArrowFocused
	} else {
		headerStyle = collapsibleStyles.Header
		arrowStyle = collapsibleStyles.Arrow
	}

	// Build header
	arrowRender := arrowStyle.Render(arrow)
	titleRender := headerStyle.Render(c.title)
	header := lipgloss.JoinHorizontal(lipgloss.Left, arrowRender, " ", titleRender)

	// Build content
	var result strings.Builder
	result.WriteString(header)

	if c.expanded && c.content != "" {
		result.WriteString("\n")
		contentRender := collapsibleStyles.Content.Render(c.content)
		result.WriteString(contentRender)
	}

	return collapsibleStyles.Container.Render(result.String())
}

// Compact renders a compact version without container styling
func (c *CollapsibleSection) Compact() string {
	var arrow string
	var headerStyle lipgloss.Style
	var arrowStyle lipgloss.Style

	if c.expanded {
		arrow = "▼"
	} else {
		arrow = "▶"
	}

	if c.focused {
		headerStyle = collapsibleStyles.HeaderFocused
		arrowStyle = collapsibleStyles.ArrowFocused
	} else {
		headerStyle = collapsibleStyles.Header
		arrowStyle = collapsibleStyles.Arrow
	}

	// Build header
	arrowRender := arrowStyle.Render(arrow)
	titleRender := headerStyle.Render(c.title)
	header := lipgloss.JoinHorizontal(lipgloss.Left, arrowRender, " ", titleRender)

	// Build content
	var result strings.Builder
	result.WriteString(header)

	if c.expanded && c.content != "" {
		result.WriteString("\n")
		result.WriteString(c.content)
	}

	return result.String()
}

// GetTitle returns the section title
func (c *CollapsibleSection) GetTitle() string {
	return c.title
}