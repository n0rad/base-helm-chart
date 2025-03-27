{{- define "base.features.e2eTests" -}}
{{- if include "base.lib.utils.isEnabled" (dig "e2eTests" dict .Values) -}}
  {{- $e2eTests := .Values.e2eTests -}}
  {{- $e2eTests = mergeOverwrite (deepCopy .Values.chartDefaults.e2eTests) $e2eTests -}}
  {{- $_ := set .Values "e2eTests" $e2eTests -}}

  {{- $typeList := list "one-app" "bus-aggregation-office" "bus-aggregation-engine" -}}
  {{- $type := "one-app" -}}

  {{- /* Validate interface contract */ -}}
  {{- if not $e2eTests.helmRelease -}}
    {{- fail (printf ".Values.e2eTests.helmRelease is mandatory") -}}
  {{- end -}}
  {{- if not $e2eTests.testSuite -}}
    {{- fail (printf ".Values.e2eTests.testSuite is mandatory") -}}
  {{- end -}}


resources:
  alerts:
  {{- /* Only one type of bus* test is allowed in a testSuite */ -}}
  {{- $BusOffice := false -}}
  {{- $BusEngine := false -}}
  
  {{- range $alert := $e2eTests.testSuite -}}

    {{- /* Validate interface contract */ -}}
    {{- if not $alert -}}
      {{- fail (printf ".Values.e2eTests.testSuite must contain 1 test") -}}
    {{- end -}}


    {{- if $alert.type -}}
      {{- $type = $alert.type -}}
    {{- end -}}
    {{- if not (has $type $typeList) -}}
      {{- fail (printf ".Values.e2eTests.testSuite[].type must be in %s" $typeList) -}}
    {{- end -}}
    {{- if eq $type "bus-aggregation-engine" -}}
      {{- if eq $BusEngine true -}}
        {{- fail (printf "Only one occurence maximue allowed for 'bus-aggregation-engine' type") -}}
      {{- end -}}
      {{- $BusEngine = true -}}
    {{- end -}}
    {{- if eq $type "bus-aggregation-office" -}}
      {{- if eq $BusOffice true -}}
        {{- fail (printf "Only one occurence maximue allowed for 'bus-aggregation-office' type") -}}
      {{- end -}}
      {{- $BusOffice = true -}}
    {{- end -}}

    {{- if not $alert.tags -}}
      {{- fail (printf ".Values.e2eTests.testSuite[].tags is mandatory") -}}
    {{- end -}}
    
    {{- $slackChannel := $alert.slackChannel -}}
    {{- if not $slackChannel -}}
      {{- if not  $e2eTests.defaultSlackChannel -}}
        {{- fail (printf "A slackChannel is mandatory (in .Values.e2eTests.testSuite[].slackChannel or .Values.e2eTests.defaultSlackChannel)") -}}
      {{- else -}}
        {{- $slackChannel = $e2eTests.defaultSlackChannel -}}
      {{- end -}}
    {{- end -}}
    {{- if or (not (hasPrefix "#" $slackChannel)) (lt (len $slackChannel) 3) -}}
      {{- fail (printf "The slackChannel must be a slack channel (starting with # and with a length > 3)") -}}
    {{- end -}}

    {{- if or (and (eq $type "one-app") (not $alert.project)) (and (ne $type "one-app") ($alert.project)) -}}
      {{- fail (printf ".Values.e2eTests.testSuite[].projects is allowed and mandatory only when type is 'one-app'") -}}
    {{- end -}}

    {{- /* Compute the name suffix to have a unique object name */ -}}
    {{- $nameSuffix := printf "-%s" $type -}}
    {{- if $alert.project -}}
      {{- $nameSuffix = printf "%s-%s" $nameSuffix $alert.project -}}
    {{- end }}
    e2eTests{{ $nameSuffix }}:
      nameOverride: e2e-tests{{ $nameSuffix }}
      provider: e2e-tests-flux-hooks
      eventSources:
        - kind: HelmRelease
          name: {{ tpl $e2eTests.helmRelease $ | quote }}
      inclusionList:
        - ".*succeeded.*"
      eventMetadata:
        type: {{ $type }}
        {{- with $alert.project }}
        project: {{ . }}
        {{- end }}
        tags: {{ join "," $alert.tags | quote }}
        slackChannel: {{ $slackChannel | quote }}
        {{/* we need to do 2 times the tpl because of the use of .Chart.AppVersion as default value of the indirection */}}
        version: {{ tpl (tpl $e2eTests.version $) $ | quote }}
    {{- end -}}
  {{- end -}}
{{- end -}}
