<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 Hitesh Soliwal, Synexia -->
# Machine Oriented Programming (MOP): the self-improving recipe invariant

Status: canonical statement, 2026-10-20. Paradigm and invariant: Hitesh Soliwal, Synexia.

## Invariant

**Every time an LLM or a coding agent corrects a recipe, the recipe records the correction.**

The record is memory for the next LLM or coding agent. Working with a coding agent therefore updates the recipe
the way a memory update would: corrections do not stay in a chat, they accumulate in the recipe, become test
cases, and every later run starts from them. A recipe only improves; this is what makes MOP self-improving.

## The four verbs

1. **Atomize**: one recipe leaf, one purpose (a pass, a gate, a census, a scaffold step), each with its own tests.
2. **Patternize**: recurring transforms and matches become catalogues (templates, code mappings), applied
   mechanically, so the machine does the repetition and the agent only adds new patterns.
3. **Annotate**: every site the recipe touches is marked (multipass marks with permalinks, `//FLLDCIM:` anchors),
   so later passes and agents read structure instead of re-deriving it.
4. **Document**: README, ledgers and receipts travel with the recipe and with every repository it changes.

## Correction record (contract)

Each recipe crate carries an append-only `RECIPE_CORRECTIONS.tsv`:

| Column | Meaning |
| --- | --- |
| `id` | `C01`, `C02`, ... never reused |
| `date`, `agent` | when and by whom (LLM, coding agent, human) |
| `symptom` | what was observed |
| `cause` | why it happened |
| `correction` | what the recipe now does instead |
| `files` | recipe files changed |
| `test_added` | the test case that pins the correction, or `-` |
| `lesson` | the rule the next agent applies before running or changing the recipe |

Rules:

1. A correction without a row is not finished.
2. When a correction can be tested, its test case lands in the same change and the row names it.
3. Rows are never edited or deleted; a later correction adds a row that names the id it supersedes.
4. An agent reads `RECIPE_CORRECTIONS.tsv` before it runs or changes the recipe (recall before action).

## Reference application

`synexia-openrewrite-recipes/recipe-crates/m3-eclipse-jdk21-compat-20261020` in `hsoliwal/com.synexia`: the text-lane
recipe that keeps the Eclipse forks at Java 21 for M3JDK21 recorded 14 corrections on its first day (line endings,
gawk column 1, failing-tool overwrite, pipefail, test fixtures, awk built-ins, native paths, NR == FNR, MSYS path
conversion, diff headers, name collisions, BOM files, process checks, per-file process cost), each with its lesson.
