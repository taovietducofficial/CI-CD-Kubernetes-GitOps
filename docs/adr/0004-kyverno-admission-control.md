# ADR-0004: Kyverno làm chốt chặn cuối, cùng policy chạy ở CI

- Trạng thái: Chấp nhận
- Ngày: 2026-11-17

## Bối cảnh

Chữ ký và provenance (ADR-0003) chỉ có giá trị khi có thứ gì đó **bắt buộc** kiểm tra chúng ngay lúc Pod được tạo. Đồng thời, có những quy tắc nền mà mọi workload phải tuân thủ (requests/limits, probes, nguồn image). Nếu chỉ phát hiện vi phạm lúc deploy thì quá muộn: lỗi lẽ ra phải lộ ra ngay trong PR.

## Quyết định

Ba lớp, mỗi lớp làm một việc:

| Lớp | Cơ chế | Kiểm tra |
|---|---|---|
| Pod Security Admission | **Native Kubernetes**, qua label namespace `pod-security.kubernetes.io/enforce: restricted` | Không root, không privileged, drop ALL capabilities, seccomp |
| `workload-baseline` | Kyverno `ValidatingPolicy` (CEL) | Có requests/limits, có probes, image lấy từ `ghcr.io/taovietducofficial/` và pin digest |
| `verify-image-provenance` | Kyverno `ImageValidatingPolicy` | Chữ ký keyless của `ci.yml@main` và SLSA provenance từ repo này |

Các nguyên tắc đi kèm:

- **Thứ gì nền tảng đã làm được thì không viết lại.** PSA đã lo phần securityContext, nên Kyverno không lặp lại.
- **Chạy cùng một policy ở hai nơi.** `make lint` (và job `deploy-lint` trong CI) chạy `kyverno apply deploy/policies/workload-baseline.yaml` trên manifest render của mọi môi trường, nên PR vi phạm sẽ fail ngay lúc review.
- **Policy là code và có test.** `deploy/policies/tests/` chứa fixture cho từng quy tắc: mỗi resource "xấu" vi phạm đúng một điều. Lệnh `kyverno test` chạy trong CI.
- **Kiểm tra cả Rollout, không chỉ Pod.** Nếu chỉ kiểm tra Pod, vi phạm sẽ nằm im trong event của ReplicaSet. Kiểm tra Rollout làm Argo CD sync fail với thông báo rõ ràng.
- **Phạm vi theo label** `workload-namespace=true`, do ApplicationSet gắn. Các namespace platform (monitoring, kyverno…) không bị ảnh hưởng.
- `verify-image-provenance` dùng `failurePolicy: Fail`: nếu Kyverno không chạy thì Pod workload không được tạo. Đây là chủ đích **fail-closed**.

## Phương án đã cân nhắc

- **OPA Gatekeeper**: mạnh, nhưng phải viết Rego. Verify image cần thêm thành phần ngoài (ratify). Kyverno làm cả hai việc trong cùng một mô hình.
- **ValidatingAdmissionPolicy native**: dùng được cho baseline, nhưng không verify được chữ ký image và không có công cụ test CLI. Kyverno `ValidatingPolicy` là superset của VAP và có thể sinh ra VAP khi cần (`spec.autogen.validatingAdmissionPolicy`).
- **ClusterPolicy (API cũ của Kyverno)**: vẫn chạy được, nhưng Kyverno 1.20 đã chuyển sang các policy type dựa trên CEL. Repo mới nên bắt đầu với API mới.

## Hệ quả

- Image không do CI trên `main` ký thì không thể chạy trong namespace workload. Điều này đúng cả khi ai đó có quyền `kubectl` hoặc quyền push registry.
- Khi Kyverno sập, workload không scale lên được. Runbook có hướng dẫn xử lý ([runbooks.md](../runbooks.md#pod-bi-kyverno-tu-choi)).
