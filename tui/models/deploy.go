package models

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/utils"
)

type DeployModel struct {
	Width   int
	Height  int
	session *utils.Session
	
	// Deployment state
	phases        []DeployPhase
	currentPhase  int
	logs          []string
	progress      int
	deploying     bool
	completed     bool
	error         error
}

type DeployPhase struct {
	Name        string
	Description string
	Status      string // "pending", "running", "complete", "error"
	Progress    int
	Duration    string
}

type DeployInitMsg struct {
	Session *utils.Session
}

// NewDeployModel creates a new deployment model
func NewDeployModel() DeployModel {
	return DeployModel{
		Width:   80,
		Height:  24,
		phases: []DeployPhase{
			{
				Name:        "Infrastructure",
				Description: "Preparing cluster infrastructure",
				Status:      "pending",
				Progress:    0,
				Duration:    "",
			},
			{
				Name:        "Secrets",
				Description: "Generating secure credentials",
				Status:      "pending",
				Progress:    0,
				Duration:    "",
			},
			{
				Name:        "Networking",
				Description: "Configuring cluster networking",
				Status:      "pending",
				Progress:    0,
				Duration:    "",
			},
			{
				Name:        "Storage",
				Description: "Setting up storage classes",
				Status:      "pending",
				Progress:    0,
				Duration:    "",
			},
			{
				Name:        "Components",
				Description: "Deploying system components",
				Status:      "pending",
				Progress:    0,
				Duration:    "",
			},
			{
				Name:        "GitOps",
				Description: "Configuring ArgoCD",
				Status:      "pending",
				Progress:    0,
				Duration:    "",
			},
			{
				Name:        "Workloads",
				Description: "Deploying applications",
				Status:      "pending",
				Progress:    0,
				Duration:    "",
			},
		},
		currentPhase: 0,
		logs:         []string{},
		progress:     0,
		deploying:    false,
		completed:    false,
		error:        nil,
	}
}

func (m DeployModel) Init() tea.Cmd {
	return nil
}

func (m DeployModel) Update(msg tea.Msg) (DeployModel, tea.Cmd) {
	switch msg := msg.(type) {
	case DeployInitMsg:
		m.session = msg.Session
		// Auto-start deployment
		m.deploying = true
		return m, m.startDeployment()
		
	case tea.KeyMsg:
		switch msg.String() {
		case "enter":
			if m.completed {
				return m, func() tea.Msg {
					return StateTransitionMsg{To: "complete"}
				}
			}
		case "q", "ctrl+c":
			return m, func() tea.Msg {
				return StateTransitionMsg{To: "quit"}
			}
		case "esc":
			if !m.deploying {
				return m, func() tea.Msg {
					return StateTransitionMsg{To: "usb"}
				}
			}
		}
	}
	
	return m, nil
}

func (m DeployModel) View() string {
	var content strings.Builder
	
	// Title
	title := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#00D4AA")).
		Bold(true).
		Render("Cluster Deployment")
	
	content.WriteString(title + "\n\n")
	
	if !m.deploying {
		// Pre-deployment screen
		content.WriteString("Ready to deploy your cluster!\n\n")
		content.WriteString("This will:\n")
		content.WriteString("• Install Kubernetes on your nodes\n")
		content.WriteString("• Configure networking and storage\n")
		content.WriteString("• Deploy monitoring and GitOps\n")
		content.WriteString("• Set up your dashboard\n\n")
		content.WriteString("Press Enter to start deployment")
	} else {
		// Deployment progress
		content.WriteString("Deploying your cluster...\n\n")
		
		// Phase progress
		for i, phase := range m.phases {
			status := m.renderPhaseStatus(phase)
			line := fmt.Sprintf("%s %s", status, phase.Name)
			
			if i == m.currentPhase {
				line = lipgloss.NewStyle().Bold(true).Render(line)
			}
			
			content.WriteString(line + "\n")
			
			if phase.Status == "running" && phase.Progress > 0 {
				progressBar := m.renderPhaseProgress(phase)
				content.WriteString("  " + progressBar + "\n")
			}
		}
		
		// Overall progress
		overallProgress := m.renderOverallProgress()
		content.WriteString("\n" + overallProgress + "\n")
		
		// Recent logs
		content.WriteString("\nRecent activity:\n")
		logHeight := 5
		startIdx := 0
		if len(m.logs) > logHeight {
			startIdx = len(m.logs) - logHeight
		}
		
		for i := startIdx; i < len(m.logs); i++ {
			content.WriteString(fmt.Sprintf("  %s\n", m.logs[i]))
		}
		
		if m.completed {
			content.WriteString("\n✓ Deployment completed successfully!")
			content.WriteString("\nPress Enter to access your cluster")
		} else if m.error != nil {
			content.WriteString(fmt.Sprintf("\n✗ Deployment failed: %v", m.error))
		}
	}
	
	// Help
	help := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#626262")).
		Render("Enter Continue • q Quit")
	
	content.WriteString("\n\n" + help)
	
	return content.String()
}

func (m DeployModel) renderPhaseStatus(phase DeployPhase) string {
	switch phase.Status {
	case "pending":
		return lipgloss.NewStyle().Foreground(lipgloss.Color("#626262")).Render("○")
	case "running":
		return lipgloss.NewStyle().Foreground(lipgloss.Color("#FFAA00")).Render("◐")
	case "complete":
		return lipgloss.NewStyle().Foreground(lipgloss.Color("#00D4AA")).Render("●")
	case "error":
		return lipgloss.NewStyle().Foreground(lipgloss.Color("#FF5555")).Render("✗")
	default:
		return "?"
	}
}

func (m DeployModel) renderPhaseProgress(phase DeployPhase) string {
	width := 30
	filled := int(float64(width) * (float64(phase.Progress) / 100.0))
	
	bar := strings.Repeat("█", filled) + strings.Repeat("░", width-filled)
	
	return fmt.Sprintf("[%s] %d%%", bar, phase.Progress)
}

func (m DeployModel) renderOverallProgress() string {
	width := 50
	filled := int(float64(width) * (float64(m.progress) / 100.0))
	
	bar := strings.Repeat("█", filled) + strings.Repeat("░", width-filled)
	
	return fmt.Sprintf("Overall: [%s] %d%%", bar, m.progress)
}

func (m DeployModel) startDeployment() tea.Cmd {
	return func() tea.Msg {
		// Simulate deployment progress
		// In reality, this would call the actual deployment scripts
		
		// This is a placeholder - would need to implement actual deployment
		return StateTransitionMsg{To: "complete"}
	}
}