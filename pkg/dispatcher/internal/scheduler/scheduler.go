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

package scheduler

import (
	schedulerapi "github.com/kubewharf/godel-scheduler-api/pkg/apis/scheduling/v1alpha1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// EnoScheduler stores all necessary metrics about one eno scheduler.
// We do not create a lock for EnoScheduler here, it is only used by scheduler maintainer and maintainer's lock will protect this too.
// TODO: if EnoScheduler is used by multiple users, we may need to revisit this to see if we need a lock here.
type EnoScheduler struct {
	schedulerName string

	scheduler *schedulerapi.Scheduler

	// active shows whether the scheduler is active or not
	active bool

	nodePartitionType string
	// when dispatcher dispatches tasks to schedulers, it should also respect scheduler's requirements
	// this scheduler will only be responsible for dispatching tasks who satisfy this TaskSelector
	taskSelector metav1.LabelSelector
	// this scheduler will only be responsible for managing nodes who satisfy this NodeSelector
	nodeSelector metav1.LabelSelector

	// TODO: Extract more fields from Scheduler CRD if necessary

	// there may be some latency to update this map after pods are scheduled
	// schedulers need to filter out scheduled pods too after dispatcher dispatching pods to them
	// TODO: if this scheduler dies, we need to get the latest state of the unscheduled pods here first and then re-dispatch still-real-unscheduled pods
	// UnscheduledPods map[string]*v1.Pod

	// nodes in this scheduler's partition
	// TODO: enrich the value of Nodes map if necessary, for example set the type to *node.NodeInfo or something like that
	nodes map[string]struct{}

	// TODO: track dispatched pods here
}

// NewEnoSchedulerWithSchedulerName create a EnoScheduler with scheduler name
func NewEnoSchedulerWithSchedulerName(schedulerName string) *EnoScheduler {
	return &EnoScheduler{
		schedulerName: schedulerName,
		// active field defaulting to true
		active: true,
		nodes:  make(map[string]struct{}),
	}
}

// NewEnoSchedulerWithSchedulerCRD creates a EnoScheduler with a scheduler CRD
func NewEnoSchedulerWithSchedulerCRD(scheduler *schedulerapi.Scheduler) *EnoScheduler {
	// TODO: initialize more fields for EnoScheduler
	// NodePartitionType ...
	return &EnoScheduler{
		schedulerName: scheduler.Name,
		// active field defaulting to true
		active:    true,
		scheduler: scheduler,
		nodes:     make(map[string]struct{}),
	}
}

func (gs *EnoScheduler) IsSchedulerActive() bool {
	return gs.active
}

func (gs *EnoScheduler) SetSchedulerActive() {
	gs.active = true
}

func (gs *EnoScheduler) SetSchedulerInActive() {
	gs.active = false
}

func (gs *EnoScheduler) SetScheduler(scheduler *schedulerapi.Scheduler) {
	gs.scheduler = scheduler
}

func (gs *EnoScheduler) GetScheduler() *schedulerapi.Scheduler {
	return gs.scheduler
}

func (gs *EnoScheduler) Clone() *EnoScheduler {
	gsClone := &EnoScheduler{
		schedulerName:     gs.schedulerName,
		scheduler:         gs.scheduler.DeepCopy(),
		nodePartitionType: gs.nodePartitionType,
		taskSelector:      gs.taskSelector,
		nodeSelector:      gs.nodeSelector,
	}
	gsClone.nodes = make(map[string]struct{})
	for nodeName := range gs.nodes {
		gsClone.nodes[nodeName] = struct{}{}
	}
	return gsClone
}

func (gs *EnoScheduler) AddNode(nodeName string) {
	gs.nodes[nodeName] = struct{}{}
}

func (gs *EnoScheduler) RemoveNode(nodeName string) {
	delete(gs.nodes, nodeName)
}

func (gs *EnoScheduler) NodeExists(nodeName string) bool {
	_, found := gs.nodes[nodeName]
	return found
}

func (gs *EnoScheduler) GetNodes() map[string]struct{} {
	return gs.nodes
}
