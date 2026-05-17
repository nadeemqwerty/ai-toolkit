# Getting Started

## What is this?

This toolkit provides production-tested patterns for making AI coding agents **reliable**.
The core problem it solves: LLM agents are confident but often wrong, and they loop
when stuck. These skills and agents enforce evidence-based reasoning, structured workflows,
and self-healing behaviors.

---

## Prerequisites

- **GitHub Copilot CLI** (or any LLM tool that accepts system prompts)
- **PowerShell 7+** (for scripts — Windows/Mac/Linux)
- **Git** (for workspace management scripts)
- **kubectl** (for port-forward script, optional)
- **Python 3.10+** (for code-heatmap, optional)

---

## Installation

### Option 1: Copy What You Need

```bash
git clone git@github.com:nadeemqwerty/ai-toolkit.git
cd ai-toolkit

# Copy specific skills
cp -r skills/evidence-driven ~/.copilot/skills/
cp -r skills/architect-first ~/.copilot/skills/

# Copy agent
cp agents/orchestrator.md ~/.copilot/agents/my-agent.md

# Copy scripts
cp scripts/*.ps1 ~/bin/
```

### Option 2: Use as Reference

Read the skill files and adapt the patterns to your own agent setup.
The key value is in the PATTERNS, not the specific tooling.

---

## Key Concepts

### Skills vs Agents

| Concept | What it is | Analogy |
|---------|-----------|---------|
| **Agent** | Complete personality + workflow (system prompt) | A person with a job description |
| **Skill** | Reusable capability that activates on keywords | A skill that person has |

An agent can have multiple skills. Skills are composable.

### The Evidence-Driven Stack

```
┌─────────────────────────────────────┐
│     Your Agent (orchestrator.md)     │  ← Personality, permissions, workflow
├─────────────────────────────────────┤
│     evidence-driven (SKILL.md)       │  ← Anti-hallucination, always active
├─────────────────────────────────────┤
│     architect-first (SKILL.md)       │  ← Requirements before code
├─────────────────────────────────────┤
│     cross-session-planner            │  ← Memory across sessions
├─────────────────────────────────────┤
│     Your domain skills               │  ← Service-specific knowledge
└─────────────────────────────────────┘
```

### Knowledge Base

The persistent knowledge system (`~/.copilot/knowledge/`) gives agents memory:
- **rules.md** — Lessons learned (never repeat mistakes)
- **patterns.md** — Solved problems (never reinvestigate)
- **tools.md** — Available utilities (never reinvent)

---

## Recommended Setup

### Minimum (any project)
1. `evidence-driven` skill — prevents hallucination
2. `architect-first` skill — prevents coding before thinking
3. `knowledge-templates/rules.md` — accumulates lessons

### Full (large codebase / team)
1. All of the above
2. `orchestrator.md` agent — full SPARC workflow
3. `critic.md` agent — validation sub-agent
4. `cross-session-planner` — never lose context
5. `workspace-status.ps1` — multi-repo awareness
6. `AgencyWorkspace.psm1` — parallel task isolation

---

## Customization Tips

1. **Replace example content** — templates have examples; replace with YOUR domain
2. **Add your telemetry** — code-heatmap needs YOUR log tables
3. **Define your VIPs** — daily-helper needs YOUR management chain
4. **Set your repos** — workspace-status needs YOUR repo list
5. **Add your skills** — domain-specific skills on top of generic ones

---

## Troubleshooting

### Agent ignores skills
- Ensure skill file is in `~/.copilot/skills/<name>/SKILL.md`
- Check that keyword triggers match your prompts
- Some tools require explicit `--skills` flag

### Agent still hallucinates
- Ensure `evidence-driven` skill is loaded (check activation keywords)
- Add project-specific NEVER-Do rules to `rules.md`
- Use the critic agent for validation passes

### Cross-session planner finds nothing
- Ensure your session store database has checkpoints
- Check that sessions have `next_steps` in checkpoint data
- Widen the time window (default 30 days may be too narrow)
