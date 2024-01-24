/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package usenodeport

import (
	networking "k8s.io/api/networking/v1"

	"k8s.io/ingress-nginx/internal/ingress/annotations/parser"
	"k8s.io/ingress-nginx/internal/ingress/errors"
	"k8s.io/ingress-nginx/internal/ingress/resolver"
)

const (
	useNodePortAnnotation = "use-node-port"
)

var useNodePortAnnotations = parser.Annotation{
	Group: "backend",
	Annotations: parser.AnnotationFields{
		useNodePortAnnotation: {
			Validator:     parser.ValidateBool,
			Scope:         parser.AnnotationScopeLocation,
			Risk:          parser.AnnotationRiskLow,
			Documentation: `This annotation enables using node port of a service in the backend`,
		},
	},
}

type useNodePort struct {
	r                resolver.Resolver
	annotationConfig parser.Annotation
}

// NewParser creates a new useNodePort annotation parser
func NewParser(r resolver.Resolver) parser.IngressAnnotation {
	return useNodePort{
		r:                r,
		annotationConfig: useNodePortAnnotations,
	}
}

func (a useNodePort) Parse(ing *networking.Ingress) (interface{}, error) {
	val, err := parser.GetBoolAnnotation(useNodePortAnnotation, ing, a.annotationConfig.Annotations)

	if err == errors.ErrMissingAnnotations {
		return false, nil
	}

	return val, nil
}

func (a useNodePort) GetDocumentation() parser.AnnotationFields {
	return a.annotationConfig.Annotations
}

func (a useNodePort) Validate(anns map[string]string) error {
	maxrisk := parser.StringRiskToRisk(a.r.GetSecurityConfiguration().AnnotationsRiskLevel)
	return parser.CheckAnnotationRisk(anns, maxrisk, useNodePortAnnotations.Annotations)
}
