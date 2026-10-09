# 此目录为 forgejo 侧 workflow 目录占位

本仓库为 GitHub 主跑双宿仓库: `.github/workflows/` 的 CI 在 GitHub Actions
运行 — verify-mirrors 周巡检的 `issues: write` 是 github-script 开关 issue
的功能必需, permissions 等 GitHub 专属字段在 GitHub 侧有功能价值。

Forgejo 解析 workflow 时按 `.forgejo/workflows` > `.gitea/workflows` >
`.github/workflows` 顺序取**第一个存在**的目录 (无论其中有无 workflow 文件,
见 forgejo v15 源码 `modules/actions/workflows.go` `ListWorkflows` 的短路逻辑;
上游语义确认: forgejo#9203 — `.github/workflows` 解析仅为迁移兼容 shim)。

本目录的存在使 forgejo 只扫这里 (README 非 .yml, 不被识别为 workflow) 而
不再解析 `.github/workflows/` — 消除 Forgejo Actions 对 GitHub 专属字段
(如 job 级 `permissions`) 的"不支持"警告, 也不再产生无 runner 可跑的死
run (org runner 无 `ubuntu-latest` label)。GitHub 侧不受任何影响 (GitHub 不
读 `.forgejo/` 目录)。

占位实体是 `ci.yml` — `form: none` 豁免标记 (forgejo-actions 豁免制巡检的
形态契约, 本仓有意不接入 org CI; 语义见 forgejo-actions README「形态豁免」)。
形态须为**合法空 workflow**: 标记注释头 + `on: workflow_dispatch` +
`jobs: {}`。勿用纯注释文件 — null YAML 会被 forgejo 判 invalid workflow,
全事件触发且 run 即红 (v16 实测, PR #4 首版即踩此坑); 合法形态下自动事件
不匹配触发器, 零 run。

未来若需 forgejo 侧 CI: 将 `ci.yml` 改写为真实 workflow 并移除豁免标记
(`form: none` 是全仓豁免语义, 与接入互斥; 注意此时 `.github/workflows/` 对
forgejo 已整体失效, 双宿双跑需两侧文件分别维护)。
