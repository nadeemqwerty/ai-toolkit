---
name: test-writer
description: >
  TDD-focused test writing skill for planning and implementing meaningful tests that
  verify behavior rather than implementation details. Activates on keywords like: test,
  unit test, write test, TDD, coverage, test case, spec.
---

# Test Writer Skill

> **Write tests that prove behavior, fail for the right reason, and stay readable when the
> implementation evolves.**

This skill helps an agent plan, write, and validate meaningful tests with a TDD-first mindset.

---

## 🎯 WHEN TO ACTIVATE

Trigger on ANY of:
- User asks to add or update tests
- User asks for unit tests, specs, or coverage
- User asks for TDD workflow or test planning
- User wants edge cases or regression cases captured in tests

---

## 🧭 TEST PRINCIPLES

Every test should be:
- **Behavior-focused** — verify externally visible outcomes
- **Readable** — a reader should know the scenario quickly
- **Fast** — avoid unnecessary integration cost
- **Independent** — no hidden ordering or shared mutable state
- **Deterministic** — same input, same result every run

Prefer:
- explicit inputs and assertions
- stable fixtures
- narrow mocks at real boundaries
- small scenarios with clear intent

---

## 🔄 WORKFLOW

### Step 1: Understand the unit under test
Identify:
- function / class / endpoint under test
- inputs and outputs
- side effects
- dependencies and boundaries

### Step 2: Identify behavior boundaries
Cover:
- happy path
- boundary values
- null / empty input behavior
- error conditions
- integration boundaries
- concurrency behavior if applicable

### Step 3: Write the test plan FIRST
Before implementation, list:
- test name
- category
- scenario input
- expected behavior
- why the case matters

### Step 4: Implement each test
Use the project's native test framework and existing patterns.

### Step 5: Run red → green
- Confirm the test would fail without the feature or fix
- Implement or adjust behavior
- Re-run until green

### Step 6: Review coverage quality
Ask:
- Did we cover meaningful edge cases?
- Are we asserting behavior instead of internals?
- Would the test still pass after harmless refactoring?

---

## 🧪 TEST CATEGORIES TO COVER

| Category | What to test |
|----------|---------------|
| Happy path | Expected successful flow |
| Boundary values | Min/max edges, off-by-one risks |
| Null / empty inputs | Missing or empty values |
| Error conditions | Exceptions, validation failures, retries |
| Concurrent access | Races, duplicate work, ordering if relevant |
| Integration points | Calls to DB, APIs, queues, files, clocks |

---

## 🚫 ANTI-PATTERNS TO AVOID

Never write tests that:
- assert private implementation details instead of behavior
- depend on test order or shared mutable state
- rely on wall-clock timing without control
- use overly broad mocks that restate the implementation
- pass nondeterministically
- encode fragile formatting details unrelated to the behavior

Smells to fix:
- too many assertions for unrelated behaviors in one test
- vague test names
- fixtures so large the scenario is unclear
- magic values with no scenario meaning

---

## 🧱 OUTPUT TEMPLATE

```markdown
## Test Plan: <component>

### Behaviors to verify
1. <behavior 1> — <why it matters>
2. <behavior 2> — <why it matters>
3. <behavior 3> — <why it matters>

### Test Cases
| # | Test Name | Category | Input | Expected |
|---|-----------|----------|-------|----------|
| 1 | should_X_when_Y | happy path | ... | ... |
| 2 | should_throw_when_Z | error | ... | ... |

### Implementation
<actual test code>
```

---

## ✅ EXECUTION RULES

- Always produce a **test plan before code**
- Prefer one behavior per test unless a sequence is the behavior
- Name tests with scenario + expected result
- For regressions, include a case that reproduces the original bug
- If concurrency matters, control timing with fakes or synchronization primitives
- Use existing helpers and fixtures before inventing new infrastructure
- Stop when coverage is behaviorally complete, not merely numerically high
