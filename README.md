# moonbit_static_analysis

`riantr/moonbit_static_analysis` — **三鉴（结构/类型/行为）静态分析流水线，一个基础设施，两种用途**：

1. **程序代码修订**：分析**快速进化中的 MoonBit 语言**的程序（未定义名、未用绑定、类型错配、死分支、不可达代码）；
2. **静态状态修订**：为多层状态机提供通用机器表审计（`src/statecheck`）——**被测对象调用本模块**，把机器表作为纯数据喂进来。参考消费方是 [riantr/pyroduct](https://mooncakes.io/docs/riantr/pyroduct@0.1.5)（主体／群体／社会／进化层状态机族），其 `audit` 包用真实机器表调用本模块做黑盒测试。

一条流水线贯穿两者：**结构走查 → 类型/符号 → 抽象解释 → 统一报告**。

## 安装 / 快速上手

```bash
moon add riantr/moonbit_static_analysis@0.1.1
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
=== undefined.mlang ===
2:10 - error: undefined variable 'missing' (UndefinedName) [structural+type+behavior]
  in main() at undefined.mlang:4
  in g at undefined.mlang:1
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

pyroduct 侧的真实审计结果（其 `moon test` 的一部分）：

```
182:12 - warning: state '失忆' is never entered: it appears only as a transition source (UnusedLocal) [structural]
182:12 - warning: state '失忆' is unreachable from the initial position '站立' (Unreachable) [structural]
825:37 - warning: state '浑噩' is never entered: it appears only as a transition source (UnusedLocal) [structural]
825:37 - warning: state '浑噩' is unreachable from the initial position '站立' (Unreachable) [structural]
Machine '主体' summary: 4 finding(s)
```

`失忆`(NoPast) 与 `浑噩`(NoFuture) 是主体机器（34 位·53 迁·8 槽）里真实存在的两个"只出不进且不可达"位置——pyroduct 自己的 95 个测试之外，用另一套三鉴语言独立复核出机器的论文边界（「过去与未来皆无处安放」）。

## 包结构

```
src/core      Span/Severity/Lens/Family(merge_group 契约)/Frame
src/report    Report 结构与渲染（lens 并集标签、vst 框架）
src/lexer     MoonBit 词法前端
src/parser    MoonBit 语法 → ast
src/ast       MoonBit 抽象语法
src/walk      结构鉴：绑定表 + 结构发现
src/types     类型鉴：Ty/Ty?/Sig 推断
src/interp    行为鉴：AbsVal 格 + 调度 + 虚栈
src/pipeline  组装：跑三鉴 + merge_group 合并
src/statecheck 用途二：通用机器表审计（MachineSpec 纯数据桥）
src/samples   demo 样例（内嵌 MoonBit 源）
src/cli       可执行入口（程序 demo + 示例机器审计）
```

## 验证

```bash
moon check                # 0 错 0 警
moon test --target js     # 14（程序语义）+ 9（机器表语义）= 21/21 全绿
moon run src/cli          # 程序 demo + pyroduct 形状示例机器审计
```

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

- **mooncakes.io**：`moon publish`（发布后 `riantr/moonbit_static_analysis@0.1.1` 可被任何 MoonBit 模块以 `import` 依赖）。
- **Gitee / GitHub**：`git push` 双推；tag 与 moon.mod 版本号保持一致。
