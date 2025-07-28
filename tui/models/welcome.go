package models

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
	"ztc-tui/utils"
)

// Template-agnostic welcome screen - no mission constants needed

// Styles for the mission selection screen
var (
	titleStyle = lipgloss.NewStyle().
			Foreground(colors.ZtcOrange).
			Bold(true).
			Align(lipgloss.Center).
			MarginBottom(1)

	choiceBoxStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colors.ZtcLightGray).
			Padding(1, 2).
			Margin(1, 0)

	selectedChoiceBoxStyle = lipgloss.NewStyle().
				Border(lipgloss.ThickBorder(), true).
				BorderForeground(colors.ZtcOrange).
				Padding(1, 2).
				Margin(1, 0)

	choiceTitleStyle = lipgloss.NewStyle().
				Foreground(colors.ZtcOrange).
				Bold(true)

	choiceDescStyle = lipgloss.NewStyle().
			Foreground(colors.ZtcWhite)

	helpStyle = lipgloss.NewStyle().
			Foreground(colors.ZtcMutedGray).
			Align(lipgloss.Center).
			MarginTop(1)
)

// ViewMode represents the current view mode of the welcome screen
type ViewMode int

const (
	ViewFeatured ViewMode = iota
	ViewAdvanced
	ViewConfigMode
)

// WelcomeModel now handles dynamic template selection
type WelcomeModel struct {
	Width             int
	Height            int
	viewport          viewport.Model
	ready             bool
	featuredTemplates []utils.TemplateInfo
	advancedTemplates []utils.TemplateInfo
	mode              ViewMode
	selectedIndex     int // Index for featured is 0 or 1, for advanced it's a list index
	selectedTemplateID string // Stores the template ID when moving to config mode selection
	err               error
}

// StateTransitionMsg is used to signal a change to the next view
type StateTransitionMsg struct {
	To         string
	TemplateID string // Pass the selected template ID to the next model
	ConfigMode utils.ConfigurationMode // Pass the selected configuration mode
}

// NewWelcomeModel creates a new welcome model
func NewWelcomeModel() WelcomeModel {
	return WelcomeModel{
		Width:             0, // Will be set by WindowSizeMsg
		Height:            0, // Will be set by WindowSizeMsg
		featuredTemplates: []utils.TemplateInfo{},
		advancedTemplates: []utils.TemplateInfo{},
		mode:              ViewFeatured,
		selectedIndex:     0,
		err:               nil,
	}
}

// Init is called when the model is created
func (m WelcomeModel) Init() tea.Cmd {
	return m.loadTemplatesCmd()
}

// loadTemplatesCmd loads available templates and partitions them
func (m WelcomeModel) loadTemplatesCmd() tea.Cmd {
	return func() tea.Msg {
		templates, err := utils.LoadAvailableTemplates()
		if err != nil {
			return templatesLoadedMsg{err: err}
		}

		var featured, advanced []utils.TemplateInfo
		for _, template := range templates {
			if template.IsFeatured {
				featured = append(featured, template)
			} else {
				advanced = append(advanced, template)
			}
		}

		return templatesLoadedMsg{
			featured: featured,
			advanced: advanced,
		}
	}
}

// templatesLoadedMsg is sent when templates are loaded
type templatesLoadedMsg struct {
	featured []utils.TemplateInfo
	advanced []utils.TemplateInfo
	err      error
}

// currentSelectableCount returns the number of selectable items in the current mode
func (m WelcomeModel) currentSelectableCount() int {
	switch m.mode {
	case ViewFeatured:
		return len(m.featuredTemplates)
	case ViewAdvanced:
		return len(m.advancedTemplates)
	case ViewConfigMode:
		return 2 // Simple and Advanced
	default:
		return 0
	}
}

// Update handles messages and user input
func (m WelcomeModel) Update(msg tea.Msg) (WelcomeModel, tea.Cmd) {
	var cmd tea.Cmd
	var cmds []tea.Cmd
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.Width = msg.Width
		m.Height = msg.Height
		if !m.ready {
			m.viewport = viewport.New(m.Width, m.Height-10)
			m.ready = true
		} else {
			m.viewport.Width = m.Width
			m.viewport.Height = m.Height - 10
		}
	case templatesLoadedMsg:
		if msg.err != nil {
			m.err = msg.err
			return m, nil
		}
		m.featuredTemplates = msg.featured
		m.advancedTemplates = msg.advanced
		
		// Initialize viewport if not ready yet (fallback for missing WindowSizeMsg)
		if !m.ready {
			width := m.Width
			height := m.Height
			if width == 0 {
				width = 80 // Fallback width
			}
			if height == 0 {
				height = 24 // Fallback height
			}
			m.viewport = viewport.New(width, height-10) // Leave space for header/footer
			m.ready = true
		}
		
		m.viewport.SetContent(m.renderContent())
		return m, nil

	case tea.KeyMsg:
		// Don't process keys if templates aren't loaded yet
		if len(m.featuredTemplates) == 0 && len(m.advancedTemplates) == 0 && m.err == nil {
			return m, nil
		}

		switch msg.String() {
		case "a", "A":
			// Toggle between featured and advanced view
			if m.mode == ViewFeatured {
				m.mode = ViewAdvanced
				m.selectedIndex = 0 // Reset selection
			} else {
				m.mode = ViewFeatured
				m.selectedIndex = 0 // Reset selection
			}
			m.viewport.SetContent(m.renderContent())
			return m, nil

		case "up", "k", "left", "h":
			if m.mode == ViewFeatured {
				m.selectedIndex = 0
			} else if m.mode == ViewAdvanced {
				if m.selectedIndex > 0 {
					m.selectedIndex--
				}
			} else if m.mode == ViewConfigMode {
				m.selectedIndex = 0
			}
			m.viewport.SetContent(m.renderContent())
			return m, nil

		case "down", "j", "right", "l":
			if m.mode == ViewFeatured {
				if m.currentSelectableCount() > 1 {
					m.selectedIndex = 1
				}
			} else if m.mode == ViewAdvanced {
				if m.selectedIndex < m.currentSelectableCount()-1 {
					m.selectedIndex++
				}
			} else if m.mode == ViewConfigMode {
				m.selectedIndex = 1
			}
			m.viewport.SetContent(m.renderContent())
			return m, nil

		case "esc", "backspace":
			// Go back to template selection from config mode selection
			if m.mode == ViewConfigMode {
				m.mode = ViewFeatured
				m.selectedIndex = 0
				m.selectedTemplateID = ""
			}
			m.viewport.SetContent(m.renderContent())
			return m, nil

		case "enter":
			if m.mode == ViewFeatured || m.mode == ViewAdvanced {
				// Get the selected template ID
				var templateID string
				if m.mode == ViewFeatured {
					if m.selectedIndex < len(m.featuredTemplates) {
						templateID = m.featuredTemplates[m.selectedIndex].ID
					}
				} else {
					if m.selectedIndex < len(m.advancedTemplates) {
						templateID = m.advancedTemplates[m.selectedIndex].ID
					}
				}

				if templateID != "" {
					// Move to configuration mode selection
					m.selectedTemplateID = templateID
					m.mode = ViewConfigMode
					m.selectedIndex = 0 // Start with Simple mode selected
					m.viewport.SetContent(m.renderContent())
				}
				return m, nil
			} else if m.mode == ViewConfigMode {
				// Configuration mode selection - proceed to config
				var configMode utils.ConfigurationMode
				if m.selectedIndex == 0 {
					configMode = utils.ConfigModeSimple
				} else {
					configMode = utils.ConfigModeAdvanced
				}

				return m, func() tea.Msg {
					return StateTransitionMsg{
						To:         "config",
						TemplateID: m.selectedTemplateID,
						ConfigMode: configMode,
					}
				}
			}
			return m, nil

		case "q", "ctrl+c":
			return m, tea.Quit
		}
	}

	m.viewport, cmd = m.viewport.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

func (m WelcomeModel) renderContent() string {
	var content strings.Builder
	// Show current mode and instructions
	if m.mode == ViewFeatured {
		subTitle := helpStyle.Render("Choose your cluster template. Press 'a' for advanced options.")
		content.WriteString(subTitle + "\n\n")
		content.WriteString(m.renderFeaturedView())
	} else if m.mode == ViewAdvanced {
		subTitle := helpStyle.Render("Advanced Templates. Press 'a' to return to featured templates.")
		content.WriteString(subTitle + "\n\n")
		content.WriteString(m.renderAdvancedView())
	} else if m.mode == ViewConfigMode {
		// Show selected template name
		var templateName string
		if m.mode == ViewConfigMode && m.selectedTemplateID != "" {
			// Find the template name from the selected ID
			for _, t := range m.featuredTemplates {
				if t.ID == m.selectedTemplateID {
					templateName = t.Name
					break
				}
			}
			if templateName == "" {
				for _, t := range m.advancedTemplates {
					if t.ID == m.selectedTemplateID {
						templateName = t.Name
						break
					}
				}
			}
		}

		if templateName != "" {
			templateInfo := choiceTitleStyle.Render(fmt.Sprintf("Template: %s", templateName))
			content.WriteString(templateInfo + "\n")
		}

		subTitle := helpStyle.Render("Choose your configuration experience. Use arrow keys to select.")
		content.WriteString(subTitle + "\n\n")
		content.WriteString(m.renderConfigModeView())
	}
	return content.String()
}

// View renders the template selection UI
func (m WelcomeModel) View() string {
	if !m.ready {
		// Check if we have templates loaded but viewport isn't ready
		if len(m.featuredTemplates) > 0 || len(m.advancedTemplates) > 0 {
			// Show a simple template list without viewport
			content := "Welcome to Zero Touch Cluster\n\nAvailable Templates:\n"
			for _, template := range m.featuredTemplates {
				content += fmt.Sprintf("- %s (Featured): %s\n", template.Name, template.Description)
			}
			for _, template := range m.advancedTemplates {
				content += fmt.Sprintf("- %s: %s\n", template.Name, template.Description)
			}
			content += "\nPress any key to continue..."
			return content
		}
		return "Initializing..."
	}
	var content strings.Builder

	// Main Title
	mainTitle := titleStyle.Render("Welcome to Zero Touch Cluster")
	content.WriteString(mainTitle + "\n")

	// Handle loading and error states
	if m.err != nil {
		errorMsg := helpStyle.Render(fmt.Sprintf("Error loading templates: %s", m.err.Error()))
		content.WriteString(errorMsg + "\n")
		return content.String()
	}

	if len(m.featuredTemplates) == 0 && len(m.advancedTemplates) == 0 {
		loadingMsg := helpStyle.Render("Loading available templates...")
		content.WriteString(loadingMsg + "\n")
		return content.String()
	}

	content.WriteString(m.viewport.View())

	// Footer Help
	var footer string
	if m.mode == ViewFeatured {
		if m.currentSelectableCount() > 1 {
			footer = helpStyle.Render("↑/↓ Scroll • Use arrow keys to select, Enter to confirm, 'a' for advanced, or 'q' to quit.")
		} else {
			footer = helpStyle.Render("↑/↓ Scroll • Enter to confirm, 'a' for advanced, or 'q' to quit.")
		}
	} else if m.mode == ViewAdvanced {
		footer = helpStyle.Render("↑/↓ Scroll • Use up/down to select, Enter to confirm, 'a' for featured, or 'q' to quit.")
	} else if m.mode == ViewConfigMode {
		footer = helpStyle.Render("↑/↓ Scroll • Use arrow keys to select, Enter to proceed, Esc to go back, or 'q' to quit.")
	}
	content.WriteString("\n\n" + footer)

	return content.String()
}

// renderFeaturedView renders the featured templates view (side-by-side boxes)
func (m WelcomeModel) renderFeaturedView() string {
	if len(m.featuredTemplates) == 0 {
		return helpStyle.Render("No featured templates available.")
	}

	// Calculate box width based on available space
	boxCount := len(m.featuredTemplates)
	availableWidth := m.Width
	if availableWidth == 0 {
		availableWidth = 80 // Fallback
	}
	
	// Account for margins and padding
	marginPerBox := 4 // 2 chars margin on each side
	paddingPerBox := 6 // 2 chars padding on each side + borders
	totalSpacing := (marginPerBox + paddingPerBox) * boxCount
	
	// Calculate width for each box
	boxWidth := (availableWidth - totalSpacing) / boxCount
	if boxWidth < 30 {
		boxWidth = 30 // Minimum width
	}

	var boxes []string
	for i, template := range m.featuredTemplates {
		templateTitle := choiceTitleStyle.Copy().Width(boxWidth-4).Render(template.Name)
		templateDesc := choiceDescStyle.Copy().Width(boxWidth-4).Render(template.Description)
		templateContent := templateTitle + "\n" + templateDesc

		var box string
		if i == m.selectedIndex {
			box = selectedChoiceBoxStyle.Copy().Width(boxWidth).Render(templateContent)
		} else {
			box = choiceBoxStyle.Copy().Width(boxWidth).Render(templateContent)
		}
		boxes = append(boxes, box)
	}

	// Join boxes horizontally if we have multiple featured templates
	if len(boxes) > 1 {
		return lipgloss.JoinHorizontal(lipgloss.Top, boxes...)
	}
	return boxes[0]
}

// renderAdvancedView renders the advanced templates view (vertical list)
func (m WelcomeModel) renderAdvancedView() string {
	if len(m.advancedTemplates) == 0 {
		return helpStyle.Render("No advanced templates available.")
	}

	var items []string
	for i, template := range m.advancedTemplates {
		templateTitle := choiceTitleStyle.Render(template.Name)
		templateDesc := choiceDescStyle.Render(template.Description)
		templateContent := templateTitle + "\n" + templateDesc

		var item string
		if i == m.selectedIndex {
			item = selectedChoiceBoxStyle.Render(templateContent)
		} else {
			item = choiceBoxStyle.Render(templateContent)
		}
		items = append(items, item)
	}

	return strings.Join(items, "\n")
}

// renderConfigModeView renders the configuration mode selection view (side-by-side boxes)
func (m WelcomeModel) renderConfigModeView() string {
	// Calculate box width based on available space
	availableWidth := m.Width
	if availableWidth == 0 {
		availableWidth = 80 // Fallback
	}
	
	// Two boxes side by side
	boxCount := 2
	marginPerBox := 4 // 2 chars margin on each side
	paddingPerBox := 6 // 2 chars padding on each side + borders
	totalSpacing := (marginPerBox + paddingPerBox) * boxCount
	
	// Calculate width for each box
	boxWidth := (availableWidth - totalSpacing) / boxCount
	if boxWidth < 35 {
		boxWidth = 35 // Minimum width for config mode boxes
	}

	// Simple mode option
	simpleTitle := choiceTitleStyle.Copy().Width(boxWidth-4).Render("🚀 Simple Setup")
	simpleDesc := choiceDescStyle.Copy().Width(boxWidth-4).Render(
		"Perfect for getting started quickly\n\n" +
		"Configure only the essentials:\n" +
		"• Cluster name\n" +
		"• Network settings (auto-detected)\n" +
		"• SSH keys (auto-discovered)\n" +
		"• Uses template defaults for everything else\n\n" +
		"Time: ~2 minutes")
	simpleContent := simpleTitle + "\n" + simpleDesc

	// Advanced mode option
	advancedTitle := choiceTitleStyle.Copy().Width(boxWidth-4).Render("⚙️  Advanced Configuration")
	advancedDesc := choiceDescStyle.Copy().Width(boxWidth-4).Render(
		"Full control over your cluster\n\n" +
		"Configure everything:\n" +
		"• Cluster & network settings\n" +
		"• Storage backend options\n" +
		"• Application bundles\n" +
		"• Resource limits & advanced options\n\n" +
		"Time: ~5-10 minutes")
	advancedContent := advancedTitle + "\n" + advancedDesc

	// Apply selection styling
	var simpleBox, advancedBox string
	if m.selectedIndex == 0 {
		simpleBox = selectedChoiceBoxStyle.Copy().Width(boxWidth).Render(simpleContent)
		advancedBox = choiceBoxStyle.Copy().Width(boxWidth).Render(advancedContent)
	} else {
		simpleBox = choiceBoxStyle.Copy().Width(boxWidth).Render(simpleContent)
		advancedBox = selectedChoiceBoxStyle.Copy().Width(boxWidth).Render(advancedContent)
	}

	// Join boxes horizontally
	return lipgloss.JoinHorizontal(lipgloss.Top, simpleBox, advancedBox)
}
