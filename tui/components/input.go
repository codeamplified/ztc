package components

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
)

// InputField represents a text input field
type InputField struct {
	Label       string
	Value       string
	Placeholder string
	Width       int
	Focused     bool
	Cursor      int
	MaxLength   int
	Validate    func(string) error
	
	// Internal state
	validationError string
}

// NewInputField creates a new input field
func NewInputField(label, placeholder string, width int) *InputField {
	return &InputField{
		Label:       label,
		Value:       "",
		Placeholder: placeholder,
		Width:       width,
		Focused:     false,
		Cursor:      0,
		MaxLength:   0, // 0 means no limit
	}
}

// Focus sets focus to the input field
func (i *InputField) Focus() {
	i.Focused = true
	i.Cursor = len(i.Value)
}

// Blur removes focus from the input field
func (i *InputField) Blur() {
	i.Focused = false
}

// Update handles input field updates
func (i *InputField) Update(msg tea.Msg) tea.Cmd {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if !i.Focused {
			return nil
		}
		
		switch msg.String() {
		case "left":
			if i.Cursor > 0 {
				i.Cursor--
			}
		case "right":
			if i.Cursor < len(i.Value) {
				i.Cursor++
			}
		case "home":
			i.Cursor = 0
		case "end":
			i.Cursor = len(i.Value)
		case "backspace":
			if i.Cursor > 0 && len(i.Value) > 0 {
				i.Value = i.Value[:i.Cursor-1] + i.Value[i.Cursor:]
				i.Cursor--
			}
		case "delete":
			if i.Cursor < len(i.Value) {
				i.Value = i.Value[:i.Cursor] + i.Value[i.Cursor+1:]
			}
		case "ctrl+a":
			i.Cursor = 0
		case "ctrl+e":
			i.Cursor = len(i.Value)
		case "ctrl+u":
			i.Value = i.Value[i.Cursor:]
			i.Cursor = 0
		case "ctrl+k":
			i.Value = i.Value[:i.Cursor]
		default:
			// Handle regular character input
			if len(msg.String()) == 1 {
				char := msg.String()
				// Check if it's a printable character
				if char >= " " && char <= "~" {
					// Check max length
					if i.MaxLength == 0 || len(i.Value) < i.MaxLength {
						i.Value = i.Value[:i.Cursor] + char + i.Value[i.Cursor:]
						i.Cursor++
						// Clear validation error when user starts typing
						i.validationError = ""
					}
				}
			}
		}
	}
	
	return nil
}

// View renders the input field
func (i *InputField) View() string {
	var b strings.Builder
	
	// Label
	if i.Label != "" {
		labelStyle := lipgloss.NewStyle().
			Foreground(colors.ZtcWhite).
			Bold(true)
		b.WriteString(labelStyle.Render(i.Label))
		b.WriteString("\n")
	}
	
	// Input box
	content := i.Value
	if content == "" && !i.Focused {
		content = i.Placeholder
	}
	
	// Add cursor if focused
	if i.Focused {
		if i.Cursor <= len(content) {
			left := content[:i.Cursor]
			right := content[i.Cursor:]
			cursor := "|"
			content = left + cursor + right
		}
	}
	
	// Ensure minimum width
	if len(content) < i.Width-2 {
		content += strings.Repeat(" ", i.Width-2-len(content))
	}
	
	// Input box style
	inputStyle := lipgloss.NewStyle().
		Width(i.Width).
		Padding(0, 1).
		Border(lipgloss.RoundedBorder())
	
	if i.Focused {
		inputStyle = inputStyle.
			BorderForeground(colors.ZtcOrange).
			Foreground(colors.ZtcWhite)
	} else {
		inputStyle = inputStyle.
			BorderForeground(colors.ZtcLightGray).
			Foreground(colors.ZtcLightGray)
	}
	
	b.WriteString(inputStyle.Render(content))
	
	// Show validation error if present
	if i.validationError != "" {
		b.WriteString("\n")
		errorStyle := lipgloss.NewStyle().
			Foreground(colors.ZtcDarkOrange).
			Bold(true)
		b.WriteString(errorStyle.Render("⚠ " + i.validationError))
	}
	
	return b.String()
}

// SetValue sets the input field value
func (i *InputField) SetValue(value string) {
	i.Value = value
	i.Cursor = len(value)
}

// GetValue returns the current input field value
func (i *InputField) GetValue() string {
	return i.Value
}

// Validate validates the current input value
func (i *InputField) ValidateInput() bool {
	if i.Validate == nil {
		return true
	}
	
	if err := i.Validate(i.Value); err != nil {
		i.validationError = err.Error()
		return false
	}
	
	i.validationError = ""
	return true
}

// IsValid returns true if the input is valid
func (i *InputField) IsValid() bool {
	return i.validationError == ""
}

// SelectField represents a dropdown selection field
type SelectField struct {
	Label    string
	Options  []string
	Selected int
	Width    int
	Focused  bool
	Open     bool
}

// NewSelectField creates a new select field
func NewSelectField(label string, options []string, width int) *SelectField {
	return &SelectField{
		Label:    label,
		Options:  options,
		Selected: 0,
		Width:    width,
		Focused:  false,
		Open:     false,
	}
}

// Focus sets focus to the select field
func (s *SelectField) Focus() {
	s.Focused = true
}

// Blur removes focus from the select field
func (s *SelectField) Blur() {
	s.Focused = false
	s.Open = false
}

// Update handles select field updates
func (s *SelectField) Update(msg tea.Msg) tea.Cmd {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if !s.Focused {
			return nil
		}
		
		switch msg.String() {
		case "enter", " ":
			s.Open = !s.Open
		case "up":
			// Allow up/down navigation even when closed
			if s.Selected > 0 {
				s.Selected--
			}
		case "down":
			// Allow up/down navigation even when closed
			if s.Selected < len(s.Options)-1 {
				s.Selected++
			}
		case "esc":
			s.Open = false
		}
	}
	
	return nil
}

// View renders the select field
func (s *SelectField) View() string {
	var b strings.Builder
	
	// Label
	if s.Label != "" {
		labelStyle := lipgloss.NewStyle().
			Foreground(colors.ZtcWhite).
			Bold(true)
		b.WriteString(labelStyle.Render(s.Label))
		b.WriteString("\n")
	}
	
	// Current selection
	currentValue := ""
	if s.Selected < len(s.Options) {
		currentValue = s.Options[s.Selected]
	}
	
	// Dropdown indicator and selection info
	indicator := "▼"
	if s.Open {
		indicator = "▲"
	}
	
	selectionInfo := fmt.Sprintf(" (%d/%d)", s.Selected+1, len(s.Options))
	content := currentValue + selectionInfo + strings.Repeat(" ", s.Width-len(currentValue)-len(selectionInfo)-3) + indicator
	
	// Select box style
	selectStyle := lipgloss.NewStyle().
		Width(s.Width).
		Padding(0, 1).
		Border(lipgloss.RoundedBorder())
	
	if s.Focused {
		selectStyle = selectStyle.
			BorderForeground(colors.ZtcOrange).
			Foreground(colors.ZtcWhite)
	} else {
		selectStyle = selectStyle.
			BorderForeground(colors.ZtcLightGray).
			Foreground(colors.ZtcLightGray)
	}
	
	b.WriteString(selectStyle.Render(content))
	
	// Options dropdown
	if s.Open {
		b.WriteString("\n")
		for i, option := range s.Options {
			optionStyle := lipgloss.NewStyle().
				Width(s.Width).
				Padding(0, 1)
			
			if i == s.Selected {
				optionStyle = optionStyle.
					Background(colors.ZtcOrange).
					Foreground(colors.ZtcBlack)
			} else {
				optionStyle = optionStyle.
					Foreground(colors.ZtcLightGray)
			}
			
			b.WriteString(optionStyle.Render(option))
			b.WriteString("\n")
		}
	}
	
	return b.String()
}

// GetValue returns the currently selected value
func (s *SelectField) GetValue() string {
	if s.Selected < len(s.Options) {
		return s.Options[s.Selected]
	}
	return ""
}

// SetValue sets the selected value
func (s *SelectField) SetValue(value string) {
	for i, option := range s.Options {
		if option == value {
			s.Selected = i
			break
		}
	}
}

// ToggleField represents a boolean toggle field
type ToggleField struct {
	Label   string
	Value   bool
	Focused bool
	Width   int
}

// NewToggleField creates a new toggle field
func NewToggleField(label string, defaultValue bool) *ToggleField {
	return &ToggleField{
		Label:   label,
		Value:   defaultValue,
		Focused: false,
		Width:   30,
	}
}

// Focus sets focus to the toggle field
func (t *ToggleField) Focus() {
	t.Focused = true
}

// Blur removes focus from the toggle field
func (t *ToggleField) Blur() {
	t.Focused = false
}

// Update handles toggle field updates
func (t *ToggleField) Update(msg tea.Msg) tea.Cmd {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if !t.Focused {
			return nil
		}
		
		switch msg.String() {
		case "enter", " ":
			t.Value = !t.Value
		}
	}
	
	return nil
}

// View renders the toggle field
func (t *ToggleField) View() string {
	var b strings.Builder
	
	// Toggle indicator
	indicator := "☐"
	if t.Value {
		indicator = "☑"
	}
	
	// Label and toggle
	content := indicator + " " + t.Label
	
	// Toggle style
	toggleStyle := lipgloss.NewStyle().
		Width(t.Width).
		Padding(0, 1)
	
	if t.Focused {
		toggleStyle = toggleStyle.
			Foreground(colors.ZtcOrange).
			Bold(true)
	} else {
		toggleStyle = toggleStyle.
			Foreground(colors.ZtcLightGray)
	}
	
	b.WriteString(toggleStyle.Render(content))
	
	return b.String()
}

// GetValue returns the toggle value
func (t *ToggleField) GetValue() bool {
	return t.Value
}

// SetValue sets the toggle value
func (t *ToggleField) SetValue(value bool) {
	t.Value = value
}