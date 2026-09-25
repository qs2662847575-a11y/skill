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
