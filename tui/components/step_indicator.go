package components

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
)

// StepIndicator represents a visual progress indicator for multi-step processes
type StepIndicator struct {
	steps       []string
	currentStep int
	width       int
}

// StepIndicatorStyles defines the styling for step indicators
var stepIndicatorStyles = struct {
	Completed    lipgloss.Style
	Current      lipgloss.Style
	Pending      lipgloss.Style
	Connector    lipgloss.Style
	Container    lipgloss.Style
	StepNumber   lipgloss.Style
	StepText     lipgloss.Style
}{
	Completed: lipgloss.NewStyle().
		Foreground(colors.ZtcGreen).
		Bold(true),

	Current: lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Background(lipgloss.Color("#2A2A2A")),

	Pending: lipgloss.NewStyle().
		Foreground(colors.ZtcMutedGray),

	Connector: lipgloss.NewStyle().
		Foreground(colors.ZtcLightGray),

	Container: lipgloss.NewStyle().
		Padding(0, 1).
		Margin(1, 0),

	StepNumber: lipgloss.NewStyle().
		Width(3).
		Align(lipgloss.Center),

	StepText: lipgloss.NewStyle().
		PaddingLeft(1),
}

// NewStepIndicator creates a new step indicator
func NewStepIndicator(steps []string, currentStep int) *StepIndicator {
	return &StepIndicator{
		steps:       steps,
		currentStep: currentStep,
		width:       80,
	}
}

// SetCurrentStep updates the current step
func (s *StepIndicator) SetCurrentStep(step int) {
	if step >= 0 && step < len(s.steps) {
		s.currentStep = step
	}
}

// GetCurrentStep returns the current step index
func (s *StepIndicator) GetCurrentStep() int {
	return s.currentStep
}

// SetSteps updates the steps list
func (s *StepIndicator) SetSteps(steps []string) {
	s.steps = steps
	// Ensure current step is valid
	if s.currentStep >= len(steps) {
		s.currentStep = len(steps) - 1
	}
	if s.currentStep < 0 {
		s.currentStep = 0
	}
}

// View renders the step indicator
func (s *StepIndicator) View() string {
	if len(s.steps) == 0 {
		return ""
	}

	var parts []string

	for i, step := range s.steps {
		var style lipgloss.Style
		var indicator string

		// Determine style and indicator based on step state
		if i < s.currentStep {
			// Completed step
			style = stepIndicatorStyles.Completed
			indicator = "●"
		} else if i == s.currentStep {
			// Current step
			style = stepIndicatorStyles.Current
			indicator = "◐"
		} else {
			// Pending step
			style = stepIndicatorStyles.Pending
			indicator = "○"
		}

		// Format step number and text
		stepNumber := stepIndicatorStyles.StepNumber.Render(fmt.Sprintf("%s", indicator))
		stepText := stepIndicatorStyles.StepText.Render(step)
		
		// Combine indicator and text with appropriate styling
		stepDisplay := style.Render(stepNumber + stepText)
		parts = append(parts, stepDisplay)
	}

	return stepIndicatorStyles.Container.Render(strings.Join(parts, "  "))
}

// Compact renders a compact version showing only current step
func (s *StepIndicator) Compact() string {
	if len(s.steps) == 0 {
		return ""
	}

	if s.currentStep < 0 || s.currentStep >= len(s.steps) {
		return ""
	}

	currentStepName := s.steps[s.currentStep]
	progress := fmt.Sprintf("Step %d/%d", s.currentStep+1, len(s.steps))
	
	progressStyle := stepIndicatorStyles.Pending.Render(progress)
	stepStyle := stepIndicatorStyles.Current.Render(currentStepName)
	
	return fmt.Sprintf("%s • %s", progressStyle, stepStyle)
}

// Progress returns the completion percentage (0-100)
func (s *StepIndicator) Progress() float64 {
	if len(s.steps) == 0 {
		return 0
	}
	return float64(s.currentStep) / float64(len(s.steps)) * 100
}

// IsComplete returns whether all steps are completed
func (s *StepIndicator) IsComplete() bool {
	return s.currentStep >= len(s.steps)-1
}

// Next advances to the next step if possible
func (s *StepIndicator) Next() bool {
	if s.currentStep < len(s.steps)-1 {
		s.currentStep++
		return true
	}
	return false
}

// Previous goes back to the previous step if possible
func (s *StepIndicator) Previous() bool {
	if s.currentStep > 0 {
		s.currentStep--
		return true
	}
	return false
}

// GetSteps returns a copy of the steps slice
func (s *StepIndicator) GetSteps() []string {
	steps := make([]string, len(s.steps))
	copy(steps, s.steps)
	return steps
}