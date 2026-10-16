# x-cmd-action/ai

> 面向 GitHub Issues 与 PR 的 AI 工具集:Issue 自动分拣、PR 代码审查、周报生成、多语言翻译等。纯 shell 实现,无 Node.js,由 GitHub 事件自动触发。

[English](./README.md)

## 这个仓库能干嘛

把 AI 接进你的 GitHub 工作流,替你在 Issues 和 PR 上干重复的活:

- **有人提了新 Issue** → 自动判断类型、优先级,贴上标签,并发一条分析评论
- **有人在评论里 @机器人** → 自动加 reaction 并回复
- **提了 PR** → 自动做 AI 代码审查(安全问题 / 风格 / 修改建议 / 摘要)
- **每周一早上** → 自动汇总上周关闭的 Issue 和合并的 PR,生成 changelog 周报
- **要维护多语言文档** → 自动翻译 Markdown(代码块不翻、URL 保留),比如 `README.md → README.cn.md`
- **要写设计文档或故障复盘** → 从 issue 讨论自动提炼出结构化的 RFC / post-mortem
- **commit 信息不规范** → 自动校验,或用 AI 按 Conventional Commits 格式生成

特点:**纯 shell 实现,无 Node.js**;由 GitHub 事件自动触发(issue 打开、PR 提交、定时任务等);每个功能是一个独立的 composite action,在 workflow 里写一行 `uses:` 就能接入。

## 怎么接入

每个功能是一个独立的 composite action,在 workflow 里用 `uses:` 引用即可:

```
x-cmd-action/ai/triage@v1
x-cmd-action/ai/reply@v1
x-cmd-action/ai/review@v1
x-cmd-action/ai/changelog@v1
x-cmd-action/ai/translate@v1
x-cmd-action/ai/spec@v1
x-cmd-action/ai/commit@v1
```

举个例子,给仓库加上「新 Issue 自动分拣」只要一个 workflow 文件:

```yaml
# .github/workflows/triage.yml
name: triage
on:
  issues:
    types: [opened]
jobs:
  triage:
    runs-on: ubuntu-latest
    permissions: { issues: write, pull-requests: write }   # PR 会话需要 pull-requests: write
    steps:
      - uses: x-cmd-action/ai/triage@v1
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}   # 也支持 DEEPSEEK / GEMINI / OPENAI 等
```

**AI token 怎么传?** 所有调用 AI 的子命令都从环境变量读 token,用 `env:` + `secrets` 传入即可。支持的 provider:

| 环境变量 | Provider |
|---|---|
| `MINIMAX_API_KEY` | MiniMax |
| `DEEPSEEK_API_KEY` | DeepSeek |
| `GEMINI_API_KEY` | Google Gemini |
| `XAI_API_KEY` | xAI(Grok) |
| `MISTRAL_API_KEY` | Mistral |
| `MOONSHOT_API_KEY` | Moonshot(Kimi) |
| `OPENAI_API_KEY` | OpenAI |

例外:`reply` 用固定文案回复时、`commit` 的 `check` 模式只做格式校验时,不需要 AI token。

七个功能一览:

| Action 引用 | 干什么用 |
|---|---|
| [`x-cmd-action/ai/triage@v1`](#aitriage--新-issue-自动分拣) | 新 Issue 自动归类:类型 + 优先级 + 标签 |
| [`x-cmd-action/ai/reply@v1`](#aireply--关键字自动反应--回复) | 提到 `@关键字` 时自动反应 + 回复 |
| [`x-cmd-action/ai/review@v1`](#aireview--pr-自动代码审查) | 对 PR diff 做 AI 代码审查(安全 + 规范 + 摘要) |
| [`x-cmd-action/ai/changelog@v1`](#aichangelog--每周自动生成-changelog) | 周报:从已关闭 Issue 与已合并 PR 自动汇总 |
| [`x-cmd-action/ai/translate@v1`](#aitranslate--markdown-自动翻译) | Markdown / 多语言文件的 AI 翻译 |
| [`x-cmd-action/ai/spec@v1`](#aispec--自动写-rfc--故障复盘) | RFC 模板自动填写 + 故障复盘自动提取 |
| [`x-cmd-action/ai/commit@v1`](#aicommit--校验--生成-conventional-commits) | Conventional Commits 规范校验 / 生成 |

## 子命令详解

每个子命令都按「有什么用 → 什么时候触发 → 怎么用」介绍,附完整 workflow 示例和全部参数。

### `ai/triage` — 新 Issue 自动分拣

**有什么用**:新 Issue 创建后,自动判断类型 / 优先级 / 所属模块,贴上标签,并可发一条带摘要的分析评论(摘要和标签二选一或都要,由 `comment` / `apply-labels` 控制)。

**什么时候触发**:`issues: opened`。也可以手动指定 `issue-number` 分拣任意 Issue。

**怎么用**:

```yaml
# .github/workflows/triage.yml
name: triage
on:
  issues:
    types: [opened]
jobs:
  triage:
    runs-on: ubuntu-latest
    permissions: { issues: write }
    steps:
      - uses: x-cmd-action/ai/triage@v1
        with:
          apply-labels: 'true'     # 'false' 则只发评论、不贴标签
          comment: 'true'          # 'false' 则不打标签时也不发评论(只贴标签)
          # issue-number: '123'    # 可选:手动指定要分拣的 Issue(默认取触发事件的 Issue)
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}
```

| Input | 默认 | 说明 |
|---|---|---|
| `apply-labels` | `true` | 自动贴建议的标签;`false` 只发评论 |
| `comment` | `true` | 是否发送分析评论;`false` 时只贴标签不发评论 |
| `issue-number` | 触发事件的 Issue | 手动指定要分拣的 Issue 编号 |

评论中的 **TL;DR** 摘要只在 AI 实际产出时显示,不会输出 `n/a` 占位。

### `ai/reply` — @关键字自动反应 + 回复

**有什么用**:有人在 Issue 或评论里提到关键字(默认 `@x`),自动加 reaction 并回复。回复可以是固定文案,也可以让 AI 根据上下文生成。适合做「机器人认领」「自动应答」。

**什么时候触发**:`issue_comment: created`(新评论)、`issues: opened`(新 Issue)。

**特点**:严格词边界匹配,`@x` 不会误触发 `@x-cmd`;同一评论上同一 reaction 只加一次,反复编辑也不会刷屏。

**注意**:如果 @ 出现在 **PR** 的评论里,reaction 和回复都是写 PR 会话,workflow 除了 `issues: write` 还要给 `pull-requests: write`,否则会报 403 `Resource not accessible by integration`。

**怎么用**:

```yaml
# .github/workflows/reply.yml
name: reply
on:
  issue_comment:
    types: [created]
  issues:
    types: [opened]
jobs:
  reply:
    runs-on: ubuntu-latest
    permissions: { issues: write }
    concurrency: { group: ai-reply, cancel-in-progress: false }   # 可选:排队执行,避免并发刷屏
    steps:
      - uses: x-cmd-action/ai/reply@v1
        with:
          keyword: '@x'           # 触发关键字(词边界匹配)
          reaction: eyes          # eyes | rocket | +1 | heart | laugh | hooray | ...
          comment: '👀 on it'     # 固定回复文案
          # use_ai: 'true'        # 改用 AI 根据上下文生成回复
          # prompt: '请用中文、口语化一点'   # 可选:给 AI 的额外要求
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}   # 仅 use_ai: 'true' 时需要
```

| Input | 默认 | 说明 |
|---|---|---|
| `keyword` | `@x` | 触发关键字,词边界匹配(`@x` 不会匹配 `@x-cmd`) |
| `reaction` | `eyes` | reaction 名(见 [GitHub API](https://docs.github.com/en/rest/reactions/reactions-about-issue-comment)) |
| `comment` | `👀 on it` | 固定回复文案(`use_ai: 'false'` 时使用) |
| `use_ai` | `false` | `true` 时由 AI 生成回复 |
| `prompt` | (空) | 给 AI 的额外要求(内联文本) |
| `prompt-file` | (空) | 给 AI 的额外要求(Markdown 文件路径;`prompt` 为空时生效) |

### `ai/review` — PR 自动代码审查

**有什么用**:PR 创建或推送新提交后,自动拉取 diff,让 AI 从安全 / 风格 / 修改建议 / 摘要几个维度审查,结果作为结构化评论发到 PR 上。超过 1500 行的 diff 自动截断,超大 PR 也能审。

**什么时候触发**:`pull_request: opened` / `synchronize`。

**怎么用**:

```yaml
# .github/workflows/review.yml
name: review
on:
  pull_request:
    types: [opened, synchronize]
jobs:
  review:
    runs-on: ubuntu-latest
    permissions: { pull-requests: write }
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: x-cmd-action/ai/review@v1
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}
```

无输入参数。

### `ai/changelog` — 每周自动生成 changelog

**有什么用**:定时汇总过去 N 天关闭的 Issue 和合并的 PR,让 AI 按 Features / Fixes / Performance / Docs / Other 分组写成 changelog。`output: file` 写入文件(随后自行提交);`output: comment` 打印到日志(可自行发到 Release / Discussion)。

**什么时候触发**:`schedule: cron`(推荐每周一),或 `workflow_dispatch` 手动触发。

**怎么用**:

```yaml
# .github/workflows/changelog.yml
name: changelog
on:
  schedule:
    - cron: '0 9 * * 1'      # 每周一 9 点(UTC)
  workflow_dispatch:
jobs:
  changelog:
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v4
      - uses: x-cmd-action/ai/changelog@v1
        with:
          days: 7                # 回顾过去几天(默认 7)
          output: file           # 'file' 写入文件 | 'comment' 输出到日志
          # file: CHANGELOG.md   # output: file 时的输出路径(默认 CHANGELOG.md)
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}
      # output: file 时,生成的文件需要自行提交:
      - run: |
          git config user.name github-actions
          git config user.email github-actions@github.com
          git add CHANGELOG.md
          git diff --cached --quiet || git commit -m "docs: update changelog"
          git push
```

| Input | 默认 | 说明 |
|---|---|---|
| `days` | `7` | 回顾过去几天的 closed Issue / merged PR |
| `output` | `comment` | `file` 写入文件 \| `comment` 输出到 stdout |
| `file` | `CHANGELOG.md` | `output: file` 时的输出路径(仓库相对路径) |

### `ai/translate` — Markdown 自动翻译

**有什么用**:把一个 Markdown 文件翻译成目标语言。AI 翻译时保留代码块、行内代码、URL 和专有名词,不乱翻。最常用于 `README.md → README.cn.md` 这类多语言文档维护。文件超过 3000 行自动截断。

**什么时候触发**:任意事件。常配合 `workflow_dispatch` 手动触发,或在源文件变更时自动跑。

**怎么用**:

```yaml
# .github/workflows/translate.yml
name: translate
on:
  workflow_dispatch:
jobs:
  translate:
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v4
      - uses: x-cmd-action/ai/translate@v1
        with:
          source: README.md       # 源文件(必填,仓库相对路径)
          target: zh              # 目标语言,ISO 639-1 代码(必填)
          # output: README.zh.md  # 可选,默认 <文件名>.<语言>.<后缀>(如 README.zh.md)
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}
      # 翻译结果写入新文件,需要自行提交:
      - run: |
          git config user.name github-actions
          git config user.email github-actions@github.com
          git add README.zh.md
          git diff --cached --quiet || git commit -m "docs: translate README to zh"
          git push
```

| Input | 默认 | 说明 |
|---|---|---|
| `source` | (必填) | 源文件路径(仓库相对路径) |
| `target` | (必填) | 目标语言 ISO 639-1 代码,如 `zh`、`ja`、`fr` |
| `output` | `<stem>.<target>.<ext>` | 输出文件路径 |

### `ai/spec` — 自动写 RFC / 故障复盘

**有什么用**:两种模式——

- `rfc`:从 feature request Issue 自动产出结构化设计文档(Summary / Motivation / Detailed Design / Alternatives / Drawbacks / Open Questions),作为评论发到 Issue 上。
- `postmortem`:从已关闭的 bug Issue(含排查过程)自动提炼复盘报告(Summary / Timeline / Root Cause / Detection / Resolution / Lessons Learned / Action Items)。

**什么时候触发**:`issues: opened`(配 `mode: rfc`)或 `issues: closed`(配 `mode: postmortem`);也可手动指定 `issue-number`。

**怎么用**:

```yaml
# .github/workflows/spec.yml
name: spec
on:
  issues:
    types: [opened, closed]
jobs:
  spec:
    runs-on: ubuntu-latest
    permissions: { issues: write }
    steps:
      - uses: x-cmd-action/ai/spec@v1
        with:
          mode: rfc                # 'rfc' 设计文档 | 'postmortem' 故障复盘
          # issue-number: '123'    # 可选:手动指定素材 Issue(默认取触发事件的 Issue)
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}
```

| Input | 默认 | 说明 |
|---|---|---|
| `mode` | (必填) | `rfc`(自动填 RFC 模板)\| `postmortem`(从已关闭 bug 提取复盘) |
| `issue-number` | 触发事件的 Issue | 手动指定素材 Issue 编号 |

### `ai/commit` — 校验 / 生成 Conventional Commits

**有什么用**:两种模式——

- `check`:校验当前分支(相对 `main`)的 commit message 是否符合 [Conventional Commits](https://www.conventionalcommits.org/) 规范。默认发现不合规就 fail;也可以让 AI 在 PR 上评论、逐条给出修改建议。
- `generate`:从当前工作区改动自动生成规范的 commit message,通过 output `commit_message` 输出,接一句 `git commit` 即可。

和 `ai/changelog` 是天生搭档:commit 历史越干净,自动生成的 changelog 越准。

**什么时候触发**:`pull_request`(check),或任意需要生成 commit message 的场景(generate)。

**怎么用**:

```yaml
# check:PR 上校验 commit message 是否规范
# .github/workflows/commit-check.yml
name: commit-check
on:
  pull_request:
jobs:
  check:
    runs-on: ubuntu-latest
    permissions: { issues: write, pull-requests: write }
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }     # check 模式需要完整的分支历史
      - uses: x-cmd-action/ai/commit@v1
        with:
          mode: check
          fail-on-invalid: 'true'    # 'false' 改为只告警、不失败
          # review_invalid: 'true'   # 不合规时让 AI 在 PR 上评论修改建议
          # pr_num: ${{ github.event.pull_request.number }}
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}   # 仅 review_invalid 时需要
```

```yaml
# generate:自动生成 commit message 并提交
- uses: x-cmd-action/ai/commit@v1
  id: ai-commit
  with:
    mode: generate
    # stage_all: 'true'          # 先 git add -A,把新文件也算进 message(默认 true)
  env:
    MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}
- name: commit with AI-generated message
  run: git commit -m "${{ steps.ai-commit.outputs.commit_message }}"
```

| Input | 默认 | 说明 |
|---|---|---|
| `mode` | (必填) | `check`(校验)\| `generate`(生成) |
| `commit_limit` | `50` | check 模式:最多校验多少条 commit |
| `fail-on-invalid` | `true` | check 模式:发现不合规时是否 fail |
| `review_invalid` | (空) | check 模式:非空则让 AI 在 PR 上评论不合规 commit + 修改建议 |
| `pr_num` | (空) | check 模式:AI 评论发到哪个 PR |
| `stage_all` | `true` | generate 模式:生成前先 `git add -A` |

**Output**:`commit_message`(generate 模式生成的 commit message;无改动时为空)

## 协议

Apache-2.0. 见 [`LICENSE`](LICENSE)。

## 相关

- [`x-cmd-action/x-cmd`](https://github.com/x-cmd-action/x-cmd) — 在 GitHub runner 上装 x-cmd。
- [`x-cmd-action/this-repo`](https://github.com/x-cmd-action/this-repo) — `actions/checkout` 的纯 shell 替代。
- [`x-cmd-action/checkout`](https://github.com/x-cmd-action/checkout) — `actions/checkout` 的纯 shell 替代。
- [`x-cmd-action/.github`](https://github.com/x-cmd-action/.github) — 组织主页 + 路线图。
