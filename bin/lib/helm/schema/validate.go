package main

import (
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"time"

	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/santhosh-tekuri/jsonschema/v6"
	"gopkg.in/yaml.v3"
)

var yamlSchemaLocationRegex = regexp.MustCompile(`#[[:space:]]*yaml-language-server:[[:space:]]*\$schema=([[:print:]]*).*`)

type HTTPURLLoader http.Client

func (l *HTTPURLLoader) Load(url string) (any, error) {
	client := (*http.Client)(l)
	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		_ = resp.Body.Close()
		return nil, fmt.Errorf("%s returned status code %d", url, resp.StatusCode)
	}
	defer resp.Body.Close()

	return jsonschema.UnmarshalJSON(resp.Body)
}

func newHTTPURLLoader(insecure bool) *HTTPURLLoader {
	httpLoader := HTTPURLLoader(http.Client{
		Timeout: 15 * time.Second,
	})
	if insecure {
		httpLoader.Transport = &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		}
	}
	return &httpLoader
}

func ValidateFileAgainstSchemaUrl(path string, schemaUrl string) error {
	content, err := os.ReadFile(path)
	if err != nil {
		return errs.WithEF(err, data.WithField("file", path), "Failed to read file")
	}

	var v interface{}
	if err := yaml.Unmarshal(content, &v); err != nil {
		return errs.WithE(err, "Failed to unmarshal file")
	}
	logs.WithField("file", path).Debug("Validating file against schema")
	return ValidateObjectsAgainstSchema(map[string]interface{}{path: v}, schemaUrl)
}

func ValidateFile(path string) error {
	content, err := os.ReadFile(path)
	if err != nil {
		return errs.WithEF(err, data.WithField("file", path), "Failed to read file")
	}
	submatch := yamlSchemaLocationRegex.FindStringSubmatch(string(content))
	if len(submatch) < 2 {
		// no schema
		return nil
	}

	var v interface{}
	if err := yaml.Unmarshal(content, &v); err != nil {
		return errs.WithE(err, "Failed to unmarshal file")
	}
	logs.WithField("file", path).Debug("Validating file against schema")
	return ValidateObjectsAgainstSchema(map[string]interface{}{path: v}, submatch[1])
}

func ValidateObjectsAgainstSchema(objects map[string]interface{}, schemaUrl string) error {
	loader := jsonschema.SchemeURLLoader{
		"file":  jsonschema.FileLoader{},
		"http":  newHTTPURLLoader(false),
		"https": newHTTPURLLoader(false),
	}

	c := jsonschema.NewCompiler()
	c.UseLoader(loader)

	sch, err := c.Compile(schemaUrl)
	if err != nil {
		return errs.WithE(err, "Failed to compile schema")
	}

	with := errs.With("Some validation failed")
	for key, object := range objects {
		if err := sch.Validate(object); err != nil {
			switch v := err.(type) {
			case *jsonschema.ValidationError:
				output, _ := json.MarshalIndent(v.DetailedOutput(), "", "  ")
				with = with.WithErr(errors.New(string(output)))
			default:
				with = with.WithErr(errs.WithEF(err, data.WithField("file", key), "Validation failed"))
			}
		}
	}
	if len(with.Errs) > 0 {
		return with
	}
	return nil
}
