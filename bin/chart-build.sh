#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$DIR/../bin/lib/color.sh"


helmDebugArg=""
if [ "$DEBUG" == "true" ]; then
  set -x
  helmDebugArg="--debug"
fi


chartPath="${1:-"."}"
PUSH="${PUSH:-false}"
CHART_TEMPLATE_PATH="$chartPath/chart-template"
CHART_PATH_FROM_CI="$chartPath"
UNIT_TESTS_RELATIVE_LOCATION="."

CHART_TEMPLATE_SUFFIX="-template"
REGISTRY_URL="oci://ghcr.io/n0rad/"

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

update_dependencies "$chartPath"

if is_library_chart "$chartPath"; then
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

  UNIT_TESTS_RELATIVE_LOCATION=".."
  CHART_PATH_FROM_CI="$CHART_TEMPLATE_PATH"
  update_dependencies "$CHART_TEMPLATE_PATH"
elif is_library_chart; then
  exit 0
fi

if ls $chartPath/ci/*-values.yaml 1> /dev/null 2>&1; then
  for filename in $(find $chartPath/ci/ -maxdepth 1 -name '*-values.yaml' -print 2> /dev/null); do
      resname=${filename//-values.yaml/-result.yaml}
      echo_purple "Validating against values file: $filename"
      content=$(helm template "$CHART_PATH_FROM_CI" $validateArg --values="$filename" $helmDebugArg)
			echo "$content" > "$resname"
  done
fi


echo_purple "Run unit tests"
helm unittest --color -f "${UNIT_TESTS_RELATIVE_LOCATION}/templates/**/*_test.yaml" -f "${UNIT_TESTS_RELATIVE_LOCATION}/tests/**/*_test.yaml" $CHART_PATH_FROM_CI



# Release
if [ "$PUSH" == true ]; then
	name=$(realpath $chartPath | xargs basename)
	version="1.$(date -u '+%y%m%d').$(date -u '+%H%M' | awk '{print $0+0}')-H$(git rev-parse --short HEAD)"
	HELM_PACKAGE_ARGS="--version=$version"

	echo_purple "Packaging $name-$version"
	helm package $chartPath $HELM_PACKAGE_ARGS -d /tmp
	echo_purple "Pushing $name-$version"
	helm push "/tmp/$name-$version.tgz" "$REGISTRY_URL"

	if is_library_chart "$chartPath"; then
    echo_purple "Packaging $name$CHART_TEMPLATE_SUFFIX-$version"
    helm package "$CHART_TEMPLATE_PATH" $HELM_PACKAGE_ARGS -d /tmp
    echo_purple "Pushing $name$CHART_TEMPLATE_SUFFIX-$version"
    helm push "/tmp/$name$CHART_TEMPLATE_SUFFIX-$version.tgz" "$REGISTRY_URL"
	fi
fi