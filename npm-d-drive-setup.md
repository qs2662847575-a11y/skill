# npm 全局安装位置迁移到 D 盘 — 配置记录

## 当前配置

| 项目 | 值 |
|---|---|
| 全局包目录 (prefix) | `D:\大模型\skill\npm-global` |
| npm 缓存 (cache) | `D:\大模型\skill\npm-cache` |
| 配置文件 | `C:\Users\1234\.npmrc`（UTF-8 无 BOM） |
| PATH | 用户级 PATH 已追加 `D:\大模型\skill\npm-global` |

`.npmrc` 内容：

```
prefix=D:\大模型\skill\npm-global
cache=D:\大模型\skill\npm-cache
```

## 验证方法（新开一个终端）

```powershell
npm config get prefix     # 应输出 D:\大模型\skill\npm-global
npm config get cache      # 应输出 D:\大模型\skill\npm-cache
npm root -g               # 应输出 D:\大模型\skill\npm-global\node_modules
```

## 已知注意事项

### 1. 不要用 `npm config set` 修改含中文的路径

在中文 Windows 上 npm 可能用 GBK 回写 `.npmrc`，导致路径变乱码。
直接编辑 `C:\Users\1234\.npmrc` 并保存为 **UTF-8** 更安全。

### 2. 在 DSH 会话内 npm 仍会写 C 盘（环境变量优先级问题）

`npm_config_*` 环境变量优先级高于 `.npmrc`。DSH 的 shell 继承了这些变量：

```
npm_config_global_prefix = C:\Users\1234\AppData\Roaming\npm
npm_config_cache         = C:\Users\1234\AppData\Local\npm-cache
```

它们来自启动 `dsh` 的那个终端（`npm install -g @deepseek-ai/dsh` 时 npm 注入的），
DSH 自身代码不设置它们。因此：

- **普通新终端**：配置已生效，全局安装走 D 盘。
- **DSH 会话内**：若要立即走 D 盘，先清掉这几个变量，或从「干净的新终端」重新启动 dsh。

在 DSH 会话内临时生效的写法：

```powershell
Remove-Item env:npm_config_global_prefix, env:npm_config_prefix, env:npm_config_cache -ErrorAction SilentlyContinue
npm config get prefix   # 此时应为 D:\大模型\skill\npm-global
```

## 已安装的全局包（仍在 C 盘，未迁移）

按你的选择「只改配置位置，不迁移已有内容」，以下包保留在
`C:\Users\1234\AppData\Roaming\npm`：

| 包 | 说明 |
|---|---|
| `@deepseek-ai/dsh` | 当前正在运行 DSH，不可在运行中删除 |
| `@alibaba-group/open-code-review` | `ocr` 命令 |
| `pnpm` | |
| `@mimo-ai/cli` | |
| `npm` | npm 自身所在目录 |

如需后续迁移，在新终端中重装即可（会装到 D 盘），例如：

```powershell
npm install -g @alibaba-group/open-code-review
```

## 磁盘占用参考

| 位置 | 占用 |
|---|---|
| `C:\Users\1234\AppData\Roaming\npm` | 约 994 MB |
| `C:\Users\1234\AppData\Local\npm-cache` | 约 908 MB |

（`Get-PSDrive` 在本机上报剩余空间为 0 是不准确的，实际以 `Win32_LogicalDisk` 为准。）

## 附：open-code-review（ocr）常用命令速查

### 前置条件

`ocr review` 要求当前目录是 Git 仓库，且已配置 LLM 端点。

```powershell
ocr config provider      # 交互式选厂商 + 填 API Key
ocr config model         # 选模型
ocr llm test             # 测连通性
ocr llm providers        # 列出全部内置厂商
```

### 审查

```powershell
ocr review                                  # 工作区：已暂存 + 未暂存 + 未跟踪
ocr review --from main --to feature-branch  # 分支区间（merge-base）
ocr review --commit abc123                  # 单个 commit（对比父提交）
ocr review --preview                        # 只预览范围，不调 LLM
ocr scan --path src/agent                   # 整文件扫描，不需要 diff
```

### 输出与查看

```powershell
ocr review --format json -o review.json     # JSON 输出
ocr review --audience agent                 # 仅摘要，适合程序消费
ocr viewer                                  # 浏览器查看历史会话，默认 localhost:5483
ocr session list                            # 列出当前仓库的会话
```

### 常用调优参数

| 参数 | 作用 | 默认值 |
|---|---|---|
| `--effort` | 审查力度 `low` / `medium` / `high` | `medium` |
| `--concurrency` | 最大并发子任务数 | 8 |
| `--exclude` | 逗号分隔的 gitignore 风格排除模式 | 无 |
| `--background` | 需求/业务背景，提升准确度 | 无 |
| `--max-tokens-budget` | 卡本次审查总 token 上限，0 为不限 | 0 |

### 免 API Key 的 Delegation 模式

由宿主 agent 用自身模型执行审查，OCR 只负责选文件和套规则：

```powershell
ocr delegate preview                            # 预览可审查文件
ocr delegate rule src/main.go src/handler.go    # 输出解析后的审查规则
```
