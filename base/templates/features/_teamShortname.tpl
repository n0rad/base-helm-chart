{{- define "base.features.teamShortname" -}}

{{- if not .Values.teamShortname -}}
  {{- fail ".teamShortname value is mandatory" -}}
{{- end -}}

global:
  labels:
    team: {{ .Values.teamShortname }}
{{- end -}}
