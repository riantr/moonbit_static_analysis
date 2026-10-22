# moonbit_static_analysis

[English](README.md) | **中文**

`riantr/moonbit_static_analysis` —— 一个 **三鉴（结构 / 类型 / 行为）静态分析流水线**，
面向 MoonBit。一套基础设施，两种用途：

1. **程序代码修订** —— 分析 **快速进化中的 MoonBit 语言** 写的程序（未定义名、未用绑定、
   类型不匹配、死分支、不可达代码）；
2. **静态状态修订** —— 面向多层状态机的通用机器表审计（`src/statecheck`）：**被审计的主体
   调用本模块**，把它的机器表当纯数据喂进来。

它能读 MoonBit 工具链的每一种文件后缀 —— `.mbt` / `.mbtx` / `.mbti` / `.mbt.md` /
`.mbtp` —— 而且 **绝不修改被扫描的目标**：被分析的仓库既不依赖本模块，也不会被本模块改动。

在 `moonbitlang/core`（1029 个文件）上的实测：**解析 957 个，actionable 33 条**——这 33 条
**没有一条**是本前端读不到的构造或算不出来的运算符，**没有一条是被分析代码的缺陷**。
同一棵树上 `moon check --target all` 只报**一条**错误，在一个 `.mbt.md` 文档文件里。

## 目录

- [特性](#特性)
- [安装](#安装)
- [快速上手](#快速上手)
- [用途一：程序代码修订](#用途一程序代码修订)
- [用途二：静态状态修订](#用途二静态状态修订)
- [API 参考](#api-参考)
- [命令行参考](#命令行参考)
- [输出怎么读](#输出怎么读)
- [覆盖范围与边界](#覆盖范围与边界)
- [文件种类](#文件种类)
- [包结构](#包结构)
- [验证](#验证)
- [发布历史](#发布历史)
- [参与开发](#参与开发)
- [许可证](#许可证)
- [参考](#参考)

## 特性

- ✅ **三鉴，一份报告** —— 结构遍历 → 类型/符号 → 抽象解释，合并之后一个缺陷就是 **一条**
  发现，它的透镜标签是所有看见它的透镜的并集。合并是无损的：合并前后的计数都保留。
- ✅ **MoonBit 的每一种文件后缀** —— `.mbt` / `.mbtx` / `.mbti` / `.mbt.md` / `.mbtp`，
  其中包括编译器**根本不审**的三种。
- ✅ **只读，不写** —— 被分析的仓库既不依赖本模块，也不会被本模块改动。本工具只在扫描时
  **读取**目标的文件。
- ✅ **跨文件符号解析** —— `--extern-iface-dir` 索引 `.mbti` 里的声明，于是从别的包用来的
  类型不会被报成未定义。
- ✅ **诚实的覆盖率** —— 前端读不完的文件被标成 `PARTIAL`，它边界之后的发现**被计数、
  但不展示**。
- ✅ **状态机审计** —— 同一套三鉴跑在纯数据的机器表上：状态即绑定、驱动槽即类型契约、
  历程即抽象执行。
- ✅ **Mermaid 图输出** —— `--mmd` / `--mmd-auto`，可选开启；被截断的图会在自己的头部
  里写明这一点。
- ✅ **文件名里带出处** —— 包、版本、**工具链**和时间戳，好让一次扫描可以和后来的扫描
  互相比较。
- ⚠️ **`--per-function`** —— 行为透镜的第二个入口。用它的数字之前，请先读
  [覆盖范围与边界](#覆盖范围与边界)。

## 安装

```bash
moon add riantr/moonbit_static_analysis@0.4.33
```

然后在 `moon.mod` 里引入：

```moonbit
import {
  "riantr/moonbit_static_analysis@0.4.33",
}
```

## 快速上手

### 扫描另一个项目 —— 不引入依赖，也不改动它

```bash
moonx riantr/moonbit_static_analysis@latest riantr/moonbit_doubleML@latest
```

`moonx` 下载 mooncakes 为该发布版本构建好的 **预编译 wasm**，缓存后用 `moonrun` 跑起来
——不用 clone，也不用本地构建。

目标可以是注册表坐标（`author/module`，可带 `@version` 或 `@latest`），也可以是本地路径；
省略则扫描当前目录。坐标会先由 `moon fetch` 落到 `.repos/`，然后再遍历。

### 当作库来用

```moonbit
// 用途一：修订一段 MoonBit（当前子集）程序
let result : @pipeline.PipelineResult =
  @pipeline.run(source, "main.mbt", @core.IfaceSymTab::empty())
println(@pipeline.render_result(result))

// 用途二：审计一台状态机（机器表以纯数据进来）
let spec : @statecheck.MachineSpec = { name: "主体", states: [...], ... }
println(@statecheck.render(spec))
```

### 跑一遍 demo

```bash
moon run src/cli          # 6 个样例 × 三鉴、文件种类 demo、样例机器
```

## 用途一：程序代码修订

三鉴是这样装配的：**后面每一鉴都消费前面那一鉴的表**。

| 透镜 | 包 | 职责 | 产出 |
|---|---|---|---|
| 结构 | `src/walk` | 以赋值论绑定、未用/未定义/形参被改、常量折叠剪枝 | 绑定表 `fn_bindings` |
| 类型 | `src/types` | 以标注论契约、推导、赋值/实参/条件检查（**声明来自绑定表**） | 签名表 `sigs` |
| 行为 | `src/interp` | 在格上做抽象解释、按签名分派方法、虚拟栈（**方法表来自签名表**） | 行为发现 |
| 合并 | `src/pipeline` | 一个缺陷在多鉴里的回声 → 一条报告，透镜取并集 | `render_result` |

```
=== undefined.mbt ===
2:10 - error: undefined variable 'missing' (UndefinedName) [structural+type+behavior]
  in main() at undefined.mbt:4
  in g at undefined.mbt:1
Summary: 1 finding(s) (before merge: structural 1, type 2, behavior 1)
```

三鉴都看见的同一个缺陷 → **一条**报告，标签取并集。死分支会被剪两次（结构侧的 `const_eval`
加上行为侧的 `ABool` 格值），而调用一个不存在的 `typo_fn` 产生零条发现。

## 用途二：静态状态修订

`src/statecheck` 接受 **任意状态机的纯数据规格** —— 一个 `MachineSpec`（状态 / 初始 /
终止 / 迁移 / 触发槽落位 / Block 理由 / 历程）。三鉴读机器表的方式，和读程序一模一样：

| 透镜 | 机器侧语义 | 它检查什么 |
|---|---|---|
| 结构 | **状态即绑定**（「以赋值论绑定」抬升到机器表） | 每个状态至少被一条迁移绑定（入或出）；只出不进 → `never entered`；从初始位出发的可达闭包；终止位必须可达——这台机器得能走到头 |
| 类型 | **驱动槽契约**（「以标注论契约」） | 每个触发必须落进已知槽，不许有空槽；一个 `Block` 必须带理由——**无路的一步必须出声说，不能沉默** |
| 行为 | **历程即抽象执行**（虚拟栈） | 每个历程步骤都必须被某条迁移承载；一个搁浅的步骤会带着虚拟栈从入口帧走到错误帧 |

```moonbit
let spec : @statecheck.MachineSpec = { name: "主体", states: [...], ... }
let findings : Array[@report.Report] = @statecheck.audit(spec)
let text : String = @statecheck.render(spec)   // 合并后的文本报告
```

**pyroduct 是被审计的主体，不是依赖**：本模块不依赖 pyroduct；方向是 pyroduct（它的
`audit` 包）拿自己的真实机器表拼出 `MachineSpec` 来调用本模块。单向：机器 → 分析器。

pyroduct 的真实自审（`moon run cmd/main -- audit`）打印：

```
规格 | 计数
---|---
状态 | 034
迁移 | 053
触发→槽 | 049 → 8
无路组合（带理由） | 228
修习历程 | 031 站

未预期发现：**0 条**
```

「未预期发现 0 条」这一行是绊线：真实表上一旦出现新的结构/类型/行为发现，就会让
pyroduct 的测试挂掉，强制一次复审。同一次运行还会列出它**每次都报**的四条**已知设计**
发现（两个只出不进的状态）——上面把它们略去了，因为那是模型本身、不是缺陷，而且要紧的
是最后那一行。

> `moon run src/cli` 末尾打印的 `pyroduct-shaped sample machine` 是本模块自己的
> **8 状态玩具**（`statecheck.pyroduct_flavored()`），不是 pyroduct 的真实表。它带的
> `182:12` 这样的坐标是**由状态名散列出来的稳定伪位置**，不是任何源文件里的行号。

## API 参考

### 程序分析 —— `src/pipeline`

| 函数 | 签名 |
|---|---|
| `run` | `(src : String, file : String, extern_iface : @core.IfaceSymTab) -> PipelineResult` |
| `run_functions` | `(src : String, file : String, extern_iface : @core.IfaceSymTab) -> PipelineResult` |
| `render_result` | `(r : PipelineResult) -> String` |
| `merge_findings` | `(all : Array[@report.Report]) -> Array[@report.Report]` |
| `merge_group` | `(g : Array[@report.Report]) -> @report.Report` |

`run` 让行为透镜在 **模块** 上入口，`run_functions` 让它在每个 **函数** 上入口（见
[覆盖范围与边界](#覆盖范围与边界)）。两个视图是**分开的，不是相加的**。

### 机器表 —— `src/statecheck`

| 函数 | 签名 |
|---|---|
| `audit` | `(spec : MachineSpec) -> Array[@report.Report]` |
| `render` | `(spec : MachineSpec) -> String` |
| `pyroduct_flavored` | `() -> MachineSpec` —— 那个 8 状态样例机器 |

### 图与出处 —— `src/sa`

| 函数 | 签名 |
|---|---|
| `mermaid_states` | `(verdicts : Array[Verdict], summary : Summary, prov : ScanProvenance, per_file : Int32, max_files : Int32) -> String` |
| `provenance_for` | `async (target : String, root : String) -> ScanProvenance` |
| `scan_artifact_name` | `(p : ScanProvenance, root : String) -> String` |
| `aggregate` | `(verdicts : Array[Verdict]) -> Summary` |
| `stamp_utc` | `(ms : Int64) -> String` |
| `moon_mod_version` | `(src : String) -> String` |

`mermaid_states` 返回合法的 mermaid `stateDiagram-v2`。它绕开的两条约束都是实测的，不是
假设的：转移标签是**第一个** `:` 之后的全部内容，所以里面不能再有 `:`——于是位置和消息
都放进带引号的状态标签里；而 MoonBit 没有运算符续行，所以以 `+` 开头的源码行是解析错误，
这就是文档一行一行 `write_string` 写出来的原因。

`per_file` 和 `max_files` 给绘图封顶，`0` 表示不封。**被封顶砍掉的部分会在图里写明**，
写在头部和文件上的一条注里，所以被截断的图不会被读成干净的图。文件按 **actionable**
条数降序排，而不是按原始发现数：在 `moonbitlang/core` 上，原始发现最多的文件是
`builtin/int64_test.mbt`，**1022** 条发现——全是 notice、零缺陷；按原始数排会把它放在一张
「该把注意力放在哪」为职责的图的第一位。

### 出处 —— 产物的文件名

一次扫描结果是对**某棵特定的树**、被**某个特定的工具链**、在**某个特定的时刻**读出来的
主张。这三样都进文件名 —— `<package>_<version>_<moonbit>_<stamp>.mmd`：

```
moonbit_static_analysis_0.4.33_0.1.20260920_20261009T155222Z.mmd
moonbitlang-core_0.1.20260920+7d59c7ec9_0.1.20260920_20261009T051925Z.mmd
tree_unknown_0.1.20260920_20261009T051511Z.mmd     # 版本没定下来
```

| 字段 | 回答什么问题 | 来源 |
|---|---|---|
| `package` | 读的是谁 | 坐标，或**解析后**的目录名 |
| `version` | 它的哪一版 | 目标的 `moon.mod`（`moon.mod.json` 也认） |
| `moonbit` | **是哪个工具链读的** | `moon version`，作为子进程跑 |
| `stamp` | 什么时候 | `@async.now()`，UTC |

`moonbit` 是从树里**恢复不出来**的那一格，也正是它决定一次扫描能不能和后来的扫描比较。
如果 `moon version` 子进程失败，这一格读作 `unknown`，而不是写错。

它刻意**不**做三件事：不省略它定不下来的东西（缺失的版本、工具链或时钟写成字面量
`unknown`——四个字段里省掉一段会让**其余几段错位**）；不产出点开头的文件名（以 `.` 开头的
名字在 `ls` 里看不见，而一个没人能列出来的产物，谁也不会再找到它）；不把文件名本身当成
记录——同样的三件事会以 `%%` 头注释在文档**里面**再写一遍，因为文件会被改名，而一旦改了名，
名字就不再是任何证据。

### 报告 —— `src/report`

| 函数 | 签名 |
|---|---|
| `Report::render` | `(self : Report) -> String` |
| `render_reports` | `(reports : Array[Report]) -> String` |

每条发现都带一条注，含 `WHY:`（哪条规则触发的、依据什么触发的）和 `HOW:`（该改什么），
取自 `@core.Family::advice`。

## 命令行参考

```
moonx riantr/moonbit_static_analysis@latest <target> [旗标]
```

| 旗标 | 含义 |
|---|---|
| `<target>` | 注册表坐标（`author/module[@version]`）或路径。省略则扫描当前目录。 |
| `--exclude <dir>` | 要跳过的目录名。可重复。它存在是因为点目录规则抓不全：项目可能把 vendored 的注册表快照放在一个普通名字下。 |
| `--extern-iface-dir <dir>` | 在这个目录里找 `.mbti`，把里面声明的类型/值当成被分析的所有 `.mbt` 文件里的合法名字。可重复。最自然的目标是 `moon fetch` 过依赖之后的 `.repos/`。目标自己的树永远被索引。 |
| `--no-auto-fetch-deps` | 默认会读目标的 `moon.mod` 并 `moon fetch` 每个直接依赖。加上它就跳过自动 fetch。 |
| `--mmd <path>` | **同时**把这次扫描写成 mermaid `stateDiagram-v2` 落到 `<path>`，并在最后一行打印 `MMD<TAB><path>`。刻意做成可选：stdout 始终是权威的文本报告。 |
| `--mmd-auto` | 同上，但自己取名，写到**工作目录**——绝不写进被分析的树里。 |
| `--per-function` | 让行为透镜在每个 **函数** 上入口，而不是在模块上。 |
| `--findings-shown-per-file N` | 每个文件**打印**多少条发现（默认 40）。这是打印上限，不是分析上限：SUMMARY 的计数来自全部发现，所以调大它只是把本来已经计数的发现显示出来，不会改动 SUMMARY 里的任何数字。 |

`--mmd` 必须带路径，`--mmd-auto` 是另一个写法，这是刻意的：一个可选的值在这里是有歧义的，
因为在 `<target> --mmd <path>` 里，`--mmd` 后面那个词既可能是路径，也可能是第二个没预期的
目标，没法分辨。

> **命令行无法以非零码退出。** MoonBit 在这里可用的包里没有暴露进程退出的入口，所以一个
> 定位不到的目标会打印 `ERROR` 然后仍然退出 0——**调用方必须读输出，而不是读退出码**。

## 输出怎么读

```
SCANNED	107 files under ...\ML\CI
CLEAN	.mbti	...\CI/pof/pkg.generated.mbti
PARTIAL	.mbt	defects=2	notices=1	read up to line 36, 57 after it not shown	...\CI/pof/aggregator.mbt
12:3 - error: ... (UndefinedName) [behavior]
PARSED	32/107 files understood (29.9%); 75 more read only up to their first parse error
SUMMARY	files=107	parsed=32	actionable=57	notices=211	unreliable=15759	withheld=6769	total=16027	(actionable+notices+unreliable = total; withheld ⊆ unreliable)
```

- **`PARSED` 才是头条。** 前端覆盖的是 MoonBit 的一个**子集**，所以它读不懂的部分量的是
  这工具的盲区，不是你的代码。
- **读了一半的文件仍然值得读。** 解析器记下它**真正**失败的那一行；之前的发现照报
  （`PARTIAL`），之后的计入 `unreliable` 且永不展示——那来自一棵已经不对的树，把它当结果
  端上来，就是这个工具当初要根治的那个毛病。
- **被跳过的声明不会挪动这条边界。** 「这个 `test` 块没被分析」不影响后面的代码仍被读到，
  所以这样的文件是 `FOUND`。
- **`actionable` 不含 notice。** 我们选择不分析的声明形式不是你代码的缺陷。
- 读不懂的文件**按原因分组**，而不是一行一个。
- `actionable + notices + unreliable` = `total`，这一行自己断言。`withheld` 另行报出，但它是
  `unreliable` 的子集，所以故意不参与这个和式。

**跨文件类型符号解析** —— 一个 `.mbt` 用了别的包里声明的类型（比如 `@argparse` 的
`Command`），单文件分析器只看得见自己那个文件，于是会报 `undefined name 'Command'`。
`--extern-iface-dir <dir>`（可重复）在指定目录里找 `.mbti`，把它们声明的类型和值签名
装进一张**跨文件符号表**；结构遍历和类型透镜在报 `FUndefinedName` 之前会先查这张表。

这张表只**抑制**，从不发明合法绑定：表里没有的名字照报。类型命中返回 `TUnknown`；值命中
返回 `TUnknownFn`——一个已知是值、但签名没读的值——于是 `Command(...)` 既不会触发
`FOpMismatch`，也不会拿一个凭空发明的参数个数去检查。查表前会先剥掉 `@pkg.` 前缀：
`.mbti` 里写的是裸名（`pub fn T::m`），使用处必须写 `@pkg.T::m`，所以精确匹配下这两种
拼法永远碰不上，而命名另一个包最常见的写法也就永远打不中。

## 覆盖范围与边界

### 这个工具不跟谁竞争

在 `.mbt` 上，本工具 **不与工具链的编译器竞争**：`moon check` 有真正的解析器，读的是**整个**
语言。在同一棵 `moonbitlang/core` 上它报**一条**错误和两种共 251 条告警；本工具的 `.mbt`
前端读的是一个 **子集**，解析 **1029 个文件里的 957 个**（93.0%）；`.mbti` 和 `.mbt.md` 是 100%。

本工具能做而编译器不能做的：编译器**根本不审**的那三种文件——`.mbti`、`.mbt.md`、
`.mbtp`——以及跨包语义。

### 前端读过去、但没有分析的构造

每一个它读过去**却没有分析**的声明或表达式形式都会报成一条 notice，而那条 notice 说的是
**工具**，不是你的代码。在本项目自己的源码上实测（170 个文件）：

| notice | 条数 | | notice | 条数 |
|---|---:|---|---|---:|
| `test` 声明 | 1175 | | 匿名函数字面量 | 10 |
| `match` 表达式 | 299 | | `const` 声明 | 6 |
| `if` 表达式 | 67 | | 短 lambda | 2 |
| `struct` 声明 | 58 | | `try` 表达式 | 1 |
| `derive` 声明 | 52 | | | |
| `enum` 声明 | 24 | | | |

去掉其中任何一行，都需要为那个形式做一个 AST 节点，所以它们是**功能**，不是措辞问题。
真正要紧的是这个区别：**表达式级**的排除（379 条）落在函数体内部，会把那个函数体的审计
整个关掉；**声明级**的排除（1315 条）在所有函数体之外，不会。

### `UndefinedName` 的两个盲点

两个都是已知的，而且都写在发现自己的注里：

- `#doc(hidden)` 的 API 在任何 `.mbti` 里都不出现，所以无法从依赖的**源码**索引；
- 写成 `@pkg.fn(1, 2)` 的顶层跨包引用，解析器不会把它折成一个可调用的名字，所以即使那个
  包**已经**被索引，它照样会被报出来。

### `--per-function`：让行为透镜在每个函数上入口

`--per-function` 把每个函数都当作程序的入口来分析，形参绑定到按**声明类型**新造的抽象值。
对入口点来说声明类型是唯一站得住的选择：形参的运行期值未知，透镜只能假定声明类型，
不能更多。

两个视图是**分开的，不是相加的**，所以可以互相比较而不会互相遮蔽。默认（模块）视图
不变：同一批语料加不加这个旗标，数字逐字节一致。

> **这个视图还不算可靠，旗标是可选的就是因为这个。** 它由
> `_verify/census_perfunction.ps1` 在**全部七个**固定语料上量，发版门禁**把数字钉住**。
> 现在它报 **58** 条 `actionable`，而模块视图报 33 条。**这 58 条没有一条是被分析代码的
> 缺陷。**
>
> | 家族 | 条数 | 透镜当时主张什么 |
> |---|---:|---|
> | A | 12 | 十六进制浮点字面量（`0x1.0p1023`）没被读出来，于是指数部分成了未定义名 |
> | B | 5 | BigInt 字面量的 `N` 后缀（`0N`）没被读出来 |
> | C | 6 | 两个数组之间的 `==` |
> | D | 3 | `Int + Char` 与 `List + List` |
> | E | 3 | 结构体上的 `*` |
> | F | 9 | 分析器看不见的名字——同包兄弟文件里的辅助函数、类型参数的方法、`.mbti` 索引里没有的内部 API、模块限定名 |
> | G | 11 | unreachable code——透镜自己对代码的主张 |
> | H | 2 | 赋了值却没被读的局部变量——透镜自己对代码的主张 |
> | I | 1 | `Double` 上的 `abs` |
> | J | 1 | 两个函数值上的 `*` |
> | K | 3 | 带具名实参的本地调用 |
> | L | 2 | 已记录的 `#doc(hidden)` 边界 |
>
> **「能过」是量出来的，不是假设的。** `moon check --target all` 在 `moonbitlang/core` 上
> 恰好报**一条**错误，在 `json/README.mbt.md`，而它不在带发现的**二十四个**文件之列。
> 这只是一半：没有诊断的文件和没人打开过的文件长得一模一样，所以
> `_verify/control_perfunction_census.ps1` 往这些文件里（**副本上**）各追加一个故意的
> 类型错误，并要求错误原样回来——**24 / 24**。
>
> **L 家族那两条是「已记录的边界」而不是缺陷**：跨包的 `#doc(hidden)` 函数没法从依赖的
> **源码**索引——只能从它的 `.mbti`——所以 `@locale.LocalePreferences::resolve` 在
> `proton` 0.3.4 里仍然报未定义函数。要回答它们，就得把这个分析器长成源码索引器，那是
> 另一个项目。**拿它来看透镜，不要拿它卡构建。**
>
> （这条注记原本写的是 **116 → 2**，而那个「2」是**六个**语料的普查——`moonbit_core`
> 不在其中，而它的发现数比其余六个加起来还多。那个数字对**量过的**语料是真的，对
> **没量过的**语料是假的。发布史见 [CHANGELOG.zh.md](CHANGELOG.zh.md)。）

## 文件种类

| 后缀 | 本工具做什么 |
|---|---|
| `.mbt` | 三鉴程序分析 |
| `.mbtx` | 三鉴程序分析 + import 块审计 |
| `.mbti` | 接口审计：畸形行 / 重复签名 / 未知的类型引用。行文法与 `moon info` 真正吐出的一致，所以生成的接口文件不会报*畸形行*。未知类型检查会查全模块的接口表，在 `moonbitlang/core` 上实测 **0**。残留的发现仍可能指向扫描范围之外声明的类型——请当作未经验证，而不是缺陷。 |
| `.mbt.md` |  literate：只认工具链真正**会编译**的围栏——`mbt check` / `mbt test` 以及 `moonbit` 写法。裸 `mbt`、裸 `moonbit` 和 `nocheck` 是展示块，跳过。 |
| `.mbtp` | 逻辑侧证明 lint（函数体里的字符串常量、被禁的 `!`/`↔` 形式、跨包调用、没有 `proof_ensure` 的引理）——**不能替代 `moon prove`** |
| `moon.mod` / `moon.pkg` / 工作区 | 只记录，不做静态分析——配置不是代码 |

完整分类见 [EXTENSIONS.md](EXTENSIONS.md)。

## 包结构

```
src/core      Span/Severity/Lens/Family(merge_group 契约)/Frame + Family::advice
src/report    Report 结构与渲染（透镜标签取并集、vst 帧）
src/sa        扫描入口 + aggregate() + mermaid_states()（public，库）
src/lexer     MoonBit 词法前端
src/parser    MoonBit 语法 → ast
src/ast       MoonBit 抽象语法
src/walk      结构透镜：绑定表 + 结构发现
src/types     类型透镜：Ty/Ty?/Sig 推导
src/interp    行为透镜：AbsVal 格 + 分派 + 虚拟栈
src/pipeline  装配：跑三鉴 + merge_group 合并
src/moonfiles 其它文件种类：.mbt.md 逐块三鉴 / .mbti 接口审计 / .mbtp 证明 lint
src/statecheck 用途二：通用机器表审计（纯数据 MachineSpec 桥）
src/samples   demo 样例（内嵌 MoonBit 源码）
src/cli       可执行入口（程序 demo + 文件种类 demo + 样例机器审计）
src/jsoncli   DeepSeek Harness 的 JSON 桥
```

根包是个薄转发层；实现是 `src/sa`，一个**库**。`src/sa` 和根包都声明
`supported_targets = "+wasm+native"`，因为文件 IO 和子进程来自 `moonbitlang/async`，
而只有部分后端有可用的 async 运行时；其余后端**跳过**这两个包而不是失败。

## 验证

```bash
moon check --target all --deny-warn   # 0 错 0 警（js / native / wasm / wasm-gc）
moon test --deny-warn                # wasm 1163/1163；js 与 wasm-gc 1083/1083
moon run src/cli                     # 程序 demo + 文件种类 demo + 样例机器审计
```

`--deny-warn` 是刻意的：不加它，就没有任何东西强制「0 警」这个说法——一次告警回归会静悄悄
地过掉 CI。CI（`.github/workflows/gate.yml`）跑 `moon update`、`moon check --deny-warn`、
`moon fmt --check`、`moon test --target js --deny-warn` 和 `moon build --target wasm`。

各 target 的测试数量不同是刻意的：`src/sa` 与 `src/jsoncli` 声明
`supported_targets = "+wasm+native"`，所以 js 与 wasm-gc 这两次运行会**跳过**这两个包而不是
失败它们。一个声称所有 target 都是同一个数字的测试计数本身就是错的，而 wasm 那个数字是
唯一同时覆盖渲染器和扫描器的。

### 唯一的发布入口

`moon check` 和 `moon test` 是地板，而本项目不只靠地板。它上面的所有东西都在**一个**脚本里：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File _verify\release.ps1
```

`_verify/release.ps1` 依次跑：门禁自身的自测；`moon fmt --check`；`moon check --deny-warn`；
三个测试 target；`moon build --target wasm`；语法探针自己的判定；自身源码自扫；**这份
README 自己的链接、锚点、版本与计数**；**变异门名册，以及一个证明它会变红的自测**；已发布包
自扫的自测；与固定基线的语料比对；逐函数普查及其对照；然后是**每一个**变异门——**79** 个。

这份名册是**被检查的，不是被断言的**：一个在磁盘上存在、却不在名册里的变异门**永远不会跑**，
而一个不会跑的变异门和一个跑绿了的变异门长得一模一样。`_verify/check_gate_roster.ps1`
把两份名册**双向**比对；它的 `-SelfTest` 往 `_verify` 的**副本**里注入六种缺陷——名册没
列的变异门、名册列了却不在磁盘上的变异门、脱离共享 harness 的变异门、被删掉的 harness
保证、harness 里的 `--filter`、harness 头部过时的计数——并要求每一种都被抓到。**六种
全部被抓到。**

两个开关会改变它的行为：`-SkipMutations` 跑除变异门以外的一切；`-SelfTest` 拿一个失败
的、一个抛异常的、一个通过的函数体去考验门禁自己的 stage 函数。**一道从没被证明会变红的
防护不是防护**，而这里就是证明它的地方。

### 形式验证（`moon prove`）

`src/core` 是证明对象：`src/core/moon.pkg` 里 `proof_enabled = true`，用来启用 MoonBit
2026 的实验性形式验证；`src/core/core_proof.mbtp` 是逻辑侧——谓词 + **19 条引理**。
这 19 条引理在 2026-10-03 实测为 **21/21 个目标 VALID**（unsat），每一个都用 cvc5
机器验证过。

> **这条命令今天跑不绿，原因已量过。** `moon prove src/core --why3-config .why3.conf`
> 报 `unbound type symbol 'map'`。`src/core` 在 2026-10-08 多了一个 `IfaceSymTab`——
> 它的字段是 `Map[String, Bool]`——而工具链的证明前导库**没有 `Map` 理论**，于是生成
> 的 Why3 文件里出现 `map int bool`，`moon prove` 和 `why3` 都加载不了它。19 条引理
> 从来没碰过 `IfaceSymTab`：被证明的是**整个包**，而包里有这个类型。修法是把
> `IfaceSymTab` 移出证明范围，而那会改本包的公开 API（`@core.IfaceSymTab` 是导出的），
> 所以这是版本线上的决定，不是一个补丁的事。
>
> 还有两处 `#proof_pure` 标注是**假的**：`path_tail` 和 `unqualified` 的函数体会
> 构造 `StringBuilder`，证明器不认（错误 4207）。一处假标注就让整个文件停止证明，
> 而这两处都是 2026-10-09 加上的。它们已被移除，并且 `_verify/check_prove_contracts.ps1`
> 现在会在发布门禁里拦住任何「证明器不认的 `#proof_pure` 函数体」。

## 发布历史

逐版本的发布史——每一版改了什么、改动的实测依据是什么、以及某个结论被撤回时的更正——
见 **[CHANGELOG.zh.md](CHANGELOG.zh.md)**（[English](CHANGELOG.md)）。

## 参与开发

1. Fork 仓库并建一个特性分支。
2. 给新功能加测试。
3. 把发布门禁跑绿：

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\release.ps1
   ```

4. 提一个 pull request。

这道门禁不是装饰：它会跑 **79 道变异门**，每一道都改源码、要求一个测试变红，
并证明恢复是逐字节一致的。426 个存活变异里有 389 个预期被杀；其中 **312 个**还点名了
必须变红的是哪个测试，所以门禁日志说的是**哪个**测试在守着这道防线，而不只是「有东西红了」。

## 许可证

MIT License。详见 [LICENSE](LICENSE)。

## 参考

- [MoonBit 语言指南](https://www.moonbitlang.com/docs/)
- [moonbitlang/core](https://mooncakes.io/docs/moonbitlang/core) —— 固定语料
- [moonbitlang/parser@0.4.3](https://mooncakes.io/docs/moonbitlang/parser@0.4.3) 与
  [moonbitlang/lexer@0.4.2](https://mooncakes.io/docs/moonbitlang/lexer@0.4.2)
  —— 工具链自己的文法，对照用
- [riantr/pyroduct](https://mooncakes.io/docs/riantr/pyroduct) —— 机器表审计的参考消费方
- [skills.mooncakes.io](https://skills.mooncakes.io) —— 已发布的 skill
