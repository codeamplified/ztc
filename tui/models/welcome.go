package models

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
	"ztc-tui/utils"
)

// Use Mission constants from utils
const (
	Pioneer     = utils.MissionPioneer
	Homesteader = utils.MissionHomesteader
)

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

// WelcomeModel now handles mission selection
type WelcomeModel struct {
	Width    int
	Height   int
	selected utils.Mission
}

// StateTransitionMsg is used to signal a change to the next view
type StateTransitionMsg struct {
	To      string
	Mission utils.Mission // Pass the selected mission to the next model
}

// NewWelcomeModel creates a new welcome model
func NewWelcomeModel() WelcomeModel {
	return WelcomeModel{
		Width:    80,
		Height:   24,
		selected: Pioneer, // Default selection
	}
}

// Init is called when the model is created
func (m WelcomeModel) Init() tea.Cmd {
	return nil
}

// Update handles messages and user input
func (m WelcomeModel) Update(msg tea.Msg) (WelcomeModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k", "left", "h":
			// Toggle selection
			if m.selected == Homesteader {
				m.selected = Pioneer
			}
		case "down", "j", "right", "l":
			// Toggle selection
			if m.selected == Pioneer {
				m.selected = Homesteader
			}
		case "enter":
			// Transition to the config view, passing the selected mission
			return m, func() tea.Msg {
				return StateTransitionMsg{
					To:      "config",
					Mission: m.selected,
				}
			}
		case "q", "ctrl+c":
			return m, tea.Quit
		}
	}

	return m, nil
}

// View renders the mission selection UI
func (m WelcomeModel) View() string {
	var content strings.Builder

	// Main Title
	mainTitle := titleStyle.Render("Welcome to Zero Touch Cluster")
	subTitle := helpStyle.Render("First, choose your mission. This will determine your cluster's architecture.")
	content.WriteString(mainTitle + "\n")
	content.WriteString(subTitle + "\n\n")

	// Pioneer Choice
	pioneerTitle := choiceTitleStyle.Render("🚀 The Pioneer")
	pioneerDesc := choiceDescStyle.Render("Explore Kubernetes with minimal gear (1-4 nodes).\nPerfect for learning and experimentation.")
	pioneerContent := pioneerTitle + "\n" + pioneerDesc
	pioneerBox := choiceBoxStyle.Render(pioneerContent)
	if m.selected == Pioneer {
		pioneerBox = selectedChoiceBoxStyle.Render(pioneerContent)
	}

	// Homesteader Choice
	homesteaderTitle := choiceTitleStyle.Render("🏰 The Homesteader")
	homesteaderDesc := choiceDescStyle.Render("Build a permanent, reliable digital home (5+ nodes).\nBuilt for high uptime and data safety.")
	homesteaderContent := homesteaderTitle + "\n" + homesteaderDesc
	homesteaderBox := choiceBoxStyle.Render(homesteaderContent)
	if m.selected == Homesteader {
		homesteaderBox = selectedChoiceBoxStyle.Render(homesteaderContent)
	}

	// Combine choices horizontally
	renderedChoices := lipgloss.JoinHorizontal(lipgloss.Top, pioneerBox, homesteaderBox)
	content.WriteString(renderedChoices)

	// Footer Help
	footer := helpStyle.Render("Use arrow keys to select, Enter to confirm, or Q to quit.")
	content.WriteString("\n\n" + footer)

	return content.String()
}
