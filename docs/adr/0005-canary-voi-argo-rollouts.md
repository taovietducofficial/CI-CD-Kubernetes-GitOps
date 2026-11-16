# ADR-0005: Canary với Argo Rollouts và phân tích metric tự động

- Trạng thái: Chấp nhận
- Ngày: 2026-11-17

## Bối cảnh

`Deployment` RollingUpdate thay pod cũ bằng pod mới ngay khi pod mới *ready*. Nhưng "ready" chỉ có nghĩa là process đã khởi động, không có nghĩa là nó đang phục vụ người dùng tốt. Một bản phát hành trả 5xx cho 30% request vẫn có thể rollout xong 100% trước khi có người kịp nhận ra.

## Quyết định

Thay `Deployment` bằng **Argo Rollouts `Rollout`** với chiến lược canary:

- Steps theo môi trường. Staging: 50% → 1 phút → 100%. Production: 20% → 2 phút → 50% → 2 phút → 100%.
- **Background analysis** (`AnalysisTemplate`) chạy từ bước đầu tới khi rollout xong. Cứ 30 giây, nó hỏi Prometheus tỉ lệ request không phải 5xx **của riêng các pod canary**.
- Pod canary được nhận diện qua label `rollouts-pod-template-hash`. PodMonitor copy label này vào mọi series bằng `podTargetLabels`, và query lọc theo hash của template mới nhất.
- Chỉ cần một lần đo dưới 99% (`failureLimit: 1`) là Rollout **tự abort**: scale canary về 0, toàn bộ traffic quay lại bản stable.
- Không có traffic (kết quả rỗng hoặc NaN) được tính là *chưa có bằng chứng*, không phải *thất bại*.

## Hệ quả

- Rollback tự động trong vòng khoảng một phút kể từ khi lỗi xuất hiện, không cần người trực.
- Sau khi abort, Git vẫn trỏ tới digest lỗi. Argo CD sẽ báo Rollout `Degraded` cho tới khi có commit sửa (`git revert` hoặc bản fix). Đây là đúng thiết kế: trạng thái mong muốn trong Git là sai, và con người phải quyết định sửa nó ([runbook](../runbooks.md#canary-bi-abort)).
- Canary dựa trên **số replica** (không có traffic router). 20% nghĩa là khoảng 1/5 số pod, nên tỉ lệ traffic chỉ xấp xỉ. Muốn chia traffic chính xác theo phần trăm thì cần ingress hoặc Gateway API làm traffic router ([ADR-0008](0008-nhung-gi-co-y-khong-lam.md)).
- Analysis chỉ có ý nghĩa khi có traffic. Ở môi trường local, hãy dùng `make load` để tạo traffic.

## Phương án đã cân nhắc

- **Flagger**: ý tưởng tương tự, nhưng gắn với service mesh hoặc ingress để chia traffic, và tạo thêm Deployment "primary". Argo Rollouts tích hợp tự nhiên với Argo CD (health, UI, lệnh `kubectl argo rollouts`).
- **Blue/green**: rollback tức thì, nhưng tốn gấp đôi tài nguyên và vẫn cần phân tích pre-promotion. Canary phù hợp hơn cho service stateless.
