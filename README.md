# x-cmd-action/ai

> AI toolkit for GitHub Issues & PRs — auto-triage issues, AI code review, weekly changelogs, i18n translation, and more. Pure shell, no Node.js, triggered by GitHub events.

[中文文档](./README.cn.md)

## What it does

Brings AI into your GitHub workflow and automates the repetitive work around Issues and PRs:

- **New issue opened** → auto-classifies type & priority, applies labels, posts an analysis comment
- **Someone @mentions the bot** → auto-reacts and replies
- **PR opened** → auto AI code review (security / style / suggestions / summary)
- **Every Monday morning** → auto-generates a weekly changelog from closed issues + merged PRs
- **Need docs in multiple languages** → auto-translates Markdown (code blocks untouched, URLs preserved), e.g. `README.md → README.cn.md`
- **Need an RFC or post-mortem** → auto-extracts a structured document from issue discussion
- **Messy commit messages** → auto-validates or generates Conventional Commits messages

Highlights: **pure shell, no Node.js**; triggered by GitHub events (issue opened, PR synced, schedule, etc.); each feature is a standalone composite action you can adopt with a single `uses:` line.

## How to use

Each feature is a standalone composite action — just reference it with `uses:` in a workflow:

```
x-cmd-action/ai/triage@v1
x-cmd-action/ai/reply@v1
x-cmd-action/ai/review@v1
x-cmd-action/ai/changelog@v1
x-cmd-action/ai/translate@v1
x-cmd-action/ai/spec@v1
x-cmd-action/ai/commit@v1
```

For example, adding "auto-triage new issues" to a repo takes one workflow file:

```yaml
# .github/workflows/triage.yml
name: triage
on:
  issues:
    types: [opened]
jobs:
  triage:
    runs-on: ubuntu-latest
    permissions: { issues: write, pull-requests: write }   # PR conversations need pull-requests: write
    steps:
      - uses: x-cmd-action/ai/triage@v1
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}   # DEEPSEEK / GEMINI / OPENAI also supported
```

**How to pass the AI token?** Every AI-calling sub-command reads its token from an environment variable — pass it via `env:` + `secrets`. Supported providers:

| Env var | Provider |
|---|---|
| `MINIMAX_API_KEY` | MiniMax |
| `DEEPSEEK_API_KEY` | DeepSeek |
| `GEMINI_API_KEY` | Google Gemini |
| `XAI_API_KEY` | xAI (Grok) |
| `MISTRAL_API_KEY` | Mistral |
| `MOONSHOT_API_KEY` | Moonshot (Kimi) |
| `OPENAI_API_KEY` | OpenAI |

Exceptions: `reply` with a static comment and `commit` in `check` mode (format validation only) don't need an AI token.

Feature overview:

| Action reference | What it's for |
|---|---|
| [`x-cmd-action/ai/triage@v1`](#aitriage--auto-triage-new-issues) | Auto-classify new issues: type + priority + labels |
| [`x-cmd-action/ai/reply@v1`](#aireply--react--reply-on-keyword) | React + reply when `@keyword` is mentioned |
| [`x-cmd-action/ai/review@v1`](#aireview--auto-pr-code-review) | AI code review on PR diff (security + style + summary) |
| [`x-cmd-action/ai/changelog@v1`](#aichangelog--weekly-changelog-generator) | Weekly changelog from closed issues + merged PRs |
| [`x-cmd-action/ai/translate@v1`](#aitranslate--auto-translate-markdown) | AI translation for Markdown / locale files |
| [`x-cmd-action/ai/spec@v1`](#aispec--auto-rfc--post-mortem) | RFC template fill-in + post-mortem extraction |
| [`x-cmd-action/ai/commit@v1`](#aicommit--check--generate-conventional-commits) | Conventional Commits check / generate |

## Sub-command details

Each sub-command is documented as **what it's for → when it triggers → how to use it**, with a complete workflow example and all inputs.

### `ai/triage` — auto-triage new issues

**What it's for**: when a new issue is created, it auto-classifies type / priority / area and applies labels, optionally posting a summary comment — mix and match via `comment` / `apply-labels`.

**When it triggers**: `issues: opened`. You can also triage any issue manually via `issue-number`.

**How to use it**:

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
          apply-labels: 'true'     # 'false' to comment only, without labels
          comment: 'true'          # 'false' to apply labels without posting a comment
          # issue-number: '123'    # optional: triage a specific issue (default: the one that triggered)
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}
```

| Input | Default | Description |
|---|---|---|
| `apply-labels` | `true` | Apply suggested labels; `false` to comment only |
| `comment` | `true` | Post the summary comment; `false` to apply labels silently |
| `issue-number` | the triggering issue | Triage a specific issue number |

The **TL;DR** line only appears when the AI actually produced a summary — no `n/a` placeholder.

### `ai/reply` — react + reply on keyword

**What it's for**: when someone mentions a keyword (default `@x`) in an issue or comment, it auto-adds a reaction and posts a reply. The reply can be a static comment or AI-generated from the context. Good for "bot ack" and auto-responder scenarios.

**When it triggers**: `issue_comment: created` (new comment) and `issues: opened` (new issue).

**Notes**: strict word-boundary matching (`@x` won't trigger on `@x-cmd`); the same reaction is added only once per comment, so re-edits don't spam.

**Note:** when the `@` mention happens on a **pull request**, both the reaction and the reply write to the PR conversation — the workflow needs `pull-requests: write` in addition to `issues: write`, or every write fails with 403 `Resource not accessible by integration`.

**How to use it**:

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
    concurrency: { group: ai-reply, cancel-in-progress: false }   # optional: queue runs to avoid spam
    steps:
      - uses: x-cmd-action/ai/reply@v1
        with:
          keyword: '@x'           # trigger keyword (word-boundary matched)
          reaction: eyes          # eyes | rocket | +1 | heart | laugh | hooray | ...
          comment: '👀 on it'     # static reply body
          # use_ai: 'true'        # let AI generate the reply from context instead
          # prompt: 'Reply in casual Chinese'   # optional: extra guidance for the AI
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}   # only needed with use_ai: 'true'
```

| Input | Default | Description |
|---|---|---|
| `keyword` | `@x` | Trigger keyword, word-boundary matched (`@x` won't match `@x-cmd`) |
| `reaction` | `eyes` | Reaction name (see [GitHub API](https://docs.github.com/en/rest/reactions/reactions-about-issue-comment)) |
| `comment` | `👀 on it` | Static reply body (used when `use_ai: 'false'`) |
| `use_ai` | `false` | `true` to generate the reply with AI |
| `prompt` | (empty) | Extra guidance for the AI (inline text) |
| `prompt-file` | (empty) | Extra guidance for the AI (markdown file path; used when `prompt` is empty) |

### `ai/review` — auto PR code review

**What it's for**: when a PR is opened or updated, it fetches the diff and asks the AI to review it across security / style / suggestions / summary, posted as a structured comment. Diffs over 1500 lines are truncated so even huge PRs get reviewed.

**When it triggers**: `pull_request: opened` / `synchronize`.

**How to use it**:

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

No inputs.

### `ai/changelog` — weekly changelog generator

**What it's for**: on a schedule, it collects issues closed and PRs merged in the last N days, and asks the AI to group them into Features / Fixes / Performance / Docs / Other as a changelog. `output: file` writes it to a file (commit it yourself); `output: comment` prints it to the log (post it to a Release / Discussion yourself).

**When it triggers**: `schedule: cron` (weekly recommended), or `workflow_dispatch` for manual runs.

**How to use it**:

```yaml
# .github/workflows/changelog.yml
name: changelog
on:
  schedule:
    - cron: '0 9 * * 1'      # Monday 9am UTC
  workflow_dispatch:
jobs:
  changelog:
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v4
      - uses: x-cmd-action/ai/changelog@v1
        with:
          days: 7                # look back N days (default 7)
          output: file           # 'file' to write a file | 'comment' to print to the log
          # file: CHANGELOG.md   # output path when output=file (default CHANGELOG.md)
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}
      # with output: file, commit the result yourself:
      - run: |
          git config user.name github-actions
          git config user.email github-actions@github.com
          git add CHANGELOG.md
          git diff --cached --quiet || git commit -m "docs: update changelog"
          git push
```

| Input | Default | Description |
|---|---|---|
| `days` | `7` | Look back N days for closed issues / merged PRs |
| `output` | `comment` | `file` to write a file \| `comment` to print to stdout |
| `file` | `CHANGELOG.md` | Output path when `output: file` (repo-relative) |

### `ai/translate` — auto-translate Markdown

**What it's for**: translates a Markdown file into a target language. Code blocks, inline code, URLs, and proper nouns are preserved. Most often used for `README.md → README.cn.md`-style multi-language doc maintenance. Files over 3000 lines are truncated.

**When it triggers**: any event — commonly `workflow_dispatch` (manual) or on changes to the source file.

**How to use it**:

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
          source: README.md       # source file (required, repo-relative path)
          target: zh              # target language, ISO 639-1 code (required)
          # output: README.zh.md  # optional, default <stem>.<target>.<ext> (e.g. README.zh.md)
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}
      # the translation is written to a new file — commit it yourself:
      - run: |
          git config user.name github-actions
          git config user.email github-actions@github.com
          git add README.zh.md
          git diff --cached --quiet || git commit -m "docs: translate README to zh"
          git push
```

| Input | Default | Description |
|---|---|---|
| `source` | (required) | Source file path (repo-relative) |
| `target` | (required) | Target language ISO 639-1 code, e.g. `zh`, `ja`, `fr` |
| `output` | `<stem>.<target>.<ext>` | Output file path |

### `ai/spec` — auto RFC & post-mortem

**What it's for**: two modes —

- `rfc`: turns a feature request issue into a structured design doc (Summary / Motivation / Detailed Design / Alternatives / Drawbacks / Open Questions), posted as a comment on the issue.
- `postmortem`: extracts a structured post-mortem from a closed bug issue (including the debugging discussion): Summary / Timeline / Root Cause / Detection / Resolution / Lessons Learned / Action Items.

**When it triggers**: `issues: opened` (with `mode: rfc`) or `issues: closed` (with `mode: postmortem`); you can also point `issue-number` at any issue.

**How to use it**:

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
          mode: rfc                # 'rfc' design doc | 'postmortem' incident review
          # issue-number: '123'    # optional: source issue (default: the one that triggered)
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}
```

| Input | Default | Description |
|---|---|---|
| `mode` | (required) | `rfc` (auto-fill RFC template) \| `postmortem` (extract from a closed bug) |
| `issue-number` | the triggering issue | Source issue number |

### `ai/commit` — check & generate Conventional Commits

**What it's for**: two modes —

- `check`: validates that commits on the current branch (vs `main`) follow [Conventional Commits](https://www.conventionalcommits.org/). Fails the workflow by default on invalid commits; optionally lets the AI post a PR comment with suggested rewrites.
- `generate`: writes a Conventional Commits message from the current working-tree changes, exported as the `commit_message` output — add one `git commit` step and you're done.

Pairs naturally with `ai/changelog` — the cleaner the commit history, the better the auto-generated changelog.

**When it triggers**: `pull_request` (check), or any step where you need a commit message (generate).

**How to use it**:

```yaml
# check: validate commit messages on a PR
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
        with: { fetch-depth: 0 }     # check mode needs the full branch history
      - uses: x-cmd-action/ai/commit@v1
        with:
          mode: check
          fail-on-invalid: 'true'    # 'false' to warn instead of failing
          # review_invalid: 'true'   # let the AI comment suggested rewrites on the PR
          # pr_num: ${{ github.event.pull_request.number }}
        env:
          MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}   # only needed with review_invalid
```

```yaml
# generate: write a commit message and commit
- uses: x-cmd-action/ai/commit@v1
  id: ai-commit
  with:
    mode: generate
    # stage_all: 'true'          # git add -A first so new files are included (default true)
  env:
    MINIMAX_API_KEY: ${{ secrets.MINIMAX_API_KEY }}
- name: commit with AI-generated message
  run: git commit -m "${{ steps.ai-commit.outputs.commit_message }}"
```

| Input | Default | Description |
|---|---|---|
| `mode` | (required) | `check` (validate) \| `generate` (write a message) |
| `commit_limit` | `50` | check mode: max commits to validate |
| `fail-on-invalid` | `true` | check mode: fail the step when invalid commits are found |
| `review_invalid` | (empty) | check mode: non-empty lets the AI comment invalid commits + suggested rewrites on the PR |
| `pr_num` | (empty) | check mode: PR number the AI comment is posted to |
| `stage_all` | `true` | generate mode: run `git add -A` before generating |

**Output**: `commit_message` (the generated commit message in generate mode; empty when there are no changes)

## License

Apache-2.0. See [`LICENSE`](LICENSE).

## Related

- [`x-cmd-action/x-cmd`](https://github.com/x-cmd-action/x-cmd) — install x-cmd on a GitHub runner.
- [`x-cmd-action/this-repo`](https://github.com/x-cmd-action/this-repo) — pure-shell `actions/checkout` alternative.
- [`x-cmd-action/checkout`](https://github.com/x-cmd-action/checkout) — pure-shell `actions/checkout` alternative.
- [`x-cmd-action/.github`](https://github.com/x-cmd-action/.github) — org profile + roadmap.
