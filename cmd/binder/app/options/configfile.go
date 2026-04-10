/*
Copyright 2023 The Eno Scheduler Authors.

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

package options

import (
	"fmt"
	"io/ioutil"

	godelbinderconfig "github.com/kubewharf/godel-scheduler/pkg/binder/apis/config"
	godelbinderscheme "github.com/kubewharf/godel-scheduler/pkg/binder/apis/config/scheme"
	"github.com/kubewharf/godel-scheduler/pkg/binder/apis/config/v1beta1"
)

func loadProfileFromFile(file string) (*godelbinderconfig.EnoBinderProfile, error) {
	data, err := ioutil.ReadFile(file)
	if err != nil {
		return nil, err
	}

	return loadProfile(data)
}

func loadProfile(data []byte) (*godelbinderconfig.EnoBinderProfile, error) {
	// The UniversalDecoder runs defaulting and returns the internal type by default.
	obj, gvk, err := godelbinderscheme.Codecs.UniversalDecoder().Decode(data, nil, nil)
	if err != nil {
		return nil, err
	}
	if cfgObj, ok := obj.(*godelbinderconfig.EnoBinderProfile); ok {
		return cfgObj, nil
	}
	return nil, fmt.Errorf("couldn't decode as EnoBinderProfile, got %s: ", gvk)
}

func loadConfigFromFile(file string) (*godelbinderconfig.EnoBinderConfiguration, error) {
	data, err := ioutil.ReadFile(file)
	if err != nil {
		return nil, err
	}

	return loadConfig(data)
}

func loadConfig(data []byte) (*godelbinderconfig.EnoBinderConfiguration, error) {
	// The UniversalDecoder runs defaulting and returns the internal type by default.
	obj, gvk, err := godelbinderscheme.Codecs.UniversalDecoder().Decode(data, nil, nil)
	if err != nil {
		return nil, err
	}
	if cfgObj, ok := obj.(*godelbinderconfig.EnoBinderConfiguration); ok {
		cfgObj.TypeMeta.APIVersion = gvk.GroupVersion().String()
		switch cfgObj.TypeMeta.APIVersion {
		case v1beta1.SchemeGroupVersion.String():
			fmt.Printf("EnoBinderConfiguration v1beta1 is loaded.\n")
		}

		return cfgObj, nil
	}
	return nil, fmt.Errorf("couldn't decode as EnoBinderConfiguration, got %s: ", gvk)
}
