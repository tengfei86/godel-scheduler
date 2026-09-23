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

package metrics

import (
	"sync"

	"k8s.io/component-base/metrics"
	"k8s.io/component-base/metrics/legacyregistry"

	"github.com/kubewharf/godel-scheduler/pkg/version"
)

var metricsList = []metrics.Registerable{
	buildInfo,
	pendingPods,
	dispatcherGoroutines,
	// TODO add when dispatcher handling more app & queue events
	cacheSize,
	schedulerSize,
	nodePartitionSize,
	nodeInPartitionSize,
	podsInPartitionSize,

	e2eDispatchingLatency,
	e2eDispatchingLatencyQuantile,
	selectingSchedulerLatency,
	// TODO metrics this when DRF is done
	fairShareComputingLatency,
	podUpdatingLatency,
	podPendingLatency,

	dispatcherIncomingPods,
	dispatchedPods,
	dispatchingAttempts,
	podUpdatingAttempts,
	podShufflingCount,
	queueSortingLatency,
	orphanPodsResetTotal,

	pendingUnits,
	unitPendingDuration,
}

var registerMetrics sync.Once

// Register all metrics.
func Register() {
	// Register the metrics.
	registerMetrics.Do(func() {
		for _, metric := range metricsList {
			legacyregistry.MustRegister(metric)
		}
	})
	info := version.Get()
	buildInfo.WithLabelValues(info.Major, info.Minor, info.GitVersion, info.GitCommit, info.GitTreeState, info.BuildDate, info.GoVersion, info.Compiler, info.Platform).Set(1)

	// 关键：CounterVec 只在 With(labels).Inc() 首次调用时才把 series 具化到 registry。
	// 若某个 reason 的 reset 事件在极短时间内成批发生（例如 CR 删除事件一次性 enqueue
	// 几千个 orphan pod）, Prometheus 从没见过该 series 的 0 值样本, rate() 会因为
	// "只有一个采样点" 或 "首个采样点已是终值" 而算不出正增量, 导致下游判据看不到峰值。
	// 这里在启动时对每个已知 reason 做一次 Add(0), 让 series 从 0 起有连续采样, 之后
	// 事件真正发生时 rate() 就能正确报告变化速率。
	orphanPodsResetTotal.WithLabelValues("stale_dispatched").Add(0)
	orphanPodsResetTotal.WithLabelValues("abnormal").Add(0)
}
