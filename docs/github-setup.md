# Thiết lập GitHub (làm một lần)

Những cấu hình dưới đây không nằm trong code, nhưng pipeline cần chúng. Mọi lệnh đều dùng [GitHub CLI](https://cli.github.com/). Đặt biến trước:

```sh
REPO=taovietducofficial/CI-CD-Kubernetes-GitOps   # đổi thành repo của bạn nếu fork
```

## 0. Fork sang tài khoản của bạn

Danh tính của repo nằm trong nhiều chỗ: URL Git cho Argo CD, tên image, subject chữ ký trong policy, CODEOWNERS. Hãy thay tất cả cùng lúc:

```sh
grep -rl --exclude-dir=.git taovietducofficial . | xargs sed -i \
  -e 's/taovietducofficial/<owner-cua-ban>/g' \
  -e 's/CI-CD-Kubernetes-GitOps/<ten-repo-cua-ban>/g'
```

Tên image trên GHCR phải viết thường (`ghcr.io/<owner>/<repo-viết-thường>`). Kiểm tra lại biến `IMAGE` trong `.github/workflows/ci.yml` và `image.repository` trong `deploy/chart/values.yaml`.

## 1. Quyền của GitHub Actions

```sh
gh api -X PUT repos/$REPO/actions/permissions/workflow \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=true
```

- `read` là mặc định an toàn. Mỗi job trong workflow tự khai báo đúng quyền nó cần (`permissions:`), nên không job nào có thêm quyền ngoài phần đã khai báo.
- `can_approve_pull_request_reviews=true` cho phép `promote.yml` mở PR. Tên của tuỳ chọn này gây hiểu nhầm, nhưng đây là công tắc *"Allow GitHub Actions to create and approve pull requests"*.

## 2. Environment `staging`

Job `deploy-staging` chạy trong environment `staging`. GitHub ghi lại lịch sử deploy, và chỉ nhánh `main` được phép deploy:

```sh
gh api -X PUT repos/$REPO/environments/staging --input - <<'EOF'
{ "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true } }
EOF
gh api -X POST repos/$REPO/environments/staging/deployment-branch-policies -f name=main -f type=branch
```

Production **không** có environment trên GitHub, vì GitHub Actions không bao giờ deploy production. Cổng duyệt của production là PR promote và CODEOWNERS.

## 3. Báo cáo lỗ hổng riêng tư

```sh
gh api -X PUT repos/$REPO/private-vulnerability-reporting
```

## 4. Đưa image lên public (sau lần chạy CI đầu tiên trên `main`)

Cluster kind và Kyverno cần kéo được image cùng chữ ký mà không phải đăng nhập. Vào **Profile → Packages → ci-cd-kubernetes-gitops → Package settings → Change visibility → Public**.

Kiểm tra:

```sh
docker logout ghcr.io && docker pull ghcr.io/taovietducofficial/ci-cd-kubernetes-gitops:<sha>
```

Nếu muốn giữ package private, phải tạo pull secret cho các namespace workload, và thêm `credentials.secrets` vào `verify-image-provenance` (secret nằm trong namespace `kyverno`).

## 5. Renovate

Cài [Renovate GitHub App](https://github.com/apps/renovate) cho repo. Renovate sẽ mở PR "Configure Renovate" (hoặc dùng luôn `renovate.json` có sẵn), rồi bắt đầu mở PR cập nhật mỗi sáng thứ Hai ([ADR-0007](adr/0007-renovate.md)).

## 6. Ruleset cho `main` (khuyến nghị cho team)

Ruleset biến các quy ước thành ràng buộc: mọi thay đổi đi qua PR, PR phải xanh, và thay đổi ở đường dẫn trong CODEOWNERS phải được owner duyệt.

```sh
gh api -X POST repos/$REPO/rulesets --input - <<'EOF'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "require_code_owner_review": true,
        "dismiss_stale_reviews_on_push": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "app" }, { "context": "codeql" }, { "context": "security" },
          { "context": "deploy-lint" }, { "context": "build" }, { "context": "e2e" }
        ]
      }
    }
  ]
}
EOF
```

**Đọc kỹ trước khi bật.** Ruleset này chặn mọi push trực tiếp vào `main`, *kể cả* commit `deploy(staging)` của job `deploy-staging`, vì job đó dùng `GITHUB_TOKEN`. Ở mức tổ chức, cách làm chuẩn là:

1. Tạo một GitHub App (ví dụ "release-bot") có quyền `contents: write` và `pull-requests: write`, rồi cài vào repo.
2. Thêm app đó vào `bypass_actors` của ruleset.
3. Trong `deploy-staging` và `promote.yml`, lấy token bằng [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token) thay cho `GITHUB_TOKEN`. Làm vậy còn có thêm lợi ích: PR promote sẽ kích hoạt CI.

Nếu repo chỉ có một người duy trì, GitHub không cho tự duyệt PR của chính mình. Hãy đặt `required_approving_review_count` là `0` và giữ các rule còn lại.
