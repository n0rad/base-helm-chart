{{/*
Basic VolumeClaimTemplate template
*/}}
{{- define "base.resources.statefulSets.volumeClaimTemplate" -}}
  {{- $rootContext := .rootContext -}}
  {{- $values := .values -}}

metadata:
  name: {{ $values.name }}
  {{- with ($values.labels | default dict) }}
  labels: {{- toYaml . | nindent 10 }}
  {{- end }}
  {{- with ($values.annotations | default dict) }}
  annotations: {{- toYaml . | nindent 10 }}
  {{- end }}
spec:
  accessModes:
    - {{ $values.accessMode  | quote }}
  resources:
    requests:
      storage: {{ $values.size | quote }}
  {{- if $values.storageClass }}
  storageClassName: {{ if (eq "-" $values.storageClass) }}""{{- else }}{{ $values.storageClass | quote }}{{- end }}
  {{- end }}
  {{- with $values.dataSource }}
  dataSource: {{- tpl (toYaml .) $rootContext | nindent 10 }}
  {{- end }}
  {{- with $values.dataSourceRef }}
  dataSourceRef: {{- tpl (toYaml .) $rootContext | nindent 10 }}
  {{- end }}
{{- end -}}

{{/*
VolumeClaimTemplates for StatefulSet
*/}}
{{- define "base.lib.statefulset.volumeclaimtemplates" -}}
  {{- $rootContext := .rootContext -}}
  {{- $statefulSetObject := .statefulSetObject -}}

  {{- /* Default to empty list */ -}}
  {{- $volumeClaimTemplates := list -}}

  {{- range $index, $volumeClaimTemplate := (dig "statefulSet" "volumeClaimTemplates" list $statefulSetObject) }}
    {{- $vct := include "base.resources.statefulSets.volumeClaimTemplate" (dict "rootContext" $rootContext "values" $volumeClaimTemplate) -}}
    {{- $volumeClaimTemplates = append $volumeClaimTemplates ($vct | fromYaml) -}}
  {{- end -}}

  {{- if not (empty $volumeClaimTemplates) -}}
    {{ $volumeClaimTemplates | toYaml }}
  {{- end -}}
{{- end -}}
