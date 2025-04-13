#!/usr/bin/env bash
set -e

DEBUG="${DEBUG:-false}"
CHART_PATH="${1:-"."}"
PUSH="${PUSH:-false}"
TESTS="${TESTS:-true}"
REGISTRY_URL="oci://ghcr.io/n0rad/"

####################

scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
unitTestsRelativeLocation="."
chartTemplateSuffix="-template"
chartPathForTests="$CHART_PATH"
chartTemplatePath="$CHART_PATH/chart-template"
version="1.$(date -u '+%y%m%d').$(date -u '+%H%M' | awk '{print $0+0}')-H$(git rev-parse --short HEAD)"
name=$(yq --unwrapScalar .name $CHART_PATH/Chart.yaml)
helmDebugArg=""
isLibraryChart=false

####################

. "$scriptDir/../bin/lib/color.sh"

if [ "$(yq --unwrapScalar '.type' "$CHART_PATH/Chart.yaml")" == "library" ]; then
	isLibraryChart=true
fi

if [ "$DEBUG" == "true" ] || [[ "$-" == *x* ]]; then
  set -x
  helmDebugArg="--debug"
fi

####################

update_dependencies() {
  # Do not allow to put manually dependencies gzip files
  rm -Rf "$1/charts/"
  echo_purple "Fetching dependencies for chart : $1"
  helm dependency update "$1"
}


####################

update_dependencies "$CHART_PATH"

# Prepare library
if $isLibraryChart; then
	rm -Rf $chartTemplatePath
	mkdir -p $chartTemplatePath/templates

	cat <<- EOF > $chartTemplatePath/Chart.yaml
		apiVersion: v2
		name: ${name}-template
		version: 0.0.0
		dependencies:
		  - name: ${name}
		    repository: file://../
		    version: ">0.0.0-0"
	EOF
	echo "---" > $chartTemplatePath/values.yaml
	initName=$(echo "${name}" | cut -f1 -d-)
	echo "{{- include \"${name}.loader.all\" . -}}" > "$chartTemplatePath/templates/${initName}.yaml"

  unitTestsRelativeLocation=".."
  chartPathForTests="$chartTemplatePath"
  update_dependencies "$chartTemplatePath"
fi

# Tests
if $TESTS; then
	if ls $CHART_PATH/ci/*-values.yaml 1> /dev/null 2>&1; then
		echo_purple "Run ci tests"
		for filename in $(find $CHART_PATH/ci/ -maxdepth 1 -name '*-values.yaml' -print 2> /dev/null); do
				resname=${filename//-values.yaml/-result.yaml}
				echo_blue "Validating against values file: $filename"
				content=$(helm template "$chartPathForTests" $validateArg --values="$filename" $helmDebugArg)
				echo "$content" > "$resname"
		done
	fi

	echo_purple "Run unit tests"
	helm unittest --color -f "${unitTestsRelativeLocation}/templates/**/*_test.yaml" -f "${unitTestsRelativeLocation}/tests/**/*_test.yaml" $chartPathForTests
fi

# Schema
echo_purple "Preparing schema"
for i in $(yq '.dependencies[]? | .name + ";" + .version + ";" + .repository' "$CHART_PATH/Chart.yaml"); do
	IFS=';' read -ra depAttributes <<< "$i"
	if [[ ${depAttributes[0]} =~ ^base* ]] && [[ ${depAttributes[2]} == "$REGISTRY_URL" ]]; then
		baseName="${depAttributes[0]}"
		baseVersion="${depAttributes[1]}"
	fi
done
if [ ! -f "$CHART_PATH/schema/root.schema.json" ] && [ -n "$baseName" ]; then
	# using base chart without declaring a schema, creating one inheriting directly
	cp "$scriptDir/lib/helm/values.schema.json" "$CHART_PATH"
fi

cp "$scriptDir/lib/helm/values-helmRelease.schema.json" "$CHART_PATH"

if [ -f "$CHART_PATH/schema/root.schema.json" ]; then
	echo_blue "Dereference schema and merge allOf"
	if [ ! -d $scriptDir/lib/helm/dereferencer/node_modules ]; then
		(
			echo_blue "Installing node modules for derefencer"
			cd $scriptDir/lib/helm/dereferencer
			npm install
		)
	fi

	(cd $CHART_PATH && node $scriptDir/lib/helm/dereferencer/dereferenceAndMerge.js)

	echo_blue "Replacing JSON schema placeholders"
	chartName="$name"
	if $isLibraryChart; then
		chartName="$name-template"
	fi
	sed -i "s/{VERSION}/$version/g; \
					s/{NAME}/$name/g; \
					s/{CHART_NAME}/$chartName/g; \
					s/{BASE_NAME}/$baseName/g; \
					s/{BASE_VERSION}/$baseVersion/g" "$CHART_PATH"/*.schema.json

echo_purple "Validating schema"
	chartRealPath=$(realpath "$CHART_PATH")
 (cd $scriptDir/lib/helm/schema && go run . "$chartRealPath")
fi


# Release
if [ "$PUSH" == true ]; then
	HELM_PACKAGE_ARGS="--version=$version"

	echo_purple "Packaging $name-$version"
	helm package $CHART_PATH $HELM_PACKAGE_ARGS -d /tmp
	echo_purple "Pushing $name-$version"
	helm push "/tmp/$name-$version.tgz" "$REGISTRY_URL"

	if $isLibraryChart; then
    echo_purple "Packaging $name$chartTemplateSuffix-$version"
    helm package "$chartTemplatePath" $HELM_PACKAGE_ARGS -d /tmp
    echo_purple "Pushing $name$chartTemplateSuffix-$version"
    helm push "/tmp/$name$chartTemplateSuffix-$version.tgz" "$REGISTRY_URL"
	fi

	tag="$name-$version"
	gh release create "$tag" --generate-notes
	gh release upload "$tag" "/tmp/$name-$version.tgz" $CHART_PATH/values*.schema.json
fi
