# Group A — Gödel Scheduler (Baseline)

This overlay deploys the **original upstream godel-scheduler** (unmodified) for baseline comparison.

## Build the godel-scheduler image

```bash
# Clone upstream repo
git clone https://github.com/kubewharf/godel-scheduler.git /tmp/godel-upstream
cd /tmp/godel-upstream

# Build Docker image
docker build -t godel-local:latest -f docker/godel-local.Dockerfile .

# Or if using the Makefile:
# make docker-build IMAGE=godel-local:latest
```

## Key differences from eno (Group B)

| Aspect            | Group A (Original Gödel)      | Group B (Eno / Embedded Binder) |
| ----------------- | ----------------------------- | ------------------------------- |
| Image             | `godel-local:latest`          | `eno-local:latest`              |
| Namespace         | `godel-system`                | `eno-system`                    |
| Scheduler Name    | `godel-scheduler`             | `eno-scheduler`                 |
| Annotation Domain | `godel.bytedance.com`         | `eno.io`                        |
| Binder            | Standalone (shared)           | Embedded in Scheduler           |
| Config Kind       | `GodelSchedulerConfiguration` | `EnoSchedulerConfiguration`     |

## Usage

```bash
# Deploy Group A
bash test/e2e/benchmark/schedulers/deploy-group-a.sh

# With multiple scheduler instances
bash test/e2e/benchmark/schedulers/deploy-group-a.sh --instances 3
```
