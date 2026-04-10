#!/usr/bin/env bash
# setup-vm.sh — 在全新 Ubuntu 22.04 VM 上一键安装所有实验依赖
#
# 用法 (以 root 或 sudo 执行):
#   curl -sSL <raw-url>/setup-vm.sh | bash
#   或:
#   bash setup-vm.sh [--with-repo <git-clone-url>]
#
# 安装清单:
#   - 基础工具: git, jq, curl, wget, make, gcc, unzip, bash-completion
#   - 终端工具: tmux, htop, tree, sysstat
#   - Docker CE (最新稳定版)
#   - Go 1.21.13
#   - kubectl (v1.29.x)
#   - kind (最新稳定版)
#   - Helm 3
#   - KWOK CLI (最新稳定版)
#   - Python 3 + pip + matplotlib/pandas/scipy (数据分析)
#
# 适配:
#   - Ubuntu 22.04 LTS (amd64)
#   - 需要 root 权限（或 sudo）
#
# 硬件建议（论文实验）:
#   - CPU: ≥ 48 vCPU (推荐 64)
#   - 内存: ≥ 128 GB (推荐 192 GB, 30K 节点时 etcd 可达 60-80GB)
#   - 存储: ≥ 500 GB NVMe SSD
#
# 测试完成后的下一步:
#   1. git clone <repo> && cd tong-godel
#   2. cd test/e2e/benchmark
#   3. bash setup-cluster.sh --rebuild-image s2
#   4. bash schedulers/deploy-group-b.sh
#   5. bash run-experiment.sh b s2 w1 1

set -euo pipefail

# ── 配置 ──
GO_VERSION="1.21.13"
KUBECTL_VERSION="v1.29.12"
KIND_VERSION=""            # 空 = 最新稳定版
HELM_VERSION=""            # 空 = 最新稳定版

# ── 颜色 ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_step()  { echo -e "${GREEN}[STEP]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── 检测架构 ──
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  GOARCH="amd64"; ARCH_ALT="amd64" ;;
  aarch64) GOARCH="arm64";  ARCH_ALT="arm64" ;;
  *)       log_error "不支持的架构: $ARCH"; exit 1 ;;
esac

# ── 参数解析 ──
GIT_REPO=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --with-repo) GIT_REPO="$2"; shift 2 ;;
    *)           log_warn "未知参数: $1"; shift ;;
  esac
done

# ═══════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════"
echo "  Gödel Scheduler — VM 环境初始化脚本"
echo "  OS: Ubuntu 22.04 LTS ($ARCH)"
echo "══════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════
# Step 1: 系统更新 & 基础包
# ═══════════════════════════════════════════════
log_step "Step 1/8: 安装基础包"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  git curl wget jq make gcc g++ unzip \
  bash-completion ca-certificates gnupg lsb-release \
  software-properties-common apt-transport-https \
  python3 python3-pip python3-venv \
  sysstat htop tmux tree > /dev/null

log_info "✓ 基础包安装完成"

# ═══════════════════════════════════════════════
# Step 2: Docker CE
# ═══════════════════════════════════════════════
log_step "Step 2/8: 安装 Docker CE"
if command -v docker &>/dev/null; then
  log_info "Docker 已安装: $(docker --version)"
else
  # 添加 Docker 官方 GPG key 和 apt repo
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=${ARCH_ALT} signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin > /dev/null

  # 将当前用户（如非 root）加入 docker 组
  if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "$SUDO_USER"
    log_info "已将 ${SUDO_USER} 加入 docker 组（需重新登录生效）"
  fi

  systemctl enable docker
  systemctl start docker
  log_info "✓ Docker CE 安装完成: $(docker --version)"
fi

# Docker 守护进程调优（大规模测试）
mkdir -p /etc/docker
if [[ ! -f /etc/docker/daemon.json ]] || ! grep -q "max-concurrent-downloads" /etc/docker/daemon.json 2>/dev/null; then
  cat > /etc/docker/daemon.json <<'EOF'
{
  "max-concurrent-downloads": 20,
  "max-concurrent-uploads": 20,
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF
  systemctl restart docker
  log_info "✓ Docker daemon 调优完成"
fi

# ═══════════════════════════════════════════════
# Step 3: Go
# ═══════════════════════════════════════════════
log_step "Step 3/8: 安装 Go ${GO_VERSION}"
if command -v go &>/dev/null && go version | grep -q "go${GO_VERSION}"; then
  log_info "Go 已安装: $(go version)"
else
  GO_TAR="go${GO_VERSION}.linux-${GOARCH}.tar.gz"
  wget -q "https://go.dev/dl/${GO_TAR}" -O "/tmp/${GO_TAR}"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "/tmp/${GO_TAR}"
  rm -f "/tmp/${GO_TAR}"

  # 写入全局 profile
  cat > /etc/profile.d/go.sh <<'GOEOF'
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
GOEOF
  # 当前 session 也生效
  export GOROOT=/usr/local/go
  export GOPATH=$HOME/go
  export PATH=$GOROOT/bin:$GOPATH/bin:$PATH

  log_info "✓ Go 安装完成: $(go version)"
fi

# ═══════════════════════════════════════════════
# Step 4: kubectl
# ═══════════════════════════════════════════════
log_step "Step 4/8: 安装 kubectl ${KUBECTL_VERSION}"
if command -v kubectl &>/dev/null; then
  log_info "kubectl 已安装: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
  curl -fsSLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${GOARCH}/kubectl"
  chmod +x /usr/local/bin/kubectl
  log_info "✓ kubectl 安装完成: $(kubectl version --client --short 2>/dev/null || true)"
fi

# kubectl bash 补全
kubectl completion bash > /etc/bash_completion.d/kubectl 2>/dev/null || true

# ═══════════════════════════════════════════════
# Step 5: kind
# ═══════════════════════════════════════════════
log_step "Step 5/8: 安装 kind"
if command -v kind &>/dev/null; then
  log_info "kind 已安装: $(kind version)"
else
  if [[ -n "$KIND_VERSION" ]]; then
    KIND_URL="https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${GOARCH}"
  else
    KIND_URL="https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-linux-${GOARCH}"
  fi
  curl -fsSLo /usr/local/bin/kind "$KIND_URL"
  chmod +x /usr/local/bin/kind
  log_info "✓ kind 安装完成: $(kind version)"
fi

# ═══════════════════════════════════════════════
# Step 6: Helm 3
# ═══════════════════════════════════════════════
log_step "Step 6/8: 安装 Helm 3"
if command -v helm &>/dev/null; then
  log_info "Helm 已安装: $(helm version --short)"
else
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  log_info "✓ Helm 安装完成: $(helm version --short)"
fi

# 添加常用 chart repo
helm repo add volcano-sh https://volcano-sh.github.io/charts 2>/dev/null || true
helm repo add koordinator-sh https://koordinator-sh.github.io/charts 2>/dev/null || true
helm repo update 2>/dev/null || true
log_info "✓ Helm repo (volcano-sh, koordinator-sh) 已添加"

# ═══════════════════════════════════════════════
# Step 7: Python 数据分析环境
# ═══════════════════════════════════════════════
log_step "Step 7/8: 安装 Python 数据分析依赖"
pip3 install -q --break-system-packages \
  matplotlib seaborn pandas numpy scipy 2>/dev/null || \
pip3 install -q \
  matplotlib seaborn pandas numpy scipy
log_info "✓ Python 数据分析包安装完成"

# ═══════════════════════════════════════════════
# Step 8: 系统调优（大规模集群必需）
# ═══════════════════════════════════════════════
log_step "Step 8/8: 系统内核参数调优"

# sysctl 调优
SYSCTL_CONF="/etc/sysctl.d/99-godel-bench.conf"
cat > "$SYSCTL_CONF" <<'EOF'
# inotify — kind 多节点需要大量 watch
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 8192

# 文件描述符
fs.file-max = 2097152
fs.nr_open = 1048576

# 网络连接 (大量 kubectl 并发)
net.core.somaxconn = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.netfilter.nf_conntrack_max = 1048576
net.core.netdev_max_backlog = 65535

# 内存 (etcd + API Server 大规模)
vm.max_map_count = 262144
vm.overcommit_memory = 1
EOF
sysctl --system > /dev/null 2>&1

# ulimits
LIMITS_CONF="/etc/security/limits.d/99-godel-bench.conf"
cat > "$LIMITS_CONF" <<'EOF'
*  soft  nofile  1048576
*  hard  nofile  1048576
*  soft  nproc   unlimited
*  hard  nproc   unlimited
EOF

log_info "✓ 系统参数调优完成"

# ═══════════════════════════════════════════════
# 可选: 克隆仓库
# ═══════════════════════════════════════════════
if [[ -n "$GIT_REPO" ]]; then
  CLONE_DIR="/root/tong-godel"
  if [[ -d "$CLONE_DIR" ]]; then
    log_info "仓库已存在: $CLONE_DIR"
  else
    log_step "克隆仓库..."
    git clone "$GIT_REPO" "$CLONE_DIR"
    log_info "✓ 仓库已克隆到 $CLONE_DIR"
  fi
fi

# ═══════════════════════════════════════════════
# 汇总
# ═══════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════"
echo "  ✓ 环境初始化完成"
echo "══════════════════════════════════════════════"
echo ""
echo "  已安装:"
echo "    Docker   : $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
echo "    Go       : $(go version 2>/dev/null | awk '{print $3}')"
echo "    tmux     : $(tmux -V 2>/dev/null | awk '{print $2}')"
echo "    kubectl  : ${KUBECTL_VERSION}"
echo "    kind     : $(kind version 2>/dev/null)"
echo "    Helm     : $(helm version --short 2>/dev/null)"
echo "    Python3  : $(python3 --version 2>/dev/null | awk '{print $2}')"
echo ""
echo "  系统调优: ✓ (inotify/ulimit/conntrack/vm)"
echo "  Helm repos: volcano-sh, koordinator-sh"
echo ""
echo "  下一步操作:"
echo "    1. 上传或克隆项目代码"
echo "    2. cd tong-godel/test/e2e/benchmark"
echo "    3. bash setup-cluster.sh --rebuild-image s2"
echo "    4. bash schedulers/deploy-group-a.sh   # 或 b/c/d/e"
echo "    5. bash run-experiment.sh a s2 w1 1"
echo ""
if [[ -n "${SUDO_USER:-}" ]]; then
  echo "  ⚠ 请重新登录以使 docker 组生效: su - ${SUDO_USER}"
fi
echo ""
