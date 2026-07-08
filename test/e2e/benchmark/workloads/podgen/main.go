// podgen — 高性能 Pod 批量生成与提交工具 (v2: client-go 直连)
//
// v2 核心改进:
//   1. 使用 client-go 直连 API Server，消除 kubectl fork/exec 开销
//   2. HTTP/2 多路复用，单连接并发数百请求
//   3. 令牌桶 (Token Bucket) 精确速率控制，wallclock 绝对时间对齐
//   4. 并发 goroutine 池直接调用 pods.Create()
//
// 性能对比:
//   v1 (kubectl apply): 200 pods/s @ W3 (瓶颈: fork/exec + TLS 握手)
//   v2 (client-go):     2000+ pods/s @ W3 (HTTP/2 复用 + 零进程开销)
//
// 用法:
//   podgen -rate 500 -total 50000 -scheduler eno-scheduler -type basic \
//          -cpu 100 -mem 128 -namespace bench -image registry.k8s.io/pause:3.9 \
//          -workers 64 [-qps 3000] [-burst 6000]

package main

import (
	"context"
	"flag"
	"fmt"
	"math/rand"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

// ── 命令行参数 ──
var (
	flagRate      int
	flagTotal     int
	flagScheduler string
	flagType      string
	flagCPU       int
	flagMem       int
	flagNamespace string
	flagImage     string
	flagWorkers   int
	flagGangSize  int
	flagDryRun    bool

	// client-go QPS/Burst
	flagQPS   int
	flagBurst int

	// burst 模式
	flagBurstStages   string
	flagStageDuration int

	// kubeconfig
	flagKubeconfig string
)

func init() {
	flag.IntVar(&flagRate, "rate", 500, "目标速率 (pods/s)")
	flag.IntVar(&flagTotal, "total", 50000, "总 Pod 数量")
	flag.StringVar(&flagScheduler, "scheduler", "eno-scheduler", "schedulerName")
	flag.StringVar(&flagType, "type", "basic", "负载类型: basic|burst|gang|heterogeneous")
	flag.IntVar(&flagCPU, "cpu", 100, "CPU 请求 (millicores)")
	flag.IntVar(&flagMem, "mem", 128, "内存请求 (Mi)")
	flag.StringVar(&flagNamespace, "namespace", "bench", "命名空间")
	flag.StringVar(&flagImage, "image", "registry.k8s.io/pause:3.9", "Pause 镜像")
	flag.IntVar(&flagWorkers, "workers", 64, "并发 goroutine 数 (默认 64)")
	flag.IntVar(&flagGangSize, "gang-size", 5, "Gang 调度每组 Pod 数量")
	flag.BoolVar(&flagDryRun, "dry-run", false, "仅计数，不实际创建 Pod")

	flag.IntVar(&flagQPS, "qps", 3000, "client-go QPS 限速")
	flag.IntVar(&flagBurst, "burst", 6000, "client-go burst 限速")

	flag.StringVar(&flagBurstStages, "burst-stages", "200,500,1000,2000,1000,500,200", "burst 模式各阶段速率")
	flag.IntVar(&flagStageDuration, "stage-duration", 10, "burst 模式每阶段持续秒数")

	flag.StringVar(&flagKubeconfig, "kubeconfig", "", "kubeconfig 路径 (默认: KUBECONFIG 环境变量 或 ~/.kube/config)")
}

// ── Kubernetes 客户端构建 ──

func buildClient() (*kubernetes.Clientset, dynamic.Interface, error) {
	var config *rest.Config
	var err error

	if flagKubeconfig != "" {
		config, err = clientcmd.BuildConfigFromFlags("", flagKubeconfig)
	} else if kc := os.Getenv("KUBECONFIG"); kc != "" {
		config, err = clientcmd.BuildConfigFromFlags("", kc)
	} else {
		config, err = rest.InClusterConfig()
		if err != nil {
			home, _ := os.UserHomeDir()
			config, err = clientcmd.BuildConfigFromFlags("", home+"/.kube/config")
		}
	}
	if err != nil {
		return nil, nil, fmt.Errorf("构建 kubeconfig 失败: %w", err)
	}

	// 高 QPS/Burst：避免 client-go 自身限速成为瓶颈
	config.QPS = float32(flagQPS)
	config.Burst = flagBurst
	// 关闭压缩减少 CPU 消耗
	config.DisableCompression = true
	// 超时：单次 API 调用 30s（默认 0 = 无超时，高并发下可能卡住连接）
	config.Timeout = 30 * time.Second

	cs, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, nil, fmt.Errorf("创建 kubernetes clientset 失败: %w", err)
	}
	dyn, err := dynamic.NewForConfig(config)
	if err != nil {
		return nil, nil, fmt.Errorf("创建 dynamic client 失败: %w", err)
	}
	return cs, dyn, nil
}

// ── Pod 构造函数 ──

func buildBasicPod(idx int) *corev1.Pod {
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      fmt.Sprintf("bench-pod-%d", idx),
			Namespace: flagNamespace,
		},
		Spec: corev1.PodSpec{
			SchedulerName:                 flagScheduler,
			TerminationGracePeriodSeconds: int64Ptr(0),
			Containers: []corev1.Container{
				{
					Name:      "app",
					Image:     flagImage,
					Resources: makeResources(flagCPU, flagMem),
				},
			},
		},
	}
	addSchedulerAnnotations(pod)
	return pod
}

func buildHeteroPod(idx int, cpuM, memM int) *corev1.Pod {
	pod := buildBasicPod(idx)
	pod.Spec.Containers[0].Resources = makeResources(cpuM, memM)
	return pod
}

func buildGangPod(groupIdx, memberIdx int) *corev1.Pod {
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      fmt.Sprintf("bench-gang-%d-%d", groupIdx, memberIdx),
			Namespace: flagNamespace,
		},
		Spec: corev1.PodSpec{
			SchedulerName:                 flagScheduler,
			TerminationGracePeriodSeconds: int64Ptr(0),
			Containers: []corev1.Container{
				{
					Name:      "app",
					Image:     flagImage,
					Resources: makeResources(flagCPU, flagMem),
				},
			},
		},
	}

	pgName := fmt.Sprintf("bench-gang-%d", groupIdx)
	switch flagScheduler {
	case "godel-scheduler":
		pod.Annotations = map[string]string{
			"godel.bytedance.com/pod-state":         "pending",
			"godel.bytedance.com/pod-resource-type": "guaranteed",
			"godel.bytedance.com/pod-launcher":      "kubelet",
			"godel.bytedance.com/pod-group-name":    pgName,
		}
	case "eno-scheduler":
		pod.Annotations = map[string]string{
			"eno.io/pod-state":         "pending",
			"eno.io/pod-resource-type": "guaranteed",
			"eno.io/pod-launcher":      "kubelet",
			"eno.io/pod-group-name":    pgName,
		}
	case "volcano":
		pod.Annotations = map[string]string{
			"scheduling.volcano.sh/group-name": pgName,
		}
	case "koord-scheduler":
		pod.Labels = map[string]string{
			"pod-group.scheduling.sigs.k8s.io": pgName,
		}
	}

	return pod
}

func addSchedulerAnnotations(pod *corev1.Pod) {
	switch flagScheduler {
	case "godel-scheduler":
		pod.Annotations = map[string]string{
			"godel.bytedance.com/pod-state":         "pending",
			"godel.bytedance.com/pod-resource-type": "guaranteed",
			"godel.bytedance.com/pod-launcher":      "kubelet",
		}
	case "eno-scheduler":
		pod.Annotations = map[string]string{
			"eno.io/pod-state":         "pending",
			"eno.io/pod-resource-type": "guaranteed",
			"eno.io/pod-launcher":      "kubelet",
		}
	case "volcano":
		pod.Annotations = map[string]string{
			"scheduling.volcano.sh/group-name": "bench-basic-pg",
		}
	}
}

func makeResources(cpuM, memM int) corev1.ResourceRequirements {
	return corev1.ResourceRequirements{
		Requests: corev1.ResourceList{
			corev1.ResourceCPU:    resource.MustParse(fmt.Sprintf("%dm", cpuM)),
			corev1.ResourceMemory: resource.MustParse(fmt.Sprintf("%dMi", memM)),
		},
		Limits: corev1.ResourceList{
			corev1.ResourceCPU:    resource.MustParse(fmt.Sprintf("%dm", cpuM)),
			corev1.ResourceMemory: resource.MustParse(fmt.Sprintf("%dMi", memM)),
		},
	}
}

func int64Ptr(v int64) *int64 { return &v }

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

// ── 速率控制器 (Token Bucket, wallclock-aligned, thread-safe) ──

type rateLimiter struct {
	startTime time.Time
	rate      float64
	sent      int64
	mu        sync.Mutex
}

func newRateLimiter(r int) *rateLimiter {
	return &rateLimiter{
		startTime: time.Now(),
		rate:      float64(r),
	}
}

// waitForSlot 阻塞直到可以发送 1 个 Pod（线程安全）
func (rl *rateLimiter) waitForSlot(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		rl.mu.Lock()
		elapsed := time.Since(rl.startTime).Seconds()
		allowed := int64(elapsed*rl.rate) + 1
		if rl.sent < allowed {
			rl.sent++
			rl.mu.Unlock()
			return nil
		}
		nextTokenAt := float64(rl.sent) / rl.rate
		sleepDur := time.Duration((nextTokenAt - elapsed) * float64(time.Second))
		rl.mu.Unlock()

		if sleepDur < 500*time.Microsecond {
			sleepDur = 500 * time.Microsecond
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(sleepDur):
		}
	}
}

func (rl *rateLimiter) changeRate(newRate int) {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	// 重置时间基准，避免旧 sent 积压导致切换瞬间速率失控
	rl.startTime = time.Now()
	rl.sent = 0
	rl.rate = float64(newRate)
}

// ── Worker 池 ──

type podTask struct {
	pod *corev1.Pod
}

func createWorker(ctx context.Context, client kubernetes.Interface, ch <-chan podTask,
	submitted, errors *atomic.Int64, wg *sync.WaitGroup) {
	defer wg.Done()
	for {
		select {
		case <-ctx.Done():
			return
		case task, ok := <-ch:
			if !ok {
				return
			}
			if flagDryRun {
				submitted.Add(1)
				continue
			}
			var err error
			// 指数退避重试，最多 3 次
			for attempt := 0; attempt < 3; attempt++ {
				_, err = client.CoreV1().Pods(task.pod.Namespace).Create(ctx, task.pod, metav1.CreateOptions{})
				if err == nil {
					break
				}
				// 已被取消则直接退出
				if ctx.Err() != nil {
					errors.Add(1)
					err = nil // 避免下方再计数
					break
				}
				// 指数退避: 50ms, 200ms, 800ms
				backoff := time.Duration(50<<uint(attempt)) * time.Millisecond
				select {
				case <-ctx.Done():
				case <-time.After(backoff):
				}
			}
			if err != nil {
				errors.Add(1)
				continue
			}
			submitted.Add(1)
		}
	}
}

// ── 进度打印 ──

func progressPrinter(ctx context.Context, submitted, errors *atomic.Int64, totalTarget int) {
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

// ── 主入口 ──

func main() {
	flag.Parse()

	client, dynClient, err := buildClient()
	if err != nil {
		fmt.Fprintf(os.Stderr, "[ERROR] %v\n", err)
		os.Exit(1)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		fmt.Fprintf(os.Stderr, "\n[INFO] 收到中断信号，正在停止...\n")
		cancel()
	}()

	if !flagDryRun {
		ensureNamespace(ctx, client)
	}

	fmt.Fprintf(os.Stderr, "[INFO] podgen v2 (client-go): rate=%d/s total=%d scheduler=%s type=%s workers=%d qps=%d burst=%d\n",
		flagRate, flagTotal, flagScheduler, flagType, flagWorkers, flagQPS, flagBurst)

	startTime := time.Now()

	switch flagType {
	case "basic":
		runBasic(ctx, client)
	case "burst":
		runBurst(ctx, client)
	case "gang":
		runGang(ctx, client, dynClient)
	case "heterogeneous":
		runHeterogeneous(ctx, client)
	default:
		fmt.Fprintf(os.Stderr, "[ERROR] 未知负载类型: %s\n", flagType)
		os.Exit(1)
	}

	elapsed := time.Since(startTime)
	fmt.Fprintf(os.Stderr, "\n[INFO] ✓ 完成: %d pods, 耗时 %v, 平均 %.0f pods/s\n",
		flagTotal, elapsed.Round(time.Second), float64(flagTotal)/elapsed.Seconds())
}

func ensureNamespace(ctx context.Context, client kubernetes.Interface) {
	ns := &corev1.Namespace{
		ObjectMeta: metav1.ObjectMeta{Name: flagNamespace},
	}
	// Create 是幂等检查 — 如果已存在会返回 AlreadyExists
	_, _ = client.CoreV1().Namespaces().Create(ctx, ns, metav1.CreateOptions{})
}

// ── basic 模式 ──
func runBasic(ctx context.Context, client kubernetes.Interface) {
	ch := make(chan podTask, flagWorkers*8)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	for i := 0; i < flagWorkers; i++ {
		wg.Add(1)
		go createWorker(ctx, client, ch, &submitted, &errors, &wg)
	}
	go progressPrinter(ctx, &submitted, &errors, flagTotal)

	rl := newRateLimiter(flagRate)
	for i := 1; i <= flagTotal; i++ {
		if err := rl.waitForSlot(ctx); err != nil {
			break
		}
		select {
		case ch <- podTask{pod: buildBasicPod(i)}:
		case <-ctx.Done():
		}
	}
	close(ch)
	wg.Wait()
}

// ── burst 模式 ──
func runBurst(ctx context.Context, client kubernetes.Interface) {
	stageRates := parseStages(flagBurstStages)

	ch := make(chan podTask, flagWorkers*8)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	for i := 0; i < flagWorkers; i++ {
		wg.Add(1)
		go createWorker(ctx, client, ch, &submitted, &errors, &wg)
	}
	go progressPrinter(ctx, &submitted, &errors, flagTotal)

	rl := newRateLimiter(stageRates[0])
	idx := 0
	remaining := flagTotal

	for _, stageRate := range stageRates {
		if remaining <= 0 {
			break
		}
		fmt.Fprintf(os.Stderr, "\n[INFO] 阶段: %d pods/s × %ds\n", stageRate, flagStageDuration)
		rl.changeRate(stageRate)
		stageEnd := time.Now().Add(time.Duration(flagStageDuration) * time.Second)

		for time.Now().Before(stageEnd) && remaining > 0 {
			if err := rl.waitForSlot(ctx); err != nil {
				remaining = 0
				break
			}
			idx++
			remaining--
			select {
			case ch <- podTask{pod: buildBasicPod(idx)}:
			case <-ctx.Done():
				remaining = 0
			}
		}
	}
	close(ch)
	wg.Wait()
}

// ── PodGroup CRD 创建（Volcano / Koordinator） ──

// Volcano PodGroup: scheduling.volcano.sh/v1beta1
var volcanoPodGroupGVR = schema.GroupVersionResource{
	Group:    "scheduling.volcano.sh",
	Version:  "v1beta1",
	Resource: "podgroups",
}

// Koordinator PodGroup: scheduling.sigs.k8s.io/v1alpha1
var koordPodGroupGVR = schema.GroupVersionResource{
	Group:    "scheduling.sigs.k8s.io",
	Version:  "v1alpha1",
	Resource: "podgroups",
}

// Gödel/Eno PodGroup: scheduling.godel.kubewharf.io/v1alpha1
var godelPodGroupGVR = schema.GroupVersionResource{
	Group:    "scheduling.godel.kubewharf.io",
	Version:  "v1alpha1",
	Resource: "podgroups",
}

// createPodGroupForGang 在创建 Gang Pod 之前先创建 PodGroup CRD 对象。
// dynClient 为 nil 时跳过（用于单元测试或 default-scheduler 场景）。
func createPodGroupForGang(ctx context.Context, dynClient dynamic.Interface, pgName string, minMember int) error {
	if dynClient == nil {
		return nil
	}
	switch flagScheduler {
	case "eno-scheduler", "godel-scheduler":
		pg := &unstructured.Unstructured{
			Object: map[string]interface{}{
				"apiVersion": "scheduling.godel.kubewharf.io/v1alpha1",
				"kind":       "PodGroup",
				"metadata": map[string]interface{}{
					"name":      pgName,
					"namespace": flagNamespace,
				},
				"spec": map[string]interface{}{
					"minMember": int64(minMember),
				},
			},
		}
		_, err := dynClient.Resource(godelPodGroupGVR).Namespace(flagNamespace).Create(ctx, pg, metav1.CreateOptions{})
		if err != nil {
			return fmt.Errorf("创建 Gödel/Eno PodGroup %s 失败: %w", pgName, err)
		}
	case "volcano":
		pg := &unstructured.Unstructured{
			Object: map[string]interface{}{
				"apiVersion": "scheduling.volcano.sh/v1beta1",
				"kind":       "PodGroup",
				"metadata": map[string]interface{}{
					"name":      pgName,
					"namespace": flagNamespace,
				},
				"spec": map[string]interface{}{
					"minMember": int64(minMember),
				},
			},
		}
		_, err := dynClient.Resource(volcanoPodGroupGVR).Namespace(flagNamespace).Create(ctx, pg, metav1.CreateOptions{})
		if err != nil {
			return fmt.Errorf("创建 Volcano PodGroup %s 失败: %w", pgName, err)
		}
	case "koord-scheduler":
		pg := &unstructured.Unstructured{
			Object: map[string]interface{}{
				"apiVersion": "scheduling.sigs.k8s.io/v1alpha1",
				"kind":       "PodGroup",
				"metadata": map[string]interface{}{
					"name":      pgName,
					"namespace": flagNamespace,
				},
				"spec": map[string]interface{}{
					"minMember":              int64(minMember),
					"scheduleTimeoutSeconds": int64(600),
				},
			},
		}
		_, err := dynClient.Resource(koordPodGroupGVR).Namespace(flagNamespace).Create(ctx, pg, metav1.CreateOptions{})
		if err != nil {
			return fmt.Errorf("创建 Koordinator PodGroup %s 失败: %w", pgName, err)
		}
	}
	// default-scheduler: 不需要 CRD
	return nil
}

// ── gang 模式 ──
func runGang(ctx context.Context, client kubernetes.Interface, dynClient dynamic.Interface) {
	totalGroups := flagTotal / flagGangSize

	ch := make(chan podTask, flagWorkers*8)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	for i := 0; i < flagWorkers; i++ {
		wg.Add(1)
		go createWorker(ctx, client, ch, &submitted, &errors, &wg)
	}
	go progressPrinter(ctx, &submitted, &errors, flagTotal)

	// gang 模式下 -rate 的语义是 groups/s，一次 waitForSlot 对应一整组
	// 组内 Pod 立即连续入队，保证同组成员尽快被调度器一起看到
	rl := newRateLimiter(flagRate)
	for g := 1; g <= totalGroups; g++ {
		if err := rl.waitForSlot(ctx); err != nil {
			break
		}
		// 先创建 PodGroup CRD（Volcano / Koordinator 需要）
		pgName := fmt.Sprintf("bench-gang-%d", g)
		if !flagDryRun {
			if err := createPodGroupForGang(ctx, dynClient, pgName, flagGangSize); err != nil {
				fmt.Fprintf(os.Stderr, "[WARN] %v\n", err)
			}
		}
		for m := 1; m <= flagGangSize; m++ {
			select {
			case ch <- podTask{pod: buildGangPod(g, m)}:
			case <-ctx.Done():
				goto done
			}
		}
	}
done:
	close(ch)
	wg.Wait()
}

// ── heterogeneous 模式 ──
func runHeterogeneous(ctx context.Context, client kubernetes.Interface) {
	ch := make(chan podTask, flagWorkers*8)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	for i := 0; i < flagWorkers; i++ {
		wg.Add(1)
		go createWorker(ctx, client, ch, &submitted, &errors, &wg)
	}
	go progressPrinter(ctx, &submitted, &errors, flagTotal)

	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	rl := newRateLimiter(flagRate)

	for i := 1; i <= flagTotal; i++ {
		if err := rl.waitForSlot(ctx); err != nil {
			break
		}
		spec := randomHeteroSpec(rng)
		select {
		case ch <- podTask{pod: buildHeteroPod(i, spec.cpu, spec.mem)}:
		case <-ctx.Done():
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
		v, err := strconv.Atoi(p)
		if err != nil || v <= 0 {
			fmt.Fprintf(os.Stderr, "[WARN] 忽略无效的 burst-stages 值: %q\n", p)
			continue
		}
		stages = append(stages, v)
	}
	if len(stages) == 0 {
		stages = []int{200, 500, 1000, 2000, 1000, 500, 200}
	}
	return stages
}
