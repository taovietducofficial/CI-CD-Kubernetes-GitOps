# ADR-0007: Renovate để cập nhật mọi dependency, kể cả chart trong Argo CD

- Trạng thái: Chấp nhận
- Ngày: 2026-11-17

## Bối cảnh

Repo này pin **mọi thứ**:

- Maven dependency.
- Base image theo digest.
- GitHub Action theo commit SHA.
- Version chart platform trong Argo CD Application.
- Trivy, kubeconform, image node kind.

Pin là điều kiện để build tái lập được và để chống supply-chain attack, ví dụ một action bị chiếm quyền rồi đẩy đè tag. Nhưng pin mà không cập nhật thì sớm muộn cũng thành nợ bảo mật.

## Quyết định

Dùng **Renovate** (`renovate.json`):

- Manager `argocd` theo dõi `targetRevision` của các chart trong `deploy/argocd/`. **Dependabot không làm được việc này.**
- `helpers:pinGitHubActionDigests` giữ action ở dạng `@<sha> # vX.Y.Z` và cập nhật cả hai.
- `docker:pinDigests` cập nhật digest của base image trong Dockerfile.
- Regex manager cho các version nằm ngoài file chuẩn (Makefile, kind config, Trivy trong workflow).
- Chart platform được tách mỗi chart một PR, để một bản nâng cấp lỗi có thể revert riêng.

## Hệ quả

- Mỗi PR của Renovate đi qua đúng pipeline như PR của người: test, scan, `make lint`, e2e.
- Cần cài [Renovate GitHub App](https://github.com/apps/renovate) cho repo. Đây là bước làm một lần, có hướng dẫn trong [github-setup.md](../github-setup.md).
- Kyverno CLI trong CI phải cùng version với Kyverno trong cluster, nên được nâng tay cùng lúc với chart (có comment trong `ci.yml`).
