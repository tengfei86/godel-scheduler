// podgen — 高性能 Pod 批量生成与提交工具
//
// 核心设计:
//   1. 内存中渲染 YAML（零 fork，零磁盘 I/O）
//   2. 令牌桶 (Token Bucket) 精确速率控制，wallclock 绝对时间对齐
//   3. 双缓冲 Pipeline: 生成 goroutine → channel → 提交 goroutine 池
//   4. 批量 kubectl apply --server-side（减少 API Server RTT）
//
// 用法:
//   podgen -rate 500 -total 50000 -scheduler godel-scheduler -type basic \
//          -cpu 100 -mem 128 -namespace bench -image registry.k8s.io/pause:3.9 \
//          -batch 200 -workers 8

package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"math/rand"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// ── 命令行参数 ──
var (
	rate      int
	total     int
	scheduler string
	wtype     string
	cpu       int
	mem       int
	namespace string
	image     string
	batch     int
	workers   int
	gangSize  int
	dryRun    bool

	// burst 模式参数
	burstStages   string
	stageDuration int
)

func init() {
	flag.IntVar(&rate, "rate", 500, "目标速率 (pods/s)")
	flag.IntVar(&total, "total", 50000, "总 Pod 数量")
	flag.StringVar(&scheduler, "scheduler", "godel-scheduler", "schedulerName")
	flag.StringVar(&wtype, "type", "basic", "负载类型: basic|burst|gang|heterogeneous")
	flag.IntVar(&cpu, "cpu", 100, "CPU 请求 (millicores)")
	flag.IntVar(&mem, "mem", 128, "内存请求 (Mi)")
	flag.StringVar(&namespace, "namespace", "bench", "命名空间")
	flag.StringVar(&image, "image", "registry.k8s.io/pause:3.9", "Pause 镜像")
	flag.IntVar(&batch, "batch", 200, "每次 kubectl apply 的 Pod 数量")
	flag.IntVar(&workers, "workers", 8, "并发 kubectl apply 的 worker 数")
	flag.IntVar(&gangSize, "gang-size", 5, "Gang 调度每组 Pod 数量")
	flag.BoolVar(&dryRun, "dry-run", false, "仅生成 YAML 到 stdout，不执行 apply")

	flag.StringVar(&burstStages, "burst-stages", "200,500,1000,2000,1000,500,200", "burst 模式各阶段速率")
	flag.IntVar(&stageDuration, "stage-duration", 10, "burst 模式每阶段持续秒数")
}

// ── YAML 渲染 ──

// renderBasicPod 在内存中渲染一个 basic Pod YAML
// 每个文档以 "---\n" 开头，这在 multi-document YAML 中是标准做法
func renderBasicPod(buf *bytes.Buffer, idx int, ns, sched string, cpuM, memM int, img string) {
	fmt.Fprintf(buf, `---
apiVersion: v1
kind: Pod
metadata:
  name: bench-pod-%d
  namespace: %s
  annotations:
    godel.bytedance.com/pod-state: pending
    godel.bytedance.com/pod-resource-type: guaranteed
    godel.bytedance.com/pod-launcher: kubelet
spec:
  schedulerName: %s
  terminationGracePeriodSeconds: 0
  containers:
    - name: app
      image: %s
      resources:
        requests:
          cpu: "%dm"
          memory: "%dMi"
        limits:
          cpu: "%dm"
          memory: "%dMi"
`, idx, ns, sched, img, cpuM, memM, cpuM, memM)
}

// renderVolcanoPod 渲染 Volcano 模式的 basic Pod
func renderVolcanoPod(buf *bytes.Buffer, idx int, ns, sched string, cpuM, memM int, img string) {
	fmt.Fprintf(buf, `---
apiVersion: v1
kind: Pod
metadata:
  name: bench-pod-%d
  namespace: %s
  annotations:
    scheduling.volcano.sh/group-name: bench-basic-pg
spec:
  schedulerName: %s
  terminationGracePeriodSeconds: 0
  containers:
    - name: app
      image: %s
      resources:
        requests:
          cpu: "%dm"
          memory: "%dMi"
        limits:
          cpu: "%dm"
          memory: "%dMi"
`, idx, ns, sched, img, cpuM, memM, cpuM, memM)
}

type podRenderer func(buf *bytes.Buffer, idx int, ns, sched string, cpuM, memM int, img string)

func selectRenderer() podRenderer {
	if scheduler == "volcano" {
		return renderVolcanoPod
	}
	return renderBasicPod
}

// ── Gang YAML 渲染 ──

func renderGangGroup(buf *bytes.Buffer, groupIdx, gSize int, ns, sched string, cpuM, memM int, img string) {
	// PodGroup（以 --- 开头）
	switch scheduler {
	case "volcano":
		fmt.Fprintf(buf, `---
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: bench-gang-%d
  namespace: %s
spec:
  minMember: %d
`, groupIdx, ns, gSize)
	case "koord-scheduler":
		fmt.Fprintf(buf, `---
apiVersion: scheduling.sigs.k8s.io/v1alpha1
kind: PodGroup
metadata:
  name: bench-gang-%d
  namespace: %s
spec:
  minMember: %d
  scheduleTimeoutSeconds: 300
`, groupIdx, ns, gSize)
	default: // godel
		fmt.Fprintf(buf, `---
apiVersion: scheduling.godel.kubewharf.io/v1alpha1
kind: PodGroup
metadata:
  name: bench-gang-%d
  namespace: %s
spec:
  minMember: %d
`, groupIdx, ns, gSize)
	}

	// Member Pods
	for m := 1; m <= gSize; m++ {
		buf.WriteString("---\n")
		switch scheduler {
		case "volcano":
			fmt.Fprintf(buf, `apiVersion: v1
kind: Pod
metadata:
  name: bench-gang-%d-%d
  namespace: %s
  annotations:
    scheduling.volcano.sh/group-name: bench-gang-%d
spec:
  schedulerName: %s
  terminationGracePeriodSeconds: 0
  containers:
    - name: app
      image: %s
      resources:
        requests:
          cpu: "%dm"
          memory: "%dMi"
        limits:
          cpu: "%dm"
          memory: "%dMi"
`, groupIdx, m, ns, groupIdx, sched, img, cpuM, memM, cpuM, memM)
		case "koord-scheduler":
			fmt.Fprintf(buf, `apiVersion: v1
kind: Pod
metadata:
  name: bench-gang-%d-%d
  namespace: %s
  labels:
    pod-group.scheduling.sigs.k8s.io: bench-gang-%d
spec:
  schedulerName: %s
  terminationGracePeriodSeconds: 0
  containers:
    - name: app
      image: %s
      resources:
        requests:
          cpu: "%dm"
          memory: "%dMi"
        limits:
          cpu: "%dm"
          memory: "%dMi"
`, groupIdx, m, ns, groupIdx, sched, img, cpuM, memM, cpuM, memM)
		default: // godel
			fmt.Fprintf(buf, `apiVersion: v1
kind: Pod
metadata:
  name: bench-gang-%d-%d
  namespace: %s
  annotations:
    godel.bytedance.com/pod-state: pending
    godel.bytedance.com/pod-resource-type: guaranteed
    godel.bytedance.com/pod-launcher: kubelet
    scheduling.godel.bytedance.com/pod-group-name: bench-gang-%d
spec:
  schedulerName: %s
  terminationGracePeriodSeconds: 0
  containers:
    - name: app
      image: %s
      resources:
        requests:
          cpu: "%dm"
          memory: "%dMi"
        limits:
          cpu: "%dm"
          memory: "%dMi"
`, groupIdx, m, ns, groupIdx, sched, img, cpuM, memM, cpuM, memM)
		}
	}
}

// ── 异构资源规格 ──
type heteroSpec struct {
	cpu, mem int
}

var heteroSpecs = []struct {
	weight int
	spec   heteroSpec
}{
	{30, heteroSpec{50, 64}},     // 30% 小
	{40, heteroSpec{200, 256}},   // 40% 中
	{20, heteroSpec{1000, 1024}}, // 20% 大
	{10, heteroSpec{4000, 8192}}, // 10% 超大
}

func randomHeteroSpec(rng *rand.Rand) heteroSpec {
	r := rng.Intn(100)
	cumulative := 0
	for _, h := range heteroSpecs {
		cumulative += h.weight
		if r < cumulative {
			return h.spec
		}
	}
	return heteroSpecs[0].spec
}

// ── 提交管道 ──

type yamlBatch struct {
	data []byte
	size int // Pod 数量
}

// applyWorker 从 channel 读取 YAML 批次，执行 kubectl apply
func applyWorker(ctx context.Context, ch <-chan yamlBatch, submitted *atomic.Int64, errors *atomic.Int64, wg *sync.WaitGroup) {
	defer wg.Done()
	for {
		select {
		case <-ctx.Done():
			return
		case batch, ok := <-ch:
			if !ok {
				return
			}
			if dryRun {
				os.Stdout.Write(batch.data)
				submitted.Add(int64(batch.size))
				continue
			}
			cmd := exec.CommandContext(ctx, "kubectl", "apply", "--server-side=true", "--force-conflicts", "-f", "-")
			cmd.Stdin = bytes.NewReader(batch.data)
			var stderr bytes.Buffer
			cmd.Stderr = &stderr
			if err := cmd.Run(); err != nil {
				// 对 apply 失败做重试
				retryCmd := exec.CommandContext(ctx, "kubectl", "apply", "-f", "-")
				retryCmd.Stdin = bytes.NewReader(batch.data)
				if retryErr := retryCmd.Run(); retryErr != nil {
					errors.Add(int64(batch.size))
					fmt.Fprintf(os.Stderr, "[ERROR] kubectl apply failed (%d pods): %s\n", batch.size, stderr.String())
					continue
				}
			}
			submitted.Add(int64(batch.size))
		}
	}
}

// ── 速率控制器 (Token Bucket on wallclock) ──
//
// 关键设计: 基于绝对时间计算应发送的总量，而非相对 sleep。
// 这意味着如果某秒内 apply 较慢导致累积，下一秒会自动追赶，
// 最终保证整体平均速率精确。

type rateLimiter struct {
	startTime time.Time
	rate      float64 // pods/s
	sent      int64   // 已调度发送的数量
}

func newRateLimiter(r int) *rateLimiter {
	return &rateLimiter{
		startTime: time.Now(),
		rate:      float64(r),
	}
}

// waitForSlot 阻塞直到可以发送下一批（最多 n 个）
// 返回实际允许发送的数量
func (rl *rateLimiter) waitForSlot(ctx context.Context, n int) (int, error) {
	for {
		select {
		case <-ctx.Done():
			return 0, ctx.Err()
		default:
		}

		elapsed := time.Since(rl.startTime).Seconds()
		allowed := int64(elapsed*rl.rate) + 1 // +1 避免启动空转
		budget := int(allowed - rl.sent)

		if budget <= 0 {
			// 精确 sleep：等到下一个 token 可用
			nextTokenAt := float64(rl.sent) / rl.rate
			sleepDur := time.Duration((nextTokenAt - elapsed) * float64(time.Second))
			if sleepDur < time.Millisecond {
				sleepDur = time.Millisecond
			}
			select {
			case <-ctx.Done():
				return 0, ctx.Err()
			case <-time.After(sleepDur):
			}
			continue
		}

		if budget > n {
			budget = n
		}
		rl.sent += int64(budget)
		return budget, nil
	}
}

// changeRate 动态调整速率（用于 burst 模式）
func (rl *rateLimiter) changeRate(newRate int) {
	rl.rate = float64(newRate)
}

// ── 进度打印 ──

func progressPrinter(ctx context.Context, submitted *atomic.Int64, errors *atomic.Int64, totalTarget int) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	start := time.Now()
	lastSubmitted := int64(0)
	lastTime := start

	for {
		select {
		case <-ctx.Done():
			return
		case now := <-ticker.C:
			cur := submitted.Load()
			errs := errors.Load()
			elapsed := now.Sub(start).Seconds()
			avgRate := float64(cur) / elapsed

			// 瞬时速率 (2s 窗口)
			dt := now.Sub(lastTime).Seconds()
			instantRate := float64(cur-lastSubmitted) / dt
			lastSubmitted = cur
			lastTime = now

			pct := float64(cur) * 100.0 / float64(totalTarget)
			fmt.Fprintf(os.Stderr, "\r[PROGRESS] %d/%d (%.1f%%) | avg %.0f pods/s | instant %.0f pods/s | errors %d   ",
				cur, totalTarget, pct, avgRate, instantRate, errs)
		}
	}
}

// ── 主流程 ──

func main() {
	flag.Parse()

	// 创建 namespace（幂等）
	if !dryRun {
		nsCmd := exec.Command("kubectl", "create", "namespace", namespace, "--dry-run=client", "-o", "yaml")
		var nsBuf bytes.Buffer
		nsCmd.Stdout = &nsBuf
		nsCmd.Run()
		applyCmd := exec.Command("kubectl", "apply", "-f", "-")
		applyCmd.Stdin = &nsBuf
		applyCmd.Run()
	}

	// Volcano passthrough PodGroup
	if scheduler == "volcano" && wtype != "gang" && !dryRun {
		ensureVolcanoPassthroughPG()
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 信号处理
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		fmt.Fprintf(os.Stderr, "\n[INFO] 收到中断信号，正在停止...\n")
		cancel()
	}()

	fmt.Fprintf(os.Stderr, "[INFO] podgen 启动: rate=%d/s, total=%d, scheduler=%s, type=%s, batch=%d, workers=%d\n",
		rate, total, scheduler, wtype, batch, workers)

	startTime := time.Now()

	switch wtype {
	case "basic":
		runBasic(ctx)
	case "burst":
		runBurst(ctx)
	case "gang":
		runGang(ctx)
	case "heterogeneous":
		runHeterogeneous(ctx)
	default:
		fmt.Fprintf(os.Stderr, "[ERROR] 未知负载类型: %s\n", wtype)
		os.Exit(1)
	}

	elapsed := time.Since(startTime)
	fmt.Fprintf(os.Stderr, "\n[INFO] ✓ 完成: %d pods, 耗时 %v, 平均 %.0f pods/s\n",
		total, elapsed.Round(time.Second), float64(total)/elapsed.Seconds())
}

func ensureVolcanoPassthroughPG() {
	yaml := `apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: bench-basic-pg
  namespace: ` + namespace + `
spec:
  minMember: 1`
	cmd := exec.Command("kubectl", "apply", "-f", "-")
	cmd.Stdin = strings.NewReader(yaml)
	cmd.Run()
}

// ── basic 模式 ──
func runBasic(ctx context.Context) {
	ch := make(chan yamlBatch, workers*4)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	// 启动 workers
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go applyWorker(ctx, ch, &submitted, &errors, &wg)
	}

	// 进度
	go progressPrinter(ctx, &submitted, &errors, total)

	render := selectRenderer()
	rl := newRateLimiter(rate)
	remaining := total

	for remaining > 0 {
		// 请求一批 token
		want := batch
		if want > remaining {
			want = remaining
		}
		got, err := rl.waitForSlot(ctx, want)
		if err != nil {
			break
		}

		// 渲染 YAML（每个 render 函数自带 --- 前缀）
		var buf bytes.Buffer
		buf.Grow(got * 350) // 预分配：每个 Pod 约 300 字节
		for i := 0; i < got; i++ {
			podIdx := total - remaining + i + 1
			render(&buf, podIdx, namespace, scheduler, cpu, mem, image)
		}

		remaining -= got

		select {
		case ch <- yamlBatch{data: buf.Bytes(), size: got}:
		case <-ctx.Done():
			remaining = 0
		}
	}

	close(ch)
	wg.Wait()
}

// ── burst 模式 ──
func runBurst(ctx context.Context) {
	// 解析阶段速率
	stageRates := parseStages(burstStages)

	ch := make(chan yamlBatch, workers*4)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go applyWorker(ctx, ch, &submitted, &errors, &wg)
	}

	go progressPrinter(ctx, &submitted, &errors, total)

	render := selectRenderer()
	rl := newRateLimiter(stageRates[0])
	remaining := total
	globalIdx := 0

	for _, stageRate := range stageRates {
		if remaining <= 0 {
			break
		}
		fmt.Fprintf(os.Stderr, "\n[INFO] 阶段: %d pods/s × %ds\n", stageRate, stageDuration)
		rl.changeRate(stageRate)
		stageEnd := time.Now().Add(time.Duration(stageDuration) * time.Second)

		for time.Now().Before(stageEnd) && remaining > 0 {
			want := batch
			if want > remaining {
				want = remaining
			}
			got, err := rl.waitForSlot(ctx, want)
			if err != nil {
				remaining = 0
				break
			}

			var buf bytes.Buffer
			buf.Grow(got * 350)
			for i := 0; i < got; i++ {
				globalIdx++
				render(&buf, globalIdx, namespace, scheduler, cpu, mem, image)
			}
			remaining -= got

			select {
			case ch <- yamlBatch{data: buf.Bytes(), size: got}:
			case <-ctx.Done():
				remaining = 0
			}
		}
	}

	close(ch)
	wg.Wait()
}

// ── gang 模式 ──
func runGang(ctx context.Context) {
	totalGroups := total / gangSize
	groupRate := rate / gangSize
	if groupRate < 1 {
		groupRate = 1
	}

	ch := make(chan yamlBatch, workers*4)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go applyWorker(ctx, ch, &submitted, &errors, &wg)
	}

	go progressPrinter(ctx, &submitted, &errors, total)

	// 对于 gang，batch 按 group 数量算
	groupBatch := batch / gangSize
	if groupBatch < 1 {
		groupBatch = 1
	}

	rl := newRateLimiter(groupRate)
	remaining := totalGroups

	for remaining > 0 {
		want := groupBatch
		if want > remaining {
			want = remaining
		}
		got, err := rl.waitForSlot(ctx, want)
		if err != nil {
			break
		}

		var buf bytes.Buffer
		buf.Grow(got * gangSize * 400)
		for g := 0; g < got; g++ {
			groupIdx := totalGroups - remaining + g + 1
			renderGangGroup(&buf, groupIdx, gangSize, namespace, scheduler, cpu, mem, image)
		}
		remaining -= got

		podCount := got * gangSize
		select {
		case ch <- yamlBatch{data: buf.Bytes(), size: podCount}:
		case <-ctx.Done():
			remaining = 0
		}
	}

	close(ch)
	wg.Wait()
}

// ── heterogeneous 模式 ──
func runHeterogeneous(ctx context.Context) {
	ch := make(chan yamlBatch, workers*4)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go applyWorker(ctx, ch, &submitted, &errors, &wg)
	}

	go progressPrinter(ctx, &submitted, &errors, total)

	render := selectRenderer()
	rl := newRateLimiter(rate)
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	remaining := total

	for remaining > 0 {
		want := batch
		if want > remaining {
			want = remaining
		}
		got, err := rl.waitForSlot(ctx, want)
		if err != nil {
			break
		}

		var buf bytes.Buffer
		buf.Grow(got * 350)
		for i := 0; i < got; i++ {
			podIdx := total - remaining + i + 1
			spec := randomHeteroSpec(rng)
			render(&buf, podIdx, namespace, scheduler, spec.cpu, spec.mem, image)
		}
		remaining -= got

		select {
		case ch <- yamlBatch{data: buf.Bytes(), size: got}:
		case <-ctx.Done():
			remaining = 0
		}
	}

	close(ch)
	wg.Wait()
}

// ── 工具函数 ──

func parseStages(s string) []int {
	parts := strings.Split(s, ",")
	stages := make([]int, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		var v int
		fmt.Sscanf(p, "%d", &v)
		if v > 0 {
			stages = append(stages, v)
		}
	}
	if len(stages) == 0 {
		stages = []int{200, 500, 1000, 2000, 1000, 500, 200}
	}
	return stages
}
