# MoonBit 文件种类与静态分析支持（文件后缀分类表）

依据：**docs.moonbitlang.com** 的工具链手册（最终依据；关键页：
[工具链总览](https://docs.moonbitlang.com/zh-cn/latest/toolchain/)、
[script-mode](https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/script-mode.html)、
[使用与发布包](https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/package-manage-tour.html)、
[工作区支持](https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/workspace.html)、
[模块配置](https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/module.html)、
[verification](https://docs.moonbitlang.com/zh-cn/latest/language/verification.html)）。

> 读取这些页时，HTML 页面每页带约 12k token 的错误码侧栏。同样的内容可直接取原始
> markdown：`https://docs.moonbitlang.com/<lang>/latest/_sources/<页面路径>.md`
> （注意后缀是 `.md`，`.md.txt` 会 404；且 zh-cn 树下的 `_sources` 返回的仍是英文原文）。
> `raw.githubusercontent.com` 在本机不可达，`_sources` 是可用的轻量入口。
本表是 `riantr/moonbit_static_analysis` 各文件种类的静态分析契约，由
`src/moonfiles`（.mbt.md / .mbti / .mbtp）与 `src/pipeline`（.mbt / .mbtx）实现，
`src/jsoncli` 桥的 `kind:"file"` 按扩展名分发。

| 后缀 | 官方语义 | 本项目落点 | 静态分析 |
|---|---|---|---|
| `.mbt` | 包内模块源码（函数/类型/逻辑） | 本模块全部 `src/**/*.mbt` | **三鉴程序分析**（`@pipeline.run`；`.mbti` 声明不参与） |
| `.mbtx` | **独立脚本**（无模块/包配置，`moon run script.mbtx`；可带 `import { ... }` 块） | `pyroduct/` 下的脚本；`Module.imports` 记录其导入块 | **三鉴程序分析** + 导入块审计：条目文法 `"path" [@alias] [*]`（修饰符**后置**且定序），记入 `Module.imports`，重复路径报 FParse；结果在报告里以 `Imports:` 段回显。不解析依赖 |
| `.mbti` | 接口文件（`moon info` 生成或手写：包的公开 API/类型签名） | 各包 `pkg.generated.mbti` | **接口审计**（`@moonfiles.iface`）：畸形行、重复签名、未知类型引用。行文法与 `moon info` 实际输出一致（注释 / `#属性` 行 / `package` / `import {}` 块 / `enum`·`struct`·`trait`·`type`·`suberror` 声明（体跳过）/ `impl … for T` / `const` / 带 `pub`、`async`、`extern`、类型参数、具名参数的 `fn`），因此生成文件不会被误判。声明体（字段/构造子）内的类型**也会解析**（`derive` 列表豁免，见下）。未知类型按**模块级接口符号表**解析（对扫描目标的每个 `.mbti` 逐文件收集声明与 `pub using` 再导出后合并；单文件审计没有目标表，行为不变），顺序：本文件声明 → 内建名 → 类型参数 → 该表（仅类型） |
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
- `.mbtx` 的 `import` 条目文法是 `"path"` + 可选 `@alias` + 可选 `*`，**修饰符后置且定序**；
  `@alias` 与 `*` 可同时出现（文档明确：别名在 import-all 下仍可用，故 `Queue` 与 `@q.Queue` 都能用）。`*` 不是独立条目。
  路径里的 `@version`（`"moonbitlang/async@0.20.2/fs"`）在引号内，不得与 `@alias` 混淆。
  import-all 仅限 `.mbtx`；条目之间用逗号分隔（末条目可省逗号）。

  **顺序由编译器钉死，不只是文档措辞。** 四种组合逐个 `moon run` 实测：

  | 条目 | 结果 |
  |---|---|
  | `"path" @alias` | exit 0 |
  | `"path" *` | exit 0 |
  | `"path" @alias *` | exit 0 |
  | `"path" * @alias` | **`invalid .mbtx import syntax`** ／ `Parsing error: unexpected token @ls at line 2, column 29` |

  ⇒ 本分析器把 `*` 建模为**后置修饰符**而非独立条目，就是照这条错误定位的。

- **`.mbtx` 不在包级测试范围内**（官方明文：package-wide test runs do not include
  `.mbtx` scripts）。实测 `moon test <script>.mbtx` → `Total tests: 0` exit 0。
  所以本项目自己的 75 个测试**不覆盖** `.mbtx` 前端；它的证据来自
  `src/parser/parser_test.mbt` 的语法钉用例，不是来自 `moon test`。
- `.mbti` 的签名行用的是**真实 MoonBit 类型**（`Array[Frame]`、`Self`、`String?`、`raise`），
  与子集程序推导签名（`fact(int) -> int`，注解名或 `Any`）**不构成可比较对**——因此 .mbti
  审计是独立健全性检查，不做声明↔实现一致性比对。
- `.mbtp` 的 `predicate`/`lemma`/`proof_ensure` 不是子集语法——证明文件走专属 lint，不走三鉴前端。

## `.mbti` 声明体内的类型（曾经是盲点，现已解析）

`.mbti` 审计**解析类型声明体**（字段 / 构造子），所以写在体内的类型引用会被检查。
`derive(...)` 列表**豁免**——它列的是 **trait** 不是类型。

**关键：先判构造子形状（顶层有 `(` 就走它），再在括号内按逗号切、逐段取类型半边。**
原因是 `Constr(a, label~ : T)` 一行里**同时**是构造子和 `label : Type` 对；
按"第一个 `:` 切分"必然把**带标签的参数名**当成类型名。踩过一次，量出来的：

| 真实行 | 只按 `:` 切分 | 先判构造子 |
|---|---|---|
| `OSError(Int, context~ : String)` | `context` 误报 | ✅ 只取 `Int`/`String` |
| `ExponentialDelay(initial~ : Int, factor~ : Double, maximum~ : Int)` | `factor`/`maximum` 误报 | ✅ |
| `Rename(old~ : String, new~ : String)` | `old`/`new` 误报 | ✅ |

**第一版（`: ` 优先）在 89 个真实接口上量到 7 条误报，已回滚**；改成构造子优先后
重测：**89 个文件 0 条误报**，且 6/6 探针全对（体内未知载荷类型、未知字段类型会被
抓；带标签参数名、`derive(...)` 列表、`UInt16` 这类真内建不会被误报）。

顺带补全内建集合：**`UInt16` 是真的**（工具链自己的 `utils.mbt` 就在用，
`moonbitlang/async` 的 `websocket` 接口也在构造子里用它），原先漏了它，
连同 `Int16` / `UInt8` / `Float` 一并加入。

⚠️ 顺带记一次**我自己探针的错误**：`ISpectacular(String)` 里的 `ISpectacular`
是**构造子名**不是类型，所以"体内未知类型"那样注入**根本构不成盲点**——要注入
得写 `Other(Ghost)` 这种载荷，或 `field : Phantom`。**盲点是真的，但我第一次的
探针没能证明它。**

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
| `.mbti` 接口审计 | **89 个**（63 个 `moon info` 生成的 + 26 个本模块自己的：13 个本地 + 13 个 vendored 副本） | **89/89 全清**；审计器审自己生成的接口亦全清（自洽性）；在本模块自己的接口形状上注入 **5 类缺陷全部抓到**、2 个负向对照全部静默（7/7） |
| `.mbt.md` 逐块三鉴 | **12 篇**真实 literate 文档（`moonbitlang/async` 等） | 子集外块每次 1 条；子集内块仍全分析 |
| `.mbtx` 导入块 | **0 个**真实脚本 | 只对官方文档的三个示例逐字验证 |
| `.mbtp` 逻辑 lint | **2 个**文件（本模块的 + 其 vendored 副本） | **无语料**；改为逐规则验证：4 条规则各有一个触发用例 + 5 个负向对照，桥上 9/9 如文档所述 |
| `.mbt` 三鉴 | 6 个内嵌样例 + 75 个单元测试 | 无外部语料——样例是合成的，真实文件的实测缺口见下 |

.mbti 一项的**自审**是其中最有分量的部分：把本模块自己 `moon info` 生成的 13 个接口
过一遍自己的审计器，89 个文件零发现——**审计器不会在它自己产出的形状上误报**。
这比任何注入测试都强，因为它用的是真实产物而不是构造样本。

更进一步：在**本模块自己的接口**上注入缺陷，5 类全部抓到（构造子载荷里的未知类型、
结构体字段里的未知类型、重复签名、畸形行、签名位置的未知类型），2 个负向对照
（真内建载荷 `UInt16`、带标签参数名 `context~`）全部静默 —— **7/7**。
注意这是**在换了 body 解析器之后重跑的**，不是沿用旧结论。

⚠️ **"语料为空 / 只有自己的文件"不等于验证充分。** `.mbtx` 与 `.mbtp` 两行
的证据强度明显低于前三行：前者靠官方文档示例逐字钉住，后者只有自证。
**扩大 `.mbtx` / `.mbtp` 的验证只能靠引入真实文件**，不能靠再加单测自证。

## 围栏语言（.mbt.md 哪一块才算代码）

**围栏语言决定一个块是不是代码**——不是文件后缀。**工具链实测为准，文档措辞不算数**：
下表是把一个未定义调用放进每种候选围栏、再问 `moon check` 到底报哪几个得到的
（moon 0.1.20260920）：

| 围栏 info | 工具链是否编译 | 本项目 |
|---|---|---|
| ` ```mbt check ` / ` ```mbt test ` | **编译**（可作测试入口） | **分析** |
| ` ```moonbit check ` / ` ```moonbit test ` | **编译** | **分析** |
| ` ```mbt ` | **不编译**（与裸 `moonbit` 同为展示块） | 跳过 |
| ` ```moonbit ` | **不编译** | 跳过 |
| ` ```mbt nocheck ` / ` ```moonbit nocheck ` | **不编译** | 跳过 |
| ` ```mbt Check `（大写 C） | 不编译——**第二个词大小写敏感** | 跳过 |
| ` ```mbtcheck `（无空格） | 不编译 | 跳过 |
| ` ```mbt check extra ` | 编译（多余词忽略） | **分析** |
| 无 info / 其他（`json`/`bash`/…） | 散文 | 跳过 |

> ⚠️ 本表曾经把 ` ```mbt ` 写成「编译，但不产生测试入口」。**那是错的**，来源是文档
> 措辞而非实测：裸 `mbt` 与裸 `moonbit` 一样是**展示**块，必须加 `check` / `test`
> 才成代码。分析这些块 = 分析工具链从不构建的代码。已改，并移除了不再产生的
> `FCheck` 变体（`moonfiles` 是 0.2.0 新增的包）。
>
> **关于版本号**：删 `FCheck` 是对已发布 0.2.1 API 的破坏性改动，但**仍走 PATCH
> （0.2.2）而不是 MINOR**。两条理由：
> 1. SemVer 2.0.0 §6/§7/§8 三条递增规则**全部**带 `| x > 0` 守卫；0.x 阶段由
>    §4 管——「Anything MAY change at any time. The public API SHOULD NOT be
>    considered stable.」
> 2. 这次是**纯修复**（分类本来就是错的），没有新功能。走 MINOR 反而会按
>    MoonBit 发布页的定义对外宣称「向后兼容地添加了功能」，那才是误导。
>
> 记这一条是因为我一度按「不兼容 → MAJOR」建议发 0.3.0，那是**套用了 x>0 才
> 生效的规则**。判据：0.x 阶段先查 SemVer §4，别急着套 §8。

早期实现把 `moonbit` / `mbt` 前缀的围栏一律当代码，于是工作区里那份真实
`.mbt.md`（`pyroduct/README.mbt.md`，其 Example 段是 ` ```moonbit nocheck `）
报了 **31 条**发现，**全部是假的**——它分析的是工具链自己声明不分析的块。
现在 `fence_mode` 按上表分派，只有 `FTest` 进入三鉴。

> 「唯一」是当时的措辞，现在不成立：pyroduct 有 `README.mbt.md` 与
> `README.zh.mbt.md` 两份，工作区里还留着一份陈旧副本。三份各含 1 个
> ` ```moonbit nocheck ` 围栏、0 个 ` ```mbt ` 围栏，**当前实现对三份都报 0 条**
> ——这正是「展示块必须跳过」这条规则的正向验证（实测，非推断）。
>
> 这三份语料的**局限**要说清楚：它们全是展示围栏，所以只验证了「跳过」这一半。
> 「`check` / `test` 会被分析」这一半**没有任何真实语料**，只有
> `src/moonfiles/moonfiles_test.mbt` 里的合成用例 + 上表的工具链实测背书。

`@moonfiles.fence_mode` 返回 `FTest | FNoCheck | FDisplay | None`，
`None` 即非 MoonBit 围栏；`@moonfiles.moonbit_fences` 只返回会被编译的块。

## 前端子集覆盖（.mbt / .mbtx 分析的语法面）

- 语句：顶层 `fn`（仅限顶层）、`let`/赋值（赋值即绑定）、`if/else if/else`、`while`、`for..in`、
  `return`、`break`、`continue`、表达式语句
- 表达式：int/float/bool/string 字面量、列表 `[a, b]`、一元 `- !`、二元
  `|| && == != < <= > >= + - * / %`（优先级爬升）、字段 `.b`、索引 `[i]`、具名调用 `f(args)`
- 词法：换行敏感（opener/二元/赋值后可跨行）、`//` 行注释、`@alias` 名字（导入块与导入别名用）
- `pub` / `pub(all)` / `priv` / `async` 是**修饰符**：不再报「未定义变量」，
  其后若跟 `fn` 仍按函数解析。`extern` 不算修饰符——它的体是裸字符串 `= "..."`。
- **不在子集内的声明**：`struct` / `enum` / `trait` / `impl` / `derive`（花括号体）
  与 `type` / `const` / `suberror`（行终结）——**整块消费、只报一条 FParse**
  并指名是哪种声明，不逐字段解析，因此不级联。顶层 `fn` 是哨兵：无体的
  `pub impl Eq for T` 不会把文件后续吃掉。
- **不在子集内的表达式**：`match`、`mut`、字符串插值、lambda、泛型、`@pkg.` 调用
  ——这些出现在**函数体内部**，目前会级联，是下述实测缺口的主要来源。
- **`extern "c" fn`（2026-10-09 本轮修正）**：原先和 `type`/`const` 一起整条跳过，
  但**跳过会丢名字**，于是每个 extern 函数的调用点都报未绑定。现在按声明建模：签名
  是真的（类型 lens 能查调用），函数体是空的（实现在别的语言里，不猜任何语义）。
  core 里有 16 个文件这么写。原先写在这里的「`extern` 整条跳过」已经不成立。
- **方法调用 `base.m(args)`（2026-10-09 本轮修正）**：原先这里写着「AST 里根本没有
  位置，属于改设计，尚未做」。已做：新增 `EMethodCall(Expr, String, Array[Expr])`，
  三个 lens 都接上（结构走 receiver 但不解析方法名，类型定型为 Unknown，行为求值
  返回 Any）。之所以必须独立成节点而不是复用 `ECall`：receiver 必须是一个独立的
  `Expr`，否则 flatten 会把「只被写入」的局部变量误报成未使用。
  修完之后 core 上 `only named functions can be called` 从 34 降到 **0**，
  882 个 `.mbt` 解析 158 → **173**。
- **`raise` 效应标注（2026-10-13，0.4.23）**：`-> T raise`、`-> T raise E`、`-> T!`
  三种形式，以及**类型位**的 `() -> T raise`，现在由单个 `Parser::parse_raise_effect`
  读取。settle 过：四种形式 `moon check` **0 错误**；裸形出自
  `moonbitlang/core/error/error_test.mbt`，不是自造的形状。**效应类型故意不记录进
  AST**——没有任何 lens 读它，给 `SFunc` 加字段会波及 walk/types/infer/interp 和
  `.mbti`，而那里还没有对应的检查。消费它才是让文件可读的那一步。
  裸形的停止判据是「下一个 token 能不能开一个类型」（`TName`/`TLParen`/`TAmp`），
  **不是**「哪些 token 终结」：两个方向不对称，多读一个 token 是**静默误解析**
  （函数体被吞进类型标注），少读一个 token 是响亮的 `expected '{'`。
- **`guard!`（2026-10-13，0.4.23）**：`guard!` 是 `guard` 加一个 `!`，而词法器不把两者
  合成一个名字。原先 `parse_guard` 读完 `guard` 就去读条件，`!` 掉进表达式读取器变成
  对条件取反，报出 `operand of '!' must be bool, got '[int]'`——一个关于**能编译的代码**的
  假阳性（`moonbitlang/async` 0.22.4 `src/internal/fd_util/pipe.mbt:31`）。
  两种形式仍然建模成同一个 `SIf`，这是 `guard` 本来就声明的展平。
  ⇒ **`TBang` 这一个 token 有三个主人**：`raise` 短式、`guard!`、真正的布尔非。
  三者只能**按位置**判定，任何一个改成扫 token 都必须有一条对照测试变红。

### `raise` 作为语句：一条子句的第三个位置（2026-10-13，0.4.24）

`raise E` / `raise E(payload)` / **不带 payload 的裸 `raise`**，现在由 `Parser::parse_raise_stmt`
读成新的 `SRaise(Expr?)` 节点。settle 过：带 payload 的五种形式、以及裸形式的三个位置
（独占函数体 / 函数体末尾 / 闭合嵌套块且无分号），`moon check` 全 **0 错误**。

**为什么之前没发现**：0.4.23 做完之后我把每一个 `UndefinedName` 分类，结论写成「`enum`/
`suberror`/`derive` 的构造子在分析子集之外」。**分类推翻了这个结论**：大约 70 条里
**65 条是字面量 `raise`**，构造子只有 7 条上下。`raise` 作为语句从来没实现过，而这一版
之前所有关于「噪声来自未建模声明」的判断都是照着 0.4.23 那批**新可读**文件里的假象做的。

规模（排除 vendored `.mooncakes`）：proton 585 处 / 54 文件、async 427 / 90、
moonbit_image 180 / 16、moonbit_labeler 15 / 9、proton_contract 6 / 1。出处
proton `facade_app_metadata.mbt:82`。⇒ 结果 **65 条假阳性全部归零，任何 family 0 条新增。**

**`SRaise` 而不是 `SReturn`**：三个透镜都会读错——`scan_returns` 的
`SReturn(Some(e)) => acc = ty_join(acc, ty_of(e))` 会把**错误构造子的类型** join 进返回类型；
`Interp` 的 `SReturn` 会把 payload 求值后 push 进 `ret_vals`，**凭空造一个 `raise` 不产生的
返回值**。payload **照常 walk 和类型检查**，但**不求值**（终止符之后都是死代码）。

**⇒ 量规模之外还要量「会不会变吵」**：行为透镜的 `if` 各分支在同一个 `Interp` 里顺序执行，
flow 会串分支。实测 12,428 个文件 `Unreachable` 0 → 0，但缺陷真实且**不需要 `raise` 就能复现**：

```moonbit
fn f(g : Int?) -> Int {
  guard g is Some(v) else { return 0 }
  return v            // 假阳性：else 终止，then（空）不终止，else 的 flow 赢了
}
```

**0.4.24 不修**（六个语料 0 次触发，且改的是分支合并语义）。**如实记账，不是缺测试。**
→ **已在 0.4.25 修掉**，见下一节。改完之后六个语料**逐字节不变**。
另记：`enum_ctors` 只接了 `enum`，没接 `suberror`/`derive`；跨文件 `.mbti` 里的构造子名字
根本进不了 `IfaceSymTab`——那是剩下那 7 条的来源。

### `derive` 没有 body：以及「度量为 0 不等于推论为 0」（2026-10-13，0.4.28）

**修法**：`derive` 从 `skip_decl_braced` 挪到 `skip_decl_line`。它本来就是**带括号的 trait 列表**，
不是大括号声明。

**两个后果，只有一个看得见**：

1. `skip` 的文案由 `braced` 标志决定 ⇒ 每条 derive 通知都写着「its body was not analyzed」，
   而 **derive 没有 body**。生产代码 570 条。
2. `skip_decl_braced` 向前扫找 `{`、只在 `fn` 处停 ⇒ `derive` 会把**后面某个**声明的大括号吞掉，
   那条声明自己的排除通知**从未发出**。实测：struct 572→829、enum 155→246、extend 238→308。

**⇒ 判据一：ParseError 通知数**上升**可能是修复在起作用。**
本版 notice 5,026 → 5,399（**+373**），而**六个语料的 actionable 全部不变**
（moui 1 / labeler 0 / image 0 / async 19 / proton 68 / proton_contract 2）。
通知是覆盖率地图；靠少报让数字变小，方向正好是反的。

**⇒ 判据二：度量对了，推论照样可以错——**这是 0.4.27 的同一个错误家族。
我量的是「`derive` **紧跟**一个大括号声明」在 moui 0.1.12 的出现次数，得到 **0**，于是写下
「对语料零影响」。**度量没错，错的是我以为它在量什么**：跳過器不在下一行停，它扫到**任何** `{`
才停，隔多少行都行。它一直在吞，只是吞的不是我量的那种紧邻形状。
**⇒ 「我量到 0」只能支持「我量的那个形状是 0」，不能支持「这个机制没有影响」。**

**⇒ 判据三：突变要按**行为的一半**分开写，不能只测整体。**
M1（退回 braced）与 M2（消息重新声称有 body）是分开的。只有 M1 被杀的话，测试锁住的是
**分派**，一条声称存在函数体的消息照样能过。

### `as` 没有产生式：以及「门禁自己可以是错的」（2026-10-19，0.4.29）

**修法**：`ECast(Expr)` + `parse_postfix_from` 里的 `as` 分支。`as` 早就在词法器关键字表里，
但**表达式**文法里没有任何东西消费它，于是 postfix 循环在它上面断开，语句读取器把剩下的 `as`
当成下一个表达式的开头，绑定遍历把它当成标识符解析 ⇒ `undefined name 'as'`。
**一个从来没存在过的名字。** `guard`（0.4.21）、`raise`（0.4.23）、`as` 是同一形状的第三次。

**对编译器的定案**（`_verify/settle_0428_cast.ps1`）：三种 `as &Trait` 形式 ACCEPTED；
`b as` 与 `b as Box` 都 REJECTED。`moon check` 原话：「`Int` is not a trait object type, it
cannot be used on the right hand side of `as`」⇒ `as` 是解析器必须接受的**运算符**，
被约束的只有右侧。**这个 settle 的前两稿什么都没定下来**：一稿把 `fn() => 1` 当 lambda
（MoonBit 用大括号，那是 3002），一稿拿 `as Int` 当目标，所有用例都死在无关的规则上。
**⇒ 一个因无关原因失败的 settle 用例，什么也没 settle，哪怕它打印了别的什么。**

**⇒ 判据一：看得起来可查 ≠ 可查。**
`as` 要求 trait object，类型**看起来**可查。**它不可查**：`IfaceSymTab` 不区分 trait 与
struct——`using @pkg { type View }`、`trait` 声明、`struct` 声明全落进同一个 `types` 集合。
基于那张表的检查会把每个转成 struct 的 cast 都报出来。所以目标类型**读掉并丢弃**，
`ECast` 只带操作数。**带着却不读，是一个没有透镜能查的字段，比不写更糟。**
这是 0.4.26 `()`→TNone 教训的反面形态。

**⇒ 判据二：修掉一个假阳性，可能顺手造出另一个。**
`walk` **必须**遍历操作数。`fn to_sink(b : Box) -> &Sink { b as &Sink }` 里只有这一处读 `b`；
不遍历就返回的 arm 会把参数报成未读，**用一个假阳性换另一个**。`EComp` 教训的原样形态：
**没被遍历的那一半，就是会消失的那一半。** M2 专门杀它。

**⇒ 判据三：存活先问「有没有夹具到得了那段代码」，再问「模式串对不对」。**
M4（interp 不求值操作数）存活。三版夹具都失败，且**每次失败原因不同**：
`MethodError` 根本不存在（`1.nomethod()` 什么都不报；我探针数到的那条是**警告** `UnusedParam`，
被 grep `error:` 滤掉了）；放进从不被调用的函数——`Interp::run_top` 直接跳过 `SFunc`
（`interp.mbt:389`）；放进 `fn main`——它**也是** `SFunc`。
最后 `_verify/probe_0429_m4.ps1` 上突变、构建、diff 真实输出，五个程序**全部逐字节一致**，
两条实测理由：操作数里的未绑定名字是 walk 报的 `undefined name`，与 interp 的
`undefined variable` **同族同 span**，`merge_findings` 只显示一个；`FMethodError` 与
`FOpMismatch` 共用 `"arg-type"` 组（`core.mbt:380`）。
**⇒ 这里记的是「我造不出能观测到它的夹具」，不是「已在整个输入空间证明等价」。**
保留 `eval` 的理由是每个兄弟 arm 都求值自己的操作数——**一致性是理由，不是证明**。

**⇒ 判据四：门禁自己可以是错的，而且会把「没钉住」报成「钉住了」。**
早先一次运行报「M4 KILLED, 2 of 442 red」，而**杀死它的两个测试在干净代码上就是红的**
（断言了一条分析器从不产生的 `MethodError`）。此后每个突变都同样报那两条红，于是门禁看起来
健康，唯一没被钉住的突变被报成钉住了。
**⇒ 突变计数只有在基线是绿的时候才有意义。** `_verify/mutate_0429.ps1` 现在先跑一遍未突变的
套件，不是全绿就中止。同族判据：**「0 problems」在往里植入已知缺陷之前，不算证据。**

**语料效果**：人口用**工具自己的输出**数（分析器每个出现发一条发现、发现里写着 token，
数它继承不到匹配器的盲区），`undefined name 'as'` 六语料**恰好 1 处**
（moui `runtime/view_tree.mbt:69:38`）——**而那一条就是 moui 全部的 actionable**。
A/B：moui actionable **1 → 0**，另外五个语料**逐字节一致**。自检 68/68、actionable=0。
测试 js 442（新增 12）/ wasm 514 / wasm-gc 442。

### 自检的 823 条通知花在哪：429 条是测试体本身（2026-10-13，0.4.29 之后补记）

补记起因：给「已发布包扫自己」加门禁（`_verify/selfscan_published.ps1`）时顺手数了一遍通知的
构成，结果动摇了「自检 actionable=0」这句话的读法。

| 排除理由 | 条数 |
|---|---:|
| **test 声明在已分析子集之外** | **429** |
| match 表达式 | 155 |
| struct 声明 | 36 |
| derive 声明 | 31 |
| enum 声明 | 14 |
| short lambda | 2 |

`test` 与 `impl`/`trait` 走同一个 `skip_decl_braced`，所以**测试体整块不遍历**。429 条
**比其余全部加起来还多**，占 823 的一半。

**⇒ 判据：`actionable=0` 必须连覆盖面一起说。** 它说的是**被分析了的那部分声明体**，
不是那 823 个被排除的体。这个 0 有一部分是**靠不看换来的**，而且看的恰好是最大的一组。
这是 0.4.10 那条（「一个干净的 0，有一部分是靠**不看**得到的」）对准了项目自己的测试套件——
同一族，只是这一次的「不看」有明确入口：`test`。

**这不是缺陷**：测试代码不是交付代码，整块跳过是既有的子集边界，通知也照实说了。
**但它是覆盖面事实，必须写出来**，否则每次引用「自检 0」都在替一个未说明的口径背书。
两个 README 的 0.4.29 段落已就地补上这句。

**⇒ 配套：门禁自己也会错，而且第一跑就错。** 新写的 `_verify/selfscan_published.ps1`
第一次跑就 `ABORT`，报「asked for 0.4.29, the registry resolved to ''」——**发版是好的，
断言是坏的**：它读 `Latest version ... is X`，而 `moonx` **只在坐标是 `@latest` 时**打这一行；
显式 `@0.4.29` 打的是 `Fetching`/`TARGET`。**缺失的行被读成空解析，于是一次健康的发版被判失败。**
改成读 `SCANNED ... under .repos/<owner>/<name>/<version>`——两种模式都有，而且更强：
它说的是发现**实际来自哪个目录**。
**⇒ 判据：断言必须读两种执行路径都存在的那条证据；只在一侧存在的那条，是把缺失当成了结论。**
配套：`-Coordinate` 参数是为了让版本断言有负控——`-Coordinate @0.4.28` 对着 moon.mod 的
0.4.29 必须**失败**，那次失败就是「这个断言会咬人」的证据。**无法被证明会失败的断言，只是注释。**

### 返回位置带括号的函数类型：以及「跨两棵树比数字，量的是树」（2026-10-18，0.4.27）

**修法**：`return_annotation` 的判据从「匹配到的 `)` 后面是不是 `->`」扩成
`arrow_inside || is_fn`——箭头只可能在两个地方：括号**之内**，或紧跟匹配到的 `)` **之后**，
一次带嵌套计数的扫描同时回答两者。

**缺陷机制**：元组分支一路吃到第一个前面没有逗号的 `)`。`(() -> Int)` 里那个 `)` 是**空参数
列表**的右括号，于是标注在 `()` 处结束，`-> Int)` 留在 token 流里，`parse_block` 找不到 `{`，
报 `expected '{'`，之后整个文件死掉。

**语料效果**：同一棵树上两个 build 的 A/B——moui 三个文件从 PARTIAL 变成完整解析
（`services/service_task.mbt`、`core/program_subscription.mbt`、
`backend/common/services/service_async_queue.mbt`），`unexpected token` 从 113 降到 110；
另外五个语料逐字节一致。

**⇒ 判据一：跨两棵树比数字，量的是树，不是改动。**
proton 的 actionable 在新树上读作 68，旧基线记的是 100，差 32 条看着像大胜。**那是语料树换了**
——旧基线取自 TEMP 兄弟树，而 `--extern-iface-dir` 会把兄弟树的接口表喂进这一轮。能归因的
只有「同一棵树、两个 build」。

**⇒ 判据二：匹配器太窄不会报「未找到」，它报「我没看」，而这两件事在屏幕上长得一模一样。**
这一版我的「这个构型在语料里出现多少次」脚本**连报两次假零**：

| # | 机制 | 为什么必然报 0 |
|---|---|---|
| 1 | `\([^()]*\)` 匹配括号组 | 匹配不了嵌套括号——**对一个按构造就含嵌套括号的形状报「未找到」** |
| 2 | 修好括号、改用平衡扫描，但前缀仍是 `\bfn\s+[A-Za-z_]\w*\s*\([^()]*\)` | 匹配不了 `fn[T]`（`fn` 后紧跟 `[`）、`Type::name`（`::`）、多行参数列表 |

真实数量是 **24 处、9 个 moui 文件**。修法不是把正则写得更长，而是**不再去认签名**：找每一个
`->` token，问紧跟其后的括号组里有没有箭头。对照不是合成文件，是 A/B——它**必须**找出 A/B 说
改动的那三个文件，否则门禁中止。

**⇒ 判据三：一个 settle 报了 15 个 clean，可能是因为它什么都没查。**
这一版 settle 因为**用例 key 没有 `.mbt` 后缀**而全绿：清理用的 `-Filter '*.mbt'` 匹配不到
任何文件（旧用例全部堆积），而 `moon check` 根本不编译无扩展名的文件，输出是 44 字节的
`Finished. moon: ran 2 tasks, now up to date`。**唯一的证据是那个本该变红的负控制，它也读了
clean。**⇒ 负控制必须**断言**变红，不能只是「列表里有一个」。

**⇒ 判据四：突变存活先分清「没测到」和「等价」，后者要证明，不要造夹具。**
M4（`arrow_inside` 初值改成 `true`）存活。证明它等价：元组分支返回 `""`，函数类型分支返回
`"(Int)"`，而 `ann_to_ty` 把**两者都**映射成 `TUnknown`（没有任何分支会剥掉那对括号）；
标注字符串只有一个消费者 `declared_ret`，所以 M4 在**整个输入空间上**都不可能改变可观测量。
**硬造一个夹具去杀它是表演**——这个突变没有行为可杀。我第一次尝试时断言的是
`ann_to_ty("(Int)") == TInt`，**错的**，那道夹具因此没有改变任何结论；它留下了（那条路径本来
就该有夹具），注释改成写明它建立了什么、没建立什么。

**顺带 settle 出来的两条 MoonBit 事实**：lambda 用**花括号**（`fn() { 1 }`；`fn() => 1` 报
`unexpected token '=>'`）；**顶层大写名是类型**（`fn G() -> Int` 报
`unexpected token '(', you may expect '::'`）。

### 尾表达式就是返回值：以及「settle 必须先证明自己在测量」（2026-10-13，0.4.26）

**修法**：新 AST 节点 `STail`，`parse_block` 多一个 `fn_body : Bool`——**只有函数体**
产生尾节点，因为同一个块解析器还要读循环体、`if` 分支和裸块，在那里尾表达式是一条被丢弃的
普通表达式语句。三个透镜各自不同：walk 同 `SExpr`；类型透镜把类型 join 进推断返回类型；
行为透镜记录值但**不动 flow**，而且**必须求值**（与 `raise` 操作数正相反）。

**语料 delta：六个语料 12,428 个文件逐字节与 0.4.25 一致。** 有复现器的正确性修复。

**⇒ 判据一：settle 必须先证明自己在测量，否则「12 个形状全过」等于什么都没测。**
这一版我的 settle 空了两处，两处都不报错：

| # | 机制 | 后果 |
|---|---|---|
| 1 | `moon check` **只检查从 `fn main` 可达的函数体** | 没有 `main` ⇒ 零类型检查 |
| 2 | 脚本 `Get-ChildItem src -File | Remove-Item` **把 `src/moon.pkg` 一起删了** | 没有包 ⇒ `moon check` 什么都不输出 |
| 3 | PowerShell 把 native 命令写 stderr 变成 `NativeCommandError`，合并串为空 | 输出被吞 |

两个反例全部读成「0 错误」：`fn f() -> Int { "a" }`（MoonBit 报 4014）和 `fn f() { 1 }`
（4074）。**⇒ settle 必须带至少一个必然失败的负控制，并且它必须真的红。**

**⇒ 判据二：settle 有时也会告诉你关于「语言」的事，而不只是关于这个分析器。**
它查出两条：`while s == "a" { "b" }` 是 **4139**（循环体的尾表达式被丢弃，只有 Unit 能静默
丢弃）——**我第一版的测试夹具就是这么写的，而一个编译器拒绝的夹具不是夹具**；以及
**尾表达式必须有声明的返回类型**（4074）。后者正好解释潜在面为什么正好是 305：**受影响的
函数集合就是编译器已经逼你标注的那个集合。**

**⇒ 更正我自己：这条待办上一版写的是「可能比 `raise` 本身还大」。实测是错的。**
`raise` 六个语料共 **1213** 处，尾表达式函数 **305** 个（moui 108 / labeler 64 / async 69 /
proton 40 / image 24）。**大约四分之一。** 潜在面用逐花括号匹配器量的，不是 grep——
一行 regex 分不清「函数的最后一条语句」和「嵌套块的最后一条语句」。

**⇒ 判据三：把一个透镜改成「更具体」的类型，可能在另一个透镜里制造新假阳性。**
我在类型透镜里也把 `()` 教成 Unit 去配行为透镜。`TNone` 是**具体**类型，于是空元组和任何
东西比较都会报——moui `backend/macos/macos_backend.mbt:204` 多出一条
`unsupported operand types for '>': 'int' and 'None'`。**那个文件的解析停止行、notice 数、
actionable 数在那一刻全都和前一版一模一样**，只有六语料逐字节 diff 看见了它。
⇒ **类型透镜那一步已回退，行为透镜保留**（签名行的值来自那里）。M5/M6 是这道门禁里的永久
对照：M5 复现这个错，M6 是它的反面。

**⇒ 配套：pre-flight（0.4.25 加的）当场回本。** 本门禁第一版有两个模式串写的是 `moon fmt`
会折成**一行**的三行臂，pre-flight 毫秒级中止并打出它要找的那行。突变门禁 **7 杀 0 存活**。

### 分支合并语义：join，以及「夹具必须真的走到被测代码」（2026-10-13，0.4.25）

**修法**：条件未知的 `if`，每个分支执行前 `self.flow = FNormal`，执行后贡献
`falls = self.flow == FNormal`；**缺 else 恒 `falls = true`**；末尾
`self.flow = if falls { FNormal } else { FReturn }`。`exec_alt` 从 `Unit` 改成返回 `Bool`，
它的 `ABool(false)` 臂做同一个 join。

**语料 delta：六个语料 12,428 个文件逐字节不变，`Unreachable` 0 → 0。**
这是**一个带复现器的正确性修复，不是「清理掉了什么」**——把 0 说成成果是本项目一直在
拒绝的话，所以这里也照写。

**⇒ 判据一：夹具必须真的走到它声称在测的那段代码，否则「通过」和「静默」无法区分。**
第一版 8 道里死了 4 道，全都死在这：

| 夹具 | 实际发生了什么 | 看起来像 |
|---|---|---|
| `let x = f(1)` + `if n > 0` | `n` 绑成 `AInt(1)`，`binop` **折叠**成 `ABool(true)`，then 单独跑，**join 所在的臂没进** | 正常 |
| `let x = f(g())`，`g` 未定义 | 调用返回 `ABottom`，`n > 0` 是 `ABottom`，**整个函数体静默** | 通过 |

能走到的形状：`s == "a"`（`binop` 的 `OpEq \| OpNe` 臂无条件返回 `AType("bool")`，
**没有字符串臂可折叠**）、`f(@core.nothing)`（`AAny` 吸收成 `AType("bool")`）、
`x is Some(v)`（`EIs` **故意**返回 `AAny`，所以真实代码里的每个 `guard` 本来就走 join）。

**⇒ 判据二：一个夹具的「对照」必须期望相反的数，否则它可能只在重测别的东西。**
折叠夹具（`f(1)`，无 else，then 返回）期望 **1**，不折叠夹具（`f("a")`，同形状）期望 **0**。
**这个反转就是「两者真的走了不同臂」的证据。** 第一版两条都用 `f(1)`，那条「对照」只是在
重测常量折叠，却长得像证明了 `else` 的什么性质。

**⇒ 判据三：NO-OP 变异只有跑完全套件才报得出来，所以模式串要先 pre-flight。**
M5/M6 的缩进按 10 空格写而文件里是 8/6；M7 的模式串写成 `None => true` 而源码是
`None => falls = true`——三道各白跑一次 `moon test`。现在任何模式串在原文里找不到就在
毫秒级中止并打出它要找的那一行；第四轮修 M8 时它立刻抓到我自己的一个错（M8 的 Find 串
误抄了 M6 的**替换后**文本）。

**⇒ 判据四：变异存活时先问「有没有夹具到得了那段代码」，而不是先调模式串。**
M6 存活是个覆盖问题：`exec_alt` 的**终止** `match els` 只在**没有剩余 else-if** 时执行，
而当时每个链式夹具都带 else-if。补夹具时又发现 **M8**——M6 背后那条「缺 else 恒
falls through」的**终止版**同样没人测过。现在 M6/M8 改**同一个 8 行块里的一行**，两个方向
互为对照。**一个两句都说不了的块是没有用的，而两个突变各自都看不见对方的夹具。**

**⇒ MoonBit 细节**：枚举**默认不实现 `Eq`**（`self.flow == FNormal` 报 `Type Flow does not
implement trait Eq`），要 `derive(Eq)`；`for j in (idx+1)..elseifs.length()` 会解析成
`(idx+1)..elseifs` 再 `.length()`，遍历剩余 else-if 必须用 `while`。

`ABottom` 条件保持原语义（不终止、falls through）——**「bottom 条件该不该压制下游」是另一
个问题，这一版两个方向都没回答**，不要把它当成已经解决。

### 计数型断言分辨不出的东西（0.4.24 突变门禁记）

**payload 不被解析时它不会消失，它变成下一条语句。** `raise E(nosuchfunction())` 被读成
`SRaise(None)` + 表达式语句 `E(nosuchfunction())`，同样两个未定义名字、同样同一行、同样合并
成一条——**所有计数断言两种实现都通过**。第一版 7 道突变死了 3 道，全是这个原因：

- 分辨它靠的是**锚点行号**，不是条数：payload 挂上去时死掉的是 `return 1` 那一行，
  被孤立时死掉的是 payload 自己那一行。
- 另一个原因：对**未知名字**的调用没有签名可查实参，`ty_of` 提前返回，payload 根本没被看。
  要让类型透镜真的检查，payload 得是它自己能查的表达式（`1 + "a"`），而不是一个调用。

### 量规模时必须排除 `.mooncakes`（2026-10-13 的一次自我更正）

开工时按「文件里出现 `-> T raise`」grep 六个语料，报出 moui 608 个文件里 149 个
（24.5%）带该标注。**那个数把 vendored 的 `.mooncakes` 一起数了，而扫描器不扫 vendored
目录。** 排除之后 moui 只有 **2** 个。同一把尺子（`.mooncakes` excluded）：

| 语料 | 文件 | 签名位 | 类型位 |
|---|---|---|---|
| `moonbitlang/async` 0.22.4 | 409 | 72 | 10 |
| `moonbit-community/proton` 0.3.4 | 136 | 70 | 33 |
| `riantr/moonbit_image` 0.3.7 | 17 | 14 | 0 |
| `wzzc-dev/moui` 0.1.12 | 607 | 2 | 0 |

修复是真的（`moonbit_image/bmp.mbt:26` 干净解析），但**规模报大了一个数量级**。
可读文件总数 787 → 825。⇒ **任何按「文件里有没有 X」计的规模数，都必须先说清楚
vendored 目录算不算**，否则报出来的数字和扫描器实际处理的文件集对不上。

### 可读性变多会让 actionable 变多（2026-10-13 的实测代价）

修好解析之后，六个语料可读文件 787 → 825，同时 **proton actionable 43 → 103**、
async 17 → 22、moonbit_image 0 → 3。**按 family 数过，新增的 actionable 一条
`UndefinedName` 都不例外**，`OperatorMismatch` 反而因为 `guard!` 修好而**减少**（2 → 0）。
抽查确认新 `UndefinedName` 是假阳性：`proton facade_error.mbt:6` 的
`OperationFailed` 是 `WindowSessionError` 的构造子，全语料四处真的这么用，但它的
声明（`enum`/`suberror`/`derive`）**在分析子集之外**，body 没被分析，名字永远进不了
符号表。**根因是既有的子集边界**，本轮只是让这些文件第一次能被读。
⇒ 「读不进去」和「读进去之后报得准」是**两件事**，一次解析修复通常只买前者。
⇒ 这也说明 `enum`/`suberror`/`derive` 的构造子入符号表，比再修几条语法更值钱。

### 真实代码上的实测缺口（2026-10-06）

用本工具只读审 pyroduct 的 `audit/` 三个真实文件：**644 条发现，无一条是真缺陷**。
归一化后的分布：

| 数量 | 消息形状 | 根因 |
|---|---|---|
| 184 | only named functions can be called | 结构体字面量 `X { f: v }` |
| 124 | unexpected token | 级联 |
| 113 | undefined variable 'X' | `@别名` 引用 |
| 67 | undefined name 'X' | 类型标注（`String` / `Report` …） |
| 49 | undefined function 'X' | 内建名表过小 |

修完顶层修饰符与声明那一类后降为 **636**——修掉的是最刺眼的一类，**不是主因**。
主因全在函数体内部，需要表达式层扩容（结构体字面量、`@alias`、`match`、内建名表），
本版本**未实现**。不要把「顶层修了」读成「真实代码可用了」。

> 教训：`src/cli` 的 6 个样例是合成的，**一个 `pub` 都没有**，所以这个缺口对自测
> 完全隐形。子集声明只对着自己的样例验是不够的——**任何子集都要拿真实文件量一遍**，
> 否则测试语料会骗你。

### 0.3.5：把「看不懂」和「有问题」分开报（2026-10-06）

在 `D:\src\MiniMax\Projects\MoonBit\ML\CI`（63 个 `.mbt`）上实测，暴露了一个比
子集缺口更要紧的问题：**输出契约本身在说谎**。

| | 本工具 | 工具链 `moon check` |
|---|---|---|
| 耗时 | 48.5s | **2.3s** |
| 解析覆盖率 | 3%（2/63） | **100%** |
| 输出 | 17,937 条 | **128 条** |
| `UnusedLocal` | 529 | `unused_value` **8** |
| `Unreachable` | 35 | `unreachable_code` **7** |

那 529 条「未使用局部」里绝大部分不是真的——**`struct` / `trait` 的函数体没解析，
它们的字段被当成了未使用的局部**。编译器 2.3 秒就数清楚了 8 条，而且每条都带
`file:line:col`、源码片段和修复建议。

> **后续（0.4.5）：这一族已经报不出来了。** 上面的数字是 0.3.5 的历史记录，保留
> 不改。但「未使用局部 / 未使用参数 / 参数被改写」是关于**整个函数**的结论，
> 被前端截断的函数支撑不了它，所以现在会整函数跳过这三族审计——不再依赖位置
> 边界去挡（它们的报告位置在声明处，本来就在边界之前，挡不住）。实测
> moonbitlang/core 从 270 条 actionable 降到 147 条，本仓库从 11 条降到 0 条，
> 逐条核对确认那 11 条全是假的。
>
> **本轮：同一原则再往前推一步，270 → 49。** 「不可信所以不作结论」不只属于被截断的
> 函数帧，也属于**模块帧**：前端没读完的文件，模块帧可证不完整，那里「找不到可见
> 绑定」证明不了任何事。而 `Type::member`（`@debug.Repr::opaque_(v)`）是成员引用不是
> 绑定——这条规则字段名和方法名本来就有，解析器却没给路径名。`extern "c" fn` 原先
> 被整条跳过，名字丢了，于是 16 个文件里每个 extern 函数的调用点都报未绑定；现在按
> 声明建模，签名是真的，函数体是空的（不猜任何语义）。实测 moonbitlang/core：
> actionable **270 → 49**，`undefined name` **64 → 0**，解析 305 → **320**。
>
> **判据：「读不到」和「不存在」是两件事，而报告必须区分它们。** 任何一个以
> 「找不到」为前提的断言，都要先问：这个查找表本身是不是完整的。表不完整时，正确
> 的输出是沉默，不是发现。

> **判据：在 `.mbt` 上和 `moon check` 竞争是必输的。** 编译器有真正的解析器和
> 约 90 条内建告警，覆盖率恒为 100%。本工具唯一能说「编译器做不到」的地方是
> `.mbti` / `.mbt.md` / `.mbtp` 与跨包语义——那些面才是产品该占的地方。

0.3.5 因此改的是**输出契约，不是语法子集**：

- 解析覆盖率升为头号指标：`PARSED 23/85 files understood (27.0%)`
- 未解析文件**不再吐级联发现**，改为按原因分组计数 + 3 个示例路径
- `actionable` / `withheld` / `total` 三者在 `SUMMARY` 里对账，一个不多一个不少
- 新增 `--exclude <dir>`（可重复）：实测某棵树上 vendored 快照占 1020 文件 /
  126,687 条发现 = **88%**，而点目录规则（`.mooncakes` / `.repos`）抓不到它们

同一棵树的输出：**17,937 行 → 45 行**，且 45 行里每一行都在说人话。

⚠ **`FParse` 有两种含义，抑制只能作用于其中一种**：对 `.mbt` / `.mbt.md` 它是
「我没看懂」（工具的局限），对 `.mbti` / `.mbtp` 它是「这个文件真有缺陷」
（工具的本职：畸形行 / 重复签名 / 未知类型 / 逻辑体里的字符串常量）。
把两者一起抑制等于删掉整个产品——`.mbti` 实测 71 个真实文件零误报、4/4 缺陷抓到。

### 子集边界的实测分布，与「加跳过分支」的真实收益（2026-10-06）

`5x unexpected token` 这种归因没有用——它不说在哪、也不说什么。把两个项目的
解析错误按行列号取出来，落到具体语法上（moonbit_linalg_gpu 6 个 `.mbt`）：

| 阻塞 | 列号指向的构造 | 文件数 |
|---|---|---|
| `expected ')'` | `a : FixedArray[Double]` — 泛型索引类型标注 | 2 |
| `unexpected token` | `test "name" {` — `test` 块 | 1 |
| `unexpected token` | `let d = if a > b { … } else { … }` — `if` 当表达式 | 1 |
| `unexpected character '#'` | `#cfg(...)` / `#borrow(...)` — 属性 | 1 |
| `const declaration` | `pub const ErrLibNotLoaded : Int = -1000` | 1 |

两个完全不同的项目（ML/CI 与 linalg_gpu）头号阻塞落在同一批语法上，
**说明这是子集边界的稳定分布，不是某项目的偶发**。

本轮补了其中两项（`test` 块、属性；`const` 其实**早已**在 `skip_decl_line` 里，
我把它列成缺口是没查）。第一轮只降噪、不提升覆盖率：

| 项目 | 补之前 | 补之后 | 解析率 |
|---|---|---|---|
| moonbit_linalg_gpu | 623 withheld | **351** | 2/8 → 2/8（未变） |
| 自噬（.repos/0.3.5） | 7,374 withheld | **6,177** | 17/39 → 17/39（未变） |
| ML/CI | 17,940 withheld | **16,463** | 23/85 → 23/98（未变） |

> **「加跳过分支」只降噪，不提升覆盖率**——判据是「只要文件里出现任何一条
> FParse，整份文件就记为未解析」，而每加一个跳过分支就会多一条 FParse。

### 拆开 FParse：读不懂 vs 读得懂但不分析（0.3.6）

上一条卡住的地方是判据本身。**「本工具不认识 `test` 块」和「本工具看不懂这个
文件」是两件本质不同的事，却共用同一个 `FParse` 家族。**

做法：`ParseResult` 增加 `skips`（故意跳过项的消息清单）。跳过报告**仍然留在
`reports` 里**（打印发现的人应该看到「这个 struct 没被分析」），但 pipeline 从
计数里把它减掉，也从主导原因的统计里减掉。

> ⚠ **`core.Family` 一个字都没动。** 本可以给它加 `FSubset` 变体，但
> `src/core` 是 moon prove 的证明对象（`core_proof.mbtp` 里有
> `severity_taxonomy_holds(f : Family)` 这类全称引理）。而 `Report` 不在证明
> 范围内——所以走「额外记一份清单」这条风险低得多的路。
> （顺带查明：若真加变体，`type_error_family` 的 `_ => false` 默认臂也能兜住，
> 证明不会破。但没必要去碰它。）

实测，三个项目：

| 项目 | 拆分前 | 拆分后 | actionable |
|---|---|---|---|
| moonbit_linalg_gpu | 2/8（25.0%），actionable **0** | **4/8（50.0%）** | 0 → **9** |
| 自噬（.repos/0.3.5） | 17/39（43.5%），actionable **0** | **22/39（56.4%）** | 0 → **86** |
| ML/CI | 23/98（23.4%），actionable **0** | **31/103（30.0%）** | 0 → **113** |

**覆盖率接近翻倍，而更重要的变化是 `actionable` 从 0 变成了真数字**：
工具第一次在真实项目上给出「它读懂了、并且认为有问题」的发现。

两个实现细节，都是踩出来的：
- 主导原因必须在**减完之后重新选**。增量更新会让「跳过项比真失败更常见」的
  文件得到空原因（实测出现过 `1x unspecified`）。
- `FixedArray[Double]` 的报错是 **`expected '='`**（在 `[` 处），不是提到
  `FixedArray`。归因消息给的是位置，不是构造。

## 发布与依赖解析（工具链权威页核对，2026-10-06）

依据[使用与发布包](https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/package-manage-tour.html)
与[工作区支持](https://docs.moonbitlang.com/zh-cn/latest/toolchain/moon/workspace.html)：

- **核发布内容用 `moon package --list`**，它是工具链自己的权威清单（本项目 54 个文件）。
  之前用 zipfile 手搓解析 tarball 是多余的——`moon package --list` 更快且不会漏规则。
  确认 `.why3.conf` / `cvc5wrap.ps1` 不在包内，`.mbtp` 证明文件与各 `_test.mbt` 在包内。
- **`moon.mod` 与 `README.md` 两处的元数据都会显示在 mooncakes.io**。发布页列出的字段：
  `license`（SPDX）/ `keywords` / `repository` / `description` / `homepage`。
  ⚠️ **但 `homepage` 目前不可用**：在 `moon.mod` 里写它，工具链直接拒绝——
  `Unexpected key 'homepage' found in moon.mod.`，`moon check` 与 `moon package` 都会失败
  （实测 moon 0.1.20260920）。已发布的 0.2.1 元数据键也确认为
  `name, version, readme, repository, license, keywords, description,
  preferred_target, warn-list, checksum, created_at`——**没有** `homepage`。
  ⇒ **文档列出的字段 ≠ 工具链接受的字段**；加任何元数据键之前先 `moon check` 验一次。
- **版本必须每次推送递增**，按语义化：MAJOR = 不兼容 API 变更，MINOR = 向后兼容的
  功能新增，PATCH = 向后兼容的错误修复。本项目 0.1.2 → 0.2.0 走 MINOR 即依此条
  （新增四类文件前端是功能）；0.2.0 → 0.2.1 走 PATCH（只改随包文档）；
  **0.2.1 → 0.2.2 走 PATCH**（修围栏误判 + 删 FCheck，属修复不属新增功能）。
- **moon 实现最小版本选择（MVS）**。⇒ 下游把 pin 写死在 `@0.2.0` 就**不会**自动升到
  后续版本（0.2.1、0.2.2 …）：pyroduct 要升必须显式改 `moon.mod` 再 `moon update`，
  不能指望发布。
- **工作区**：唯一清单是 `moon.work`；`moon work init <mods…>` 建、`moon work use <mod>`
  加成员、`moon work sync` 对齐成员版本。`publish` 是**模块专属**命令，在工作区根
  不可用，须 `moon -C <member> publish`。
- **`supported_targets` 不写 = 声明支持全部后端**（模块配置页 Notes 明文）。
- **wasm 预构建是全自动的，发布方没有任何开关可拧**。`moon publish --help`（本机
  moon 0.1.20260920）**不存在** wasm / target / artifact 相关的选项；`moon.mod` 的
  全部字段里也没有产物地址项（章节清单：Name / Version / Dependency Management /
  Meta Information / `.moonignore` / Preferred Target / Supported Targets / Source
  directory / Warning List / Rule / Scripts）。构建发生在**服务端**：产物落在
  `https://download.mooncakes.io/prebuild/<author>/<module>@<ver>[/<pkg>]/<artifact>.wasm`
  并经 wasm-opt 优化。skills.mooncakes.io 的 `wasm_url` / `checksum_url` 指的就是
  它，「Download wasm」按钮可用。
- **⚠ 更正我先前发布的两条错误断言 —— 两者都是测量方法造成的，不是工具链行为**：
  1. ~~「全站 28 条 skill 的 `wasm_url` 一律 404 / wasm 预构建这条路全站不通」~~。
     **错。** `download.mooncakes.io` 对**确实存在的对象不响应 HEAD**，一律回 404；
     换成 GET 即 200。实测本模块 `@0.3.3` 的 `moonbit_static_analysis.wasm`
     GET 200 / 254566 字节 / magic `asm`，官方 `moonbitlang/office@0.2.1/office.wasm`
     GET 200 / 15958555 字节 / magic `asm`。
     **判据：「拿 HEAD 探对象存在性」在 `download.mooncakes.io` 上恒假**，404 不构成
     「东西不存在」的证据。
  2. ~~「`moonx` / `moon runwasm` 走本地编译，并不消费预构建资源」~~。**错。**
     `moonx -v` 明写
     `Using cached ~/.moon/registry/cache/assets/<author>/<module>/<ver>/<artifact>.wasm`
     并交给 `moonrun` 执行；未缓存时打印 `Downloading <url>`。缓存文件的 SHA256
     与服务端公布的 `.wasm.sha256` 逐位一致（`dd9afabf…28db7f`）。这与
     `moonbitlang/openseek` README 的自述一致：「mooncakes.io hosts a prebuilt wasm
     binary for every published version. moonx fetches and caches it」。
- **`moon runwasm` 已被工具链标记弃用**（写明 2026-09-14 后移除）**但目前仍可用**；
  官方推荐 `moonx`。

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
