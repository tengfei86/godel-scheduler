# Benchmark 测试指南

## 快速验证（Smoke Test）

在 kind 集群上验证命名改动或代码变更是否正常工作。

### 前置条件

- Docker（推荐 WSL2 backend）
- kind >= v0.20
- kubectl
- jq、curl

```bash
# 检查工具链
docker version && kind version && kubectl version --client && jq --version
```

> **性能提示**: 在 WSL2 中建议将项目放在 Linux 原生文件系统（`~/dev/`），而非 `/mnt/c/`，编译和镜像构建速度可提升 10-50 倍。

### 前置：确保 kind 容器能访问外网（新装机器/VM 必查）

**症状**：VM 上 `docker pull xxx` 能拉，但 kind 集群里 Pod 卡在 `ImagePullBackOff`，`crictl pull` 报 `i/o timeout`。

**根因**：kind 节点是 Docker 容器，出向流量走 Linux 内核 FORWARD 链。以下两项**必须**同时满足：

1. `net.ipv4.ip_forward=1`（内核允许包转发）
2. `iptables FORWARD` 默认策略为 `ACCEPT`（不静默丢包）

某些云厂商基线镜像（AWS EC2、部分公有云硬化 Ubuntu）默认关闭 forwarding 或把 FORWARD 设为 DROP，Docker 启动时不会自动改。

**诊断**：

```bash
sysctl net.ipv4.ip_forward
sudo iptables -L FORWARD -n | head -1
```

预期输出：
```
net.ipv4.ip_forward = 1
Chain FORWARD (policy ACCEPT)
```

如果看到 `0` 或 `policy DROP`，走下面的修复。

**一次性修复**：

```bash
# 1. 打开 IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# 2. FORWARD 默认策略改为 ACCEPT
sudo iptables -P FORWARD ACCEPT

# 3. 立即验证 kind 节点能出网
docker exec eno-bench-control-plane bash -c '
  timeout 5 curl -sS -o /dev/null -w "http_code=%{http_code}\n" -k https://1.1.1.1/
'
# 预期: http_code=301 (或任何非 000 的值)
```

**持久化**（重启不丢）：

```bash
# sysctl 持久化
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-docker-kind.conf
sudo sysctl -p /etc/sysctl.d/99-docker-kind.conf

# iptables 持久化（Ubuntu）
sudo apt install -y iptables-persistent
sudo netfilter-persistent save
```

> **为什么 Docker 官方要求 FORWARD 默认 ACCEPT**：Docker 假设它插入的规则会先命中；如果 FORWARD 默认 DROP，说明系统不是设计给容器 workload 用的。跑容器的机器上 `FORWARD ACCEPT` 是正常状态。参考 [Docker 官方 iptables 说明](https://docs.docker.com/engine/network/packet-filtering-firewalls/)。

### Step 1: 搭建集群

创建 kind 集群 + KWOK 模拟节点 + 构建最新镜像：

```bash
cd test/e2e/benchmark
bash setup-cluster.sh --rebuild-image s1
```

| 参数              | 说明                                 |
| ----------------- | ------------------------------------ |
| `s1`              | 100 个 KWOK 节点（最小规模，验证用） |
| `--rebuild-image` | 强制重新编译代码并构建 Docker 镜像   |
| `--force-rebuild` | 销毁已有集群并重新创建               |

### Step 2: 部署调度器

```bash
# 组 B — Embedded Binder（论文提出的架构）
bash schedulers/deploy-group-b.sh

# 或组 A — Shared Binder（Baseline）
bash schedulers/deploy-group-a.sh
```

### Step 3: 验证组件就绪

```bash
kubectl get pods -n eno-system
```

预期所有 Pod 状态为 `Running`（Binder 在组 B 中 replicas=0，不会出现）。

### Step 4: 提交测试 Pod

```bash
kubectl create namespace bench 2>/dev/null || true
kubectl run smoke-test --image=registry.k8s.io/pause:3.9 \
  --restart=Never \
  --overrides='{"spec":{"schedulerName":"eno-scheduler"}}' \
  -n bench
```

### Step 5: 检查调度结果

```bash
kubectl get pod smoke-test -n bench -o wide
```

预期 Pod 状态为 `Running`，且 `NODE` 列显示被分配到某个 KWOK 节点。

### 排查

如果 Pod 卡在 `Pending`：

```bash
# 查看调度器日志
kubectl logs -n eno-system deployment/scheduler --tail=50

# 查看 Dispatcher 日志
kubectl logs -n eno-system deployment/dispatcher --tail=50

# 查看事件
kubectl get events -n bench --field-selector reason=FailedScheduling
```

### 清理

```bash
kubectl delete namespace bench
bash schedulers/teardown.sh
kind delete cluster --name eno-bench
```

---

## 完整对比测试

### 小规模快速对比（组 A vs B）

```bash
bash run-all.sh --groups "a b" --scales "s1" --workloads "w1" --runs 1
```

### 中等规模多负载

```bash
bash run-all.sh --groups "a b" --scales "s2" --workloads "w1 w2 w3" --runs 3
```

### 水平扩展测试

```bash
bash run-all.sh --groups "a b" --scales "s3" --workloads "w3" --instances "1 2 3 5"
```

### 预览执行计划（不实际运行）

```bash
bash run-all.sh --dry-run
```

---

## 仅重建镜像（不重建集群）

当只修改了代码、需要更新镜像时：

```bash
cd /path/to/godel-scheduler

# 编译
GO_BUILD_PLATFORMS=linux/amd64 make build

# 构建镜像
docker build --no-cache -f docker/eno-local.Dockerfile -t eno-local:latest .

# 加载到 kind
kind load docker-image eno-local:latest --name eno-bench

# 重启 deployment
kubectl rollout restart deployment -n eno-system
```
