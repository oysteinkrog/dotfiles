# TanStack Libraries — Decision Guide

## Table of Contents
- [TanStack Query](#tanstack-query)
- [TanStack Table](#tanstack-table)
- [TanStack Form](#tanstack-form)
- [TanStack Router](#tanstack-router)
- [TanStack Virtual](#tanstack-virtual)

---

## TanStack Query

**Purpose:** Server state management, caching, synchronization.

### Good Candidates

- API calls that need caching
- Data fetched frequently
- Optimistic updates
- Background refetching
- Pagination with caching
- Infinite scroll
- Mutation with cache invalidation

### Skip If

- Simple one-time fetches
- Static data
- Data that doesn't need synchronization
- Server components with no client interactivity

### Key Features

```typescript
// Basic query
const { data, isLoading, error, refetch } = useQuery({
  queryKey: ['users'],
  queryFn: fetchUsers,
});

// With stale time
const { data } = useQuery({
  queryKey: ['users'],
  queryFn: fetchUsers,
  staleTime: 5 * 60 * 1000, // 5 minutes
});

// Mutation
const mutation = useMutation({
  mutationFn: createUser,
  onSuccess: () => queryClient.invalidateQueries(['users']),
});
```

---

## TanStack Table

**Purpose:** Headless table/grid logic.

### Good Candidates

- Complex data tables with sorting/filtering
- Tables with pagination
- Column resizing/reordering
- Row selection
- Expandable rows
- Server-side data tables
- Tables with 50+ rows

### Skip If

- Simple static tables
- Tables with < 20 rows
- No interactivity needed
- Display-only data grids

### Key Features

```typescript
const table = useReactTable({
  data,
  columns,
  getCoreRowModel: getCoreRowModel(),
  getSortedRowModel: getSortedRowModel(),
  getFilteredRowModel: getFilteredRowModel(),
  getPaginationRowModel: getPaginationRowModel(),
  state: { sorting, pagination, columnFilters },
  onSortingChange: setSorting,
  onPaginationChange: setPagination,
  onColumnFiltersChange: setColumnFilters,
});
```

### Column Definition

```typescript
const columns = [
  { accessorKey: 'name', header: 'Name' },
  { accessorKey: 'email', header: 'Email' },
  {
    accessorKey: 'status',
    header: 'Status',
    cell: ({ row }) => <Badge>{row.getValue('status')}</Badge>
  },
];
```

---

## TanStack Form

**Purpose:** Form state management and validation.

### Good Candidates

- Complex multi-step forms
- Forms with complex validation
- Forms with dynamic fields
- Forms with async validation
- Wizard-style workflows
- Forms with many dependencies between fields

### Skip If

- Simple contact forms
- Forms with 3-4 fields
- Basic validation needs
- Server actions with basic form data

### Key Features

```typescript
const form = useForm({
  defaultValues: { name: '', email: '' },
  onSubmit: async ({ value }) => {
    await submitForm(value);
  },
});

// Field with validation
<form.Field
  name="email"
  validators={{
    onChange: ({ value }) =>
      !value.includes('@') ? 'Invalid email' : undefined,
  }}
>
  {(field) => (
    <input
      value={field.state.value}
      onChange={(e) => field.handleChange(e.target.value)}
    />
  )}
</form.Field>
```

---

## TanStack Router

**Purpose:** Type-safe routing.

### Good Candidates

- Large apps needing type-safe routing
- Complex nested routes
- Route-based code splitting
- Search params management
- File-based routing with type safety

### Skip If

- Using Next.js App Router (already good)
- Simple navigation needs
- Few routes (< 10)
- Server-rendered apps

### Key Features

```typescript
// Route definition
const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/',
  component: HomePage,
});

// Type-safe navigation
<Link to="/users/$userId" params={{ userId: '123' }} />

// Type-safe search params
const { search } = useSearch({ from: '/users' });
```

---

## TanStack Virtual

**Purpose:** Virtualization for large lists.

### Good Candidates

- Lists with 1000+ items
- Infinite scroll views
- Large data grids
- Chat message lists
- Long dropdown menus
- File explorers

### Skip If

- Lists with < 100 items
- Performance is already fine
- Already using windowing elsewhere
- Static content

### Key Features

```typescript
const virtualizer = useVirtualizer({
  count: items.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 50, // item height
});

// Render only visible items
{virtualizer.getVirtualItems().map((virtualItem) => (
  <div
    key={virtualItem.key}
    style={{
      height: `${virtualItem.size}px`,
      transform: `translateY(${virtualItem.start}px)`,
    }}
  >
    {items[virtualItem.index]}
  </div>
))}
```

---

## Combination Patterns

### Query + Table

Common pattern for server-side tables:

```typescript
const { data, isLoading } = useQuery({
  queryKey: ['users', pagination, sorting],
  queryFn: () => fetchUsers({ page, sort }),
});

const table = useReactTable({
  data: data?.users ?? [],
  columns,
  pageCount: data?.pageCount ?? -1,
  manualPagination: true,
  manualSorting: true,
});
```

### Query + Virtual

For infinite scroll:

```typescript
const { data, fetchNextPage, hasNextPage } = useInfiniteQuery({
  queryKey: ['items'],
  queryFn: fetchItemsPage,
  getNextPageParam: (lastPage) => lastPage.nextCursor,
});

const allItems = data?.pages.flatMap(page => page.items) ?? [];

const virtualizer = useVirtualizer({
  count: hasNextPage ? allItems.length + 1 : allItems.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 50,
});
```
