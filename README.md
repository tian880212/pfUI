# pfUI — 个人修改版

> **非官方修改版。** 基于 [Shagu/pfUI](https://github.com/Shagu/pfUI)（MIT 许可）修改，
> 面向 **Turtle WoW / WoW 1.12 (Interface 11200)** 客户端。
> 本仓库与 Shagu 本人无关，上游问题请勿提交到原仓库。

一套完整的界面替换插件。本仓库在保留 pfUI 原有结构与皮肤体系的前提下，
针对 1.12 客户端的实际使用场景做了若干修正与增强，重点在**光环计时**、
**团队框架布局**、**解锁与布局保存**、**中文本地化** 和 **加载开销**。

---

## 与上游的主要差异

### 光环 / 减益监控

- 接入 **Nampower v4** 事件流：`BUFF_ADDED|REMOVED|UPDATED`、`DEBUFF_ADDED|REMOVED|UPDATED`、
  `SPELL_GO_SELF|OTHER`，替代原先基于战斗日志文本匹配的路径。
- 用 `SPELL_GO`（命中后触发，带 `numHit`/`numMissed`/`targetGuid`）修正计时漂移：
  DoT 被**刷新**时重置起始时间、被**叠加消耗**时按层扣除，且只改 `startTime` 不动
  `duration`，使所有 `(startTime + duration) - now` 的读取点（含进度环）自动同步。
  客户端在重挂光环时不会补发 `DEBUFF_ADDED`，这是上游计时偏早/偏晚的主因。
- `auraFlags` 按槽位解码：该字段是 **6 × uint32 覆盖 48 个槽位、每槽 4 bit**，
  直接按 `auraFlags[slot]` 取值拿到的是"第 slot 个 32 位块"，判据永远不可能命中。
- 溢出槽位加**单调闩锁**：光环在 buff 区与 debuff 区之间的归属会随战斗状态翻转，
  若直接拿实时状态当判据，同一批图标会在两行之间整批跳动。闩锁只置位不清位。
- 一次 `GetUnitField(guid, "aura")` 取回完整的 48 项快照并透传，避免在循环里重复调用。

### 姓名板

- 中文本地化与显示对齐（贴近 TBC 风格的排版与间距）。
- 边框颜色判定链整理为"前项命中即短路"的顺序，便于逐项排查。
- 新增 `pfUI_HidePlateElements` 全局钩子用于批量隐藏元素。
  姓名板的 `OnDataChanged` 闭包已贴满 Lua 5.0 的 32 个 upvalue 上限，
  再往里引用任何文件级 local 都会让整个文件编译失败且**游戏内无任何提示**，
  因此这类逻辑必须走全局函数而非 `nameplates.xxx` 方法。

### 回能条

- 回能 tick 相位唯一来源收敛到 `modules/energytick.lua`：用相位锚点 `anchorMS` 推算，
  并计入 Blade Rush 一类敏捷修正（`EffectiveEnergyTickMS()`）。
- 所有"回能进度/光点"共用同一个 `pfUI.energytick:EnergyProgress()`，
  不再各自用 `lastgain + 固定 tick 间隔` 另算（那样必然与服务器 tick 不同步）。

### 解锁与布局

- 解锁界面的坐标输入框重设位置时先 `ClearAllPoints()` 再按完整锚点
  （`anchor` / `xpos` / `ypos`）重建。只取 `GetPoint()` 的前三个返回值再喂三参数
  `SetPoint` 会丢掉 `relativeTo`，相对目标框定位的模块一改就飞到屏幕边缘。
- 底部堆叠（`bottomalign`）的"退出堆叠"只认 `C.position[name].manual == "1"`，
  拖动、方向键、坐标框、保存都会打标，且打标必须早于 `SavePosition`——
  否则触发的重新对齐会立刻把模块拉回原位（表现为"一放就弹回 / 拖不动"）。
- 拖动过程中一次 `SetPoint` 都不调用：会使 `StartMoving` 中止，模块粘死在原地。
  拖动期间只画参考线，松手后才绝对定位。

### 团队 / 宠物框架

- 支持反向填充（`vertical up` / `vertical down`）。
- `maxraid` 上限提升到 50。
- 41–50 号槽位预留给团队宠物（`GetNumRaidMembers ≤ 40` 的限制下另行编号）。

### 聊天

- 聊天行显示发言人等级。
- 聊天内容复制：`/pfchatcopy` 进入复制模式后可选中并按 `Ctrl+C`。
  1.12 客户端**不存在**任何从 Lua 写入剪贴板或模拟按键的途径
  （引擎、SuperWoW、Nampower、UnitXP_SP3 均无此接口），因此必须由玩家按一次 `Ctrl+C`。
  选区灰块与文本框走同一绘制路径，把 alpha 置 0 可在不显示灰块的同时保留选区与焦点
  （`/pfchatcopy ghost off` 切回可见，作兜底）。

### 加载开销与本地化

- 只加载 `enUS` + `zhCN` 两套语言数据。`koKR` / `frFR` / `deDE` / `esES` / `ruRU` / `zhTW`
  已移入 `env/unused/`，不再参与解析——合计约 2.4 万行纯数据表，此前不论客户端语言
  都要在启动时全部读取。恢复方式见下方「恢复其他语言」。
- `zhCN` 界面的 GUI 翻译补全。

---

## 安装

1. 下载本仓库（`Code` → `Download ZIP`，或 `git clone`）。
2. 把整个 `pfUI` 文件夹放到：
   ```
   <客户端目录>\Interface\AddOns\pfUI\
   ```
   确认 `pfUI.toc` 就在该目录下（不要再套一层文件夹）。
3. 删除旧的 `WTF\Account\<账号>\SavedVariables\pfUI.lua`（**可选**，但换了版本建议先备份）。
4. 进游戏，`/pfui` 打开设置。

## 依赖

全部为**可选**。没有也能运行，只是失去对应增强：

| 依赖 | 作用 |
| --- | --- |
| [Nampower](https://github.com/pepopo978/nampower) v4+ | 精确光环事件与 `SPELL_GO` 命中信号，光环计时修正依赖它 |
| [SuperWoW](https://github.com/bRUhmoment/SuperWoW) | 单位字段读取（`GetUnitField`），读取任意单位光环的前提 |
| UnitXP_SP3 | 部分距离 / 坐标相关功能 |

未安装上述 DLL 时插件会自动降级，光环计时精度下降但界面正常。

## 恢复其他语言

把 `env/unused/` 下需要的文件移回 `env/`，再在 `init/env.xml` 里补一行 `Include`：

```xml
<Include file="..\env\locales_deDE.lua"/>
<Include file="..\env\translations_deDE.lua"/>
```

`translations_enUS.lua` 必须保留：当配置的语言没有对应翻译表时，`pfUI.lua` 会回退到它。

## 已知限制

- 目标环境是 **Turtle WoW / 1.12**。TBC 客户端（`pfUI-tbc.toc`）未针对本版本的改动做过验证。
- 代码遵循 **Lua 5.0** 语法：不使用 `#` 长度运算符、`//`、`goto`、二元 `%`；
  `...` 只能出现在函数参数表中。修改时请保持这一约束。
- 单个文件出现语法错误时，客户端会**静默跳过该文件**而不报错，
  排查请先看 `Logs\FrameXML.log`。

## 许可

MIT，与原项目一致。原始版权声明保留在 [LICENSE](LICENSE) 中：

```
Copyright (c) 2016-2021 Eric Mauser (Shagu)
```

本仓库的修改部分同样以 MIT 发布。按 MIT 要求，再分发时请保留上述版权声明与许可全文。

## 致谢

- [Shagu](https://github.com/Shagu) — pfUI 原作者，这套界面的全部基础设计
- [pfUI 社区](https://github.com/Shagu/pfUI/graphs/contributors) — 上游贡献者
- Nampower / SuperWoW / UnitXP_SP3 的维护者 — 1.12 客户端扩展能力
