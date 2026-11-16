# ADR-0001: Monorepo, tách cấu hình môi trường khỏi con trỏ release

- Trạng thái: Chấp nhận
- Ngày: 2026-11-17

## Bối cảnh

Repo GitOps phải trả lời được hai câu hỏi khác nhau: *môi trường X được cấu hình thế nào* và *môi trường X đang chạy build nào*. Câu thứ nhất do con người thay đổi (replicas, canary steps, tài nguyên). Câu thứ hai do máy thay đổi: CI ghi nhận build mới, PR promote ghi nhận một lần phát hành.

Có hai cách tổ chức phổ biến:

1. **Hai repo**: code ứng dụng ở một repo, cấu hình triển khai ở repo khác. CI của repo code mở PR sang repo cấu hình.
2. **Monorepo**: code, chart và cấu hình môi trường nằm chung một chỗ.

## Quyết định

Dùng **monorepo**, và mỗi môi trường có hai file:

| File | Ai sửa | Nội dung |
|---|---|---|
| `deploy/envs/<env>/values.yaml` | Người, qua PR | Cấu hình: replicas, autoscaling, canary steps |
| `deploy/envs/<env>/image.yaml` | CI (staging) hoặc PR promote (production) | `tag` + `digest` của build đang chạy, kèm link tới lần build |

ApplicationSet dùng git files generator trên `deploy/envs/*/image.yaml`. Một môi trường **chỉ tồn tại trong cluster khi đã có release**: staging xuất hiện sau build đầu tiên trên `main`, production xuất hiện sau PR promote đầu tiên.

## Hệ quả

- Một PR có thể vừa đổi code vừa đổi chart, và được review, test cùng nhau. Không còn cảnh "chart đã merge, code chưa merge".
- Bot chỉ ghi vào `image.yaml`, nên không bao giờ conflict với người đang sửa `values.yaml`.
- Lịch sử `git log deploy/envs/production/image.yaml` chính là lịch sử phát hành production.
- `ci.yml` bỏ qua thay đổi ở `deploy/envs/*/image.yaml` (`paths-ignore`), nên commit của bot không kích hoạt build mới.
- Đánh đổi: ai có quyền ghi vào repo đều chạm được tới cấu hình production. Rủi ro này được giảm bằng CODEOWNERS và branch ruleset ([github-setup.md](../github-setup.md)). Nếu tổ chức cần tách quyền tuyệt đối, hãy chuyển sang mô hình hai repo. Thiết kế `image.yaml` vẫn giữ nguyên.

## Phương án đã cân nhắc

- **Hai repo**: tách quyền rõ hơn. Đổi lại cần thêm token hoặc GitHub App để CI ghi chéo repo, và thay đổi xuyên suốt app với chart phải đi qua hai PR. Với một service và một nhóm thì chi phí này chưa đáng.
- **Một file values cho mỗi môi trường**: đơn giản hơn, nhưng bot và người cùng sửa một file, dễ conflict, và lịch sử phát hành bị lẫn với thay đổi cấu hình.
