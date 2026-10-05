# MoonBit 文件种类与静态分析支持（文件后缀分类表）

依据：**docs.moonbitlang.com/en/latest**（最终依据；关键页：
[script-mode](https://docs.moonbitlang.com/en/latest/toolchain/moon/script-mode.html)、
[verification](https://docs.moonbitlang.com/en/latest/language/verification.html)）。
本表是 `riantr/moonbit_static_analysis` 各文件种类的静态分析契约，由
`src/moonfiles`（.mbt.md / .mbti / .mbtp）与 `src/pipeline`（.mbt / .mbtx）实现，
`src/jsoncli` 桥的 `kind:"file"` 按扩展名分发。

| 后缀 | 官方语义 | 本项目落点 | 静态分析 |
|---|---|---|---|
| `.mbt` | 包内模块源码（函数/类型/逻辑） | 本模块全部 `src/**/*.mbt` | **三鉴程序分析**（`@pipeline.run`；`.mbti` 声明不参与） |
| `.mbtx` | **独立脚本**（无模块/包配置，`moon run script.mbtx`；可带 `import { ... }` 块） | `pyroduct/` 下的脚本；`Module.imports` 记录其导入块 | **三鉴程序分析** + 导入块审计：条目文法 `"path" [@alias] [*]`（修饰符**后置**且定序），记入 `Module.imports`，重复路径报 FParse；结果在报告里以 `Imports:` 段回显。不解析依赖 |
| `.mbti` | 接口文件（`moon info` 生成或手写：包的公开 API/类型签名） | 各包 `pkg.generated.mbti` | **接口审计**（`@moonfiles.iface`）：畸形行、重复签名、未知类型引用。行文法与 `moon info` 实际输出一致（注释 / `#属性` 行 / `package` / `import {}` 块 / `enum`·`struct`·`trait`·`type`·`suberror` 声明（体跳过）/ `impl … for T` / `const` / 带 `pub`、`async`、`extern`、类型参数、具名参数的 `fn`），因此生成文件不会被误判。类型声明体（字段/构造器/derive）跳过——**这是一个盲点，见下** |
| `.mbt.md` | literate MoonBit：Markdown 中嵌可编译/可测试代码块 | `pyroduct/README.mbt.md`；mooncakes 依赖的 README | **逐块三鉴**（`@moonfiles.literate`）：只分析**会被编译**的围栏（`mbt` / `mbt check`），行号按文件真实行对齐（块前补空行），块间独立。`mbt nocheck` 与裸 `moonbit` 是**展示块**——工具链既不编译也不测试它们——一律跳过（见下「围栏语言」）|
| `.mbtp` | 证明文件（`moon prove` 形式化验证的逻辑侧） | `src/core/core_proof.mbtp` | **逻辑侧结构审计**（`@moonfiles.proof`）：体内字符串常量（E4207 同型）、`!`/`↔` 禁形（写 `== false` 与 `→`）、跨包 `@pkg.` 调用、lemma 缺 `proof_ensure`。**这是 lint，不替代 `moon prove`** |
| `moon.mod` / `moon.mod.json` | 模块配置 | 两模块各一 | 记录在案，不做静态分析（配置非代码，见下「配置文件的边界」） |
| `moon.pkg` / `moon.pkg.json` | 包配置 | 各包一（`src/*/moon.pkg`） | 记录在案，不做静态分析（同上） |
| `moon.work` | **多模块工作区清单**（官方唯一的名字，**没有 `moon.workspace`**） | 本模块未用（单模块）；`moonbitlang/async` 用 | 记录在案 |

## 配置文件的边界（为什么 `moon.mod` / `moon.pkg` 不进三鉴）

`moon.mod` 与 `moon.pkg` 是**配置**，不是代码，本项目明确不对它们跑三鉴。原因不是"没写"：

- 官方把这两者的解析放在 `moonbitlang/parser@0.4.3` 的 **`moon_config`** 子包里，与
  `syntax`（程序 AST）、`mbti_parser`（接口 AST）**并列但独立**——工具链自己就把配置
  与源码分成了两套前端。
- 本项目的三鉴是**一个发现通道**（`@report.Report` + `Family` + lens 并集），它的输入
  是 `ast.Module`。配置里没有绑定、没有类型、没有轨迹，三鉴的三个阶段都无从施加。
- 硬塞进去只会产出"配置没有 `let` 绑定"这类无意义条目——与 `.mbti` 审计早先对每个
  真实生成文件误报是同一类错误。

**边界是「不分析」，不是「不看」**：`moon.pkg` 里的 `import { }` 声明的是包的依赖边，
它与 `.mbtx` 脚本的 import 块是**同一种语法**。本项目对后者建模为 `ast.ImportSpec`
并审计（重复路径即 FParse），对前者不做——因为 `moon.pkg` 的 import 由 `moon` 自己
在构建期解析并校验，重复项会让 `moon check` 直接失败，我们再报一遍只是噪声。

官方 `parser@0.4.3` 的 `mbti_ast` 里同样有 `PackageImport`，可见"import 声明"在
接口/配置侧是同一个概念的不同载体。

## 分类要点（易混处）

- `.mbt` vs `.mbtx`：**包内源码 vs 独立脚本**。判据是"是否带模块/包配置"，不是内容语法。
  粘贴一段代码给分析器时，默认文件名 `main.mbt`；独立脚本请传 `xxx.mbtx`。
- `.mbtx` 的 `import` 条目文法是 `"path"` + 可选 `@alias` + 可选 `*`，**修饰符后置**；
  `@alias` 与 `*` 可同时出现（文档明确：别名在 import-all 下仍可用）。`*` 不是独立条目。
  路径里的 `@version`（`"moonbitlang/async@0.20.2/fs"`）在引号内，不得与 `@alias` 混淆。
  import-all 仅限 `.mbtx`；条目之间用逗号分隔（末条目可省逗号）。
- `.mbti` 的签名行用的是**真实 MoonBit 类型**（`Array[Frame]`、`Self`、`String?`、`raise`），
  与子集程序推导签名（`fact(int) -> int`，注解名或 `Any`）**不构成可比较对**——因此 .mbti
  审计是独立健全性检查，不做声明↔实现一致性比对。
- `.mbtp` 的 `predicate`/`lemma`/`proof_ensure` 不是子集语法——证明文件走专属 lint，不走三鉴前端。

## `.mbti` 的已知盲点：声明体内的类型

`.mbti` 审计**跳过类型声明体**（字段 / 构造器 / `derive`），所以**写在体内的类型引用
从不被解析**。实测（对本模块自己的 `ast/pkg.generated.mbti` 注入对照）：

| 注入 | 结果 |
|---|---|
| `ISpectacular(String)` 放在 `enum ImportSpec` 的构造子列表里 | **0 条**（不报） |
| 同一个 `ISpectacular` 放在签名位置 `pub fn Probe::p(ISpectacular) -> Unit` | 1 条 `unknown type` |

这不是 bug 而是**范围选择**（体里还有字段名、`derive(...)` 列表等噪声，逐行解析的
误报率高于收益），但**必须写明**：`.mbti` 的未知类型检查**只覆盖签名与别名右侧**，
**不覆盖声明体内部**。`moon info` 确实会生成带类型的构造子
（如 `IStar(String)`），所以那里的类型拼写错误本工具**看不见**。

⚠️ 这类"跳过"与"检查通过"在结论上不可区分——**89/89 全清不等于 89/89 全查过**。

## 工作区清单的实际形状（`moon.work`）

官方 [workspace 文档](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html)
只承认**一个**名字：`moon.work`。`moon work init <mod...>` 生成，`moon work use <mod>` 增员，
`moon work sync` 对齐成员版本；`publish` 这类**模块专属命令**在工作区根上不可用，
要 `moon -C <mod> publish`。

真实形状（`moonbitlang/async` 的工作区根）：

```
members = [
  ".",
  "./examples",
  "./test_programs",
]
```

⚠️ **成员用相对路径，且 `"."` 指工作区根自己**——本模块没有 `moon.work`，
所以「成员列表为空」与「不存在该文件」是**两件事**，不要混为一谈。

## 真实语料的验证基础（各检查的证据强度不同）

| 检查 | 真实语料 | 证据 |
|---|---|---|
| `.mbti` 接口审计 | **89 个**（63 个 `moon info` 生成的 + 26 个本模块自己的：13 个本地 + 13 个 vendored 副本） | **89/89 全清**；其中**审计器审自己生成的接口**亦全清（自洽性）；注入 4 类缺陷逐个被抓 |
| `.mbt.md` 逐块三鉴 | **12 篇**真实 literate 文档（`moonbitlang/async` 等） | 子集外块每次 1 条；子集内块仍全分析 |
| `.mbtx` 导入块 | **0 个**真实脚本 | 只对官方文档的三个示例逐字验证 |
| `.mbtp` 逻辑 lint | **2 个**文件（本模块的 + 其 vendored 副本） | **无语料**；改为逐规则验证：4 条规则各有一个触发用例 + 5 个负向对照，桥上 9/9 如文档所述 |
| `.mbt` 三鉴 | 6 个内嵌样例 + 51 个单元测试 | 无外部语料 |

.mbti 一项的**自审**是其中最有分量的部分：把本模块自己 `moon info` 生成的 13 个接口
过一遍自己的审计器，89 个文件零发现——**审计器不会在它自己产出的形状上误报**。
这比任何注入测试都强，因为它用的是真实产物而不是构造样本。

⚠️ **"语料为空 / 只有自己的文件"不等于验证充分。** `.mbtx` 与 `.mbtp` 两行
的证据强度明显低于前三行：前者靠官方文档示例逐字钉住，后者只有自证。
**扩大 `.mbtx` / `.mbtp` 的验证只能靠引入真实文件**，不能靠再加单测自证。

## 围栏语言（.mbt.md 哪一块才算代码）

**围栏语言决定一个块是不是代码**——不是文件后缀。工具链的规则：

| 围栏 | 官方语义 | 本项目 |
|---|---|---|
| ` ```mbt ` | 编译，但不产生测试入口 | **分析** |
| ` ```mbt check ` | 文档测试代码 | **分析** |
| ` ```mbt nocheck ` | 只展示，**不编译也不测试** | 跳过 |
| ` ```moonbit ` | 普通展示块，**不编译也不测试** | 跳过 |
| 其他（`json`/`bash`/…） | 散文 | 跳过 |

早期实现把 `moonbit` / `mbt` 前缀的围栏一律当代码，于是工作区里唯一的真实
`.mbt.md`（`pyroduct/README.mbt.md`，其 Example 段是 ` ```moonbit nocheck `）
报了 **31 条**发现，**全部是假的**——它分析的是工具链自己声明不分析的块。
现在 `fence_mode` 按上表分派，只有 `FCheck` / `FTest` 进入三鉴。

`@moonfiles.fence_mode` 返回 `FCheck | FTest | FNoCheck | FDisplay | None`，
`None` 即非 MoonBit 围栏；`@moonfiles.moonbit_fences` 只返回会被编译的块。

## 前端子集覆盖（.mbt / .mbtx 分析的语法面）

- 语句：顶层 `fn`（仅限顶层）、`let`/赋值（赋值即绑定）、`if/else if/else`、`while`、`for..in`、
  `return`、`break`、`continue`、表达式语句
- 表达式：int/float/bool/string 字面量、列表 `[a, b]`、一元 `- !`、二元
  `|| && == != < <= > >= + - * / %`（优先级爬升）、字段 `.b`、索引 `[i]`、具名调用 `f(args)`
- 词法：换行敏感（opener/二元/赋值后可跨行）、`//` 行注释、`@alias` 名字（导入块与导入别名用）
- **不在子集内**：`struct`/`enum`/`trait` 定义、`match`、`pub`、`mut`、字符串插值、lambda、
  泛型、`async`、`extern`、`@pkg.` 调用——遇到以 ParseError 如实报告

## 与官方 parser/lexer 包的关系（mooncakes 参考面）

参考：**`moonbitlang/parser@0.4.3`** 与 **`moonbitlang/lexer@0.4.2`**
（https://mooncakes.io/docs/moonbitlang/parser@0.4.3 、https://mooncakes.io/docs/moonbitlang/lexer@0.4.2 ）。

官方 `parser@0.4.3` 的子包：`basic` / `tokens` / `lexer` / `attribute` / `syntax` /
`handrolled_parser` / `yacc_parser` / **`mbti_ast`** / **`mbti_parser`** /
**`moon_config`** / `fmt` / `cmd/{moonfmt,mq}`；入口 `parse_string` / `parse_file`
返回 `Impl` 列表加 `Report` 列表。其 `mbti_ast` 把 `.mbti` 建成 AST，签名种类为
`FuncSig` / `ValueSig` / `ConstSig` / `ImplSig` / `TraitSig` / `TraitMethodSig` /
`AliasSig` / `TypeSig`，外加 `PackageImport`、`MethodSelfType`、`QualifiedName`。

官方 `lexer@0.4.2` 返回
`LexResult { tokens : Array[(Token, Position, Position)], errors : Array[(Position, Position, LexicalError)], docstrings : Array[List[(Location, Comment)]] }`，
入口 `tokens_from_string` 与 `tokens_from_string_with_utf16_location`（同 token 流，位置按
UTF-16 code unit 计，供编辑器/LSP 用）；`LexicalError` 含
`IllegalCharacter` / `UnterminatedString` / `InvalidDotInt` / `MissingIdentifierAfterDot` /
`InvalidByteLiteral` / `Reserved_keyword` / `InvalidMetavarSyntax` 及若干插值相关项。

本项目与它们的**有意差异**（不是未实现，是设计选择）：

- **单一发现通道**。官方把词法错误放进独立的 `LexicalError` 枚举，本项目把它折进
  `@report.Report`（`FParse` + `[LStructural]`）。理由：三鉴模型只有一条发现通道，多一条
  就得在渲染、合并、计数里重复一份。
- **不建关键字表**。官方 lexer 用 `Reserved_keyword` 拒绝保留字；本子集 lexer 把所有标识符
  一律发成 `TName`，由 parser 按字符串分派关键字。保留字（如 `alias`）由编译器警告兜底，
  本项目的源文件因此把访问器命名成 `alias_name`。
- **不实现 `enable_metavar` / 插值 / UTF-16 位置模式**：那三条是编辑器与 LSP 的关注点，
  与三鉴发现无关。
- **`.mbti` 走行式审计而非 AST**。`@moonfiles.iface` 要做的检查（未知类型引用、重复签名、
  畸形行）本质是名字解析，行式读取已经够用；`moonbitlang/parser` 的 `mbti_parser` 会建完整
  AST，对本项目的目标而言是过度实现。
- **`moon.mod` / `moon.pkg` 不做静态分析**：官方把它们放在 `moon_config` 子包里解析，与
  `syntax` / `mbti_parser` 并列而独立；本项目的三鉴只有一条发现通道且输入是
  `ast.Module`，配置里没有绑定/类型/轨迹，三阶段都无从施加。详见上节「配置文件的边界」。
