# ADR-0008: Những gì cố ý không làm

- Trạng thái: Chấp nhận
- Ngày: 2026-11-17

## Bối cảnh

Kiến trúc tốt cần ranh giới. Mỗi thành phần thêm vào là thêm thứ phải nâng cấp, giám sát và hiểu. Repo này nhắm tới việc **dạy một luồng phát hành đầy đủ và chạy được trên một laptop** (Docker khoảng 8 GB RAM). Những thứ dưới đây có giá trị thật ở production, nhưng chưa cần cho mục tiêu đó. Mình ghi lại ở đây để ai đọc cũng hiểu đây là quyết định có chủ đích, không phải bỏ sót.

## Danh sách

| Không làm | Vì sao | Khi nào nên thêm, và thêm thế nào |
|---|---|---|
| **Cluster production riêng** | Một laptop chỉ chạy nổi một cluster đầy đủ | Đăng ký cluster vào Argo CD, đổi ApplicationSet sang cluster/matrix generator. Không cần đổi gì khác |
| **SLSA Build L3** | Cần thêm một repo chứa reusable workflow được tin cậy | Chuyển build + attest sang reusable workflow ở repo riêng, rồi sửa `subject` trong `verify-image-provenance` |
| **Traffic router** (ingress/Gateway API) cho canary | Canary theo replica đủ để minh hoạ phân tích tự động | Khi cần chia đúng 5% traffic: thêm `trafficRouting` vào Rollout |
| **Service mesh** (Istio/Linkerd) | mTLS và retry chưa cần với một service | Khi có nhiều service gọi nhau và cần mTLS hoặc chính sách theo danh tính |
| **External Secrets + Vault/cloud secret store** | Local không có backend | Khi lên cloud: ESO + Secrets Manager, bỏ Sealed Secrets |
| **Logs (Loki) và traces (Tempo/OpenTelemetry)** | Tốn RAM; metric + log JSON đủ cho các bài học ở đây | Thêm OpenTelemetry Collector, rồi bật `management.opentelemetry` trong Spring Boot |
| **Argo CD notifications / Alertmanager receiver** | Không có Slack/PagerDuty để gửi tới | Cấu hình receiver trong values của kube-prometheus-stack |
| **Kargo / Argo CD Image Updater** | PR promote bằng workflow đã đủ minh bạch | Khi có nhiều stage và cần verification gate tự động giữa các stage |
| **SSO cho Argo CD (Dex/OIDC)** | Một người dùng local | Bật `dex` hoặc `oidc.config`, rồi map group sang RBAC của AppProject |
| **harden-runner (giám sát egress của runner)** | Thêm một dependency vào mọi job | Repo có secret giá trị cao, hoặc cần audit egress của CI |
| **Ingress + TLS** | `kubectl port-forward` đủ cho local | Thêm ingress controller và cert-manager, rồi bỏ `server.insecure` của Argo CD |

## Những cấu hình chỉ an toàn ở local

Các cấu hình dưới đây có comment ngay trong code, và **phải đổi** khi đưa lên cluster dùng chung:

- `server.insecure: true` của Argo CD (`deploy/argocd/bootstrap/values.yaml`).
- Mật khẩu admin mặc định của Grafana (`deploy/platform/kube-prometheus-stack.yaml`).
- `--kubelet-insecure-tls` của metrics-server (`deploy/argocd/apps/platform.yaml`).
- Staging và production chung một cluster, khác namespace (`deploy/argocd/apps/demo-service.yaml`).
