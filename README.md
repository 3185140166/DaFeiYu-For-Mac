<p align="center">
  <img src="docs/icon.png" width="128" alt="白饭鱼 / BaifanYu">
</p>

<h1 align="center">大肥鱼 / DaFeiYu for Mac</h1>

<p align="center">
  A rice-eating whale girl who lives on your Mac desktop
  <br>
  <b>Native Swift · Offline pet · Optional AI chat · MIT code</b>
</p>

<p align="center">
  <i>A macOS port of the Android desktop pet
  <a href="https://github.com/LIN428924379/baifanyu">白饭鱼 / baifanyu</a> by
  <a href="https://github.com/LIN428924379">LIN428924379</a></i>
  <br>
  <b>Thank you, LIN428924379 — the original idea, the character, the artwork and the
  interaction design are all yours. 感谢原作者，这个移植只是把你的作品搬到了 Mac 上。</b>
</p>

---

## 当前定制版

基于 [duhaoze2007/Baifanyu-For-Mac](https://github.com/duhaoze2007/Baifanyu-For-Mac) 扩展，保留上游历史、作者署名和素材许可。

- 默认 Claude 卫衣大肥鱼，正面放松待机 / 开心姿态及四分之三侧身走路动画；菜单栏、聊天头像与应用图标使用同套形象。原饭盆头和女仆装仍可切换。
- 可配置兼容 Chat Completions 的模型接口，支持流式聊天、回车发送 / Shift+回车换行、停止生成。
- 独立多会话、新建 / 切换 / 删除会话；长对话按阈值增量摘要，保留近期原文与完整本地记录，并显示 token 用量。
- API Key 使用 macOS 钥匙串，聊天记录存放在应用支持目录，不包含在代码仓库。
- 点击桌宠显示 DeepSeek 官方 API 账户余额，缓存 60 秒；保留换表情和音效。
- 修复短距离拖离屏幕边缘后不恢复全身、右侧扒边点击检测及旋转裁剪比例。

构建运行：

```bash
bash build.sh
open BaifanYu.app
```

最低 macOS 14，需 Swift 6 工具链。应用显示名为「大肥鱼」，可执行文件、应用包名和本地数据目录保留 `BaifanYu` 以兼容既有数据。模型 API Key 需在聊天连接设置中自行配置。

代码采用 MIT；卫衣素材及衍生图标采用 CC BY-NC-SA 4.0，原美术素材亦有独立限制，详见下方许可和素材出处。

---

## What she is / 她是什么

She floats on your desktop as a tiny borderless window. Drag her anywhere; drop her at the left or right edge of the screen and she hangs there with only her head showing, so she never blocks what you are looking at. Click her for another expression and a rubber-duck squeak. Rest the pointer on her and she stops, showing a bubble with the date, a live clock and a random kind word; leave her alone and she wanders a little and changes expression by herself now and then.

她以一个极小的无边框窗口浮在桌面上。按住她可以拖到任意位置；拖到屏幕左右边缘松手，她会扒在边上、只露一个脑袋，绝不挡住你看的东西。点她一下换一个表情，顺便吱一声（小黄鸭音效）。鼠标停在她身上她就不动了，旁边浮出一个小气泡写着日期、时间和一句随机的关心话；没人理她的时候她会自己爬两下、时不时自己换个表情。

<p align="center">
  <img src="docs/expressions.png" width="760" alt="standing art + six expressions">
</p>

---

## Features / 功能

- **Floats on top** of every app, on every Space, over full-screen windows
- **Drag** her anywhere — she tilts in the direction you are dragging
- **Perch on a screen edge** — drag her to the left or right edge and let go: she hangs there, head rotated 90°, only her head visible
- **Six expressions** per skin, cycled by clicking her (whole artwork swaps, so no seams)
- **Random expressions** — while she idles she changes face by herself every 18–75 s (menu bar + Settings toggle)
- **Rest the pointer on her** and she stops wandering; a bubble appears with today's date, a live clock and a random kind word — move the pointer away and she carries on
- **Three skins**: Claude hoodie (default, idle + happy), bowl-head (饭盆头) and maid outfit (女仆装)
- **Rubber-duck squeak** on click, three real duck samples, can be switched off
- **Idle wandering** — she crawls around on her own; she stops when you touch, drag, perch her, or leave the pointer resting on her
- **Three size sliders**: floating height, head width while perched, amount of motion
- **Right-click menu** on her body: skin / next expression / settings / call her back
- **Menu bar resident**, no Dock icon — her face sits in the menu bar
- **Launch at login** support
- **Stops rendering when you cannot see her** (occluded, screens asleep, session locked)
- **Trilingual UI**: English / 简体中文 / 繁體中文 (follows the system or a manual override)
- **Offline pet, optional AI chat** — pet interactions work offline; chat sends summaries and recent turns to your configured provider when you send; long chats make an extra summarization request
- **MIT licensed code**, no third-party dependencies

---

- **浮在所有 App 之上**，所有桌面空间、全屏窗口上都在
- **拖拽** —— 拖到哪算哪，拖动时朝拖动方向倾斜
- **扒边** —— 拖到屏幕左右边缘松手，她扒在边上、头旋转 90°、只露一个脑袋
- **每套皮肤 6 个表情**，点她循环切换（整张立绘切换，没有接缝）
- **随机换表情** —— 闲着的时候她自己每隔 18~75 秒换一个表情（菜单栏 + 设置里都能开关）
- **鼠标停在她身上**：她就不走了，旁边浮出一个小气泡，写今天的日期、实时的时间和一句随机的关心话；鼠标移开她就继续
- **三套皮肤**：Claude 卫衣（默认，待机 + 开心）/ 饭盆头 / 女仆装
- **小黄鸭音效**：点击时随机播一个真实鸭叫，可关
- **自动溜达** —— 闲着的时候她自己爬来爬去；碰她、拖她、趴边、鼠标停在她身上时不动
- **三档调节**：悬空大小 / 扒边时脑袋宽度 / 动态幅度
- **右键菜单**：皮肤 / 换表情 / 设置 / 收回她
- **菜单栏常驻**，没有 Dock 图标 —— 她的脸就在菜单栏上
- **支持登录时自动启动**
- **看不见她的时候真的停止渲染**（被遮挡、屏幕休眠、会话锁定时）
- **三语界面**：English / 简体中文 / 繁體中文（跟随系统或手动切换）
- **离线桌宠，可选 AI 聊天**：桌宠互动离线运行；发送聊天消息时，摘要及近期原文会交给配置的服务商，长对话会额外请求模型生成摘要
- **MIT 开源代码**，无第三方依赖

---

## Requirements / 系统要求

- macOS 14.0 or later / macOS 14.0 或更高版本
- Apple Silicon or Intel / Apple Silicon 或 Intel
- No Xcode needed — Command Line Tools are enough / 无需 Xcode，装了 Command Line Tools 即可

Detailed version-by-version notes, the Android↔macOS comparison table and the known limitations:
**[RELEASE_NOTES.md](RELEASE_NOTES.md)**
版本说明、Android↔macOS 差异对照表和已知限制见 **[RELEASE_NOTES.md](RELEASE_NOTES.md)**。

## Build / 构建

```bash
bash build.sh          # → BaifanYu.app
open BaifanYu.app
```

The script builds in release mode, bundles the artwork, sounds and the app icon, and ad-hoc signs the result. `build.sh` also picks a working SDK automatically: on a Command Line Tools-only toolchain the newest SDK declares SwiftUI's property wrappers as macros whose plugin lives only inside Xcode, so the script falls back to the newest SDK where that is not the case.

脚本以 release 模式构建，把立绘、音效、图标全部打进 `BaifanYu.app` 并完成 ad-hoc 签名。`build.sh` 还会自动挑选可用的 SDK：在只装 Command Line Tools 的机器上，最新 SDK 会把 SwiftUI 的属性包装器声明成宏，而宏插件只随 Xcode 提供，所以脚本会自动回退到不启用宏的 SDK。

Extra scripts / 附带脚本:

```bash
swift scripts/gen_icon.swift            # 1024² app icon        → icon-src/AppIcon_1024.png
swift scripts/gen_menubar_icon.swift    # menu bar face (colour) → Sources/Resources/MenuBarIcon.png
swift scripts/gen_expressions.swift     # README montage         → docs/expressions.png
bash scripts/make_dmg.sh                # distributable disk image
```

---

## How to use / 怎么用

1. `open BaifanYu.app` — the first time, the system asks nothing and she simply appears
2. **Hold her and drag** to move her; **drag to the left or right screen edge and let go** to make her hang there
3. **Click her** for another expression (and a squeak)
4. **Rest the pointer on her** — she stops, and a bubble shows the date, a live clock and a random kind word; move away and she keeps wandering
5. **Right-click her** (or press and hold) for skin / next expression / settings / call her back
6. Her face in the **menu bar** is home base: bring her out or call her back, switch skin, toggle the squeak, the wandering and the random expressions, open **Settings (⌘,)** or **About**
7. Closing the settings window leaves her on your desktop — quit from the menu bar or with **⌘Q**

---

## macOS port notes / 移植说明

The Android original is a foreground service with a `TYPE_APPLICATION_OVERLAY` window. On macOS the equivalent is an **`NSPanel`** with `.nonactivatingPanel`, borderless, transparent, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. It cannot become key, so clicking her never steals focus from what you are typing in.

Three things from the original's "three hard rules for floating windows" carry over and are implemented:

| Android rule | macOS equivalent |
|---|---|
| The window must hug the pet, never a full-screen transparent layer | the panel is resized to exactly her bounding box, per state |
| The window must be non-focusable | `NSPanel` + `.nonactivatingPanel` + `canBecomeKey = false` |
| Rendering must really stop when invisible | the 60 Hz timer is torn down on occlusion, screen sleep and session lock |

Per-pixel click-through is added on top: a global + local mouse monitor toggles `ignoresMouseEvents` depending on the alpha of the pixel under the pointer, so the transparent margin around her does not swallow clicks meant for the app behind her.

The geometry is a direct port of the Android `PetView` — the same floating bob (`0.022 · amp · sin(2πt/2.4)`), the same breathing squash, the same drag tilt, the same `min(56 pt, width × 25 %)` edge-snap threshold, the same head-only crop while perched, and the original rest timings (0.8 s settle, 1.2–3.6 s rest, 5 s after a touch). Wandering now uses elapsed time, about 48 pt/s at the default size, and a distance-driven three-quarter illustrated gait for the hoodie skin. `dp` becomes points ~1:1, so the sliders keep their original ranges (120–480 / 56–160 / 30–150 %) and the defaults (240 / 96 / 75 %).

While she hangs on an edge, the same artwork is reused: rotated 90° and cropped to her head, exactly as on Android — no extra "perched" asset is needed.

---

## Project structure / 项目结构

```
Sources/
  App/
    BaifanYuApp.swift        @main, menu bar extra, first-launch dialogs
    AppSettings.swift        UserDefaults-backed settings (same keys & numbers as Android)
    LocalizationManager.swift 三语 UI strings
  Pet/
    PetSkin.swift            the two skins + their head-crop ratios
    PetBitmap.swift          pre-scaled / pre-rotated artwork + alpha hit testing
    PetView.swift            drawing, animation, mouse handling
    PetController.swift      panel, drag, edge snap, perch, wander, menu, sounds
    DuckSound.swift          duck squeak pool (AVAudioPlayer)
  Views/
    MenuBarView.swift        the menu bar dropdown
    SettingsView.swift       the settings window
    AboutWindow.swift        About window, launch-at-login helper
    HoverBubble.swift        the hover bubble (date / clock / kind word)
    BundledImage.swift       resource lookup
  Resources/                 artwork + duck samples + icon
```

---

## Credits & thanks / 致谢与许可

### Thank you / 特别感谢

**This project is a port. Nothing here would exist without
[LIN428924379/baifanyu](https://github.com/LIN428924379/baifanyu) — the original Android app by
[@LIN428924379](https://github.com/LIN428924379).**

**All credit for the concept, the character, the artwork and the interaction design belongs to
the original author. The macOS port reuses their artwork, their interaction design and their
animation maths, and only re-implements the code for macOS. Thank you for building it and for
releasing it under the MIT license. 感谢原作者把《白饭鱼》开源出来 —— 这个 macOS 版只是把她的家从手机
搬到了 Mac 上，创意、角色、立绘、动作设计全部属于原作者。**

### What comes from where / 各部分出处

| Part / 部分 | Origin / 出处 |
|---|---|
| Original app, concept, interaction design / 原应用、创意、交互设计 | [LIN428924379/baifanyu](https://github.com/LIN428924379/baifanyu) (MIT) |
| Standing art & 6 expressions per skin / 立绘与 6 个表情 | The original author's assets (community fan art, **not** MIT) / 原作者的素材（社区同人创作，**不在 MIT 范围**） |
| Duck squeaks / 小黄鸭音效 | [Mixkit](https://mixkit.co/free-sound-effects/duck/) (Mixkit Free License) |
| Character / 角色形象 | DeepSeek-community whale girl, as delivered with the original app / 随原应用提供的 DeepSeek 社区鲸鱼娘 |
| macOS code (SwiftUI + AppKit) / macOS 代码 | This repository, MIT, © 2026 Du Haoze |
| macOS support / 本移植 | © 2026 [Du Haoze](https://github.com/duhaoze2007) |

### License / 许可证

- **Code**: MIT — see [LICENSE](LICENSE) (keeps the original copyright notice alongside this port's)
- **Artwork** (`Sources/Resources/*.png`, `docs/`): community fan art from the original project, **not** covered by MIT — personal, non-commercial use only
- **代码**：MIT —— 见 [LICENSE](LICENSE)（许可证里同时保留了原作者和本移植的版权声明）
- **美术资源**（`Sources/Resources/*.png`、`docs/`）：来自原项目的社区同人创作，**不在 MIT 许可范围内**，仅限个人非商业使用

macOS version © 2026 Du Haoze · Original Android app © 2026 LIN428924379


## AI chat / AI 聊天

Open **Chat with DaFeiYu** from the menu bar, the pet's right-click menu, or Settings.
In **Connection settings**, enter the full Chat Completions endpoint URL, your provider's model ID and API key.
The endpoint must support streaming (`stream: true`, SSE `data:` events with `choices[].delta.content`).
Use HTTPS for remote services; HTTP is accepted only for localhost.

从菜单栏、桌宠右键菜单或设置打开「和大肥鱼聊天」，点击齿轮配置：

- **接口地址**：填写完整聊天接口，例如 `https://api.deepseek.com/chat/completions`，而不是仅填写域名。
- **模型名称**：按服务商提供的模型 ID 填写，不使用 Codex CLI 登录凭证。
- **API Key**：按接口地址分别保存在 macOS 钥匙串。本机无需认证的服务可留空。
- **本机服务**：例如支持兼容接口的 `http://localhost:11434/v1/chat/completions`，模型须提前安装并启动服务。

Press **Return** or click Send; **Shift+Return** inserts a new line. Stop cancels generation and keeps any received text.
Closing the chat window also stops generation. The plus button starts a new conversation, the history button switches conversations, and the trash button permanently deletes the selected conversation after confirmation.
A fixed character prompt, a per-conversation rolling summary (if available) and recent verbatim turns are sent to the selected provider. Compaction triggers at about 4,000 estimated input tokens or 12,000 recent content characters, and only when there is enough older material to amortize the summary request.
History is stored as plaintext in `~/Library/Application Support/BaifanYu/chat.json`; keys are never stored there.
Provider fees and data policies apply. No API call occurs simply from opening chat or saving connection settings.
Other pet features remain offline. Conversations are independent; the active conversation is shared across model connections: clear it before switching providers if you do not want to send previous messages to the new provider.

按 **回车** 或「发送」聊天，**Shift＋回车**换行；「停止」或关闭聊天窗口会取消生成并保留已收到的文字。
聊天记录以明文保存在本机 `~/Library/Application Support/BaifanYu/chat.json`，可通过加号新建会话、历史按钮切换会话、垃圾桶按钮确认永久删除当前会话。
每次发送会将角色设定、当前会话摘要（如有）和近期原文交给当前模型服务。约 4,000 估算输入 tokens 或 12,000 原文字符触发压缩；有足够较早消息时才额外请求一次摘要，可能产生 API 费用。
打开聊天和保存设置不会自动发起模型请求。各会话相互独立；同一会话可切换模型连接，切换服务商前可先清空，避免把旧对话发送给新服务商。

Developer validation / 开发验证：`python3 Tests/run_chat_tests.py` runs the real chat store against a local mock streaming server without Xcode, API keys or paid requests.

当前定制版界面及聊天角色名为「大肥鱼 / DaFeiYu」。保留原应用标识、可执行文件名及数据路径，已有设置、密钥和对话继续可用；原作者作品名与版权声明保留。

会话记录继续保存在 `chat.json`，格式升级为包含会话列表、当前会话 ID 和版本号的对象。旧版消息数组在首次保存时自动迁移为一个会话，保留原消息 ID 和正文。新会话不发送其他会话的内容；历史窗口可以删除单个会话，删除最后一个后自动保留一个空会话。生成回复时需先停止，才能切换、新建或删除会话。单条输入上限 8,000 字符；字符限制不等同于精确 token 计数，不含固定角色提示词。


### Rolling memory / 滚动摘要

- A short conversation reuses verbatim history. Many short turns are not dropped just because the count exceeds 21.
- At approximately 4,000 estimated input tokens (or the raw-text character guard), summarize older complete turns while keeping recent turns verbatim. The last completed exchange and current question are always excluded from the summary request.
- Summarization uses the same configured endpoint/model and credential as chat. It receives the previous summary plus only the next batch of unsummarized older messages, not the whole conversation. A single summary input batch is bounded at about 8,000 estimated content tokens, with a 600-token output cap. Oversized imported histories may need several chat requests to catch up.
- Each conversation stores an optional summary with a version and covered message ID in `chat.json`; original messages are never deleted by compression. New conversations start without memory; deleting or clearing one removes its summary too.
- A summary is committed only after complete generation and local persistence. Failure keeps prior memory and falls back to recent messages, with a retry cooldown of six added messages. Stop/close cancels both summarization and reply generation.
- The provider-neutral estimate uses UTF-8 byte length / 2 plus message overhead. It is not an exact tokenizer or a guarantee of model context fit. Large recent individual messages may exceed the soft target. Original fallback guards (21 recent messages / 12,000 content characters) apply when the complete recent context does not fit the soft budget. Omitted gaps are explicitly marked for the model.
- **上下文与用量** shows the estimated chat input separately from provider-reported chat/summary usage and optional cache-hit counts. Numbers are for the latest send only, not a cumulative bill or guaranteed savings. Missing provider usage stays unavailable. In Connection settings, disable usage reporting if a provider rejects `stream_options`.

滚动摘要会产生额外模型请求；短会话不压缩，长会话分批压缩并跨轮复用。摘要可能遗漏信息，重要原文仍可在本地历史查看。摘要作为历史资料发送，不提升为系统指令。没有跨会话记忆，也没有后台定时模型请求。聊天停止、切换、新建、删除和旧格式迁移的行为保持一致。


### Click for DeepSeek balance / 点击查询 DeepSeek 余额

After saving the official DeepSeek chat endpoint and API key in chat connection settings, click the pet to change expression and display the official account balance for about eight seconds. The read-only request is `GET https://api.deepseek.com/user/balance`, authenticated using the same endpoint-specific Keychain credential. This does not invoke a chat model or send conversation text. Hovering without clicking still shows the date/clock/caring sentence.

点击角色保留换表情和音效，并显示官方 API 账户余额、币种和查询时间，约 8 秒后恢复原悬停气泡。成功结果在内存缓存 60 秒；连续点击合并请求，失败后短暂冷却，不会轮询。切换密钥后不会复用其他账户的余额；缓存过期查询失败时显示不可用，不冒充最新余额。查询不使用大模型，不消耗聊天 tokens。未配置密钥、非官方域名、网络或接口错误均会明确提示；仅允许官方 HTTPS 域名，拒绝重定向。余额不会写入聊天记录或发送给模型。

Validation / 验证：`bash Tests/run_balance_tests.sh` exercises mocked balance responses, host restrictions, cache expiry, credential isolation, concurrent clicks and error handling without reading your real API key or calling the real account endpoint.


### Default Claude hoodie skin / 默认 Claude 卫衣皮肤

默认形象为「Claude 卫衣」：待机使用基于 CrossPet 衍生的正面放松立绘，双手自然下垂；点击切换到 happy 开心立绘，再点回到待机；闲置随机换表情也在这两张之间切换。原饭盆头和女仆装保留，可在设置或菜单栏切回。首次运行这个版本会一次性切换至卫衣，此后的手动选择会记住。菜单栏、聊天头像、设置页和应用图标使用同套卫衣形象。

The original CrossPet sources are preserved; the current hand-refined derivatives expose readable palms and orange sleeve trim, normalized onto a shared transparent canvas. Hoodie expressions are counted dynamically; the original skins keep their six expressions. Head-only edge cropping preserves the rotated source aspect ratio.

卫衣立绘及衍生图标：**CrossPet / lokicorvus and CrossPet contributors**；角色设计：**上善无形 / ZipZipPipe**。采用 **CC BY-NC-SA 4.0**，须署名、非商业使用、相同方式共享，不适用代码 MIT 许可。素材出处、固定版本、文件校验值和修改说明见 [artwork-src/claude-hoodie/README.md](artwork-src/claude-hoodie/README.md)，原许可及出处也随应用资源打包。

Skin validation / 皮肤验证：构建应用后执行 `bash Tests/run_skin_tests.sh`，验证默认迁移、手动切换保留、素材加载、两种姿态切换、透明画布和扒边比例。


### 本机 GitHub 发布配置

可在项目根目录的 `.env.github-publish` 中本地填写 `GITHUB_USERNAME` 和 `GITHUB_PAT`。该文件已被 Git 忽略，文件权限设为仅当前用户可读写。PAT 是敏感凭据，不要发到聊天、截图、日志或仓库；不要将其拼入 Git 远程 URL。该文件为明文，适合临时使用，发布完成后可清空 `GITHUB_PAT`；文件权限不提供加密。配置完成后只需告知「已填好」，不要发送变量内容。

卫衣手部优化：两种姿态的小手已伸出袖口，采用肤色、手指轮廓和橙色袖边，提升桌宠尺寸下的辨识度。原版素材保留，编辑提示词及处理说明见 `artwork-src/claude-hoodie/hand-refinement/PROMPTS.md`。


### Hoodie walking animation / 卫衣走路动画

当前步态使用完整的四分之三侧身立绘，左右各八帧；不再剪切或重新拼接腿部，避免裙摆、大腿出现透明断层。停止后以 0.16 秒过渡回正面放松姿态，保留点击时的开心举手。

步态按实际移动距离推进，移动按时间计算：默认约 48 pt/s，随角色大小调整并限制在 28–72 pt/s。悬停、拖动、扒边、关闭自动溜达或到达目标都会停止迈腿。其他皮肤保留原立绘和身体起伏。

素材归一化到 896×640 透明画布，左右步态与正面立绘对齐脸部位置、共用缩放比例。加宽透明画布以容纳不同朝向的尾巴，实际人物高度仍由原滑块控制；透明处继续点击穿透。扒边使用正面头部裁剪，不使用走路图。脚底、尾巴均留出透明边距。

Illustrated frames are decoded and cached once; only the current pixel size's gait rasters remain cached. Drawing and alpha hit testing use the same active frame. Pose transitions include both visible silhouettes in alpha hit testing. Existing sleep/occlusion suspension is retained. Source sprites, edits and prompts are in `artwork-src/claude-hoodie/motion-v3/` and `motion-v4/`, prepared using built-in image_gen with transparent backgrounds; small linework variations may remain from generation; detected name badges are re-typeset as Claude.

![四分之三侧身步态预览](docs/hoodie-walk-preview.gif)

Rebuild assets with `swift scripts/prepare_hoodie_art.swift` then `bash scripts/prepare_hoodie_motion.sh`; regenerate icons using the existing scripts. The source sheets, relaxed idle, derived frames and GIF retain CC BY-NC-SA 4.0, credit CrossPet / lokicorvus and CrossPet contributors, 上善无形 / ZipZipPipe. `bash Tests/run_skin_tests.sh` verifies both eight-frame cycles, matching canvases, transparent safety margins, pose transitions, stride phase and timer-independent speed.


步态 v4：默认速度为 48 点/秒，完整循环约 1.2 秒。切帧后仅通过连通区域检测清除远离角色的相邻帧边角，保留完整身体、细节和抗锯齿。v5 新增另一只脚领先的后半周期，近侧花纹靴从前方移到后方，远侧脚迈到前方。v6 对换脚素材重新校色，并在解码缓存时统一蓝色和橙色的色相、饱和度；保持透明轮廓和明暗层次，避免换脚时突然变色。仍保留少量插画线条变化。处理细节见 `artwork-src/claude-hoodie/motion-v4/PROMPTS.md`；再生成入口为 `bash scripts/prepare_hoodie_motion.sh`。
