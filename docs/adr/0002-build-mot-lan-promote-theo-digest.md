# ADR-0002: Build một lần, promote bằng digest bất biến

- Trạng thái: Chấp nhận
- Ngày: 2026-11-17

## Bối cảnh

Một lỗi kinh điển là "staging chạy tốt, production lại hỏng", vì hai môi trường thực ra chạy **hai artifact khác nhau**: build lại cho từng môi trường, hoặc dùng tag di động như `latest` hay `v1` mà ai đó đã đẩy đè.

## Quyết định

1. Image được build **đúng một lần** trong job `build`, rồi lưu thành `image.tar`. Job `e2e` chạy trên chính file tar đó, và job `publish` đẩy chính file tar đó lên GHCR. Trivy quét file tar **trước khi** push, nên image có CVE nghiêm trọng (đã có bản vá) không bao giờ lên tới registry.
2. Mọi môi trường tham chiếu image bằng **digest** (`repo:tag@sha256:…`). Tag là git SHA, chỉ để người đọc nhận ra build nào. Container runtime luôn kéo image theo digest.
3. Promote production nghĩa là **copy nguyên `image.yaml`** của staging sang production qua một PR. Không build lại, không đổi tag.
4. `values.schema.json` của chart bắt `digest` phải khớp `^sha256:[a-f0-9]{64}$`. Policy Kyverno `workload-baseline` từ chối mọi image không pin digest trong namespace workload.

## Hệ quả

- Thứ chạy ở production chính xác là thứ đã qua test, scan, e2e và đã chạy ở staging, đúng từng byte.
- Rollback là trỏ lại digest cũ (`git revert`). Image cũ vẫn còn trên registry, không cần build lại.
- Đánh đổi: thêm một bước upload/download artifact giữa các job (vài chục MB), đổi lại có được bảo đảm trên.
- Mỗi commit lên `main` đều sinh một ứng viên release, kể cả commit chỉ đổi docs không nằm trong `paths-ignore`. Đây là đặc trưng của trunk-based development: `main` luôn ở trạng thái phát hành được.
