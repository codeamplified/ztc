package utils

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// ConfigurationMode represents the configuration complexity level
type ConfigurationMode int

const (
	ConfigModeSimple ConfigurationMode = iota
	ConfigModeAdvanced
)

// String returns the string representation of the configuration mode
func (m ConfigurationMode) String() string {
	switch m {
	case ConfigModeSimple:
		return "Simple"
	case ConfigModeAdvanced:
		return "Advanced"
	default:
		return "Unknown"
	}
}

// Session represents the persistent state of the TUI wizard
type Session struct {
	ID               string            `yaml:"id"`
	StartedAt        time.Time         `yaml:"started_at"`
	CurrentPhase     string            `yaml:"current_phase"`
	CompletedSteps   []string          `yaml:"completed_steps"`
	ClusterConfig    string            `yaml:"cluster_config"`
	ConfigMode       ConfigurationMode `yaml:"config_mode"`
	USBDevices       []USBDevice       `yaml:"usb_devices"`
	DeploymentLog    string            `yaml:"deployment_log"`
	Progress         map[string]int    `yaml:"progress"`
	Metadata         map[string]string `yaml:"metadata"`
}

// USBDevice represents a USB device used for node installation
type USBDevice struct {
	Device    string    `yaml:"device"`
	Hostname  string    `yaml:"hostname"`
	IP        string    `yaml:"ip"`
	Created   bool      `yaml:"created"`
	Verified  bool      `yaml:"verified"`
	CreatedAt time.Time `yaml:"created_at"`
}

// ClusterConfig represents the cluster configuration
type ClusterConfig struct {
	Cluster    ClusterMetadata  `yaml:"cluster" json:"cluster"`
	Network    NetworkConfig    `yaml:"network" json:"network"`
	Nodes      NodesConfig      `yaml:"nodes" json:"nodes"`
	Storage    StorageConfig    `yaml:"storage" json:"storage"`
	Components ComponentsConfig `yaml:"components" json:"components"`
	Workloads  WorkloadsConfig  `yaml:"workloads" json:"workloads"`
	Deployment DeploymentConfig `yaml:"deployment,omitempty" json:"deployment,omitempty"`
	Advanced   AdvancedConfig   `yaml:"advanced,omitempty" json:"advanced,omitempty"`
}

// ClusterMetadata represents the cluster metadata section
type ClusterMetadata struct {
	Name        string    `yaml:"name" json:"name"`
	Description string    `yaml:"description" json:"description"`
	Version     string    `yaml:"version" json:"version"`
	HAConfig    *HAConfig `yaml:"ha_config,omitempty" json:"ha_config,omitempty"`
}

// HAConfig represents high availability configuration
type HAConfig struct {
	Enabled      bool          `yaml:"enabled" json:"enabled"`
	VirtualIP    string        `yaml:"virtual_ip,omitempty" json:"virtual_ip,omitempty"`
	LoadBalancer *LoadBalancer `yaml:"load_balancer,omitempty" json:"load_balancer,omitempty"`
	EtcdConfig   *EtcdConfig   `yaml:"etcd_config,omitempty" json:"etcd_config,omitempty"`
}

// EtcdConfig represents embedded etcd configuration for HA
type EtcdConfig struct {
	SnapshotCount     int    `yaml:"snapshot_count,omitempty" json:"snapshot_count,omitempty"`
	HeartbeatInterval string `yaml:"heartbeat_interval,omitempty" json:"heartbeat_interval,omitempty"`
}

// LoadBalancer represents load balancer configuration
type LoadBalancer struct {
	Type string `yaml:"type" json:"type"`
	Port int    `yaml:"port,omitempty" json:"port,omitempty"`
}

type NetworkConfig struct {
	Subnet      string    `yaml:"subnet" json:"subnet"`
	Gateway     string    `yaml:"gateway" json:"gateway"`
	PodCIDR     string    `yaml:"pod_cidr" json:"pod_cidr"`
	ServiceCIDR string    `yaml:"service_cidr" json:"service_cidr"`
	DNS         DNSConfig `yaml:"dns" json:"dns"`
}

type DNSConfig struct {
	Enabled   bool     `yaml:"enabled" json:"enabled"`
	ServerIP  string   `yaml:"server_ip" json:"server_ip"`
	Domain    string   `yaml:"domain" json:"domain"`
	Upstreams []string `yaml:"upstreams" json:"upstreams"`
}

type NodesConfig struct {
	SSH          SSHConfig              `yaml:"ssh" json:"ssh"`
	ClusterNodes map[string]ClusterNode `yaml:"cluster_nodes" json:"cluster_nodes"`
}

type SSHConfig struct {
	PublicKeyPath  string `yaml:"public_key_path" json:"public_key_path"`
	PrivateKeyPath string `yaml:"private_key_path" json:"private_key_path"`
	Username       string `yaml:"username" json:"username"`
}

type ClusterNode struct {
	IP        string        `yaml:"ip" json:"ip"`
	Role      string        `yaml:"role" json:"role"`
	Resources NodeResources `yaml:"resources,omitempty" json:"resources,omitempty"`
}

type NodeResources struct {
	CPU    string `yaml:"cpu" json:"cpu"`
	Memory string `yaml:"memory" json:"memory"`
}

type StorageConfig struct {
	DefaultStorageClass string          `yaml:"default_storage_class" json:"default_storage_class"`
	LocalPath           LocalPathConfig `yaml:"local_path" json:"local_path"`
	Longhorn            LonghornConfig  `yaml:"longhorn" json:"longhorn"`
	NFS                 NFSConfig       `yaml:"nfs" json:"nfs"`
}

type LocalPathConfig struct {
	Enabled bool `yaml:"enabled" json:"enabled"`
}

type LonghornConfig struct {
	Enabled      bool                 `yaml:"enabled" json:"enabled"`
	Namespace    string               `yaml:"namespace,omitempty" json:"namespace,omitempty"`
	ReplicaCount int                  `yaml:"replica_count,omitempty" json:"replica_count,omitempty"`
	StorageClass LonghornStorageClass `yaml:"storage_class,omitempty" json:"storage_class,omitempty"`
	Settings     LonghornSettings     `yaml:"settings,omitempty" json:"settings,omitempty"`
}

type LonghornStorageClass struct {
	Name          string `yaml:"name" json:"name"`
	ReclaimPolicy string `yaml:"reclaim_policy" json:"reclaim_policy"`
}

type LonghornSettings struct {
	BackupTarget    string `yaml:"backup_target,omitempty" json:"backup_target,omitempty"`
	DefaultDataPath string `yaml:"default_data_path,omitempty" json:"default_data_path,omitempty"`
}

type NFSConfig struct {
	Enabled             bool            `yaml:"enabled" json:"enabled"`
	Namespace           string          `yaml:"namespace,omitempty" json:"namespace,omitempty"`
	BackendStorageClass string          `yaml:"backend_storage_class,omitempty" json:"backend_storage_class,omitempty"`
	StorageSize         string          `yaml:"storage_size,omitempty" json:"storage_size,omitempty"`
	StorageClass        NFSStorageClass `yaml:"storage_class,omitempty" json:"storage_class,omitempty"`
}

type NFSStorageClass struct {
	Name string `yaml:"name" json:"name"`
}

type ComponentsConfig struct {
	SealedSecrets SealedSecretsConfig `yaml:"sealed_secrets" json:"sealed_secrets"`
	ArgoCD        ArgoCDConfig        `yaml:"argocd" json:"argocd"`
	Monitoring    MonitoringConfig    `yaml:"monitoring" json:"monitoring"`
	Gitea         GiteaConfig         `yaml:"gitea" json:"gitea"`
	MinIO         MinIOConfig         `yaml:"minio" json:"minio"`
	Homepage      HomepageConfig      `yaml:"homepage" json:"homepage"`
}

type SealedSecretsConfig struct {
	Enabled bool `yaml:"enabled" json:"enabled"`
}

type ArgoCDConfig struct {
	Enabled   bool   `yaml:"enabled" json:"enabled"`
	Namespace string `yaml:"namespace" json:"namespace"`
}

type MonitoringConfig struct {
	Enabled    bool                 `yaml:"enabled" json:"enabled"`
	Namespace  string               `yaml:"namespace" json:"namespace"`
	Components MonitoringComponents `yaml:"components,omitempty" json:"components,omitempty"`
	Resources  MonitoringResources  `yaml:"resources,omitempty" json:"resources,omitempty"`
}

type MonitoringComponents struct {
	Prometheus   bool `yaml:"prometheus" json:"prometheus"`
	Grafana      bool `yaml:"grafana" json:"grafana"`
	AlertManager bool `yaml:"alertmanager" json:"alertmanager"`
}

type MonitoringResources struct {
	Prometheus PrometheusResources `yaml:"prometheus,omitempty" json:"prometheus,omitempty"`
	Grafana    GrafanaResources    `yaml:"grafana,omitempty" json:"grafana,omitempty"`
}

type PrometheusResources struct {
	MemoryLimit string `yaml:"memory_limit" json:"memory_limit"`
	StorageSize string `yaml:"storage_size" json:"storage_size"`
}

type GrafanaResources struct {
	MemoryLimit string `yaml:"memory_limit" json:"memory_limit"`
}

type GiteaConfig struct {
	Enabled   bool           `yaml:"enabled" json:"enabled"`
	Namespace string         `yaml:"namespace" json:"namespace"`
	Features  GiteaFeatures  `yaml:"features,omitempty" json:"features,omitempty"`
	Resources GiteaResources `yaml:"resources,omitempty" json:"resources,omitempty"`
}

type GiteaFeatures struct {
	ContainerRegistry bool `yaml:"container_registry" json:"container_registry"`
	ActionsRunner     bool `yaml:"actions_runner" json:"actions_runner"`
}

type GiteaResources struct {
	MemoryLimit string `yaml:"memory_limit" json:"memory_limit"`
	StorageSize string `yaml:"storage_size" json:"storage_size"`
}

type MinIOConfig struct {
	Enabled      bool             `yaml:"enabled" json:"enabled"`
	Namespace    string           `yaml:"namespace,omitempty" json:"namespace,omitempty"`
	StorageClass string           `yaml:"storage_class,omitempty" json:"storage_class,omitempty"`
	Replicas     int              `yaml:"replicas,omitempty" json:"replicas,omitempty"`
	StorageSize  string           `yaml:"storage_size,omitempty" json:"storage_size,omitempty"`
	Console      MinIOConsole     `yaml:"console,omitempty" json:"console,omitempty"`
	API          MinIOAPI         `yaml:"api,omitempty" json:"api,omitempty"`
	Credentials  MinIOCredentials `yaml:"credentials,omitempty" json:"credentials,omitempty"`
	Resources    MinIOResources   `yaml:"resources,omitempty" json:"resources,omitempty"`
}

type MinIOConsole struct {
	Enabled  bool   `yaml:"enabled" json:"enabled"`
	Hostname string `yaml:"hostname,omitempty" json:"hostname,omitempty"`
}

type MinIOAPI struct {
	Hostname string `yaml:"hostname,omitempty" json:"hostname,omitempty"`
}

type MinIOCredentials struct {
	AccessKey string `yaml:"access_key,omitempty" json:"access_key,omitempty"`
	SecretKey string `yaml:"secret_key,omitempty" json:"secret_key,omitempty"`
}

type MinIOResources struct {
	MemoryLimit string `yaml:"memory_limit" json:"memory_limit"`
	CPULimit    string `yaml:"cpu_limit" json:"cpu_limit"`
}

type HomepageConfig struct {
	Enabled   bool             `yaml:"enabled" json:"enabled"`
	Namespace string           `yaml:"namespace" json:"namespace"`
	Features  HomepageFeatures `yaml:"features,omitempty" json:"features,omitempty"`
}

type HomepageFeatures struct {
	ServiceDiscovery bool `yaml:"service_discovery" json:"service_discovery"`
	ClusterMetrics   bool `yaml:"cluster_metrics" json:"cluster_metrics"`
}

type WorkloadsConfig struct {
	AutoDeployBundles []string          `yaml:"auto_deploy_bundles" json:"auto_deploy_bundles"`
	Templates         WorkloadTemplates `yaml:"templates,omitempty" json:"templates,omitempty"`
}

type WorkloadTemplates struct {
	DefaultStorageClass string `yaml:"default_storage_class" json:"default_storage_class"`
	DefaultMemoryLimit  string `yaml:"default_memory_limit" json:"default_memory_limit"`
	DefaultCPULimit     string `yaml:"default_cpu_limit" json:"default_cpu_limit"`
}

type DeploymentConfig struct {
	Phases  DeploymentPhases  `yaml:"phases,omitempty" json:"phases,omitempty"`
	Options DeploymentOptions `yaml:"options,omitempty" json:"options,omitempty"`
}

type DeploymentPhases struct {
	Infrastructure   bool `yaml:"infrastructure" json:"infrastructure"`
	Secrets          bool `yaml:"secrets" json:"secrets"`
	Networking       bool `yaml:"networking" json:"networking"`
	Storage          bool `yaml:"storage" json:"storage"`
	SystemComponents bool `yaml:"system_components" json:"system_components"`
	GitOps           bool `yaml:"gitops" json:"gitops"`
	Workloads        bool `yaml:"workloads" json:"workloads"`
}

type DeploymentOptions struct {
	WaitForReady    bool `yaml:"wait_for_ready" json:"wait_for_ready"`
	TimeoutMinutes  int  `yaml:"timeout_minutes" json:"timeout_minutes"`
	RetryFailed     bool `yaml:"retry_failed" json:"retry_failed"`
	BackupOnSuccess bool `yaml:"backup_on_success" json:"backup_on_success"`
}

type AdvancedConfig struct {
	Ansible    AnsibleConfig    `yaml:"ansible,omitempty" json:"ansible,omitempty"`
	Kubernetes KubernetesConfig `yaml:"kubernetes,omitempty" json:"kubernetes,omitempty"`
	Security   SecurityConfig   `yaml:"security,omitempty" json:"security,omitempty"`
	Backup     BackupConfig     `yaml:"backup,omitempty" json:"backup,omitempty"`
}

type AnsibleConfig struct {
	InventoryPath     string `yaml:"inventory_path" json:"inventory_path"`
	VaultPasswordFile string `yaml:"vault_password_file" json:"vault_password_file"`
}

type KubernetesConfig struct {
	Version          string `yaml:"version" json:"version"`
	ContainerRuntime string `yaml:"container_runtime" json:"container_runtime"`
}

type SecurityConfig struct {
	AutoGeneratePasswords bool `yaml:"auto_generate_passwords" json:"auto_generate_passwords"`
	PasswordLength        int  `yaml:"password_length" json:"password_length"`
	EnableRBAC            bool `yaml:"enable_rbac" json:"enable_rbac"`
}

type BackupConfig struct {
	AutoBackupSecrets bool   `yaml:"auto_backup_secrets" json:"auto_backup_secrets"`
	BackupLocation    string `yaml:"backup_location" json:"backup_location"`
	RetentionDays     int    `yaml:"retention_days" json:"retention_days"`
}

const sessionFile = ".ztc-session.yaml"

// NewSession creates a new session with default values
func NewSession() *Session {
	return &Session{
		ID:             generateSessionID(),
		StartedAt:      time.Now(),
		CurrentPhase:   "welcome",
		CompletedSteps: []string{},
		ClusterConfig:  "cluster.yaml",
		ConfigMode:     ConfigModeSimple, // Default to simple mode
		USBDevices:     []USBDevice{},
		DeploymentLog:  "",
		Progress:       make(map[string]int),
		Metadata:       make(map[string]string),
	}
}

// LoadSession loads session from file or creates a new one
func LoadSession() (*Session, error) {
	if _, err := os.Stat(sessionFile); os.IsNotExist(err) {
		return NewSession(), nil
	}

	data, err := os.ReadFile(sessionFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read session file: %w", err)
	}

	var session Session
	if err := yaml.Unmarshal(data, &session); err != nil {
		return nil, fmt.Errorf("failed to unmarshal session: %w", err)
	}

	return &session, nil
}

// Save saves the session to file
func (s *Session) Save() error {
	data, err := yaml.Marshal(s)
	if err != nil {
		return fmt.Errorf("failed to marshal session: %w", err)
	}

	if err := os.WriteFile(sessionFile, data, 0644); err != nil {
		return fmt.Errorf("failed to write session file: %w", err)
	}

	return nil
}

// SetPhase sets the current phase and saves the session
func (s *Session) SetPhase(phase string) error {
	s.CurrentPhase = phase
	return s.Save()
}

// AddCompletedStep adds a step to the completed steps
func (s *Session) AddCompletedStep(step string) error {
	for _, existing := range s.CompletedSteps {
		if existing == step {
			return nil // Already completed
		}
	}
	s.CompletedSteps = append(s.CompletedSteps, step)
	return s.Save()
}

// IsStepCompleted checks if a step is completed
func (s *Session) IsStepCompleted(step string) bool {
	for _, completed := range s.CompletedSteps {
		if completed == step {
			return true
		}
	}
	return false
}

// AddUSBDevice adds a USB device to the session
func (s *Session) AddUSBDevice(device USBDevice) error {
	s.USBDevices = append(s.USBDevices, device)
	return s.Save()
}

// SetProgress sets progress for a specific task
func (s *Session) SetProgress(task string, progress int) error {
	s.Progress[task] = progress
	return s.Save()
}

// GetProgress gets progress for a specific task
func (s *Session) GetProgress(task string) int {
	return s.Progress[task]
}

// SetMetadata sets metadata key-value pair
func (s *Session) SetMetadata(key, value string) error {
	s.Metadata[key] = value
	return s.Save()
}

// GetMetadata gets metadata value by key
func (s *Session) GetMetadata(key string) string {
	return s.Metadata[key]
}

// LoadClusterConfig loads the cluster configuration from file
func (s *Session) LoadClusterConfig() (*ClusterConfig, error) {
	if _, err := os.Stat(s.ClusterConfig); os.IsNotExist(err) {
		return nil, fmt.Errorf("cluster config file not found: %s", s.ClusterConfig)
	}

	data, err := os.ReadFile(s.ClusterConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to read cluster config: %w", err)
	}

	var config ClusterConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to unmarshal cluster config: %w", err)
	}

	// Validate configuration against schema
	if validationResult, err := GetValidator().ValidateClusterConfig(&config); err != nil {
		return nil, fmt.Errorf("failed to validate cluster config: %w", err)
	} else if !validationResult.Valid {
		return nil, fmt.Errorf("cluster config validation failed:\n%s", validationResult.FormatErrors())
	}

	return &config, nil
}

// SaveClusterConfig saves the cluster configuration to file
func (s *Session) SaveClusterConfig(config *ClusterConfig) error {
	data, err := yaml.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to marshal cluster config: %w", err)
	}

	// Add YAML schema header
	header := "# yaml-language-server: $schema=./schema/cluster-schema.json\n"
	header += "# Zero Touch Cluster Configuration\n"
	header += fmt.Sprintf("# Generated by TUI wizard on %s\n\n", time.Now().Format(time.RFC3339))

	content := header + string(data)

	if err := os.WriteFile(s.ClusterConfig, []byte(content), 0644); err != nil {
		return fmt.Errorf("failed to write cluster config: %w", err)
	}

	return nil
}

// Clean removes the session file
func (s *Session) Clean() error {
	if err := os.Remove(sessionFile); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to remove session file: %w", err)
	}
	return nil
}

// generateSessionID generates a simple session ID
func generateSessionID() string {
	return fmt.Sprintf("ztc-%d", time.Now().Unix())
}

// GetWorkspaceDir returns the workspace directory
func GetWorkspaceDir() string {
	if wd := os.Getenv("ZTC_WORKSPACE"); wd != "" {
		return wd
	}
	wd, _ := os.Getwd()
	return wd
}

// GetLogFile returns the path to the deployment log file
func GetLogFile() string {
	return filepath.Join(GetWorkspaceDir(), ".ztc-deployment.log")
}

// GetStatusFile returns the path to the deployment status file
func GetStatusFile() string {
	return filepath.Join(GetWorkspaceDir(), ".ztc-status.json")
}

// Mission types removed - TUI is now template-agnostic

// Template represents a cluster template with metadata
type Template struct {
	Name        string         `yaml:"name"`
	Description string         `yaml:"description"`
	NodeCount   string         `yaml:"node_count"`
	HardwareReq string         `yaml:"hardware_req"`
	Bundles     []string       `yaml:"bundles"`
	Config      *ClusterConfig `yaml:"config"`
}

// LoadClusterTemplate loads a cluster template based on template ID
func LoadClusterTemplate(templateID string) (*ClusterConfig, error) {
	templatePath := filepath.Join(GetWorkspaceDir(), "templates", fmt.Sprintf("cluster-%s.yaml", templateID))

	// Check if template file exists
	if _, err := os.Stat(templatePath); os.IsNotExist(err) {
		return nil, fmt.Errorf("template not found for ID %s: %s", templateID, templatePath)
	}

	// Read template file
	data, err := os.ReadFile(templatePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read template file: %w", err)
	}

	// Parse YAML
	var config ClusterConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse template YAML: %w", err)
	}

	return &config, nil
}

// LoadClusterTemplateByMission removed - use LoadClusterTemplate directly

// ValidateTemplate is now implemented in validation.go using JSON schema validation

// GetAvailableBundles returns all available workload bundles (template-agnostic)
func GetAvailableBundles() []Bundle {
	return []Bundle{
		{
			ID:          "starter",
			Name:        "Starter Bundle",
			Description: "Essential homelab services: Homepage dashboard + Uptime Kuma monitoring",
			Services:    []string{"homepage", "uptime-kuma"},
			Resources:   "192Mi RAM, 2Gi storage",
			Recommended: true,
		},
		{
			ID:          "monitoring",
			Name:        "Monitoring Bundle",
			Description: "Complete monitoring solution",
			Services:    []string{"uptime-kuma", "homepage"},
			Resources:   "192Mi RAM, 3Gi storage",
			Recommended: false,
		},
		{
			ID:          "productivity",
			Name:        "Productivity Bundle",
			Description: "Development and automation toolkit",
			Services:    []string{"code-server", "n8n"},
			Resources:   "1Gi RAM, 15Gi storage",
			Recommended: false,
		},
		{
			ID:          "security",
			Name:        "Security Bundle",
			Description: "Professional password management",
			Services:    []string{"vaultwarden"},
			Resources:   "128Mi RAM, 5Gi storage",
			Recommended: false,
		},
	}
}

// Bundle represents a workload bundle
type Bundle struct {
	ID          string   `yaml:"id" json:"id"`
	Name        string   `yaml:"name" json:"name"`
	Description string   `yaml:"description" json:"description"`
	Services    []string `yaml:"services" json:"services"`
	Resources   string   `yaml:"resources" json:"resources"`
	Recommended bool     `yaml:"recommended" json:"recommended"`
}

// GetTemplateMetadata removed - metadata is now generated from template data

// TemplateMetadata provides information about a template (generated from template data)
type TemplateMetadata struct {
	Name         string   `yaml:"name" json:"name"`
	Description  string   `yaml:"description" json:"description"`
	NodeCount    string   `yaml:"node_count" json:"node_count"`
	HardwareReq  string   `yaml:"hardware_req" json:"hardware_req"`
	Architecture string   `yaml:"architecture" json:"architecture"`
	StorageTypes []string `yaml:"storage_types" json:"storage_types"`
	UseCases     []string `yaml:"use_cases" json:"use_cases"`
	TradeOffs    []string `yaml:"trade_offs" json:"trade_offs"`
}

// TemplateInfo represents a discovered template file with metadata
type TemplateInfo struct {
	Name        string `yaml:"name" json:"name"`
	Description string `yaml:"description" json:"description"`
	ID          string `yaml:"id" json:"id"`
	FilePath    string `yaml:"file_path" json:"file_path"`
	IsFeatured  bool   `yaml:"is_featured" json:"is_featured"`
}

// LoadAvailableTemplates discovers all cluster template files
func LoadAvailableTemplates() ([]TemplateInfo, error) {
	templatesDir := filepath.Join(GetWorkspaceDir(), "templates")

	// Check if templates directory exists
	if _, err := os.Stat(templatesDir); os.IsNotExist(err) {
		return nil, fmt.Errorf("templates directory not found: %s", templatesDir)
	}

	// Read directory contents
	entries, err := os.ReadDir(templatesDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read templates directory: %w", err)
	}

	var templates []TemplateInfo

	// Scan for cluster-*.yaml files
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		name := entry.Name()
		if !strings.HasPrefix(name, "cluster-") || !strings.HasSuffix(name, ".yaml") {
			continue
		}

		filePath := filepath.Join(templatesDir, name)

		// Extract template ID from filename
		baseName := strings.TrimSuffix(name, ".yaml")
		id := strings.TrimPrefix(baseName, "cluster-")

		// Determine if this is a featured template
		// For now, consider templates with good descriptions as featured
		// In the future, this could come from template metadata
		isFeatured := false

		// Read the template file to extract metadata
		data, err := os.ReadFile(filePath)
		if err != nil {
			// Log warning but continue with other templates
			continue
		}

		// Try to parse as ClusterConfig to get name and description
		var config ClusterConfig
		templateName := strings.Title(strings.ReplaceAll(id, "-", " "))
		templateDesc := fmt.Sprintf("Cluster template: %s", templateName)

		if err := yaml.Unmarshal(data, &config); err == nil {
			if config.Cluster.Name != "" {
				templateName = config.Cluster.Name
			}
			if config.Cluster.Description != "" {
				templateDesc = config.Cluster.Description
			}

			// Determine featured status based on template quality/completeness
			// A featured template should have:
			// - A clear name and description
			// - At least one node configured
			// - Storage configuration
			// - Components configured
			if config.Cluster.Name != "" &&
				config.Cluster.Description != "" &&
				len(config.Nodes.ClusterNodes) > 0 &&
				config.Storage.DefaultStorageClass != "" &&
				(config.Components.ArgoCD.Enabled || config.Components.Monitoring.Enabled) {
				isFeatured = true
			}
		}

		templates = append(templates, TemplateInfo{
			Name:        templateName,
			Description: templateDesc,
			ID:          id,
			FilePath:    filePath,
			IsFeatured:  isFeatured,
		})
	}

	return templates, nil
}

// GetNodeList extracts node information from cluster config for USB creation
func GetNodeList(config *ClusterConfig) []NodeInfo {
	var nodes []NodeInfo

	// Add cluster nodes
	for hostname, node := range config.Nodes.ClusterNodes {
		nodes = append(nodes, NodeInfo{
			Hostname: hostname,
			IP:       node.IP,
			Role:     node.Role,
			Type:     "cluster",
		})
	}

	return nodes
}

// NodeInfo represents node information for USB creation
type NodeInfo struct {
	Hostname string `yaml:"hostname" json:"hostname"`
	IP       string `yaml:"ip" json:"ip"`
	Role     string `yaml:"role" json:"role"`
	Type     string `yaml:"type" json:"type"` // "cluster" or "storage"
}
