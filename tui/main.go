package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/models"
	"ztc-tui/utils"
)

var (
	// ZTC Brand Colors
	primaryColor    = lipgloss.Color("#FFA500") // Orange - primary brand
	secondaryColor  = lipgloss.Color("#EAEAEA") // Light gray - secondary text
	accentColor     = lipgloss.Color("#FF6600") // Dark orange - accent
	backgroundColor = lipgloss.Color("#1A1A1A") // Dark gray - background
	textColor       = lipgloss.Color("#FFFFFF") // White - main text
	warningColor    = lipgloss.Color("#FFA500") // Orange for warnings
	errorColor      = lipgloss.Color("#FF6600") // Dark orange for errors

	// Styles
	titleStyle = lipgloss.NewStyle().
			Foreground(primaryColor).
			Bold(true).
			MarginLeft(2)

	subtitleStyle = lipgloss.NewStyle().
			Foreground(secondaryColor).
			MarginLeft(2)
)

type sessionState int

const (
	welcomeView sessionState = iota
	configView
	usbView
	deployView
	completeView
)

type model struct {
	state    sessionState
	welcome  models.WelcomeModel
	config   models.ConfigModel
	usb      models.USBModel
	deploy   models.DeployModel
	complete models.CompleteModel

	// Shared state
	session *utils.Session
	width   int
	height  int
}

func initialModel() model {
	session := utils.NewSession()

	return model{
		state:    welcomeView,
		welcome:  models.NewWelcomeModel(),
		config:   models.NewConfigModel(),
		usb:      models.NewUSBModel(),
		deploy:   models.NewDeployModel(),
		complete: models.NewCompleteModel(),
		session:  session,
		width:    0,
		height:   0,
	}
}

func (m model) Init() tea.Cmd {
	return m.welcome.Init()
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

		// Update all models with new dimensions
		m.welcome.Width = msg.Width
		m.welcome.Height = msg.Height
		m.config.Width = msg.Width
		m.config.Height = msg.Height
		m.usb.Width = msg.Width
		m.usb.Height = msg.Height
		m.deploy.Width = msg.Width
		m.deploy.Height = msg.Height
		m.complete.Width = msg.Width
		m.complete.Height = msg.Height

		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		}

	case models.StateTransitionMsg:
		switch msg.To {
		case "config":
			m.state = configView
			// Store the selected configuration mode in session
			m.session.ConfigMode = msg.ConfigMode
			// Pass the selected template ID to the config model
			cfgInit := models.ConfigInitMsg{
				Session:    m.session,
				TemplateID: msg.TemplateID,
			}
			m.config, cmd = m.config.Update(cfgInit)
			initCmd := m.config.Init()
			return m, tea.Batch(cmd, initCmd)

		case "usb":
			m.state = usbView
			m.usb, cmd = m.usb.Update(models.USBInitMsg{Session: m.session})
			initCmd := m.usb.Init()
			return m, tea.Batch(cmd, initCmd)

		case "deploy":
			m.state = deployView
			m.deploy, cmd = m.deploy.Update(models.DeployInitMsg{Session: m.session})
			initCmd := m.deploy.Init()
			return m, tea.Batch(cmd, initCmd)

		case "complete":
			m.state = completeView
			m.complete, cmd = m.complete.Update(models.CompleteInitMsg{Session: m.session})
			initCmd := m.complete.Init()
			return m, tea.Batch(cmd, initCmd)

		case "quit":
			return m, tea.Quit
		}
	}

	// Update current view
	switch m.state {
	case welcomeView:
		m.welcome, cmd = m.welcome.Update(msg)
		cmds = append(cmds, cmd)
	case configView:
		m.config, cmd = m.config.Update(msg)
		cmds = append(cmds, cmd)
	case usbView:
		m.usb, cmd = m.usb.Update(msg)
		cmds = append(cmds, cmd)
	case deployView:
		m.deploy, cmd = m.deploy.Update(msg)
		cmds = append(cmds, cmd)
	case completeView:
		m.complete, cmd = m.complete.Update(msg)
		cmds = append(cmds, cmd)
	}

	return m, tea.Batch(cmds...)
}

func (m model) View() string {
	switch m.state {
	case welcomeView:
		return m.welcome.View()
	case configView:
		return m.config.View()
	case usbView:
		return m.usb.View()
	case deployView:
		return m.deploy.View()
	case completeView:
		return m.complete.View()
	}

	return "Unknown state"
}

func main() {
	// Check if running in guided mode
	if os.Getenv("ZTC_GUIDED_MODE") != "true" {
		fmt.Println("This TUI application is designed to run within the ZTC guided setup.")
		fmt.Println("Please use: ./ztc")
		os.Exit(1)
	}

	// Create the program
	p := tea.NewProgram(
		initialModel(),
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)

	// Run the program
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running TUI: %v\n", err)
		os.Exit(1)
	}
}
