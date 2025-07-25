package models

import (
	"fmt"
	"strings"

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
		Width:             80,
		Height:            24,
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

// Update handles messages and user input
func (m WelcomeModel) Update(msg tea.Msg) (WelcomeModel, tea.Cmd) {
	switch msg := msg.(type) {
	case templatesLoadedMsg:
		if msg.err != nil {
			m.err = msg.err
			return m, nil
		}
		m.featuredTemplates = msg.featured
		m.advancedTemplates = msg.advanced
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
			return m, nil

		case "up", "k":
			if m.mode == ViewFeatured {
				// Only toggle between featured templates (0 or 1)
				m.selectedIndex = 0
			} else if m.mode == ViewAdvanced {
				// Navigate advanced list
				if m.selectedIndex > 0 {
					m.selectedIndex--
				}
			} else if m.mode == ViewConfigMode {
				// Toggle between Simple (0) and Advanced (1)
				m.selectedIndex = 0
			}
			return m, nil

		case "down", "j":
			if m.mode == ViewFeatured {
				// Only toggle between featured templates (0 or 1)
				if len(m.featuredTemplates) > 1 {
					m.selectedIndex = 1
				}
			} else if m.mode == ViewAdvanced {
				// Navigate advanced list
				if m.selectedIndex < len(m.advancedTemplates)-1 {
					m.selectedIndex++
				}
			} else if m.mode == ViewConfigMode {
				// Toggle between Simple (0) and Advanced (1)
				m.selectedIndex = 1
			}
			return m, nil

		case "left", "h":
			if m.mode == ViewFeatured && len(m.featuredTemplates) > 1 {
				m.selectedIndex = 0
			} else if m.mode == ViewConfigMode {
				// Toggle between Simple (0) and Advanced (1)
				m.selectedIndex = 0
			}
			return m, nil

		case "right", "l":
			if m.mode == ViewFeatured && len(m.featuredTemplates) > 1 {
				m.selectedIndex = 1
			} else if m.mode == ViewConfigMode {
				// Toggle between Simple (0) and Advanced (1)  
				m.selectedIndex = 1
			}
			return m, nil

		case "esc", "backspace":
			// Go back to template selection from config mode selection
			if m.mode == ViewConfigMode {
				m.mode = ViewFeatured
				m.selectedIndex = 0
				m.selectedTemplateID = ""
			}
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

	return m, nil
}

// View renders the template selection UI
func (m WelcomeModel) View() string {
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

	// Footer Help
	var footer string
	if m.mode == ViewFeatured {
		footer = helpStyle.Render("Use arrow keys to select, Enter to confirm, 'a' for advanced, or 'q' to quit.")
	} else if m.mode == ViewAdvanced {
		footer = helpStyle.Render("Use up/down to select, Enter to confirm, 'a' for featured, or 'q' to quit.")
	} else if m.mode == ViewConfigMode {
		footer = helpStyle.Render("Use arrow keys to select, Enter to proceed, Esc to go back, or 'q' to quit.")
	}
	content.WriteString("\n\n" + footer)

	return content.String()
}

// renderFeaturedView renders the featured templates view (side-by-side boxes)
func (m WelcomeModel) renderFeaturedView() string {
	if len(m.featuredTemplates) == 0 {
		return helpStyle.Render("No featured templates available.")
	}

	var boxes []string
	for i, template := range m.featuredTemplates {
		templateTitle := choiceTitleStyle.Render(template.Name)
		templateDesc := choiceDescStyle.Render(template.Description)
		templateContent := templateTitle + "\n" + templateDesc

		var box string
		if i == m.selectedIndex {
			box = selectedChoiceBoxStyle.Render(templateContent)
		} else {
			box = choiceBoxStyle.Render(templateContent)
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
	// Simple mode option
	simpleTitle := choiceTitleStyle.Render("🚀 Simple Setup")
	simpleDesc := choiceDescStyle.Render(
		"Perfect for getting started quickly\n\n" +
		"Configure only the essentials:\n" +
		"• Cluster name\n" +
		"• Network settings (auto-detected)\n" +
		"• SSH keys (auto-discovered)\n" +
		"• Uses template defaults for everything else\n\n" +
		"Time: ~2 minutes")
	simpleContent := simpleTitle + "\n" + simpleDesc

	// Advanced mode option
	advancedTitle := choiceTitleStyle.Render("⚙️  Advanced Configuration")
	advancedDesc := choiceDescStyle.Render(
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
		simpleBox = selectedChoiceBoxStyle.Render(simpleContent)
		advancedBox = choiceBoxStyle.Render(advancedContent)
	} else {
		simpleBox = choiceBoxStyle.Render(simpleContent)
		advancedBox = selectedChoiceBoxStyle.Render(advancedContent)
	}

	// Join boxes horizontally
	return lipgloss.JoinHorizontal(lipgloss.Top, simpleBox, advancedBox)
}
