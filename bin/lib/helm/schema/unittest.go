package main

import (
	"fmt"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/helm-unittest/helm-unittest/pkg/unittest"
	"github.com/helm-unittest/helm-unittest/pkg/unittest/valueutils"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/yargevad/filepathx"
	"gopkg.in/yaml.v3"
	"helm.sh/helm/v3/pkg/chartutil"
)

// wrap suite so we can add file as exported
type Suite struct {
	*unittest.TestSuite
	DefinitionFile string
}

func GetSuites() ([]*Suite, error) {
	testFilesSet, terr := getFiles(".", []string{"./templates/**/*_test.yaml", "./tests/**/*_test.yaml"}, false)
	if terr != nil {
		return nil, terr
	}

	resultSuites := make([]*Suite, 0, len(testFilesSet))
	for _, file := range testFilesSet {
		suites, err := unittest.ParseTestSuiteFile(file, "chart-name", false, []string{})
		if err != nil {
			return nil, errs.WithEF(err, data.WithField("file", file), "Failed to parse unit test file")
		}

		var tests []*unittest.TestJob

		for i := range suites {
			suite := suites[i]
			for j := range suite.Tests {
				test := suite.Tests[j]
				// remove tests that assert a fail since values will be wrong
				if !(len(test.Assertions) == 1 && test.Assertions[0].AssertType == "failedTemplate") {
					// copy suite values files to each test
					test.Values = append(test.Values, suite.Values...)
					tests = append(tests, test)
				}
			}
			suite.Tests = tests
			resultSuites = append(resultSuites, &Suite{suite, file})
		}
	}
	return resultSuites, nil
}

// coming from unittest
func GetUserValues(t *unittest.TestJob, testSuiteGlobalSet map[string]interface{}, chartRoute string, definitionFile string) (map[string]interface{}, error) {
	base := map[string]interface{}{}
	routes := splitChartRoutes(chartRoute)

	// Load and merge values files.
	for _, specifiedPath := range t.Values {
		value := map[string]interface{}{}
		var valueFilePath string
		if path.IsAbs(specifiedPath) {
			valueFilePath = specifiedPath
		} else {
			valueFilePath = filepath.Join(filepath.Dir(definitionFile), specifiedPath)
		}

		bytes, err := os.ReadFile(valueFilePath)
		if err != nil {
			return base, err
		}

		if err := yaml.Unmarshal(bytes, &value); err != nil {
			return base, fmt.Errorf("failed to parse %s: %s", specifiedPath, err)
		}
		base = chartutil.MergeTables(scopeValuesWithRoutes(routes, value), base)
	}

	// Merge global set values before merging the other set values
	for path, values := range testSuiteGlobalSet {
		setMap, err := valueutils.BuildValueOfSetPath(values, path)
		if err != nil {
			return base, err
		}

		base = chartutil.MergeTables(scopeValuesWithRoutes(routes, setMap), base)
	}

	for path, values := range t.Set {
		setMap, err := valueutils.BuildValueOfSetPath(values, path)
		if err != nil {
			return base, err
		}

		base = chartutil.MergeTables(scopeValuesWithRoutes(routes, setMap), base)
	}

	return base, nil
}

// copy/paste from unittest.test_runner.go
func scopeValuesWithRoutes(routes []string, values map[string]interface{}) map[string]interface{} {
	if len(routes) > 1 {
		newvalues := make(map[string]interface{})
		if v, ok := values["global"]; ok {
			newvalues["global"] = v
		}
		newvalues[routes[len(routes)-1]] = values
		return scopeValuesWithRoutes(
			routes[:len(routes)-1],
			newvalues,
		)
	}
	return values
}

func splitChartRoutes(routePath string) []string {
	splitPath := strings.Split(routePath, string(filepath.Separator))
	routes := make([]string, len(splitPath)/2+1)
	for r := 0; r < len(routes); r++ {
		routes[r] = splitPath[r*2]
	}
	return routes
}

func getFiles(chartPath string, filePatterns []string, setAbsolute bool) ([]string, error) {
	filesSet := make([]string, 0)
	for _, pattern := range filePatterns {
		if !filepath.IsAbs(pattern) {
			files, err := filepathx.Glob(filepath.Join(chartPath, pattern))
			if err != nil {
				return nil, err
			}
			if setAbsolute {
				for _, file := range files {
					file, _ = filepath.Abs(file)
					filesSet = append(filesSet, file)
				}
			} else {
				filesSet = append(filesSet, files...)
			}
		} else {
			filesSet = append(filesSet, pattern)
		}
	}

	return filesSet, nil
}
