# Bảo mật

## Báo cáo lỗ hổng

Vui lòng **không** mở issue công khai. Hãy dùng
[Private vulnerability reporting](https://github.com/taovietducofficial/CI-CD-Kubernetes-GitOps/security/advisories/new)
của GitHub, mô tả cách tái hiện và ảnh hưởng. Bạn sẽ nhận phản hồi trong vòng 7 ngày.

## Phạm vi

- Mã nguồn và image `ghcr.io/taovietducofficial/ci-cd-kubernetes-gitops`, chỉ nhánh `main`.
- Pipeline (`.github/workflows`), Helm chart, policy và cấu hình Argo CD trong repo.

Cấu hình chỉ dùng cho cluster local được ghi rõ trong code và trong
[ADR-0008](docs/adr/0008-nhung-gi-co-y-khong-lam.md), ví dụ `server.insecure` của Argo CD,
mật khẩu Grafana mặc định và `--kubelet-insecure-tls`. Đây không phải lỗ hổng.

## Tự kiểm chứng một image

```sh
gh attestation verify oci://ghcr.io/taovietducofficial/ci-cd-kubernetes-gitops@sha256:<digest> \
  --repo taovietducofficial/CI-CD-Kubernetes-GitOps

cosign verify ghcr.io/taovietducofficial/ci-cd-kubernetes-gitops@sha256:<digest> \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity https://github.com/taovietducofficial/CI-CD-Kubernetes-GitOps/.github/workflows/ci.yml@refs/heads/main
```
