---
description: "Use when renaming godel-related identifiers to eno across the codebase. Covers labels, annotations, constants, function names, type names, Kubernetes manifests, Prometheus metrics, and Docker images. Excludes external dependency paths."
applyTo: ["**/*.go", "**/*.yaml", "**/*.sh", "**/*.py", "**/*.tpl"]
---

# Godel → Eno Naming Refactor Instructions

## Goal

Replace all "godel" branding/naming identifiers with "eno" equivalents throughout the codebase.
**Only change naming — never alter logic, algorithms, or control flow.**

---

## Naming Mapping Rules

| Original Pattern | Replacement | Example |
|---|---|---|
| `godel` (lowercase) | `eno` | `godel-scheduler` → `eno-scheduler` |
| `Godel` (PascalCase) | `Eno` | `GodelScheduler` → `EnoScheduler` |
| `GODEL` (UPPER_CASE) | `ENO` | (if exists) |
| `godel.bytedance.com` | `eno.io` | annotation domain prefix |
| `godel-system` | `eno-system` | Kubernetes namespace |
| `godel-local` | `eno-local` | Docker image name |
| `godel:` (Prometheus prefix) | `eno:` | recording rule names |
| `godel-controller-manager` | `eno-controller-manager` | component names |
| `godel-bench` | `eno-bench` | Kind cluster name, node names in comments |
| `GODEL_IMAGE` | `ENO_IMAGE` | Shell variable names |
| `GODEL_NAMESPACE` | `ENO_NAMESPACE` | Shell variable names |
| `GODEL_SHARED_QUERIES` | `ENO_SHARED_QUERIES` | Shell variable names |
| `GODEL_EMBEDDED_QUERIES` | `ENO_EMBEDDED_QUERIES` | Shell variable names |
| `teardown_godel` | `teardown_eno` | Shell function names |
| `tong-godel` | `tong-eno` | Directory/repo display names |
| `99-godel-bench.conf` | `99-eno-bench.conf` | System config file names |
| `scheduling.godel.bytedance.com` | `scheduling.eno.io` | CRD annotation domain (gang scheduling) |
| `Gödel` (in log/comments) | `Eno` | Human-readable display text |
| `A (Godel)` | `A (Eno)` | Chart legend labels |

---

## MUST NOT Rename (Exclusion List)

These items reference external URLs, dependencies, or generated code that will break the build if renamed:

1. **Go module path**: `github.com/kubewharf/godel-scheduler` in `go.mod` line 1
2. **External dependency**: `github.com/kubewharf/godel-scheduler-api` (import path and all usages)
3. **All internal import paths**: e.g., `github.com/kubewharf/godel-scheduler/pkg/...` — these must match go.mod
4. **vendor/ directory**: Never modify anything under `vendor/`
5. **LICENSES/ directory**: Never modify license files
6. **go.sum**: Auto-generated, do not touch
7. **Generated code comments**: `// Code generated ... DO NOT EDIT` blocks
8. **CRD kind/apiVersion values** defined by `godel-scheduler-api`: e.g., `Scheduler`, `PodGroup` kinds — these come from the external API and must match
9. **CRD apiVersion strings**: `scheduling.godel.kubewharf.io/v1alpha1` — this is defined by the external `godel-scheduler-api` CRD, renaming it breaks CRD creation
10. **Third-party tool references** (e.g., `kubewharf` in GitHub URLs inside docs)
11. **Prometheus result JSON files** under `test/e2e/benchmark/results/` — these are collected data, not source code; metric label values like `job:"godel-scheduler"` in JSON are historical data
12. **podgen go.mod**: `github.com/kubewharf/godel-scheduler/test/e2e/benchmark/workloads/podgen` — module path must match root

### How to distinguish "rename" vs "don't rename"

- If the string is an **import path** matching `github.com/kubewharf/godel-scheduler...` → **DON'T rename**
- If the string is a **label value, annotation key, constant string, function name, type name, variable name, k8s resource name** → **RENAME**
- If the string is inside `vendor/` → **DON'T rename**

---

## Scope by Directory

### `pkg/` — Go source (RENAME)

| Area | What to Rename |
|---|---|
| `pkg/util/pod/podstate.go` | Function names: `DispatchedPodOfGodel` → `DispatchedPodOfEno`, etc. |
| `pkg/util/pod/util.go` | Annotation constants: `godel.bytedance.com/...` → `eno.io/...` |
| `pkg/features/godel_features.go` | Rename file to `eno_features.go`; update references |
| `pkg/framework/config/defaults.go` | `DefaultSchedulerName = "godel-scheduler"` → `"eno-scheduler"` |
| `pkg/scheduler/apis/config/types.go` | Type `GodelSchedulerConfiguration` → `EnoSchedulerConfiguration`; constants |
| `pkg/binder/apis/config/types.go` | Type `GodelBinderConfiguration` → `EnoBinderConfiguration` |
| `pkg/dispatcher/config/types.go` | Type `GodelDispatcherConfiguration` → `EnoDispatcherConfiguration` |
| `pkg/controller/apis/config/types.go` | Type `GodelControllerManagerConfiguration` → `EnoControllerManagerConfiguration` |
| `pkg/controller/clientbuilder/` | `godelClient`, `godelClientBuilder`, `SimpleGodelClientBuilder` → `eno` variants |
| `pkg/binder/metrics/` | Prometheus recording rule name prefix `godel:` → `eno:` |
| `pkg/scheduler/metrics/` | Same as above |

### `cmd/` — Entry points (RENAME)

| File | What to Rename |
|---|---|
| `cmd/scheduler/app/server.go` | `NewGodelSchedulerCmd` → `NewEnoSchedulerCmd`; component name |
| `cmd/binder/app/server.go` | `NewGodelBinderCmd` → `NewEnoBinderCmd` |
| `cmd/controller/app/controller_manager.go` | `NewGodelControllerCmd` → `NewEnoControllerCmd`; `ComponentName` |
| `cmd/scheduler/app/options/options.go` | Flag `--godel-scheduler-name` → `--eno-scheduler-name` |

### `manifests/` — Kubernetes YAML (RENAME)

| File | What to Rename |
|---|---|
| `manifests/base/namespace.yaml` | `godel-system` → `eno-system` |
| `manifests/base/deployment/*.yaml` | Labels `app: godel-*` → `app: eno-*`; namespace; image name |
| `manifests/monitoring/**/*.yaml` | Service names, Prometheus rule names, job labels |
| `manifests/overlays/**/*.yaml` | Namespace references, image patches |

### `docker/` — Build (RENAME)

| File | What to Rename |
|---|---|
| `docker/godel-local.Dockerfile` | Rename file to `eno-local.Dockerfile` if desired; update references |

### `hack/` and `Makefile` — Build scripts (RENAME)

| File | What to Rename |
|---|---|
| `hack/make-rules/local-up.sh` | Image name `godel-local` → `eno-local` |
| `Makefile` | If any target names reference godel |

### `test/e2e/benchmark/` — Benchmark & experiment scripts (RENAME)

#### Shell scripts — config & variables

| File | What to Rename |
|---|---|
| `config.sh` | `KIND_CLUSTER_NAME="godel-bench"` → `"eno-bench"`; `GODEL_IMAGE` → `ENO_IMAGE`; `GODEL_NAMESPACE` → `ENO_NAMESPACE`; scheduler names `"godel-scheduler"` → `"eno-scheduler"` |
| `setup-vm.sh` | `99-godel-bench.conf` → `99-eno-bench.conf`; `tong-godel` → `tong-eno`; display text |
| `setup-cluster.sh` | All `${GODEL_IMAGE}` references (auto-fixed by variable rename); Dockerfile path `godel-local.Dockerfile` → `eno-local.Dockerfile` |
| `run-experiment.sh` | Label selector `app=godel-scheduler` → `app=eno-scheduler`; `"Gödel Scheduler"` → `"Eno Scheduler"` |

#### Shell scripts — scheduler deploy & teardown

| File | What to Rename |
|---|---|
| `schedulers/deploy-group-a.sh` | `${GODEL_NAMESPACE}` (auto); log text `godel-scheduler` → `eno-scheduler` |
| `schedulers/deploy-group-b.sh` | Same; label selectors `app=godel-scheduler` → `app=eno-scheduler` |
| `schedulers/deploy-group-c.sh` | `${GODEL_NAMESPACE}` refs; variable `local_godel_running` → `local_eno_running`; log text |
| `schedulers/scale-schedulers.sh` | CLI flag `--godel-scheduler-name` → `--eno-scheduler-name`; inline YAML labels `app: godel-scheduler` → `app: eno-scheduler`; label key `godel-scheduler-name` → `eno-scheduler-name`; service account `godel` → `eno`; configmap `godel-scheduler-config` → `eno-scheduler-config`; scheduler name pattern `godel-scheduler-${idx}` → `eno-scheduler-${idx}` |
| `schedulers/teardown.sh` | Function `teardown_godel` → `teardown_eno`; comments with `Gödel` → `Eno` |

#### Workload templates (YAML)

| File | What to Rename |
|---|---|
| `workloads/templates/basic-pod.yaml.tpl` | Annotation keys: `godel.bytedance.com/pod-state` → `eno.io/pod-state` etc. |
| `workloads/templates/gang-pod.yaml.tpl` | Same; **KEEP** `apiVersion: scheduling.godel.kubewharf.io/v1alpha1` (CRD from external API); rename `scheduling.godel.bytedance.com/pod-group-name` → `scheduling.eno.io/pod-group-name` |

#### Pod generator (Go)

| File | What to Rename |
|---|---|
| `workloads/podgen/main.go` | Flag default `"godel-scheduler"` → `"eno-scheduler"`; case labels; annotation key strings; comments |
| `workloads/podgen/main_test.go` | Test function names `TestBuildBasicPod_GodelScheduler` → `TestBuildBasicPod_EnoScheduler`, `TestBuildGangPod_Godel` → `TestBuildGangPod_Eno`; all `flagScheduler = "godel-scheduler"` → `"eno-scheduler"`; annotation assertion strings; error messages |
| `workloads/podgen/main_v1_kubectl.go.bak` | Same patterns as main.go (backup file) |

#### Data collection scripts

| File | What to Rename |
|---|---|
| `collect/collect-distribution.sh` | Annotation key in jq: `godel.bytedance.com/selected-scheduler` → `eno.io/selected-scheduler` |
| `collect/export-prometheus.sh` | Variable names `GODEL_SHARED_QUERIES` → `ENO_SHARED_QUERIES`; `GODEL_EMBEDDED_QUERIES` → `ENO_EMBEDDED_QUERIES`; log text `Gödel` → `Eno` |

#### Prometheus query definitions (inside export-prometheus.sh)

All Prometheus recording rule names with `godel:` prefix → `eno:` prefix. Examples:
- `godel:scheduler_pod_scheduling_attempts:rate1m` → `eno:scheduler_pod_scheduling_attempts:rate1m`
- `godel:binder_embedded_bind_pods:rate1m` → `eno:binder_embedded_bind_pods:rate1m`
- (All other `godel:` prefixed rules follow same pattern)

#### Python visualization

| File | What to Rename |
|---|---|
| `collect/generate-final-thesis-charts.py` | Legend label `"A (Godel)"` → `"A (Eno)"`; all comparison summary text mentioning `Godel` → `Eno` |

#### Library functions

| File | What to Rename |
|---|---|
| `lib/cluster.sh` | Annotation keys in jq expressions: `godel.bytedance.com/scheduler-name` → `eno.io/scheduler-name`; comments mentioning `godel-scheduler` |

#### Result reports (Markdown) — OPTIONAL

| File | What to Rename |
|---|---|
| `results/report_*.md` | Cluster name `godel-bench` → `eno-bench` in headers |
| `results/final-charts/chart-index.md` | Comparison text `Godel` → `Eno` |

**NOTE**: Prometheus result JSON files under `results/` are historical data — do NOT modify them.

---

## Execution Order

Perform the rename in this order to minimize breakage:

1. **Constants and string literals first** — annotation keys, label values, scheduler names
2. **Type names** — `GodelSchedulerConfiguration` etc.
3. **Function names** — `NewGodelSchedulerCmd`, utility functions
4. **Variable names** — `godelClient`, `godelClientBuilder`
5. **File renames** — `godel_features.go` → `eno_features.go`
6. **Kubernetes manifests** — namespace, labels, service names, image names
7. **Build scripts and Dockerfile** — image names, script references
8. **Prometheus recording rules** — metric name prefixes in `manifests/monitoring/` and `test/e2e/benchmark/collect/export-prometheus.sh`
9. **Benchmark scripts** — `test/e2e/benchmark/config.sh` (variables), deploy scripts, workload templates
10. **Benchmark Go code** — `podgen/main.go`, `podgen/main_test.go` (flag defaults, case labels, annotations, test names)
11. **Data collection & visualization** — `collect/*.sh`, `collect/*.py` (variable names, jq annotation keys, chart labels)
12. **Result reports** (optional) — `results/report_*.md`, `results/final-charts/chart-index.md`

---

## Validation Checklist

After completing the rename:

1. **Compile check**: `go build ./...` must succeed
2. **Unit tests**: `go test ./pkg/... ./cmd/...` must pass
3. **Vet check**: `go vet ./...` must pass
4. **Grep audit (Go)**: `grep -r "godel" --include="*.go" | grep -v vendor/ | grep -v "github.com/kubewharf"` should return zero results outside allowed contexts
5. **Grep audit (YAML)**: `grep -r "godel" --include="*.yaml" manifests/` should return zero results
6. **Grep audit (shell)**: `grep -r "godel" --include="*.sh" test/e2e/benchmark/ | grep -v results/` should return zero results
7. **Grep audit (templates)**: `grep -r "godel" --include="*.tpl" test/e2e/benchmark/` should only contain CRD apiVersion (`scheduling.godel.kubewharf.io`)
8. **Grep audit (Python)**: `grep -ri "godel" --include="*.py" test/e2e/benchmark/` should return zero results
9. **Import check**: All `import` statements still reference `github.com/kubewharf/godel-scheduler/...` (unchanged)
10. **Podgen tests**: `cd test/e2e/benchmark/workloads/podgen && go test ./...` must pass
11. **Integration test**: If `test/e2e/` tests exist, run and verify they pass

---

## Safety Rules

- **Never modify files in `vendor/`** — these are managed by `go mod vendor`
- **Never change the go.mod module line** — this breaks all imports
- **Never change `godel-scheduler-api` references** — this is an external dependency
- **Preserve all existing test assertions** — only update string literals that match renamed identifiers
- **Test after EACH major step** (compile + unit tests) to catch breakage early
- **Use `git diff` to review changes** before committing