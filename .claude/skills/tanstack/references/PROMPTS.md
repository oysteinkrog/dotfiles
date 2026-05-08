# TanStack Analysis Prompts — Reference

## Table of Contents
- [Full Analysis](#full-analysis)
- [Focused Analyses](#focused-analyses)
- [Migration Prompts](#migration-prompts)
- [Review Prompts](#review-prompts)

---

## Full Analysis

### Primary Prompt

```
Ok, I want you to look through the ENTIRE project and look for areas where, if we leveraged one of the many TanStack libraries (e.g., query, table, forms, etc), we could make part of the code much better, simpler, more performant, more maintainable, elegant, shorter, more reliable, etc. Use ultrathink
```

### With Priority Ranking

```
Analyze the entire project for TanStack adoption opportunities. For each opportunity found:
1. Identify the current vanilla implementation
2. Explain what TanStack library would improve it
3. Rate the improvement potential (high/medium/low)
4. Estimate implementation effort

Rank opportunities by value (benefit / effort ratio). Use ultrathink.
```

---

## Focused Analyses

### Query Analysis

```
Look through the project for data fetching patterns that would benefit from TanStack Query. Consider:
- Caching needs
- Refetching patterns
- Optimistic updates
- Request deduplication

Identify the top 3 opportunities with specific file locations. Use ultrathink.
```

### Table Analysis

```
Look through the project for table/grid components that would benefit from TanStack Table. Consider:
- Sorting complexity
- Filtering requirements
- Pagination handling
- Column management

Identify candidates with specific file locations. Use ultrathink.
```

### Form Analysis

```
Look through the project for form implementations that would benefit from TanStack Form. Consider:
- Validation complexity
- Multi-step flows
- Dynamic fields
- Async validation

Identify candidates with specific file locations. Use ultrathink.
```

### Virtual Analysis

```
Look through the project for lists or grids that would benefit from TanStack Virtual. Consider:
- Lists with 100+ items
- Infinite scroll implementations
- Performance issues with long lists
- Memory concerns

Identify candidates with specific file locations. Use ultrathink.
```

---

## Migration Prompts

### Migrate to TanStack Query

```
Migrate the data fetching in [FILE_PATH] from vanilla fetch/useEffect to TanStack Query.

Requirements:
1. Preserve existing functionality
2. Add appropriate caching strategy
3. Handle loading and error states
4. Set up query key structure
5. Add any needed mutations with cache invalidation

Show the complete migration. Use ultrathink.
```

### Migrate to TanStack Table

```
Migrate the table component in [FILE_PATH] from vanilla implementation to TanStack Table.

Requirements:
1. Preserve existing columns and data structure
2. Implement sorting (if currently manual)
3. Implement filtering (if currently manual)
4. Implement pagination (if currently manual)
5. Keep existing styling

Show the complete migration. Use ultrathink.
```

### Migrate to TanStack Virtual

```
Add virtualization to the list component in [FILE_PATH] using TanStack Virtual.

Requirements:
1. Preserve existing item rendering
2. Calculate correct item sizes
3. Handle dynamic height if needed
4. Maintain scroll position on data changes

Show the complete migration. Use ultrathink.
```

---

## Review Prompts

### Post-Migration Review

```
Review the TanStack migration we just completed:

1. Are we using the library idiomatically?
2. Are there any missed optimization opportunities?
3. Is the caching strategy appropriate?
4. Are there any edge cases not handled?
5. Is the code cleaner than before?

Use ultrathink.
```

### Bundle Impact Review

```
Analyze the bundle size impact of our TanStack adoption:

1. Which TanStack packages are we importing?
2. Are we tree-shaking effectively?
3. Are there any unnecessary imports?
4. Should any packages be lazy-loaded?

Suggest optimizations if needed. Use ultrathink.
```

### Second Round Analysis

```
We've completed the first round of TanStack adoption. Now look for:

1. Additional opportunities we may have missed
2. Places where we over-adopted (vanilla would be simpler)
3. Patterns that could be consolidated
4. New opportunities created by the changes

Use ultrathink.
```

---

## Model Configurations

| Model | Command/Config |
|-------|----------------|
| Claude Code + Opus 4.5 | Add "Use ultrathink" to prompt |
| Codex + GPT 5.2 | Set reasoning effort to "High" or "Extra-High" |
| Claude Code + Sonnet 4 | Good for focused single-file migrations |
| Codex + GPT 5 | Good for straightforward migrations |

---

## Creating Beads

After analysis, create beads for the work:

```bash
# Evaluation bead
br create "Evaluate TanStack Query opportunities" -t enhancement -p 3

# Migration beads
br create "Migrate user data fetching to TanStack Query" -t enhancement -p 2
br create "Implement data table with TanStack Table" -t feature -p 2
br create "Add TanStack Virtual to chat message list" -t performance -p 2
```
