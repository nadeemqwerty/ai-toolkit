# Knowledge Templates

These are starter templates for building a persistent knowledge base for your AI agent.
Copy them to `~/.copilot/knowledge/` and customize for your project.

## Files

| Template | Purpose |
|----------|---------|
| [patterns.md](patterns.md) | Problem→solution pattern library |
| [rules.md](rules.md) | Operational rules and lessons learned |
| [tools.md](tools.md) | Shared tools and scripts documentation |

## Philosophy

A persistent knowledge base gives your AI agent **long-term memory** that survives
across sessions. Instead of re-learning the same lessons, the agent reads its
knowledge files at the start of each session and applies accumulated wisdom.

### Lifecycle

1. **Session start** → Agent reads relevant knowledge files
2. **During work** → Agent checks knowledge before reinventing solutions
3. **After work** → Agent appends new learnings (never deletes)
4. **Over time** → Knowledge base grows, agent gets smarter

### Rules for Knowledge Entries

- **Always include dates** — context decay is real
- **Never delete** — mark as `[SUPERSEDED]` if outdated
- **Keep entries concise** — facts, not narratives
- **Include reproduction steps** — future-you needs exact commands
- **Append at the bottom** — chronological order

## Customization

These templates show the FORMAT. Replace the example content with your own:

- **patterns.md** — Fill with problems you've solved in YOUR system
- **rules.md** — Fill with lessons YOU'VE learned about YOUR tools
- **tools.md** — Document YOUR team's scripts and utilities
