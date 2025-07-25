package config_steps

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
	"ztc-tui/components"
	"ztc-tui/utils"
	"ztc-tui/validation"
)

// SSHModel handles SSH configuration
type SSHModel struct {
	BaseStepModel
	
	// SSH configuration components
	sshPublicKeyInput  *components.InputField
	sshPrivateKeyInput *components.InputField
	sshUsernameInput   *components.InputField
	
	// UI state
	focusedField int
	fields       []string
}

// NewSSHModel creates a new SSH configuration model
func NewSSHModel() *SSHModel {
	return &SSHModel{
		BaseStepModel: BaseStepModel{
			Width:  80,
			Height: 24,
		},
		fields: []string{
			"sshPublicKey",
			"sshPrivateKey",
			"sshUsername",
		},
	}
}

// Init initializes the SSH model
func (m SSHModel) Init() tea.Cmd {
	return nil
}

// InitWithConfig initializes the model with shared configuration
func (m *SSHModel) InitWithConfig(session *utils.Session, template *utils.ClusterConfig) tea.Cmd {
	m.session = session
	m.template = template
	
	if template == nil {
		return nil
	}
	
	// Initialize SSH input fields with template values
	m.sshPublicKeyInput = components.NewInputField("SSH Public Key Path", "~/.ssh/id_ed25519.pub", 50)
	m.sshPublicKeyInput.SetValue(template.Nodes.SSH.PublicKeyPath)
	m.sshPublicKeyInput.Validate = validation.ValidateSSHPublicKeyPath
	
	m.sshPrivateKeyInput = components.NewInputField("SSH Private Key Path", "~/.ssh/id_ed25519", 50)
	m.sshPrivateKeyInput.SetValue(template.Nodes.SSH.PrivateKeyPath)
	m.sshPrivateKeyInput.Validate = validation.ValidateSSHPrivateKeyPath
	
	m.sshUsernameInput = components.NewInputField("SSH Username", "ubuntu", 30)
	m.sshUsernameInput.SetValue(template.Nodes.SSH.Username)
	m.sshUsernameInput.Validate = validation.ValidateSSHUsername
	
	// Set initial focus
	m.setFocus()
	
	return nil
}

// Update handles messages and user input
func (m SSHModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	var cmds []tea.Cmd
	
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "tab", "down", "j":
			m.nextField()
		case "shift+tab", "up", "k":
			m.prevField()
		default:
			// Pass to focused component
			cmd = m.updateFocusedField(msg)
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		}
	}
	
	return m, tea.Batch(cmds...)
}

// View renders the SSH configuration interface
func (m SSHModel) View() string {
	var content strings.Builder
	
	// Step title
	title := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Render("SSH Configuration")
	content.WriteString(title + "\n\n")
	
	content.WriteString("Configure SSH access for cluster nodes:\n\n")
	
	// SSH fields
	if m.sshPublicKeyInput != nil {
		content.WriteString(m.sshPublicKeyInput.View() + "\n\n")
	}
	if m.sshPrivateKeyInput != nil {
		content.WriteString(m.sshPrivateKeyInput.View() + "\n\n")
	}
	if m.sshUsernameInput != nil {
		content.WriteString(m.sshUsernameInput.View() + "\n")
	}
	
	// Help text
	helpStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcMutedGray).
		Italic(true)
	
	content.WriteString("\n\n")
	content.WriteString(helpStyle.Render("💡 Tip: SSH keys will be used for secure access to cluster nodes.\n"))
	content.WriteString(helpStyle.Render("   Make sure the public key is deployed to all nodes."))
	
	return content.String()
}

// Validate checks if all SSH configuration is valid
func (m SSHModel) Validate() error {
	// Validate all fields
	if m.sshPublicKeyInput != nil && !m.sshPublicKeyInput.ValidateInput() {
		return fmt.Errorf("SSH public key validation failed")
	}
	if m.sshPrivateKeyInput != nil && !m.sshPrivateKeyInput.ValidateInput() {
		return fmt.Errorf("SSH private key validation failed")
	}
	if m.sshUsernameInput != nil && !m.sshUsernameInput.ValidateInput() {
		return fmt.Errorf("SSH username validation failed")
	}
	
	return nil
}

// ApplyToTemplate applies the SSH configuration to the template
func (m SSHModel) ApplyToTemplate(template *utils.ClusterConfig) error {
	if template == nil {
		return nil
	}
	
	// Apply SSH configuration
	if m.sshPublicKeyInput != nil {
		template.Nodes.SSH.PublicKeyPath = m.sshPublicKeyInput.GetValue()
	}
	if m.sshPrivateKeyInput != nil {
		template.Nodes.SSH.PrivateKeyPath = m.sshPrivateKeyInput.GetValue()
	}
	if m.sshUsernameInput != nil {
		template.Nodes.SSH.Username = m.sshUsernameInput.GetValue()
	}
	
	return nil
}

// GetStepName returns the display name for this step
func (m SSHModel) GetStepName() string {
	return "SSH Setup"
}

// ShouldShow returns true if this step should be shown in the given mode
func (m SSHModel) ShouldShow(mode utils.ConfigurationMode) bool {
	return true // SSH configuration is always shown
}

// Helper methods for focus management
func (m *SSHModel) setFocus() {
	m.clearAllFocus()
	
	if len(m.fields) > 0 && m.focusedField < len(m.fields) {
		m.focusField(m.fields[m.focusedField])
	}
}

func (m *SSHModel) clearAllFocus() {
	if m.sshPublicKeyInput != nil {
		m.sshPublicKeyInput.Blur()
	}
	if m.sshPrivateKeyInput != nil {
		m.sshPrivateKeyInput.Blur()
	}
	if m.sshUsernameInput != nil {
		m.sshUsernameInput.Blur()
	}
}

func (m *SSHModel) focusField(fieldName string) {
	switch fieldName {
	case "sshPublicKey":
		if m.sshPublicKeyInput != nil {
			m.sshPublicKeyInput.Focus()
		}
	case "sshPrivateKey":
		if m.sshPrivateKeyInput != nil {
			m.sshPrivateKeyInput.Focus()
		}
	case "sshUsername":
		if m.sshUsernameInput != nil {
			m.sshUsernameInput.Focus()
		}
	}
}

func (m *SSHModel) nextField() {
	if len(m.fields) > 0 && m.focusedField < len(m.fields)-1 {
		m.focusedField++
		m.setFocus()
	}
}

func (m *SSHModel) prevField() {
	if m.focusedField > 0 {
		m.focusedField--
		m.setFocus()
	}
}

func (m *SSHModel) updateFocusedField(msg tea.Msg) tea.Cmd {
	if len(m.fields) == 0 || m.focusedField >= len(m.fields) {
		return nil
	}
	
	fieldToUpdate := m.fields[m.focusedField]
	switch fieldToUpdate {
	case "sshPublicKey":
		if m.sshPublicKeyInput != nil {
			return m.sshPublicKeyInput.Update(msg)
		}
	case "sshPrivateKey":
		if m.sshPrivateKeyInput != nil {
			return m.sshPrivateKeyInput.Update(msg)
		}
	case "sshUsername":
		if m.sshUsernameInput != nil {
			return m.sshUsernameInput.Update(msg)
		}
	}
	return nil
}