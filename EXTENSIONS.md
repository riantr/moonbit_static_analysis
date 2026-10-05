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
| `.mbti` | 接口文件（`moon info` 生成或手写：包的公开 API/类型签名） | 各包 `pkg.generated.mbti` | **接口审计**（`@moonfiles.iface`）：畸形行、重复签名、未知类型引用。行文法与 `moon info` 实际输出一致（注释 / `#属性` 行 / `package` / `import {}` 块 / `enum`·`struct`·`trait`·`type`·`suberror` 声明（体跳过）/ `impl … for T` / `const` / 带 `pub`、`async`、`extern`、类型参数、具名参数的 `fn`），因此生成文件不会被误判。类型声明体（字段/构造器/derive）跳过 |
| `.mbt.md` | literate MoonBit：Markdown 中嵌可执行/可测试代码块 | `pyroduct/README.mbt.md`；mooncakes 依赖的 README | **逐块三鉴**（`@moonfiles.literate`）：```moonbit / ```mbt 围栏，行号按文件真实行对齐（块前补空行），块间独立 |
| `.mbtp` | 证明文件（`moon prove` 形式化验证的逻辑侧） | `src/core/core_proof.mbtp` | **逻辑侧结构审计**（`@moonfiles.proof`）：体内字符串常量（E4207 同型）、`!`/`↔` 禁形（写 `== false` 与 `→`）、跨包 `@pkg.` 调用、lemma 缺 `proof_ensure`。**这是 lint，不替代 `moon prove`** |
| `moon.mod` / `moon.mod.json` | 模块配置 | 两模块各一 | 记录在案，不做静态分析（配置非代码） |
| `moon.pkg` / `moon.pkg.json` | 包配置 | 各包一 | 记录在案，不做静态分析 |
| `moon.work` / workspace | 多模块工作区配置 | 未使用（两模块独立） | 记录在案 |

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
- **`moon.mod` / `moon.pkg` 不做静态分析**：官方把它们放在 `moon_config` 子包里解析，本项目
  在上表里明确记为"记录在案"——配置不是代码，不进三鉴。
