# AST-Grep Patterns for Mock/Stub Detection

## Rust

### Explicit Stubs

```bash
# todo!() and unimplemented!() in function bodies
ast-grep run -l Rust -p 'fn $NAME($$$) -> $RET { todo!($$$) }'
ast-grep run -l Rust -p 'fn $NAME($$$) -> $RET { unimplemented!($$$) }'
ast-grep run -l Rust -p 'fn $NAME($$$) { todo!($$$) }'

# panic! used as placeholder
ast-grep run -l Rust -p 'fn $NAME($$$) -> $RET { panic!($$$) }'
```

### Empty / Trivial Implementations

```bash
# Empty function bodies
ast-grep run -l Rust -p 'fn $NAME($$$) { }'
ast-grep run -l Rust -p 'fn $NAME($$$) -> $RET { Default::default() }'

# Empty impl blocks
ast-grep run -l Rust -p 'impl $TRAIT for $TYPE { }'

# Impl blocks with only one trivial method
ast-grep run -l Rust -p 'impl $TYPE {
    fn $NAME(&self) -> $RET { $SINGLE }
}'
```

### Suspicious Return Patterns

```bash
# Always returns Ok with empty/default value
ast-grep run -l Rust -p 'fn $NAME($$$) -> Result<$T, $E> { Ok(Default::default()) }'
ast-grep run -l Rust -p 'fn $NAME($$$) -> Result<$T, $E> { Ok(vec![]) }'
ast-grep run -l Rust -p 'fn $NAME($$$) -> Result<$T, $E> { Ok(String::new()) }'

# Always returns Some/None
ast-grep run -l Rust -p 'fn $NAME($$$) -> Option<$T> { None }'
ast-grep run -l Rust -p 'fn $NAME($$$) -> Option<$T> { Some(Default::default()) }'

# Always returns hardcoded bool
ast-grep run -l Rust -p 'fn $NAME($$$) -> bool { true }'
ast-grep run -l Rust -p 'fn $NAME($$$) -> bool { false }'
```

### Error Handling Stubs

```bash
# Empty error arms
ast-grep run -l Rust -p 'Err(_) => {}'
ast-grep run -l Rust -p 'Err($E) => Ok(())'
ast-grep run -l Rust -p 'Err(_) => Default::default()'

# Blanket unwrap (often placeholder for proper error handling)
ast-grep run -l Rust -p '$EXPR.unwrap()'
```

---

## Python

### Explicit Stubs

```bash
# pass-only functions
ast-grep run -l Python -p 'def $NAME($$$):
    pass'

# Ellipsis stubs (protocol/ABC methods)
ast-grep run -l Python -p 'def $NAME($$$):
    ...'

# NotImplementedError
ast-grep run -l Python -p 'def $NAME($$$):
    raise NotImplementedError($$$)'
```

### Trivial Returns

```bash
# Return None (explicit)
ast-grep run -l Python -p 'def $NAME($$$):
    return None'

# Return empty collections
ast-grep run -l Python -p 'def $NAME($$$):
    return {}'
ast-grep run -l Python -p 'def $NAME($$$):
    return []'
ast-grep run -l Python -p 'def $NAME($$$):
    return ""'
```

---

## TypeScript / JavaScript

### Explicit Stubs

```bash
# Empty functions
ast-grep run -l TypeScript -p 'function $NAME($$$) { }'
ast-grep run -l TypeScript -p '($$$) => { }'
ast-grep run -l TypeScript -p 'async function $NAME($$$) { }'

# Throw not-implemented
ast-grep run -l TypeScript -p 'function $NAME($$$) { throw new Error($$$) }'
```

### Trivial Returns

```bash
# Return undefined/null
ast-grep run -l TypeScript -p 'function $NAME($$$) { return undefined; }'
ast-grep run -l TypeScript -p 'function $NAME($$$) { return null; }'

# Return empty structures
ast-grep run -l TypeScript -p 'function $NAME($$$) { return {}; }'
ast-grep run -l TypeScript -p 'function $NAME($$$) { return []; }'
```

### Empty Class Methods

```bash
ast-grep run -l TypeScript -p '$NAME($$$) { }'
ast-grep run -l TypeScript -p 'async $NAME($$$) { }'
```

---

## Go

### Explicit Stubs

```bash
# Empty functions
ast-grep run -l Go -p 'func $NAME($$$) $RET { }'

# Panic placeholders
ast-grep run -l Go -p 'func $NAME($$$) $RET { panic($$$) }'

# Return nil, nil (error swallowing)
ast-grep run -l Go -p 'func $NAME($$$) ($RET, error) { return nil, nil }'
```

---

## Combining ast-grep with jq for Analysis

```bash
# Find all functions, sort by body size (smallest first)
ast-grep run -l Rust -p 'fn $NAME($$$) $$$BODY' --json | \
  jq '[.[] | {
    name: .metaVariables.NAME.text,
    file: .file,
    start_line: .range.start.line,
    end_line: .range.end.line,
    body_lines: (.range.end.line - .range.start.line)
  }] | sort_by(.body_lines) | .[:30]'

# Find functions under N lines (suspicious threshold)
ast-grep run -l Rust -p 'fn $NAME($$$) $$$BODY' --json | \
  jq '[.[] | select((.range.end.line - .range.start.line) < 3) | {
    name: .metaVariables.NAME.text,
    file: .file,
    line: .range.start.line
  }]'
```
