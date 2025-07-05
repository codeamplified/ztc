{{/*
Expand the name of the chart.
*/}}
{{- define "ztc-vaultwarden.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ztc-vaultwarden.fullname" -}}
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
{{- define "ztc-vaultwarden.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ztc-vaultwarden.labels" -}}
helm.sh/chart: {{ include "ztc-vaultwarden.chart" . }}
{{ include "ztc-vaultwarden.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ztc
app.kubernetes.io/component: credential-manager
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ztc-vaultwarden.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ztc-vaultwarden.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ztc-vaultwarden.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ztc-vaultwarden.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the namespace name
*/}}
{{- define "ztc-vaultwarden.namespace" -}}
{{- default .Values.global.namespace "vaultwarden" }}
{{- end }}

{{/*
Get the domain name
*/}}
{{- define "ztc-vaultwarden.domain" -}}
{{- default .Values.global.domain "vault.homelab.lan" }}
{{- end }}