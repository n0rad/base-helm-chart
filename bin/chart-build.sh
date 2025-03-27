#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$DIR/../bin/color.sh"


helmDebugArg=""
if [ "$DEBUG" == "true" ]; then
  set -x
  helmDebugArg="--debug"
fi


chartPath="${1:-"."}"
CHART_TEMPLATE_PATH="$chartPath/chart-template"
UPDATE_SNAPSHOTS=true
CHART_TEMPLATE_SUFFIX="-template"

####################

is_library_chart() {
  if [ "$(yq --unwrapScalar '.type' "$1/Chart.yaml")" == "library" ]; then
    return 0
  fi
  return 1
}

update_dependencies() {
  # Do not allow to put manually dependencies gzip files
  rm -Rf "$1/charts/"
  echo_purple "Fetching dependencies for chart : $1"
  helm dependency update "$1"
}

####################

chartTestsPath="."
if is_library_chart $chartPath; then
	libraryName=$(yq --unwrapScalar .name $chartPath/Chart.yaml)
	rm -Rf $CHART_TEMPLATE_PATH
	mkdir -p $CHART_TEMPLATE_PATH/templates

	cat <<- EOF > $CHART_TEMPLATE_PATH/Chart.yaml
		apiVersion: v2
		name: ${libraryName}-template
		version: 0.0.0
		dependencies:
		  - name: ${libraryName}
		    repository: file://../
		    version: ">0.0.0-0"
	EOF
	echo "---" > $CHART_TEMPLATE_PATH/values.yaml
	initName=$(echo "${libraryName}" | cut -f1 -d-)
	echo "{{- include \"${libraryName}.loader.all\" . -}}" > "$CHART_TEMPLATE_PATH/templates/${initName}.yaml"
	[ -d "$chartPath/ci" ] && cp -r "$chartPath/ci" "$CHART_TEMPLATE_PATH"

  chartPath=$CHART_TEMPLATE_PATH
  chartTestsPath=".."
  update_dependencies "$chartPath"
elif is_library_chart; then
  exit 0
fi

if ls $chartPath/ci/*-values.yaml 1> /dev/null 2>&1; then
  for filename in $(find $chartPath/ci/ -maxdepth 1 -name '*-values.yaml' -print 2> /dev/null); do
      resname=${filename//-values.yaml/-result.yaml}
      echo_purple "Validating against values file : $filename"
      content=$(helm template $chartPath $validateArg --values="$filename" $helmDebugArg)
      [ "$DEBUG" == "true" ] && echo $content
      if [ -f "$resname" ]; then
        if [ "$UPDATE_SNAPSHOTS" == "true" ]; then
          echo_purple "Updating result in $resname"
          echo "$content" > "$resname"
        else
          echo_purple "Comparing with expected result in $resname"
          diff -u "$resname" <(echo "$content")
        fi
      fi
  done
fi


echo_purple "Run unit tests"
helm unittest --color -f "${chartTestsPath}/templates/**/*_test.yaml" -f "${chartTestsPath}/tests/**/*_test.yaml" $chartPath
