[![Lint & Validate](https://github.com/nadeemqwerty/ai-toolkit/actions/workflows/lint.yml/badge.svg)](https://github.com/nadeemqwerty/ai-toolkit/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![GitHub stars](https://img.shields.io/github/stars/nadeemqwerty/ai-toolkit?style=social)](https://github.com/nadeemqwerty/ai-toolkit)

# 🧰 AI Toolkit

A collection of **production-tested** agent skills, orchestration patterns, and utilities for building reliable AI coding agents — specifically designed for [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) and similar LLM-powered development tools.

> Built and battle-tested by an engineer running AI agents daily on large enterprise codebases.

---

## 🎯 What's Inside

| Category | Description |
|----------|-------------|
| **[agents/](agents/)** | Complete agent system prompts — orchestrator, domain expert, daily helper |
| **[skills/](skills/)** | Reusable skill definitions that enforce specific workflows |
| **[scripts/](scripts/)** | PowerShell and Bash utilities for workspace management and developer productivity |
| **[knowledge-templates/](knowledge-templates/)** | Starter templates for persistent agent knowledge bases |
| **[docs/](docs/)** | Guides for creating your own agents and skills |

---

## 🌟 Highlights

### 🛡️ Evidence-Driven Skill
The crown jewel — a skill that forces AI agents to **prove every claim with evidence**, run self-critique before delivering findings, and avoid hallucination loops. See [`skills/evidence-driven/`](skills/evidence-driven/).

### 🏗️ Orchestrator Agent
A full agent system prompt implementing the **SPARC framework** (Specification → Plan → Architecture → Execute → Verify). Includes anti-hallucination protocols, anti-loop detection, workspace overlap protection, and multi-agent delegation. See [`agents/orchestrator.md`](agents/orchestrator.md).

### 🧠 Architect-First Workflow
Prevents the #1 AI failure mode: **coding before thinking**. Enforces requirements → architecture → POC → implementation → documentation. See [`skills/architect-first/`](skills/architect-first/).

### 📋 Cross-Session Planner
Harvests pending tasks across ALL past sessions, deduplicates, clusters by project, scores priority, and produces an actionable backlog. Never lose context between sessions. See [`skills/cross-session-planner/`](skills/cross-session-planner/).

### 🔥 Code Heatmap
Combines static code graphs with production telemetry to classify every class/method as hot, cold, or dead. Evidence-based dead code detection. See [`skills/code-heatmap/`](skills/code-heatmap/).

---

## 🚀 Quick Start

### Using with GitHub Copilot CLI

1. **Install Copilot CLI** (requires GitHub Copilot subscription)
2. **Copy agents** to `~/.copilot/agents/`:
   ```bash
   cp agents/orchestrator.md ~/.copilot/agents/my-agent.md
   ```
3. **Copy skills** to `~/.copilot/skills/`:
   ```bash
   cp -r skills/evidence-driven ~/.copilot/skills/
   cp -r skills/architect-first ~/.copilot/skills/
   ```
4. **Launch** your agent:
   ```bash
   copilot-cli --agent my-agent
   ```

### Using with other LLM tools

The agent prompts and skill definitions are plain Markdown. They work with any LLM that supports system prompts:
- Claude (Anthropic)
- GPT (OpenAI)
- Gemini (Google)
- Any tool supporting `.md` system prompts

---

## 📁 Structure

```
ai-toolkit/
├── README.md
├── agents/
│   ├── README.md                    # Guide to agent system prompts
│   ├── orchestrator.md              # Full orchestrator with SPARC framework
│   ├── domain-expert-example.md     # Example: domain-specific agent
│   └── daily-helper.md              # Daily work-life dashboard agent
├── skills/
│   ├── evidence-driven/SKILL.md     # Anti-hallucination + evidence critique
│   ├── architect-first/SKILL.md     # Requirements-first workflow
│   ├── cross-session-planner/SKILL.md  # Cross-session backlog
│   ├── code-heatmap/                # Runtime heat analysis
│   │   ├── SKILL.md
│   │   └── heatmap.py
│   ├── flow-discovery/SKILL.md      # API flow tracing
│   └── agent-output-contract/SKILL.md  # Orchestration output contract
├── scripts/
│   ├── workspace-status.ps1         # Multi-repo workspace dashboard (PowerShell)
│   ├── workspace-status.sh          # Multi-repo workspace dashboard (Bash)
│   ├── switch-java.ps1              # JDK version switcher (PowerShell)
│   ├── switch-java.sh               # JDK version switcher (Bash)
│   ├── Start-PortForward.ps1        # Auto-reconnecting kubectl port-forward (PowerShell)
│   ├── start-port-forward.sh        # Auto-reconnecting kubectl port-forward (Bash)
│   ├── AgencyWorkspace.psm1         # Git worktree isolation for parallel tasks (PowerShell)
│   └── agency-workspace.sh          # Git worktree isolation for parallel tasks (Bash)
├── knowledge-templates/
│   ├── patterns.md                  # Problem→solution pattern library
│   ├── rules.md                     # Operational rules template
│   └── tools.md                     # Shared tools documentation
└── docs/
    ├── getting-started.md           # Setup guide
    └── creating-skills.md           # How to write your own skills
```

---

## 🧩 Philosophy

These tools are built on hard-learned principles from running AI agents on production codebases:

1. **Evidence over assertion** — Never let the AI claim something without proof
2. **Think before coding** — Architecture and requirements BEFORE implementation
3. **Anti-loop** — Detect when the AI is stuck and force a pivot
4. **Persistent memory** — Knowledge that survives across sessions
5. **Workspace safety** — Protect against concurrent modifications
6. **Delegation** — Use specialist sub-agents for specialist work

---

## 🖥️ Scripts Compatibility

| Script | PowerShell | Bash | Dependencies |
|--------|:----------:|:----:|-------------|
| workspace-status | ✅ | ✅ | git |
| switch-java | ✅ | ⚠️ `source` required | JDK installations |
| port-forward | ✅ | ✅ | kubectl |
| agency-workspace | ✅ | ✅ | git, jq |
| code-heatmap | — | — | Python 3.8+, az CLI, curl |

### Prerequisites

- **Git** — for workspace scripts
- **kubectl** — for port-forward scripts
- **jq** — for agency-workspace (bash version)
- **Python 3.8+** — for code-heatmap
- **Azure CLI (`az`)** — for Kusto authentication in code-heatmap
- **JDK installations** — for switch-java (configure paths in script)

---

## 🤝 Contributing

Contributions welcome! If you've developed skills, agents, or patterns that make AI coding assistants more reliable, please open a PR.

---

## 📜 License

MIT — use freely, attribution appreciated.
