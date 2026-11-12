# short-context-agent

An open reproduction of **"You Don't Need Long Context"** (Belcak et al., NVIDIA, 2026 — [arXiv:2611.05306](https://arxiv.org/abs/2611.05306)), packaged as a Claude skill plus a reference agent harness.

The paper's claim: an agent working in a sequential loop never needs its whole conversation, nor a whole document, in its context window. It needs (1) a compact, forward-looking description of where it stands and (2) a tool to fetch raw data on demand. With both, task accuracy holds flat or improves while peak live context drops by an order of magnitude — and decode throughput on your own hardware goes up 3–7x.

This repository is not affiliated with NVIDIA or the paper's authors.

## What is reproduced

| In the paper | Here |
|---|---|
| Selective reading of long inputs (LCW2): sources stay on disk, located with `grep`, read through a bounded `doc-read` window (6K chars default, 8K hard cap) | [`scripts/doc-read`](skills/short-context-agent/scripts/doc-read) and protocol A in [`SKILL.md`](skills/short-context-agent/SKILL.md) |
| The six-part forward-looking handoff brief that replaces generic summarisation (compaction prompt, Appendix G.1) | [`references/handoff-brief.md`](skills/short-context-agent/references/handoff-brief.md), [`references/compaction-prompt.md`](skills/short-context-agent/references/compaction-prompt.md) |
| End-of-Conversation Compaction (EoCC) and Single-Action Compaction (SAC) on a minimal one-bash-command-per-turn ReAct loop | [`scripts/sac_harness.py`](skills/short-context-agent/scripts/sac_harness.py) — `fha` / `eocc` / `sac` regimes, `limit/threshold` settings |
| Full history logged to disk for exact recall | `--log` in the harness; [`scripts/backup_transcript.py`](skills/short-context-agent/scripts/backup_transcript.py) for Claude Code |
| Thresholds and their failure modes (16K/12K collapses verbose models) | Table in [`references/compaction-prompt.md`](skills/short-context-agent/references/compaction-prompt.md) |

Two things the paper leaves implicit are made explicit here: the *resume* protocol (what a fresh instance does with a brief: trust verified facts, re-check hypotheses, skip dead ends, start at plan step 1), and the *event-based checkpointing* an agent needs when it cannot see its own token count, as in Claude Code.

## Status

**Method reproduction, not (yet) results reproduction.** The regimes, compaction prompt, tool and thresholds follow the paper; the benchmark numbers (SWE-bench Verified, Terminal-Bench 2.1, LongBench v2, RULER, …) have not been re-run with this code. The harness is dry-run tested and the hooks are tested against the documented hook contract (`tests/smoke.sh`). See [Roadmap](#roadmap).

## Layout

The repository is a Claude Code and Codex plugin that is also its own
marketplace; the skill inside it is a plain
[Agent Skill](https://agentskills.io) folder, so it also works anywhere a
`SKILL.md` does.

```
short-context-agent/
├── .claude-plugin/
│   ├── plugin.json                  plugin manifest (name, version, metadata)
│   └── marketplace.json             one-entry marketplace pointing at this repo (source "./")
├── .codex-plugin/
│   ├── plugin.json                  Codex manifest: skill path and hook path
│   └── hooks.json                   Codex SessionStart hook definition
├── hooks/hooks.json                 SessionStart hook: re-inject the brief after /compact or /clear
├── skills/short-context-agent/      the skill
│   ├── SKILL.md                     selective reading, handoff brief, resume protocol
│   ├── references/
│   │   ├── handoff-brief.md         six-part template, worked example, rules per section
│   │   ├── compaction-prompt.md     harness-ready compaction prompt, /compact text, regimes, thresholds
│   │   └── claude-code-setup.md     manual hook config, /compact vs /clear, cost caveats
│   ├── scripts/
│   │   ├── doc-read                 bounded window reader (--lines, --around, --chars, --grep, --head)
│   │   ├── inject_brief.py          SessionStart hook script
│   │   ├── backup_transcript.py     optional PreCompact hook: copies the transcript to disk
│   │   └── sac_harness.py           reference FHA / EoCC / SAC loop with one bash tool
│   └── evals/                       three test cases in `claude plugin eval` layout
├── tests/smoke.sh                   offline checks for manifests, scripts, hooks and fixtures (CI runs this)
└── .github/workflows/               ci.yml (smoke tests), release.yml (builds the .skill and plugin zip on tags)
```

## Install

Pick your agent: [Claude Code](#claude-code) · [Codex](#codex) · [Gemini CLI](#gemini-cli) · [Qwen Code](#qwen-code) · [Pi](#pi) · [OpenCode](#opencode) · [Copilot CLI](#copilot-cli) · [Kiro](#kiro) · [VS Code](#vs-code) · [ZCode](#zcode)

Open its block and copy its install command. Every block also contains update,
check and remove commands.

There are two installation levels:

- **Full plugin** — Claude Code and Codex install the skill plus the packaged
  `SessionStart` hook that restores `.claude/handoff.md` after a context reset.
- **Skill only** — the other agents install the portable `SKILL.md` bundle with
  the third-party [`skills`](https://github.com/vercel-labs/skills) CLI. The
  agent still writes and reads handoff briefs, but automatic hook injection is
  unavailable.

Full plugin installs require Python 3 for the hook. Skill-only installs require
Node.js/npm for `npx` and Git for fetching the repository. Add `-p` instead of
`-g` to the `skills` commands if you want a project-local installation.

### Claude Code

```bash
# install
claude plugin marketplace add nnnet/short-context-agent
claude plugin install short-context-agent@short-context-agent
# update
claude plugin update short-context-agent@short-context-agent
# check
claude plugin list
# remove
claude plugin uninstall short-context-agent@short-context-agent
claude plugin marketplace remove short-context-agent
```

Hooks ✓ (package) · Skills ✓

### Codex

```bash
# install
codex plugin marketplace add nnnet/short-context-agent --ref main
codex plugin add short-context-agent@short-context-agent
# one-time step: restart Codex, review the packaged hook and trust it
# update
codex plugin marketplace upgrade short-context-agent
# check
codex plugin list
# remove
codex plugin remove short-context-agent@short-context-agent
codex plugin marketplace remove short-context-agent
```

Hooks ✓ (package; explicit trust required) · Skills ✓

Codex does not execute newly installed non-managed hooks until you review and
trust their current definition. The packaged hook only runs
`skills/short-context-agent/scripts/inject_brief.py`; without a fresh
`.claude/handoff.md` it exits without output. The repository acceptance suite
installs the plugin into an isolated Codex configuration, checks both packaged
components, executes the hook against a handoff brief, and removes the plugin.

### Gemini CLI

```bash
# install
npx skills add nnnet/short-context-agent --skill short-context-agent -g -a gemini-cli -y
# update
npx skills update short-context-agent -g -y
# check
npx skills list -g -a gemini-cli
# remove
npx skills remove short-context-agent -g -a gemini-cli -y
```

Hooks — · Skills ✓

### Qwen Code

```bash
# install
npx skills add nnnet/short-context-agent --skill short-context-agent -g -a qwen-code -y
# update
npx skills update short-context-agent -g -y
# check
npx skills list -g -a qwen-code
# remove
npx skills remove short-context-agent -g -a qwen-code -y
```

Hooks — · Skills ✓

### Pi

```bash
# install
npx skills add nnnet/short-context-agent --skill short-context-agent -g -a pi -y
# update
npx skills update short-context-agent -g -y
# check
npx skills list -g -a pi
# remove
npx skills remove short-context-agent -g -a pi -y
```

Hooks — · Skills ✓

### OpenCode

```bash
# install
npx skills add nnnet/short-context-agent --skill short-context-agent -g -a opencode -y
# update
npx skills update short-context-agent -g -y
# check
npx skills list -g -a opencode
# remove
npx skills remove short-context-agent -g -a opencode -y
```

Hooks — · Skills ✓

### Copilot CLI

```bash
# install
npx skills add nnnet/short-context-agent --skill short-context-agent -g -a github-copilot -y
# update
npx skills update short-context-agent -g -y
# check
npx skills list -g -a github-copilot
# remove
npx skills remove short-context-agent -g -a github-copilot -y
```

Hooks — · Skills ✓

### Kiro

```bash
# install
npx skills add nnnet/short-context-agent --skill short-context-agent -g -a kiro-cli -y
# update
npx skills update short-context-agent -g -y
# check
npx skills list -g -a kiro-cli
# remove
npx skills remove short-context-agent -g -a kiro-cli -y
```

Hooks — · Skills ✓

Kiro's default agent loads the skill automatically. A custom Kiro agent must
include `skill://.kiro/skills/**/SKILL.md` in its `resources` array.

### VS Code

VS Code uses the GitHub Copilot skill location, so its lifecycle commands use
the `github-copilot` agent target too.

```bash
# install
npx skills add nnnet/short-context-agent --skill short-context-agent -g -a github-copilot -y
# update
npx skills update short-context-agent -g -y
# check
npx skills list -g -a github-copilot
# remove
npx skills remove short-context-agent -g -a github-copilot -y
```

Hooks — · Skills ✓

### ZCode

```bash
# install
npx skills add nnnet/short-context-agent --skill short-context-agent -g -a zcode -y
# update
npx skills update short-context-agent -g -y
# check
npx skills list -g -a zcode
# remove
npx skills remove short-context-agent -g -a zcode -y
```

Hooks — · Skills ✓

Claude apps can instead download `short-context-agent.skill` from the
[Releases](https://github.com/nnnet/short-context-agent/releases) page and add
it as a custom skill. App-managed skills do not include hooks.

### Using it

On long tasks the agent writes `.claude/handoff.md` at milestones (add it to `.gitignore`). Run `/compact` with the instruction text from `references/compaction-prompt.md`, or `/clear` for a true reset in the paper's sense; the hook puts the brief back and the agent resumes from it. `PreCompact` cannot rewrite the built-in summary, which is why the brief lives on disk and is re-injected afterwards.

## Run the reference harness

```bash
pip install anthropic
export ANTHROPIC_API_KEY=...

# EoCC at the paper's 24K/18K setting, every discarded conversation logged
python3 skills/short-context-agent/scripts/sac_harness.py --task "Fix the failing test in tests/" --workdir ./repo \
    --mode eocc --limit 24000 --threshold 18000 --log runs/eocc.jsonl --verbose

# SAC: compaction after every single action
python3 skills/short-context-agent/scripts/sac_harness.py --task "..." --workdir ./repo --mode sac

# No API key: scripted fake model exercises all three regimes
python3 skills/short-context-agent/scripts/sac_harness.py --task "dry run" --workdir /tmp/wd --mode eocc --dry-run
```

The model runs arbitrary shell commands in `--workdir`; run it inside a container. Output is a JSON summary with steps, actions, compactions, peak live context and token totals.

## Evals

`skills/short-context-agent/evals/` holds three cases in the layout `claude plugin eval` reads (Claude Code ≥ 2.1.269). From the skill directory:

```bash
cd skills/short-context-agent && claude plugin eval . --allow-tools Write,Edit,Bash --scaffold
```

Offline checks (manifests, scripts, hooks, fixtures) run with `bash tests/smoke.sh`; CI runs them on every push.

- `selective-read-large-doc` — a 775 KB grammar with one needle; the agent must `grep` and read a window, never the whole file (the paper's LongBench v2 Kalamang example).
- `writes-handoff-brief-mid-task` — a timezone regression in a small repo; the brief must be written before the full suite runs and follow the six-part format.
- `resume-from-handoff-brief` — the same repo plus a brief; the agent must start at plan step 1 and not retry the listed dead ends.

These are real, billed model runs.

## Caveats the paper is explicit about

- Compaction is lossy by construction. Exact recall of arbitrary history needs the full log on disk, read selectively; multi-document synthesis (FRAMES) loses 1–4 ppts at every threshold.
- Every reset discards the prompt cache. Under flat API pricing the paper's nominal bills went *up* (e.g. SWE-bench Verified $168 → $203 at 16K/12K); the gains are accuracy on long tasks and bounded memory on your own hardware.
- Weaker or verbose models need more room: at 16K/12K one open-weight model fell from 53.0% to 3.6% because its traces exhausted the budget before any progress. Raise the threshold before blaming the regime.

## Roadmap

1. Re-run SWE-bench Verified and Terminal-Bench 2.1 subsets through `sac_harness.py` under FHA / EoCC / SAC and publish the numbers next to the paper's.
2. OpenAI-compatible endpoint support in the harness (vLLM) to reproduce the open-weight results and the decode-throughput measurements.
3. A Semantic State Space Model experiment: post-train a small model on (state, action, observation) → state transitions and compare with the frontier models under SAC.

Contributions welcome, especially benchmark runs.

## Citing

If you build on this, cite the paper first:

```bibtex
@article{belcak2026youdontneed,
  title   = {You Don't Need Long Context},
  author  = {Belcak, Peter and Muralidharan, Saurav and Jiang, Jindong and Fu, Yonggan and
             Byeon, Wonmin and Ye, Hanrong and Angilly, Ryan and Taghibakhshi, Ali and
             Liu, Shih-Yang and Ouyang, Siru and Heinrich, Greg and Molchanov, Pavlo},
  journal = {arXiv preprint arXiv:2611.05306},
  year    = {2026}
}
```

The repository itself can be cited via [`CITATION.cff`](CITATION.cff).

## License

[MIT](LICENSE).
