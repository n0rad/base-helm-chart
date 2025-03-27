{{- define "base.features.debug" -}}
  {{- $rootContext := .rootContext -}}
  {{- $chartName := .chartName -}}

{{- with $rootContext.Values.debug }}
resources:
  configMaps:
    debug-{{ $chartName }}:
      enabled: true
      noTemplating: true
      data:
        values: |
          {{ $rootContext.Values | toYaml | nindent 8 }}
{{- end }}
{{- end -}}
