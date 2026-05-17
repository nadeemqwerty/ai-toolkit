# Contributing to AI Toolkit

Thanks for your interest in contributing! Here's how to get started.

## What We're Looking For

- **New skills** — Reusable workflow definitions that make AI agents more reliable
- **Agent templates** — System prompts for specific use cases
- **Scripts** — Developer productivity utilities (prefer cross-platform)
- **Knowledge templates** — Starter templates for persistent agent knowledge

## Guidelines

1. **No internal/proprietary data** — All contributions must be generic and free of company-specific references
2. **Cross-platform** — Provide both PowerShell and Bash versions of scripts where possible
3. **Documentation** — Include clear usage instructions and examples
4. **Evidence-based** — Skills should enforce verification, not blind trust

## Sanitization Checklist

Before submitting, verify your contribution does NOT contain:
- [ ] Internal URLs, clusters, or endpoints
- [ ] Company/team names or employee aliases
- [ ] Subscription IDs, tenant IDs, or resource group names
- [ ] Internal repo or service names
- [ ] Kubernetes contexts, namespaces, or pod names specific to internal infra
- [ ] Kusto table/database names from internal telemetry
- [ ] API keys, tokens, or credentials

## Submitting

1. Fork this repository
2. Create a feature branch
3. Make your changes
4. Run the sanitization checklist above
5. Open a Pull Request with a clear description

## Code Style

- **Markdown skills**: Follow the format in `skills/evidence-driven/SKILL.md`
- **Scripts**: Include header comments with synopsis, usage, and examples
- **Python**: Use type hints, docstrings, and `argparse` for CLI tools

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
