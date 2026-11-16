# ADR-0006: Sealed Secrets cho secret trong Git

- Trạng thái: Chấp nhận
- Ngày: 2026-11-17

## Bối cảnh

Trong GitOps, Git là nguồn sự thật duy nhất, nhưng secret thì không được nằm trong Git ở dạng có thể đọc được. Cần một cách để secret đi cùng luồng PR và review như mọi cấu hình khác.

## Quyết định

Dùng **Bitnami Sealed Secrets**:

- Controller trong cluster giữ khóa riêng. Ai cũng có thể mã hoá bằng khóa công khai (`make seal`), nhưng chỉ controller giải mã được.
- Giá trị đã mã hoá nằm trong `deploy/envs/<env>/values.yaml` ở mục `sealedSecrets`. Chart render ra một `SealedSecret`, và controller tạo `Secret` tương ứng.
- Phạm vi mặc định là **strict**: ciphertext chỉ giải mã được cho đúng tên `demo-service` trong đúng namespace. Copy giá trị của staging sang production sẽ **không** hoạt động.
- Pod template có annotation `checksum/secrets`, nên đổi secret sẽ kích hoạt một rollout mới.

## Hệ quả

- Secret đã mã hoá được review như code, và đi vào cluster qua Argo CD như mọi thứ khác.
- **Khóa riêng của controller là thứ phải backup.** Mất cluster mà không có khóa thì mọi giá trị đã seal đều thành vô dụng ([runbook](../runbooks.md#sao-luu-va-xoay-vong-khoa-sealed-secrets)).
- Ciphertext gắn với một cluster cụ thể. Ai fork repo và dựng cluster mới thì phải seal lại.
- Không có xoay vòng tự động, audit truy cập hay secret động như với Vault.

## Phương án đã cân nhắc

- **External Secrets Operator + Vault / AWS Secrets Manager / GCP Secret Manager**: lựa chọn chuẩn khi tổ chức đã có secret store, vì có xoay vòng, audit và quản lý tập trung. Cluster local không có backend như vậy, nên ESO là hướng nâng cấp khi lên cloud ([ADR-0008](0008-nhung-gi-co-y-khong-lam.md)).
- **SOPS + age/KMS**: mã hoá ngay trong file. Linh hoạt, nhưng Argo CD cần thêm plugin để giải mã.
