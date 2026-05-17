# Agents

This directory contains complete agent system prompts — ready to use with GitHub Copilot CLI
or any LLM tool that accepts system prompts.

## Available Agents

| Agent | Purpose | Complexity |
|-------|---------|-----------|
| [orchestrator.md](orchestrator.md) | Full SPARC-based orchestrator with anti-hallucination, evidence protocols, sub-agent delegation | Advanced |
| [critic.md](critic.md) | Evidence-validation sub-agent for critiquing findings before delivery | Intermediate |
| [domain-expert-example.md](domain-expert-example.md) | Example of a domain-specific agent (real estate) | Simple |
| [daily-helper.md](daily-helper.md) | Daily work-life dashboard pulling from multiple data sources | Intermediate |

## How to Use

### With GitHub Copilot CLI
```bash
# Copy to agents directory
cp orchestrator.md ~/.copilot/agents/my-orchestrator.md

# Launch (method depends on your setup)
copilot-cli --agent my-orchestrator
```

### With Claude/GPT APIs
Use the content of these `.md` files as your system prompt.

### With any LLM tool
These are plain Markdown files describing behavior. Paste into system prompt field.

## Creating Your Own Agent

See [docs/creating-skills.md](../docs/creating-skills.md) for the full guide.

Key principles:
1. **Be specific** — vague instructions produce vague behavior
2. **Include examples** — show the agent what good output looks like
3. **Set boundaries** — define what the agent should NOT do
4. **Layer skills** — use skills for reusable capabilities, agents for personality + workflow
