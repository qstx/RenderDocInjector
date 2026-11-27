# Vulkan模式下从MuMu模拟器中截帧的方法

让 **RenderDoc 能 attach 到 MuMu 模拟器的 Vulkan 渲染进程**，从而抓取渲染帧。

## ⚠️ 用之前先把路径改成你自己的

仓库里的脚本写死了下面两条默认路径，**都是原作者机器上的位置**，直接跑会失败：

| # | 要改什么 | 在哪儿改 | 默认值 |
|---|---|---|---|
| 1 | **RenderDoc 安装路径** | `tools\gen_manifest.py` 顶部两个常量：`RENDERDOC_JSON`、`RENDERDOC_DLL` | `C:\Program Files\RenderDoc\renderdoc.json` / `C:\Program Files\RenderDoc\renderdoc.dll` |
| 2 | **MuMu 模拟器路径** | 仓库根 `README.md` 里 d3d11 注入器那条流程（本 vulkan 方案**不需要** MuMu 路径，见下） | `C:\Program Files\Netease\MuMuPlayer-12.0\device` |

首次使用、修改安装路径或更换 RenderDoc 版本后，请用当前安装的 RenderDoc **重新生成 manifest 并注册**。生成的 manifest 里 `library_path`
是绝对路径，不重跑就还指着旧位置：

```
python tools\gen_manifest.py
deploy\register-layer.bat        :: 以管理员身份运行
```

> **为什么本 Vulkan 方案不用改 MuMu 路径**：Vulkan loader 从注册表读取层配置，跟 MuMu 装在哪个目录无关。

## 前置要求（Requirements）

| 项 | 要求 | 说明 |
|---|---|---|
| 操作系统 | Windows 10 / 11 **x64** | 本方案依赖 Windows 上的 Vulkan loader 注册表机制 |
| Vulkan loader | `%SystemRoot%\System32\vulkan-1.dll` 必须存在（其 Product 名为 `Vulkan Runtime`） | **不是 Vulkan SDK**：这个 loader 通常随**显卡驱动**安装，Windows 自身不附带。没有它，MuMu 的 Vulkan 模式本身就起不来 |
| RenderDoc | **已安装** | 需要 64 位 `renderdoc.dll`，且版本必须与 `qrenderdoc.exe` 一致（用 `(Get-Item 文件).VersionInfo` 对比） |
| MuMu 模拟器 | MuMu 12 / MuMu 15（实测），渲染模式必须是 **Vulkan（高性能）** | DirectX / 稳定模式 = ANGLE 的 D3D11 后端，最多 GLES 3.1，很多游戏会直接崩，本方案在该模式下也不生效 |
| 权限 | **需要管理员** | 写 `HKLM`。MuMu 以管理员权限（elevated）运行，而 elevated 进程里的 Vulkan loader **完全不读 `HKCU` 的 layer**，所以只写 `HKCU` 对 MuMu 无效 |

**Vulkan SDK 不需要**：本方案不编译任何代码。

## 用（三步）

```
deploy\register-layer.bat      :: 1. 注册（HKLM，以管理员身份运行）
                               :: 2. 完全退出并重启 MuMu，渲染模式保持 Vulkan（高性能）
                               :: 3. 起游戏 → qrenderdoc → File → Attach to Running Instance
```

⚠️ 撤销：

```
deploy\unregister-layer.bat    :: 同样以管理员身份运行
```

⚠️ 注册期间，符合条件的 64 位 Vulkan 程序会自动加载这个层。抓完帧或重新安装 RenderDoc 前，请先撤销，以恢复脚本临时停用的官方 64 位层注册。

## 原理一句话

RenderDoc 的 Vulkan 支持是个 **layer**，必须由 Vulkan loader 自己加载；它默认被
`enable_environment: ENABLE_VULKAN_RENDERDOC_CAPTURE=1` 关着。而 MuMu 的渲染进程
（MuMu 12 是 `MuMuVMMHeadless.exe`，MuMu 15 是 `MuMuNxHeadless.exe`）由服务链启动，继承的是**服务环境**，用户设的环境变量传不进去，
DLL 代理劫持 `vulkan-1.dll` 也实测无效。于是唯一可行的办法就是：**注册一份"去掉门槛"的
隐式 layer**，让 loader 自己把它挂上。

注册需要处理两个问题：

1. **两个注册项不能同时启用。** 单纯保留官方名字，loader 可能按名称去重并留下带门槛的官方项；
   单纯改名，loader 又可能把同一个 `renderdoc.dll` 加进两次调用链。新版脚本在启用
   `VK_LAYER_RENDERDOC_Capture_Ungated` 前，先临时停用 HKLM 下已启用的官方 `renderdoc.json` 项；
   撤销时恢复原来启用的项，不改 RenderDoc 安装目录里的文件。
2. **必须写 HKLM，不能写 HKCU。** MuMu 以 elevated 身份运行（关掉 UAC 的机器上所有进程都是 elevated），
   elevated 进程里的 loader 只扫描 `HKLM\...\ImplicitLayers`，`HKCU` 里的条目根本不会被读到。

## 目录

| 路径 | 说明 |
|---|---|
| `deploy\renderdoc-layer-ungated.json` | 去门槛的 layer manifest（由 gen_manifest.py 生成） |
| `deploy\register-layer.bat` | 注册到 HKLM 的 64 位 `ImplicitLayers`，临时停用官方层并清理当前用户的旧副本（需管理员） |
| `deploy\unregister-layer.bat` | 移除副本并恢复被临时停用的官方层（需管理员） |
| `deploy\manage-layer.ps1` | 两个批处理共用的注册逻辑；在 HKLM 记录需恢复的官方项 |
| `tools\gen_manifest.py` | 从 RenderDoc 自带的 `renderdoc.json` 重新生成 manifest（**顶部路径常量按你的安装位置改**） |

## 验证装没装成功

注册后，MuMu 渲染进程的模块表里应出现你 RenderDoc 目录下的 `renderdoc.dll`
（在管理员 PowerShell 里执行）：

```powershell
Get-Process MuMuVMMHeadless, MuMuNxHeadless -ErrorAction SilentlyContinue |
  %{ $_.Modules | ? ModuleName -match renderdoc }
```

如果没有，可以用 loader 日志看它对 layer 做了什么（输出里搜 `RENDERDOC`）：
看到 `Insert instance layer "VK_LAYER_RENDERDOC_Capture_Ungated"` 说明 loader 已经加载了；
如果看到两种 RenderDoc 层都被插入，先撤销再重新注册。

```bat
set VK_LOADER_DEBUG=layer,warn,error
vkcube.exe
```

注意：**不要**用 `vkEnumerateInstanceLayerProperties` 判断 —— 被门槛关掉的 layer
照样可能出现在那个列表里。

## `hello_triangle` 启动时崩溃

在 RenderDoc 1.47 / Vulkan Loader 1.4.357 上，旧版脚本留下的两个注册项并存时，
样例会在 RenderDoc 的 `vkEnumeratePhysicalDevices` 中触发 `0xC0000005`。将任意一个注册项停用，
让另一个单独加载，样例均能渲染 120 帧并正常退出。已有旧注册时，从管理员命令行重新运行新版
`deploy\register-layer.bat` 即可切换到互斥配置；只想恢复原状时，运行 `deploy\unregister-layer.bat`。
