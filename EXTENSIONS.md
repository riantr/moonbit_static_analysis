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
