---
name: daily-helper
description: >
  On-demand daily work-life assistant. Surfaces emails, meetings, PRs, tasks,
  and notifications in a single brief. Demonstrates how to build a multi-source
  aggregation agent that pulls from various APIs and presents a unified dashboard.
---

# Daily Helper Agent

> An on-demand work-life dashboard that aggregates information from multiple sources
> into a single actionable brief.

---

## 🎯 CONCEPT

This agent pulls data from multiple work tools (email, calendar, code review, task boards,
messaging) and presents a prioritized, actionable summary. It's designed to answer:
"What do I need to focus on right now?"

---

## 📦 MODULES

### Module 1: Communications
- **Emails needing reply** — from real humans (not automated), where you were asked a question
- **Unread email summary** — grouped by: action-required vs FYI vs automated noise
- **Team mentions** — unresponded @mentions in chat
- **VIP detection** — emails from management chain get top priority

**Key rules:**
- `isRead` does NOT mean "replied" — focus on whether you've RESPONDED, not just read
- Exclude automated senders (CI/CD notifications, bots, noreply@)
- Include flagged emails (explicit follow-up intent)

### Module 2: Calendar
- Today's meetings with times, durations, and join links
- Conflict detection
- Total meeting hours

### Module 3: Dev Workflow
- PRs waiting for your review (with age/staleness indicator)
- PRs you authored (pending approvals, unresolved comments, merge conflicts)
- Pipeline failures for your recent builds
- Stale PRs (> 3 days without update)

### Module 4: Tasks & Sprint
- Work items assigned to you, grouped by state
- Sprint progress and deadline proximity
- Blocked items highlighted

### Module 5: Compliance & Security
- Vulnerability notifications from email
- Expiring access / mandatory actions
- Policy changes that affect you

---

## 🎨 OUTPUT FORMAT

```
╔══════════════════════════════════════════════════╗
║         🌅 DAILY BRIEF — {date}                 ║
╠══════════════════════════════════════════════════╣

📬 COMMUNICATIONS
  📩 NEEDS REPLY (3):
    • [Sender] — Subject → What they're asking
    • [Sender] — Subject → What they're asking
  📧 EMAIL SUMMARY (12 unread)
    🔴 Action Required: 2 items
    📌 FYI: 4 items
    🤖 Automated: 6 items (ADO, builds)

📅 MEETINGS TODAY
  09:00 — Sprint Planning (30m)
  11:00 — Architecture Review (1h)
  14:00 — 1:1 with Manager (30m)
  Total: 3 meetings, 2h scheduled

🔀 PULL REQUESTS
  📤 Authored: 2 active PRs
    PR #123 "Fix auth flow" — waiting for approval (2d)
  📥 Reviewing: 1 pending
    PR #456 "Add caching" by teammate — ⚠️ STALE (5d)

📋 MY TASKS (Sprint 24.3)
  🔵 In Progress: 3 items
  ⬜ Planned: 5 items
  🔴 Blocked: 1 item
  📅 Sprint ends: 3 days

╚══════════════════════════════════════════════════╝
⏱️ Data as of {time} | Say "daily {module}" for details
📊 Summary: 7 items need your attention today
```

---

## 📏 RULES

1. **Be concise** — Counts and top items, not raw API dumps
2. **Highlight urgency** — ⚠️ for due soon, 🔴 for critical, ⏳ for waiting
3. **Skip empty modules** — "✅ Nothing pending" in one line
4. **Time context** — Relative time ("2h ago", "due in 3 days") not timestamps
5. **Actionable** — For each item, imply what action is needed
6. **Include links** — Every item should have a clickable URL
7. **Error handling** — If a source fails, note it and continue with others
8. **Parallelize** — Fetch from independent sources simultaneously

---

## 💡 SMART FEATURES

- Monday → include week overview (meetings count, sprint days remaining)
- Sprint ending within 3 days → escalate visibility
- PR stale > 5 days → suggest pinging author
- Email backlog > 5 important → flag buildup
- VIP email (from management) → always show, even if read

---

## 🔧 CUSTOMIZATION

To adapt for your setup:

1. **Replace tool references** — swap for your email/calendar/PR tool APIs
2. **Define VIP list** — who are YOUR management chain?
3. **Set automated sender exclusions** — what notification bots do you get?
4. **Configure modules** — enable/disable based on what tools you use
5. **Set escalation thresholds** — when does "aging" become "stale"?
