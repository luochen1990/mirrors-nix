# 此目录为 forgejo 侧 workflow 目录占位

本仓库为 GitHub 主跑双宿仓库: `.github/workflows/` 的 CI 在 GitHub Actions
运行 — verify-mirrors 周巡检的 `issues: write` 是 github-script 开关 issue
的功能必需, permissions 等 GitHub 专属字段在 GitHub 侧有功能价值。

Forgejo 解析 workflow 时按 `.forgejo/workflows` > `.gitea/workflows` >
`.github/workflows` 顺序取**第一个存在**的目录 (无论其中有无 workflow 文件,
见 forgejo v15 源码 `modules/actions/workflows.go` `ListWorkflows` 的短路逻辑;
上游语义确认: forgejo#9203 — `.github/workflows` 解析仅为迁移兼容 shim)。

本目录 (含本 README, 非 .yml 不被识别为 workflow) 的存在使 forgejo 只扫这里
(空) 而不再解析 `.github/workflows/` — 消除 Forgejo Actions 对 GitHub 专属
字段 (如 job 级 `permissions`) 的"不支持"警告, 也不再产生无 runner 可跑的死
run (org runner 无 `ubuntu-latest` label)。GitHub 侧不受任何影响 (GitHub 不
读 `.forgejo/` 目录)。

未来若需 forgejo 侧 CI: 直接在此目录放置 workflow yml 即可 (注意此时
`.github/workflows/` 对 forgejo 已整体失效, 双宿双跑需两侧文件分别维护)。
