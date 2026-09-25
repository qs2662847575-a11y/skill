# GitHub Actions 配置指南 —— PR 自动审查

工作流文件已生成在 `.github/workflows/ocr-review.yml`。

> **当前状态：还不能运行。** 这个仓库没有配置任何 git 远端（`git remote -v` 为空），
> GitHub 看不到它，Actions 自然不会触发。需要先建仓库并推送。

## 一、创建 GitHub 仓库并推送

在 GitHub 上新建一个仓库（空仓库，**不要**勾选自动生成 README），然后：

```powershell
cd D:\大模型\自动化工作流\skill
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

推送前请确认身份没问题。当前本仓库的提交身份是本地占位值：

```
user.name  = skill-local
user.email = skill@local
```

如果想让提交显示为你的 GitHub 身份，改成真实值（`--global` 会作用于所有仓库，这里只改本仓库更安全）：

```powershell
git config user.name  "你的名字"
git config user.email "你的邮箱"
```

已经产生的 4 个提交不会改（改历史需要 rebase，本地仓库没必要）。

## 二、配置 Secret 和 Variables

进入 GitHub 仓库页面 → **Settings → Secrets and variables → Actions**。

### Secrets 标签页 → New repository secret

| Name | Value |
|---|---|
| `OCR_LLM_AUTH_TOKEN` | 你的 DeepSeek API Key（`sk-` 开头） |

### Variables 标签页 → New repository variable

| Name | Value |
|---|---|
| `OCR_LLM_URL` | `https://api.deepseek.com` |
| `OCR_LLM_MODEL` | `deepseek-flash` |
| `OCR_LLM_USE_ANTHROPIC` | `false` |

为什么 Key 放 Secret、其余放 Variable：只有 Key 是机密。URL 和模型名放在 Variable 里可以在日志中明文显示，便于排错。

> `GITHUB_TOKEN` 不用配，GitHub 自动提供。

## 三、验证

1. 建一个分支，改点代码，提 PR。
2. 进 **Actions** 标签页，应看到 `OpenCodeReview PR Review` 运行。
3. 跑完后 PR 会话里会出现一条摘要评论，代码差异页出现行内评论。
4. 在 PR 里评论 `/open-code-review` 可以手动重审。

## 四、工作流关键设置的取舍

| 设置 | 值 | 原因 |
|---|---|---|
| 触发器 | `pull_request_target` | fork 提的 PR 也能拿到 secrets。安全前提：该 action 只读 diff，不执行 PR 里的代码 |
| 固定版本 | action pin 到 `bccbc15f`（v1.12.9） | 避免 `@main` 漂移导致审查行为突变 |
| `ocr_version` | 未设置（默认 `latest`） | 想让审查行为也完全可复现，需同时固定：加 `ocr_version: '1.12.9'` |
| `llm_extra_body` | `'{}'` | 见下方说明 |
| `language` | `Chinese` | 审查意见用中文 |
| `max_tokens_budget` | `3000000` | 单次审查总 token 上限，防大 PR 烧钱 |
| `incremental` | `'true'` | 只追加不重复的行内评论，历史不删 |
| `sticky_summary` | `'true'` | 摘要评论原地更新，不刷屏 |
| 并发组 | 条件化 per-PR | 官方示例的写法。用扁平 group 会导致「任意一条普通评论取消正在跑的审查」 |

### 关于 `llm_extra_body`

action 默认发送 `{"thinking": {"type": "disabled"}}`。我实测过 DeepSeek 对三种写法**都返回 HTTP 200**：

```
[action 默认 extra_body]              HTTP 200
[我配置的 {}]                          HTTP 200
[官方 workflow 用的 enable_thinking]   HTTP 200
```

所以传 `{}` 是稳妥起见而非必需。换到别的厂商（尤其 Anthropic）时注意：Anthropic API 会拒绝未知字段。

## 五、成本与额度

| 项目 | 说明 |
|---|---|
| GitHub Actions 分钟数 | **公开仓库免费无限**；私有仓库每月 2000 分钟免费额度（Windows/macOS runner 有倍率，`ubuntu-latest` 是 1x） |
| 单次审查耗时 | 本机实测：1 个文件的小改动约 1～4 分钟；大 PR 会更久（工作流设了 30 分钟上限） |
| 单次审查 token | 本机实测 3 万～20 万 tokens 不等，取决于改动规模 |
| LLM 费用 | 由 DeepSeek 按量计费，与 GitHub 无关。`max_tokens_budget` 是唯一的硬闸 |

想更省：把 `effort` 改成 `low`，或调低 `max_tokens_budget`。

## 六、常见排错

| 现象 | 原因 |
|---|---|
| Actions 里完全没有运行记录 | 仓库没推上去，或工作是流文件不在默认分支上（PR 触发要求工作流已存在于默认分支） |
| 报 `Failed to parse OCR output` | 看运行日志里 `Run OpenCodeReview` 步骤，或下载 `ocr-review-result-*` artifact 里的 `ocr-stderr.log`；多为 Key 无效或模型名不对 |
| 评论没出现 | 检查 job 的 `permissions` 是否含 `pull-requests: write` |
| 评论没落在预期行号 | 行内评论锚定在 PR head commit 上；若审查期间被 force-push，GitHub 会拒绝行内投递，该评论改渲染到摘要里 |
| 模型名报错 | DeepSeek 只认 `deepseek-flash` 和 `deepseek-v4-pro`（本机踩过这个坑） |

## 七、升级指南

action 固定在 commit SHA 上，所以不会自动跟随上游。升级步骤：

1. 打开 https://github.com/alibaba/open-code-review/releases 取新版本 tag。
2. 解析 tag 对应的 commit SHA（附注标签需要点进去看 `object.sha`）。
3. 改 `.github/workflows/ocr-review.yml` 里的 `uses:` 那一行，并同步注释里的版本号。
4. 想连 CLI 行为一起固定，再加 `ocr_version: 'X.Y.Z'`。

若不在乎可复现性、只想始终跑最新，把 `uses:` 改成 `alibaba/open-code-review@main` 即可（官方示例就是这么写的）。
