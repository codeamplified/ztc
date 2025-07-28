package models

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
	"ztc-tui/utils"
)

type CompleteModel struct {
	Width   int
	Height  int
	session *utils.Session

	// Completion state
	services []ServiceInfo
	selected int
	showHelp bool
}

type ServiceInfo struct {
	Name        string
	URL         string
	Description string
	Status      string
	Credentials string
}

type CompleteInitMsg struct {
	Session *utils.Session
}

// NewCompleteModel creates a new completion model
func NewCompleteModel() CompleteModel {
	return CompleteModel{
		Width:  0, // Will be set by WindowSizeMsg
		Height: 0, // Will be set by WindowSizeMsg
		services: []ServiceInfo{
			{
				Name:        "Homepage Dashboard",
				URL:         "http://homelab.lan",
				Description: "Unified entry point to all services",
				Status:      "ready",
				Credentials: "No login required",
			},
			{
				Name:        "Gitea Git Server",
				URL:         "http://gitea.homelab.lan",
				Description: "Private Git hosting and container registry",
				Status:      "ready",
				Credentials: "admin / <generated-password>",
			},
			{
				Name:        "ArgoCD GitOps",
				URL:         "http://argocd.homelab.lan",
				Description: "Continuous deployment management",
				Status:      "ready",
				Credentials: "admin / <generated-password>",
			},
			{
				Name:        "Grafana Monitoring",
				URL:         "http://grafana.homelab.lan",
				Description: "Metrics and dashboards",
				Status:      "ready",
				Credentials: "admin / <generated-password>",
			},
			{
				Name:        "Uptime Kuma",
				URL:         "http://status.homelab.lan",
				Description: "Service monitoring and status page",
				Status:      "ready",
				Credentials: "Setup required on first visit",
			},
		},
		selected: 0,
		showHelp: false,
	}
}

func (m CompleteModel) Init() tea.Cmd {
	return nil
}

func (m CompleteModel) Update(msg tea.Msg) (CompleteModel, tea.Cmd) {
	switch msg := msg.(type) {
	case CompleteInitMsg:
		m.session = msg.Session
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			if m.selected > 0 {
				m.selected--
			}
		case "down", "j":
			if m.selected < len(m.services)-1 {
				m.selected++
			}
		case "enter":
			// Open selected service URL (in a real implementation)
			// For now, just show help
			m.showHelp = true
		case "h":
			m.showHelp = !m.showHelp
		case "c":
			// Show credentials
			return m, m.showCredentials()
		case "q", "ctrl+c":
			return m, func() tea.Msg {
				return StateTransitionMsg{To: "quit"}
			}
		case "esc":
			if m.showHelp {
				m.showHelp = false
			}
		}
	}

	return m, nil
}

func (m CompleteModel) View() string {
	var content strings.Builder

	// Title with celebration
	title := lipgloss.NewStyle().
		Foreground(colors.ZtcGreen).
		Bold(true).
		Render("🎉 Cluster Deployment Complete!")

	content.WriteString(title + "\n\n")

	// Success message
	successMsg := `Congratulations! Your Zero Touch Cluster is ready.
All services are running and accessible via the URLs below.`

	content.WriteString(successMsg + "\n\n")

	// Services list
	content.WriteString("Available Services:\n")
	content.WriteString("==================\n\n")

	for i, service := range m.services {
		style := lipgloss.NewStyle()
		if i == m.selected {
			style = style.Background(colors.ZtcGreen).Foreground(colors.ZtcBlack)
		}

		status := m.renderServiceStatus(service)
		serviceLine := fmt.Sprintf("%s %s", status, service.Name)

		if i == m.selected {
			serviceLine = fmt.Sprintf("→ %s", serviceLine)
		} else {
			serviceLine = fmt.Sprintf("  %s", serviceLine)
		}

		content.WriteString(style.Render(serviceLine) + "\n")

		if i == m.selected {
			// Show details for selected service
			details := lipgloss.NewStyle().
				Foreground(colors.ZtcMutedGray).
				MarginLeft(4).
				Render(fmt.Sprintf("URL: %s\n    %s", service.URL, service.Description))

			content.WriteString(details + "\n")
		}
	}

	// Quick actions
	content.WriteString("\nQuick Actions:\n")
	content.WriteString("=============\n")
	content.WriteString("• View credentials: ./ztc-tui show-credentials\n")
	content.WriteString("• Backup secrets: ./ztc-tui backup-secrets\n")
	content.WriteString("• Deploy more apps: ./ztc-tui list-bundles\n")
	content.WriteString("• Check status: ./ztc-tui status\n")

	// Next steps
	content.WriteString("\nNext Steps:\n")
	content.WriteString("==========\n")
	content.WriteString("1. Visit http://homelab.lan to explore your cluster\n")
	content.WriteString("2. Configure services using the generated credentials\n")
	content.WriteString("3. Deploy additional applications via ArgoCD\n")
	content.WriteString("4. Read the documentation for advanced features\n")

	if m.showHelp {
		helpContent := `
Navigation:
  ↑/↓ or k/j    Select service
  Enter         Open service (in browser)
  h             Toggle this help
  c             Show all credentials
  q             Quit

Troubleshooting:
  • Services not accessible? Check firewall and network settings
  • Forgot credentials? Use: ./ztc-tui show-credentials
  • Need support? Check docs/ or GitHub issues

Documentation:
  • Quick start: docs/quick-start.md
  • Developer guide: docs/developer-guide.md
  • Architecture: docs/architecture.md`

		helpBox := lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colors.ZtcYellow).
			Padding(1).
			Width(m.Width - 4).
			Render(helpContent)

		content.WriteString("\n" + helpBox)
	}

	// Help
	help := lipgloss.NewStyle().
		Foreground(colors.ZtcMutedGray).
		Render("↑↓ Navigate • Enter Open • h Help • c Credentials • q Quit")

	content.WriteString("\n\n" + help)

	return content.String()
}

func (m CompleteModel) renderServiceStatus(service ServiceInfo) string {
	switch service.Status {
	case "ready":
		return lipgloss.NewStyle().Foreground(colors.ZtcGreen).Render("✓")
	case "starting":
		return lipgloss.NewStyle().Foreground(colors.ZtcYellow).Render("◐")
	case "error":
		return lipgloss.NewStyle().Foreground(colors.ZtcRed).Render("✗")
	default:
		return "?"
	}
}

func (m CompleteModel) showCredentials() tea.Cmd {
	return func() tea.Msg {
		// In a real implementation, this would show the credentials screen
		// For now, just return a message
		return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("credentials")}
	}
}
