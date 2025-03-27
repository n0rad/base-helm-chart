#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$DIR/../bin/lib/color.sh"



DEBUG="${DEBUG:-false}"
chartPath="${1:-"."}"
PUSH="${PUSH:-false}"
CHART_TEMPLATE_PATH="$chartPath/chart-template"
CHART_PATH_FROM_CI="$chartPath"
UNIT_TESTS_RELATIVE_LOCATION="."

CHART_TEMPLATE_SUFFIX="-template"
REGISTRY_URL="oci://ghcr.io/n0rad/"

####################

version="1.$(date -u '+%y%m%d').$(date -u '+%H%M' | awk '{print $0+0}')-H$(git rev-parse --short HEAD)"
name=$(yq --unwrapScalar .name $chartPath/Chart.yaml)
helmDebugArg=""

####################

if [ "$DEBUG" == "true" ] || [[ "$-" == *x* ]]; then
  set -x
  helmDebugArg="--debug"
fi

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

getBaseDependencyNameAndVersion() {
		for i in $(yq '.dependencies[]? | .name + ";" + .version + ";" + .repository' Chart.yaml); do
			IFS=';' read -ra depAttributes <<< "$i"
			if [[ ${depAttributes[0]} =~ ^base* ]] && [[ ${depAttributes[2]} == "$REGISTRY_URL" ]]; then
				echo "${depAttributes[0]}" "${depAttributes[1]}"
				return
			fi
		done
}

####################

update_dependencies "$chartPath"

if is_library_chart "$chartPath"; then
	rm -Rf $CHART_TEMPLATE_PATH
	mkdir -p $CHART_TEMPLATE_PATH/templates

	cat <<- EOF > $CHART_TEMPLATE_PATH/Chart.yaml
		apiVersion: v2
		name: ${name}-template
		version: 0.0.0
		dependencies:
		  - name: ${name}
		    repository: file://../
		    version: ">0.0.0-0"
	EOF
	echo "---" > $CHART_TEMPLATE_PATH/values.yaml
	initName=$(echo "${name}" | cut -f1 -d-)
	echo "{{- include \"${name}.loader.all\" . -}}" > "$CHART_TEMPLATE_PATH/templates/${initName}.yaml"
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


# prepare schema
echo_purple "Prepare schema"
read baseName baseVersion < <(getBaseDependencyNameAndVersion) || true
if [ ! -f "$chartPath/schema/root.schema.json" ] && [ -n "$baseName" ]; then
	# using base chart without declaring a schema, creating one inheriting directly
	cp "$DIR/lib/helm/values.schema.json" "$chartPath"
fi

if [ -f "./schema/values.schema.json" ]; then
	echo_blue "Replacing JSON schema placeholders"
	chartName="$name"
	if is_library_chart; then
		chartName="$name-template"
	fi
	sed -i "s/{VERSION}/$version/g; \
					s/{NAME}/$name/g; \
					s/{CHART_NAME}/$chartName/g; \
					s/{BASE_NAME}/$baseName/g; \
					s/{BASE_VERSION}/$baseVersion/g" ./schema/*.schema.json ./helmRelease.schema.json

	echo_purple "Dereference schema and merge allOf"
	node $DIR/lib/helm/dereferencer/dereferenceAndMerge.js
fi



# Release
if [ "$PUSH" == true ]; then
	name=$(realpath $chartPath | xargs basename)
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