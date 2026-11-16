# ADR-0003: Ký keyless và SLSA provenance bằng GitHub OIDC

- Trạng thái: Chấp nhận
- Ngày: 2026-11-17

## Bối cảnh

Digest bảo đảm *image không bị đổi*. Nhưng nó không trả lời được *image này do ai build, từ source nào*. Kẻ tấn công có quyền push lên registry vẫn có thể đẩy một image độc hại, rồi tự sửa `image.yaml` trỏ tới digest của nó.

Cách truyền thống là ký bằng một cặp khóa. Nhưng khóa bí mật phải được lưu ở đâu đó (secret CI, KMS), phải xoay vòng, và bản thân nó trở thành mục tiêu tấn công.

## Quyết định

Dùng **Sigstore keyless**. Danh tính ký chính là OIDC token mà GitHub cấp cho đúng lần chạy workflow:

```
issuer : https://token.actions.githubusercontent.com
subject: https://github.com/taovietducofficial/CI-CD-Kubernetes-GitOps/.github/workflows/ci.yml@refs/heads/main
```

Fulcio cấp chứng chỉ ngắn hạn cho danh tính đó. Mọi chữ ký được ghi vào transparency log công khai Rekor. Job `publish` tạo ba thứ, tất cả gắn vào image dưới dạng OCI referrer:

| Artifact | Công cụ | Chứng minh điều gì |
|---|---|---|
| Chữ ký image | `cosign sign` | Image do `ci.yml` trên `main` của repo này đẩy lên |
| SLSA provenance v1 | `actions/attest` | Build từ commit nào, workflow nào, runner nào |
| SBOM CycloneDX | Trivy + `actions/attest` | Image chứa những thành phần gì (để tra CVE về sau) |

Cuối job, CI **tự kiểm chứng lại** bằng `cosign verify` và `gh attestation verify`. Nếu bước này fail thì Kyverno cũng sẽ từ chối, nên tốt hơn là fail sớm với thông báo rõ ràng.

## Mức SLSA

Cấu hình này đạt **SLSA Build L2**: provenance do nền tảng build (GitHub Actions) sinh ra và ký, người dùng workflow không giả mạo được.

Để lên **L3**, phần build và attest phải nằm trong một reusable workflow đặt ở repo khác (được tin cậy), để chính các bước build trong repo này cũng không can thiệp được vào quá trình ký. Mình không làm bước này vì repo mẫu chỉ có một repo. Hướng nâng cấp nằm trong [ADR-0008](0008-nhung-gi-co-y-khong-lam.md).

## Phương án đã cân nhắc

- **slsa-github-generator**: từng là con đường chuẩn để đạt L3, nhưng không có release mới từ 02/2025. GitHub Artifact Attestations (`actions/attest`) nay là cơ chế native, được bảo trì, hiển thị ngay trên tab *Attestations* của repo và kiểm chứng được bằng `gh attestation verify`.
- **Ký bằng khóa (cosign key pair, Notation + KMS)**: hợp lý trong môi trường air-gapped hoặc khi không dùng được Sigstore public. Đổi lại phải vận hành vòng đời khóa.
