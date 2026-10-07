# moonbit_static_analysis

**中文** | [English](README.en.md)

`riantr/moonbit_static_analysis` — **三鉴（结构/类型/行为）静态分析流水线，一个基础设施，两种用途**：

1. **程序代码修订**：分析**快速进化中的 MoonBit 语言**的程序（未定义名、未用绑定、类型错配、死分支、不可达代码）；
2. **静态状态修订**：为多层状态机提供通用机器表审计（`src/statecheck`）——**被测对象调用本模块**，把机器表作为纯数据喂进来。参考消费方是 [riantr/pyroduct](https://mooncakes.io/docs/riantr/pyroduct@0.1.28)（主体／群体／社会／进化层状态机族），其 `audit` 包用真实机器表调用本模块做黑盒测试。

一条流水线贯穿两者：**结构走查 → 类型/符号 → 抽象解释 → 统一报告**。

## 安装 / 快速上手

```bash
moon add riantr/moonbit_static_analysis@0.3.6
```

```moonbit
// 用途一：修订一段 MoonBit（当前子集）程序
let result : @pipeline.PipelineResult = @pipeline.run(source, "main.mbt")
println(@pipeline.render_result(result))

// 用途二：审计一台状态机（机器表以纯数据进来）
let spec : @statecheck.MachineSpec = { name: "主体", states: [...], ... }
println(@statecheck.render(spec))
```

## 三鉴（结构/类型/行为）（流水线核心）

三鉴按"后者消费前者的表"组装：

| 鉴 | 包 | 职责 | 产出 |
|---|---|---|---|
| 结构 | `src/walk` | 赋值即绑定、未用/未定义/参数被改、常量折叠剪枝 | 绑定表 `fn_bindings` |
| 类型 | `src/types` | 注解即契约、推断、赋值/实参/条件检查（**声明取自绑定表**） | 签名表 `sigs` |
| 行为 | `src/interp` | 格上抽象解释、按签名调度、虚栈（**方法表取自签名表**） | 行为发现 |
| 合并 | `src/pipeline` | 同一缺陷的多鉴回声 → 一条报告，lens 并集 | `render_result` |

四个组装点：绑定表→符号表（组装点1）、签名表→方法表（组装点2）、常量折叠的格化（组装点3）、合并去重（组装点4）。

## 用途一：程序代码修订（快速进化中的 MoonBit 语言）

```bash
moon run src/cli          # demo：6 个样例 × 三鉴
```

```
=== undefined.mbt ===
2:10 - error: undefined variable 'missing' (UndefinedName) [structural+type+behavior]
  in main() at undefined.mbt:4
  in g at undefined.mbt:1
Summary: 1 finding(s) (before merge: structural 1, type 2, behavior 1)
```

一条缺陷三鉴都看见 → **一条**报告，标签是并集；合并前后计数都保留（合并无损）。死分支被剪两次（结构层 `const_eval` + 行为层 `ABool` 格值），不存在的 `typo_fn` 零报告。

## 用途二：静态状态修订（机器表 → 三鉴）

`src/statecheck` 接受**任意状态机的纯数据规格** `MachineSpec`（状态 / 初始 / 终点 / 迁移 / 触发-槽位 / Block 理由 / 修习历程），三鉴读机器表就像读程序：

| 鉴 | 机器侧语义 | 检查内容 |
|---|---|---|
| 结构 | **状态即绑定**（"赋值即绑定"推广到机器表） | 任何状态都必须被至少一条迁移绑定（出或入）；只出不进 → `never entered`；从初始位置的可达性闭包；终点必须可达（机器必须能完成） |
| 类型 | **驱动槽契约**（"注解即契约"） | 每个触发必须归位已知槽、无空槽；`Block` 必须带理由——**无路必须说出口，不能沉默** |
| 行为 | **轨迹抽象执行**（虚栈） | 修习历程每一步都必须有触发承载；断链的轨迹步带入口帧→出错帧的虚栈 |

```moonbit
let spec : @statecheck.MachineSpec = { name: "主体", states: [...], ... }
let findings : Array[@report.Report] = @statecheck.audit(spec)
let text : String = @statecheck.render(spec)   // 合并后的文本报告
```

**pyroduct 是被测对象，不是依赖**：本模块自身不依赖 pyroduct；方向是 pyroduct（其 `audit` 包）用真实机器表构造 `MachineSpec` 调用本模块。依赖单向：机器 → 分析器。

pyroduct 侧的真实自审计（`moon run cmd/main -- audit`）。**它 pin 的是 0.2.0**，所以
下面输出里出现的 `0.2.0` 指那个 pin，不是上面 `moon add` 的安装版本：

```
规格 | 计数
---|---
状态 | 034
迁移 | 053
触发→槽 | 049 → 8
无路组合（带理由） | 228
修习历程 | 031 站

已知设计（4 条，出处层：设计使然——0.2.0 审计已验证）：
- state '无忆' is never entered: it appears only as a transition source
- state '无筹' is never entered: it appears only as a transition source
- state '无忆' is unreachable from the initial position '立位'
- state '无筹' is unreachable from the initial position '立位'

未预期发现：**0 条**
```

`无忆`／`无筹`（原文：失忆／浑噩）是主体机器（34 位·53 迁·8 槽）里真实存在的两个"只出不进且不可达"
位置——pyroduct 自己的 192 个测试之外，用另一套三鉴语言独立复核出机器的论文边界
（「记不起来的过去」与「尚未到来的未来」）。"未预期发现 0 条"是回归绊线：三鉴在真实表上
任何新增报警都会让 pyroduct 的测试失败，强制复审。

> `moon run src/cli` 末尾那台 `pyroduct 形状示例机器` 是本模块内嵌的 **8 状态玩具机**
> （`statecheck.pyroduct_flavored()`），不是 pyroduct 的真表；它带 `182:12` 这类
> `行:列`，那是 `state_span()` 按状态名哈希出来的**稳定伪 span**（同一名字永远同一坐标），
> 不是任何源文件的位置——别拿它去 pyroduct 里对行号。

## 包结构

```
src/core      Span/Severity/Lens/Family(merge_group 契约)/Frame
src/report    Report 结构与渲染（lens 并集标签、vst 框架）
src/lexer     MoonBit 词法前端
src/parser    MoonBit 语法 → ast（含 .mbtx 脚本的 import 块）
src/ast       MoonBit 抽象语法
src/walk      结构鉴：绑定表 + 结构发现
src/types     类型鉴：Ty/Ty?/Sig 推断
src/interp    行为鉴：AbsVal 格 + 调度 + 虚栈
src/pipeline  组装：跑三鉴 + merge_group 合并
src/moonfiles 其余文件种类：.mbt.md 逐块三鉴 / .mbti 接口审计 / .mbtp 证明 lint
src/statecheck 用途二：通用机器表审计（MachineSpec 纯数据桥）
src/samples   demo 样例（内嵌 MoonBit 源）
src/cli       可执行入口（程序 demo + 文件种类 demo + 示例机器审计）
```

## 文件种类（MoonBit 工具链的其它后缀）

完整分类表见 [EXTENSIONS.md](EXTENSIONS.md)，语义依据
[docs.moonbitlang.com/en/latest](https://docs.moonbitlang.com/en/latest/)（最终依据），
并与 mooncakes 的 [`moonbitlang/parser@0.4.3`](https://mooncakes.io/docs/moonbitlang/parser@0.4.3) /
[`moonbitlang/lexer@0.4.2`](https://mooncakes.io/docs/moonbitlang/lexer@0.4.2) 对照过：

| 后缀 | 本项目静态分析 |
|---|---|
| `.mbt` | 三鉴程序分析 |
| `.mbtx` | 三鉴程序分析 + 导入块审计（条目文法 `"path" [@alias] [*]`；重复路径报 FParse；导入清单随报告回显） |
| `.mbti` | 接口审计：畸形行 / 重复签名 / 未知类型引用。行文法与 `moon info` 实际输出一致，生成文件零误报 |
| `.mbt.md` | literate：只分析工具链**确实编译**的围栏 —— `mbt check` / `mbt test` 及其 `moonbit` 写法；第二个词是 `check` 或 `test` 才使块成为活代码。行号对齐 `.md` 真实行。裸 `mbt`、裸 `moonbit` 与 `nocheck` 是展示块，跳过——**按工具链实测**，见 EXTENSIONS.md |
| `.mbtp` | 证明文件逻辑侧 lint（体内字符串常量、`!`/`↔` 禁形、跨包调用、lemma 缺 `proof_ensure`）——**不替代 `moon prove`** |
| `moon.mod` / `moon.pkg` / workspace | 记录在案，不做静态分析（配置不是代码——官方也把两者放在 `parser` 的 `moon_config` 子包里，与 `syntax` / `mbti_parser` 并列而独立；理由见 EXTENSIONS.md「配置文件的边界」）|

`.mbti` 审计的行文法是照着真实生成物对齐的：`moon info` 实际会输出 `import {}` 块、
`#deprecated` / `#alias(...)` / `#callsite(...)` 属性行、`const`、`impl … for T`、
`suberror`、带 `pub` / `async` / `extern` / 类型参数 / 具名参数（`input_offset? : Int`）/
`raise` / `String?` 的 `fn` 签名。早期版本会把其中每一种都当成"畸形行"报出来，
也就是对**每一个**真实生成的接口文件都误报。

## 验证

```bash
moon check --target all --deny-warn   # 0 错 0 警（js / native / wasm / wasm-gc）
moon test --deny-warn                # 75/75 全绿（四个 target 各 75）
moon run src/cli                     # 程序 demo + 文件种类 demo + pyroduct 形状示例机器审计
```

`--deny-warn` 是有意的：官方包配置页要求「In CI, add `--deny-warn` to `moon check`,
`moon test`, or the equivalent command to treat enabled warnings as fatal errors」。
少了它，「0 警」这句话没有任何东西强制 —— 冒出警告 CI 照样绿。`.github/workflows/gate.yml`
里的 CI 门禁因此带 `--deny-warn`；代价是工具链日后新增警告会让 CI 变红，这正是它的用途。

> CI 只跑 `--target js`；上面「四个 target」是本地跑的结论，CI 不覆盖 native/wasm。


## 形式验证（moon prove）

`src/core` 是纯内核（无 Array 携带的结构体、无字符串），以 `"proof-enabled": true` 开启
MoonBit 2026 实验形式验证；`src/core/core_proof.mbtp` 是逻辑侧：谓词（is_error /
type_error_family / lower_irreflexive_ok / lower_transitive_ok / lower_antisymmetric_ok /
rank_order_ok）+ **19 条引理**（rank 顺序三常数、lower 三律、rank_order_agrees、
severity 分类：5 个 Error 族 + 7 个 Warning 族逐条 + 全量 taxonomy）。

```bash
moon prove src/core --why3-config .why3.conf   # 生成 19 个 VC 并交 cvc5/alt-ergo
```

验证状态（why3 降级产物 `_build/verif/src/core/*.smt2` 逐目标 cvc5 机检）：

- **21/21 目标全部 VALID**（unsat）：19 条引理 + span_at/zero_span 两个自动安全 VC。
- 已知工具链限制（均为上游问题，非本项目代码）：
  1. `#proof_pure` 函数体为**结构体字面量**时（pos/span_at/zero_span）降级为不透明逻辑符号
     —— 函数体被丢弃，span 形状律在逻辑侧不可证（已由测试钉住，见 core_proof.mbtp 注释）。
  2. 捆绑 why3server（Windows 构建）丢失求解器 stdout —— why3 报 "High failure"、输出仅
     `.`；裸 `why3 ... prove` CLI 同样复现。逐目标机检绕过：
     `why3 -o <dir> -P cvc5 <mlw>` 导出 SMT 后对每个文件跑 cvc5。

本地复现所需 shim（不进发布 zip）：`.why3.conf`（datadir/libdir 指向 `.moon/share/why3`
与 `.moon/lib/why3`，显式 `[prover]` 节）与 `cvc5wrap.ps1`（滤掉 why3 文件尾部的
`get-info :reason-unknown` —— cvc5 1.0.9 对确定性回答会报错，why3 1.7.2 解析失败）。

## 发布

本模块通过以下渠道发布（同一份源码，三处同步）：

| 渠道 | 地址 |
|---|---|
| Gitee（主仓） | <https://gitee.com/ren-yongxiang/moonbit_static_analysis.git> |
| GitHub（镜像） | <https://github.com/riantr/moonbit_static_analysis> |
| mooncakes.io（包注册表） | <https://mooncakes.io/docs/riantr/moonbit_static_analysis> |

- **mooncakes.io**：`moon publish`（发布后 `riantr/moonbit_static_analysis@0.3.6` 可被任何 MoonBit 模块以 `import` 依赖；`src/cli` 附带 SKILL.md，上架 [skills.mooncakes.io](https://skills.mooncakes.io)）。
- **Gitee / GitHub**：`git push` 双推；tag 与 moon.mod 版本号保持一致。

## 分析其他项目（不引入本项目）

本工具可以扫**任意** MoonBit 仓库，而那个仓库既不依赖本模块、也不会被改动 —— 源码只在扫描时被**读取**：

```bash
moonx riantr/moonbit_static_analysis@latest riantr/moonbit_doubleML@latest
```

第一个参数是要扫的目标：registry 坐标（`author/module`，可带 `@version` / `@latest`）或一个本地路径；省略则扫当前目录。坐标会经 `moon fetch` 落到 `.repos/` 再遍历。

输出每行 `kind<TAB>count<TAB>path`，末行 `SUMMARY`。**已实测**：

| 目标 | 文件 | 结果 |
|---|---|---|
| 本仓库自身 | 38 | `.mbti` 16 个 / `.mbtp` 1 个 **各 0 条**；`.mbt` 21 个 7215 条（全为子集边界） |
| `riantr/moonbit_doubleML@latest` → 0.107.0 | 177 | `.mbt.md` **0 条**；`.mbt` 176 个 49945 条（全为子集边界） |

根包是薄转发层，真正的实现在 `src/sa`（library）。设成 library 是因为「main 包 import 另一个 main 包」已被工具链标记为将来会报错；`src/sa` 与根包都声明 `supported_targets = "+wasm+native"`，因为文件 IO 与子进程来自 `moonbitlang/async`，只有 wasm / native 后端有可用的 async 运行时（js 没有，wasm-gc 缺 `run_async_main`），其余后端会**跳过**这两个包而不是失败。

## DeepSeek Harness 插件

`src/jsoncli` 是 JSON 桥接入口（Node 下运行，一条 JSON 请求进、一条 JSON 应答出）：
`{"kind":"program","source":...}` 走程序三鉴，`{"kind":"file","filename":...}` 按扩展名
分派到对应文件种类的分析（`.mbt` / `.mbtx` / `.mbt.md` / `.mbti` / `.mbtp`），
`{"kind":"machine","spec":...}` 走机器表审计。
它被打包为 DeepSeek Harness 插件 `@riantr/moonbit-static-analysis-dsh`（工作区目录
`dsh-plugin-moonbit-static-analysis/`），向 agent 暴露 `moonbit_analyze` /
`moonbit_analyze_file` / `moonbit_audit` / `moonbit_gates` **四个**工具——插件只是生成器与
格式化器，分析语义全部留在 MoonBit 侧、随模块一起版本化与跑门禁。
安装方式见该目录 README（`plugin_manager` 的 `install_bundle`）。
