package main

import (
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	_ "github.com/n0rad/go-erlog/register"
	"os"
	"path"
	"path/filepath"
)

const ValuesSchemaFileName = "values.schema.json"
const DefaultValuesSchemaFileName = "default-values.schema.json"

func main() {
	if err := run(os.Args[1]); err != nil {
		logs.WithE(err).Error("Run failed")
	}
}

func run(chartPath string) error {
	schemaUrl := path.Join(chartPath, ValuesSchemaFileName)
	if stat, err := os.Stat(schemaUrl); err == nil && !stat.IsDir() {
		if err := validateIntegrationTestsValuesAgainstSchema(path.Join(chartPath, "ci"), path.Join("..", ValuesSchemaFileName)); err != nil {
			return errs.WithEF(err, data.WithField("schema", schemaUrl), "validation of IT tests values failed against schema")
		}
		if err := validateUnitTestsValuesAgainstSchema(schemaUrl); err != nil {
			return errs.WithEF(err, data.WithField("schema", schemaUrl), "validation of UT tests values failed against schema")
		}
	}
	if stat, err := os.Stat(schemaUrl + "/" + DefaultValuesSchemaFileName); err == nil && !stat.IsDir() {
		if err := validateDefaultValuesAgainstSchema(schemaUrl + "/" + DefaultValuesSchemaFileName); err != nil {
			return errs.WithEF(err, data.WithField("schema", schemaUrl), "validation of default values failed against schema")
		}
	}
	return nil
}

func validateDefaultValuesAgainstSchema(schemaUrl string) error {
	logs.Info("Validating 'values.yaml' against default schema")
	err := ValidateFileAgainstSchemaUrl("values.yaml", schemaUrl)
	if err != nil {
		return errs.WithE(err, "values.yaml file is not valid against default schema")
	}
	return nil
}

func validateIntegrationTestsValuesAgainstSchema(ciFolder string, schemaUrl string) error {
	if info, err := os.Stat(ciFolder); err != nil || !info.IsDir() {
		return nil
	}
	logs.Info("Validating Integration Tests values against schema")

	files, err := os.ReadDir(ciFolder)
	if err != nil {
		return errs.WithE(err, "Failed to read ci/ directory")
	}
	cwd, err := os.Getwd()
	if err != nil {
		return errs.WithE(err, "Failed to get current working dir")
	}
	defer os.Chdir(cwd)
	if err := os.Chdir(ciFolder); err != nil {
		return errs.WithE(err, "Failed to change dir to ci/")
	}
	for _, file := range files {
		matched, _ := filepath.Match("*-values.yaml", file.Name())
		if matched {
			err := ValidateFileAgainstSchemaUrl(file.Name(), schemaUrl)
			if err != nil {
				return err
			}
		}
	}
	return nil
}

func validateUnitTestsValuesAgainstSchema(schemaUrl string) error {
	suites, err := GetSuites()
	if err != nil {
		return err
	}

	tests := make(map[string]interface{})
	for _, suite := range suites {
		for _, test := range suite.Tests {
			values, err := GetUserValues(test, test.Set, "root-name", suite.DefinitionFile)
			if err != nil {
				return err
			}
			tests[suite.DefinitionFile+"#"+test.Name] = values
		}
	}
	logs.Info("Validating Unit Tests values against schema")
	err = ValidateObjectsAgainstSchema(tests, schemaUrl)
	return err
}
