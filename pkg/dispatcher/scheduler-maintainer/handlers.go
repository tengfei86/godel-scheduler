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

package scheduler_maintainer

import (
	nodev1alpha1 "github.com/kubewharf/godel-scheduler-api/pkg/apis/node/v1alpha1"
	schedulerapi "github.com/kubewharf/godel-scheduler-api/pkg/apis/scheduling/v1alpha1"
	v1 "k8s.io/api/core/v1"

	sche "github.com/kubewharf/godel-scheduler/pkg/dispatcher/internal/scheduler"
	"github.com/kubewharf/godel-scheduler/pkg/dispatcher/metrics"
	nodeutil "github.com/kubewharf/godel-scheduler/pkg/util/node"
)

// AddScheduler adds schedulers to maintainer cache
func (maintainer *SchedulerMaintainer) AddScheduler(scheduler *schedulerapi.Scheduler) {
	maintainer.schedulerMux.Lock()
	defer maintainer.schedulerMux.Unlock()

	maintainer.updateSchedulerBasedOnSchedulerCRD(scheduler)
}

// updateSchedulerBasedOnSchedulerCRD updates gs based on schedulers crd
// we assume the caller has already got the lock
func (maintainer *SchedulerMaintainer) updateSchedulerBasedOnSchedulerCRD(scheduler *schedulerapi.Scheduler) {
	if maintainer.generalSchedulers[scheduler.Name] == nil {
		// schedulers are not added before, add it to active schedulers map directly
		gs := sche.NewEnoSchedulerWithSchedulerCRD(scheduler)
		metrics.SchedulerSizeInc(metrics.ActiveScheduler)
		maintainer.generalSchedulers[scheduler.Name] = gs
		return
	}

	maintainer.generalSchedulers[scheduler.Name].SetScheduler(scheduler)
	/*if maintainer.generalInactiveSchedulers[schedulers.Name] != nil {
		// TODO: update some gs fields here if necessary based on schedulers crd
	}
	if maintainer.generalActiveSchedulers[schedulers.Name] != nil {
		// TODO: update some gs fields here if necessary based on schedulers crd
	}*/
	if IsSchedulerActive(scheduler) {
		if !maintainer.generalSchedulers[scheduler.Name].IsSchedulerActive() {
			metrics.SchedulerSizeInc(metrics.ActiveScheduler)
			metrics.SchedulerSizeDec(metrics.InactiveScheduler)
			maintainer.generalSchedulers[scheduler.Name].SetSchedulerActive()
		}
	} else {
		if maintainer.generalSchedulers[scheduler.Name].IsSchedulerActive() {
			metrics.SchedulerSizeInc(metrics.InactiveScheduler)
			metrics.SchedulerSizeDec(metrics.ActiveScheduler)
			maintainer.generalSchedulers[scheduler.Name].SetSchedulerInActive()
		}
	}
}

// UpdateScheduler updates schedulers info in maintainer cache
func (maintainer *SchedulerMaintainer) UpdateScheduler(oldScheduler *schedulerapi.Scheduler, newScheduler *schedulerapi.Scheduler) {
	maintainer.schedulerMux.Lock()
	defer maintainer.schedulerMux.Unlock()

	maintainer.updateSchedulerBasedOnSchedulerCRD(newScheduler)
}

// DeleteScheduler moves schedulers from active queue to inactive queue to trigger shuffle operation later
func (maintainer *SchedulerMaintainer) DeleteScheduler(scheduler *schedulerapi.Scheduler) {
	maintainer.schedulerMux.Lock()
	defer maintainer.schedulerMux.Unlock()

	// deactivate the schedulers
	if maintainer.generalSchedulers[scheduler.Name] != nil {
		// TODO: if we add more fields into EnoScheduler,
		// add more checks here (for example: check if dispatched pods are all dispatched) if we want to delete it from generalInactiveSchedulers
		if len(maintainer.generalSchedulers[scheduler.Name].GetNodes()) == 0 {
			delete(maintainer.generalSchedulers, scheduler.Name)
		} else {
			maintainer.generalSchedulers[scheduler.Name].SetSchedulerInActive()
		}
	}
}

// getEnoScheduler gets the EnoScheduler by schedulers name
// we assume the caller has get the lock
func (maintainer *SchedulerMaintainer) getEnoScheduler(schedulerName string) *sche.EnoScheduler {
	return maintainer.generalSchedulers[schedulerName]
}

func (maintainer *SchedulerMaintainer) addNodeToEnoScheduler(schedulerName string, nodeName string) {
	scheduler := maintainer.getEnoScheduler(schedulerName)
	newlyCreate := false
	if scheduler == nil {
		scheduler = sche.NewEnoSchedulerWithSchedulerName(schedulerName)
		newlyCreate = true
		metrics.SchedulerSizeInc(metrics.ActiveScheduler)
	}

	// node and nmnode objects share the same node name, so only one node will be added to this map
	scheduler.AddNode(nodeName)
	if newlyCreate {
		// we directly add node to active schedulers here,
		// schedulers will be moved to inactive schedulers by a separate sync-up goroutine if it is not alive
		maintainer.generalSchedulers[schedulerName] = scheduler
	}
}

// AddNodeToEnoSchedulerIfNotPresent adds node to specific eno schedulers
func (maintainer *SchedulerMaintainer) AddNodeToEnoSchedulerIfNotPresent(node *v1.Node) error {
	maintainer.schedulerMux.Lock()
	defer maintainer.schedulerMux.Unlock()

	if len(node.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]) == 0 {
		// annotation is nil or does not contain EnoSchedulerNodeAnnotationKey,
		// this kind of node will be handled by a separate sync-up goroutine, so skip directly here
		return nil
	}

	schedulerName := node.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]
	maintainer.addNodeToEnoScheduler(schedulerName, node.Name)

	return nil
}

// AddNMNodeToEnoSchedulerIfNotPresent adds NMNode to specific eno schedulers
func (maintainer *SchedulerMaintainer) AddNMNodeToEnoSchedulerIfNotPresent(nmNode *nodev1alpha1.NMNode) error {
	maintainer.schedulerMux.Lock()
	defer maintainer.schedulerMux.Unlock()

	if len(nmNode.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]) == 0 {
		// annotation is nil or does not contain EnoSchedulerNodeAnnotationKey,
		// this kind of node will be handled by a separate sync-up goroutine, so skip directly here
		return nil
	}

	schedulerName := nmNode.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]
	maintainer.addNodeToEnoScheduler(schedulerName, nmNode.Name)

	return nil
}

// we assume the caller has already get the lock
func (maintainer *SchedulerMaintainer) nodeExistsInEnoScheduler(nodeName string, schedulerName string) bool {
	if maintainer.generalSchedulers[schedulerName] == nil {
		// schedulers does not exist in maintainer, return false
		return false
	}

	_, found := maintainer.generalSchedulers[schedulerName].GetNodes()[nodeName]
	return found
}

// UpdateNodeInEnoSchedulerIfNecessary updates node info for specific eno schedulers
func (maintainer *SchedulerMaintainer) UpdateNodeInEnoSchedulerIfNecessary(oldNode *v1.Node, newNode *v1.Node) error {
	maintainer.schedulerMux.Lock()
	defer maintainer.schedulerMux.Unlock()

	oldSchedulerName := oldNode.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]
	newSchedulerName := newNode.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]
	// schedulers name exists and is not updated
	if oldSchedulerName == newSchedulerName && len(newSchedulerName) > 0 {
		nodeExist := maintainer.nodeExistsInEnoScheduler(newNode.Name, newSchedulerName)
		if !nodeExist {
			maintainer.addNodeToEnoScheduler(newSchedulerName, newNode.Name)
		}

		// schedulers name is not updated and node is already in eno schedulers partition, return directly
		return nil
	}

	if len(oldSchedulerName) > 0 {
		if maintainer.generalSchedulers[oldSchedulerName] != nil {
			maintainer.generalSchedulers[oldSchedulerName].RemoveNode(oldNode.Name)
		}
	}

	if len(newSchedulerName) > 0 {
		maintainer.addNodeToEnoScheduler(newSchedulerName, newNode.Name)
	}
	return nil
}

// UpdateNMNodeInEnoSchedulerIfNecessary updates nmnode info for specific eno schedulers
func (maintainer *SchedulerMaintainer) UpdateNMNodeInEnoSchedulerIfNecessary(oldNMNode *nodev1alpha1.NMNode, newNMNode *nodev1alpha1.NMNode) error {
	maintainer.schedulerMux.Lock()
	defer maintainer.schedulerMux.Unlock()

	oldSchedulerName := oldNMNode.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]
	newSchedulerName := newNMNode.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]
	// TODO: We can remove this check
	if oldSchedulerName == newSchedulerName && len(newSchedulerName) > 0 {
		nodeExist := maintainer.nodeExistsInEnoScheduler(newNMNode.Name, newSchedulerName)
		if !nodeExist {
			maintainer.addNodeToEnoScheduler(newSchedulerName, newNMNode.Name)
		}

		// schedulers name is not updated and node is already in eno schedulers partition, return directly
		return nil
	}

	if len(oldSchedulerName) > 0 {
		if maintainer.generalSchedulers[oldSchedulerName] != nil {
			maintainer.generalSchedulers[oldSchedulerName].RemoveNode(oldNMNode.Name)
		}
	}

	if len(newSchedulerName) > 0 {
		maintainer.addNodeToEnoScheduler(newSchedulerName, newNMNode.Name)
	}
	return nil
}

// DeleteNodeFromEnoScheduler deletes node from specific eno schedulers
func (maintainer *SchedulerMaintainer) DeleteNodeFromEnoScheduler(node *v1.Node) error {
	maintainer.schedulerMux.Lock()
	defer maintainer.schedulerMux.Unlock()

	if len(node.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]) == 0 {
		// annotation is nil or does not contain EnoSchedulerNodeAnnotationKey,
		// this kind of node will be handled by a separate sync-up goroutine, so skip directly here
		return nil
	}

	schedulerName := node.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]
	if maintainer.generalSchedulers[schedulerName] != nil {
		maintainer.generalSchedulers[schedulerName].RemoveNode(node.Name)
	}

	return nil
}

// DeleteNMNodeFromEnoScheduler deletes nmnode from specific eno schedulers
func (maintainer *SchedulerMaintainer) DeleteNMNodeFromEnoScheduler(nmNode *nodev1alpha1.NMNode) error {
	maintainer.schedulerMux.Lock()
	defer maintainer.schedulerMux.Unlock()

	if len(nmNode.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]) == 0 {
		// annotation is nil or does not contain EnoSchedulerNodeAnnotationKey,
		// this kind of node will be handled by a separate sync-up goroutine, so skip directly here
		return nil
	}

	schedulerName := nmNode.Annotations[nodeutil.EnoSchedulerNodeAnnotationKey]
	if maintainer.generalSchedulers[schedulerName] != nil {
		maintainer.generalSchedulers[schedulerName].RemoveNode(nmNode.Name)
	}

	return nil
}
