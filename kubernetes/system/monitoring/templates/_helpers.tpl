{{/*
Homelab Monitoring Chart Helpers
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "homelab-monitoring.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "homelab-monitoring.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "homelab-monitoring.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "homelab-monitoring.labels" -}}
helm.sh/chart: {{ include "homelab-monitoring.chart" . }}
{{ include "homelab-monitoring.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "homelab-monitoring.selectorLabels" -}}
app.kubernetes.io/name: {{ include "homelab-monitoring.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Determine storage class to use
Priority: 
1. Explicit storageClassName in component config
2. Global storageClass value
3. Default to empty string (uses cluster default)
*/}}
{{- define "homelab-monitoring.storageClass" -}}
{{- if .storageClassName }}
{{- .storageClassName }}
{{- else if .Values.global.storageClass }}
{{- .Values.global.storageClass }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}