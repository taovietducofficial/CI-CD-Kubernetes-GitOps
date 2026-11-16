# Runbooks

Mỗi alert trong `deploy/chart/templates/prometheusrule.yaml` có `runbook_url` trỏ về một mục trong file này. Mỗi mục trả lời ba câu: **chuyện gì đang xảy ra**, **kiểm tra gì**, **làm gì**.

Trong các lệnh dưới đây, `<env>` là `staging` hoặc `production`.

- [DemoServiceErrorBudgetBurnFast](#demoserviceerrorbudgetburnfast)
- [DemoServiceErrorBudgetBurnSlow](#demoserviceerrorbudgetburnslow)
- [DemoServiceLatencyHigh](#demoservicelatencyhigh)
- [Canary bị abort](#canary-bi-abort)
- [Rollback thủ công](#rollback-thu-cong)
- [Pod bị Kyverno từ chối](#pod-bi-kyverno-tu-choi)
- [Argo CD báo OutOfSync hoặc sync lỗi](#argo-cd-sync-loi)
- [Sao lưu và xoay vòng khóa Sealed Secrets](#sao-luu-va-xoay-vong-khoa-sealed-secrets)

---

## DemoServiceErrorBudgetBurnFast

**Mức độ:** critical, cần xử lý ngay.

**Ý nghĩa.** SLO là 99.9% request API thành công trong 30 ngày, tức error budget là 0.1%. Alert này bắn khi tỉ lệ 5xx vượt **14.4 × 0.1% = 1.44%** ở cả cửa sổ 1 giờ lẫn 5 phút. Với tốc độ đó, budget của cả tháng sẽ cạn trong khoảng 2 ngày. Cửa sổ 5 phút bảo đảm lỗi *vẫn đang diễn ra*, nên khi đã sửa xong thì alert tự tắt nhanh.

**Kiểm tra**

1. Có bản phát hành mới không? Nếu Rollout đang hoặc vừa chạy, rất có thể đó là nguyên nhân.
   ```sh
   kubectl -n app-<env> get rollout demo-service
   kubectl -n app-<env> get analysisrun --sort-by=.metadata.creationTimestamp
   git log -3 --oneline -- deploy/envs/<env>/image.yaml
   ```
2. Lỗi nằm ở endpoint nào, mã gì (chạy trong Prometheus, `make ui` → http://localhost:9090):
   ```promql
   sum by (uri, status) (rate(http_server_requests_seconds_count{namespace="app-<env>", status=~"5.."}[5m]))
   ```
3. Log lỗi gần nhất (log dạng JSON ECS, nên lọc được theo level):
   ```sh
   kubectl -n app-<env> logs -l app.kubernetes.io/name=demo-service --since=15m | grep '"level":"ERROR"'
   ```

**Xử lý**

- Lỗi xuất hiện ngay sau một release: [rollback](#rollback-thu-cong) trước, điều tra sau.
- Không liên quan release: kiểm tra node, tài nguyên (`kubectl top pods -n app-<env>`), và các thay đổi cấu hình gần đây trong `deploy/envs/<env>/values.yaml`.

## DemoServiceErrorBudgetBurnSlow

**Mức độ:** warning, xử lý trong giờ làm việc.

**Ý nghĩa.** Tỉ lệ 5xx vượt **6 × 0.1% = 0.6%** ở cả cửa sổ 6 giờ và 30 phút. Đây không phải sự cố cấp bách, nhưng budget sẽ cạn trong khoảng 5 ngày.

**Kiểm tra và xử lý:** giống [BurnFast](#demoserviceerrorbudgetburnfast). Thường gặp nhất là một lỗi chỉ xảy ra với một nhóm request nhỏ: xem phân bố theo `uri` và `status`.

## DemoServiceLatencyHigh

**Mức độ:** warning.

**Ý nghĩa.** p99 độ trễ của API vượt `slo.latencyP99Seconds` (mặc định 300ms) trong 10 phút.

**Kiểm tra**

1. HPA đã chạm `maxReplicas` chưa? `kubectl -n app-<env> get hpa`
2. CPU và bộ nhớ: `kubectl -n app-<env> top pods`
3. Dashboard **JVM (Micrometer)** trong Grafana: thời gian GC, heap, số thread.

**Xử lý:** tăng `autoscaling.maxReplicas` hoặc `resources` trong `deploy/envs/<env>/values.yaml` qua PR. Nếu do GC, xem lại `resources.limits.memory`, vì heap được tính bằng 75% của limit.

---

<a id="canary-bi-abort"></a>
## Canary bị abort

**Dấu hiệu.** Argo CD báo `demo-service-<env>` ở trạng thái **Degraded**. Rollout ở trạng thái `Degraded`, message `RolloutAborted`.

**Chuyện gì đã xảy ra.** AnalysisTemplate đo được tỉ lệ thành công của pod canary dưới 99%. Argo Rollouts đã **tự động** scale canary về 0, toàn bộ traffic đã quay lại bản stable. Người dùng không còn bị ảnh hưởng.

**Kiểm tra**

```sh
kubectl -n app-<env> get analysisrun --sort-by=.metadata.creationTimestamp
kubectl -n app-<env> describe analysisrun <tên-mới-nhất>   # xem "Measurements"
```

Hoặc mở dashboard Argo Rollouts (`make ui` → http://localhost:3100/rollouts).

**Xử lý.** Git vẫn đang khai báo digest lỗi là trạng thái mong muốn, nên phải sửa Git. Đừng sửa cluster.

- **staging:** đẩy bản fix lên `main`, hoặc revert commit gây lỗi. CI sẽ ghi digest mới vào `deploy/envs/staging/image.yaml`.
- **production:** `git revert` merge commit của PR promote, rồi mở PR. Khi merge xong, production trỏ lại digest trước đó.

Nếu chắc chắn đó là false positive (ví dụ Prometheus bị lỗi trong lúc phân tích), có thể chạy lại:

```sh
kubectl argo rollouts retry rollout demo-service -n app-<env>
```

<a id="rollback-thu-cong"></a>
## Rollback thủ công

Trong GitOps, **rollback là một commit**, không phải một lệnh `kubectl`. Nếu bạn sửa trực tiếp trên cluster, Argo CD (`selfHeal`) sẽ đưa mọi thứ về đúng trạng thái trong Git chỉ sau vài chục giây.

```sh
# Tìm commit đã đưa bản lỗi vào môi trường
git log --oneline -- deploy/envs/production/image.yaml

# Revert và đưa qua PR như mọi thay đổi khác
git switch -c rollback/production
git revert <sha>
git push -u origin rollback/production
gh pr create --title "deploy(production): rollback demo-service" --body "Lý do: ..."
```

Image cũ vẫn còn trên GHCR và vẫn có chữ ký hợp lệ, nên Rollout chuyển về rất nhanh và Kyverno vẫn cho phép.

**Dừng khẩn cấp** khi rollout đang chạy dở và chưa kịp có PR: `kubectl argo rollouts abort demo-service -n app-<env>` đưa traffic về bản stable ngay lập tức. Lệnh này *không* thay đổi Git. Sau đó vẫn phải revert như trên.

<a id="pod-bi-kyverno-tu-choi"></a>
## Pod bị Kyverno từ chối

**Dấu hiệu.** Argo CD sync lỗi với thông báo `admission webhook ... denied the request`, hoặc ReplicaSet có event `FailedCreate`.

```sh
kubectl -n app-<env> get events --field-selector reason=FailedCreate
```

**Đọc thông báo lỗi để biết policy nào từ chối:**

| Thông báo chứa | Nguyên nhân | Xử lý |
|---|---|---|
| `cpu/memory requests and a memory limit` | Chart hoặc values thiếu `resources` | Sửa `deploy/envs/<env>/values.yaml`. Lẽ ra `make lint` đã bắt được lỗi này trong PR |
| `readinessProbe and a livenessProbe` | Thiếu probe | Như trên |
| `pinned by digest` | `image.yaml` không có `digest`, hoặc image từ registry khác | Chỉ dùng `image.yaml` do CI hoặc promote ghi ra |
| `not signed by this repository's CI` | Image không do `ci.yml` trên `main` ký. Có thể ai đó đã sửa `image.yaml` bằng tay, hoặc push image từ máy cá nhân | Không có ngoại lệ: build lại qua CI. Kiểm tra bằng các lệnh trong [SECURITY.md](../SECURITY.md) |
| `failed calling webhook` | Bản thân Kyverno không chạy | Xem bên dưới |

**Kyverno không chạy.** Policy ảnh `verify-image-provenance` được cấu hình *fail-closed*, nên khi Kyverno sập, pod workload mới không được tạo. Pod đang chạy thì không bị ảnh hưởng.

```sh
kubectl -n kyverno get pods
kubectl -n kyverno logs deploy/kyverno-admission-controller --tail=100
```

Ưu tiên khôi phục Kyverno. Nếu thật sự cần ngoại lệ, hãy dùng [PolicyException](https://kyverno.io/docs/guides/exceptions/) **qua PR** vào `deploy/policies/`, phạm vi hẹp nhất có thể, kèm hạn gỡ bỏ. Đừng gỡ label `workload-namespace` khỏi namespace: Argo CD sẽ gắn lại, và làm vậy là tắt *mọi* kiểm tra cùng lúc.

<a id="argo-cd-sync-loi"></a>
## Argo CD báo OutOfSync hoặc sync lỗi

```sh
make status
kubectl -n argocd get application demo-service-<env> -o jsonpath='{.status.operationState.message}{"\n"}'
kubectl -n argocd get application demo-service-<env> -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'
```

Các nguyên nhân thường gặp:

- **Lỗi render chart** (`values don't meet the specifications of the schema`): giá trị trong `deploy/envs/<env>/*.yaml` sai kiểu. Chạy `make lint` ở local để xem chi tiết.
- **Resource bị AppProject chặn** (`resource ... is not permitted in project apps`): chart đã thêm một kind mới. Thêm kind đó vào `namespaceResourceWhitelist` trong `deploy/argocd/apps/projects.yaml`, qua PR (thuộc CODEOWNERS).
- **Admission từ chối**: xem [Pod bị Kyverno từ chối](#pod-bi-kyverno-tu-choi).

<a id="sao-luu-va-xoay-vong-khoa-sealed-secrets"></a>
## Sao lưu và xoay vòng khóa Sealed Secrets

Khóa riêng của controller là thứ **duy nhất** giải mã được mọi `SealedSecret`. Mất cluster mà không có bản sao lưu nghĩa là phải seal lại toàn bộ secret.

**Sao lưu** (lưu vào password manager hoặc vault, **không bao giờ** commit vào Git):

```sh
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-keys.yaml
```

**Khôi phục** vào cluster mới, trước khi Argo CD cài controller hoặc ngay sau đó:

```sh
kubectl apply -f sealed-secrets-keys.yaml
kubectl -n kube-system delete pod -l app.kubernetes.io/name=sealed-secrets   # controller nạp lại khóa
```

**Xoay vòng.** Controller tự sinh khóa mới mỗi 30 ngày, và vẫn giữ các khóa cũ để giải mã những gì đã seal trước đó. Nếu lo khóa cũ bị lộ, hãy seal lại từng giá trị bằng `make seal` (dùng khóa mới nhất) và đưa qua PR. Sau đó **phải đổi luôn giá trị secret gốc**, vì ciphertext cũ vẫn còn trong lịch sử Git.
