# TanStack Examples — Before/After

## Table of Contents
- [Query: Data Fetching](#query-data-fetching)
- [Query: Mutation](#query-mutation)
- [Table: Complex Grid](#table-complex-grid)
- [Form: Multi-Step](#form-multi-step)
- [Virtual: Long List](#virtual-long-list)

---

## Query: Data Fetching

### Before (Vanilla)

```typescript
function UserList() {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function fetchUsers() {
      try {
        setLoading(true);
        const res = await fetch('/api/users');
        if (!res.ok) throw new Error('Failed to fetch');
        const data = await res.json();
        if (!cancelled) setUsers(data);
      } catch (err) {
        if (!cancelled) setError(err as Error);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    fetchUsers();
    return () => { cancelled = true; };
  }, []);

  if (loading) return <Spinner />;
  if (error) return <Error message={error.message} />;
  return <UserTable users={users} />;
}
```

### After (TanStack Query)

```typescript
function UserList() {
  const { data: users, isLoading, error } = useQuery({
    queryKey: ['users'],
    queryFn: async () => {
      const res = await fetch('/api/users');
      if (!res.ok) throw new Error('Failed to fetch');
      return res.json();
    },
  });

  if (isLoading) return <Spinner />;
  if (error) return <Error message={error.message} />;
  return <UserTable users={users} />;
}
```

**Benefits:**
- Automatic caching
- Request deduplication
- Background refetching
- DevTools support
- Much less code

---

## Query: Mutation

### Before (Vanilla)

```typescript
function CreateUserForm() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(data: UserData) {
    setLoading(true);
    setError(null);

    try {
      const res = await fetch('/api/users', {
        method: 'POST',
        body: JSON.stringify(data),
      });
      if (!res.ok) throw new Error('Failed to create user');

      // Manually refresh user list somehow...
      window.location.reload(); // Yikes
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  }

  return <Form onSubmit={handleSubmit} loading={loading} error={error} />;
}
```

### After (TanStack Query)

```typescript
function CreateUserForm() {
  const queryClient = useQueryClient();

  const { mutate, isPending, error } = useMutation({
    mutationFn: async (data: UserData) => {
      const res = await fetch('/api/users', {
        method: 'POST',
        body: JSON.stringify(data),
      });
      if (!res.ok) throw new Error('Failed to create user');
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
  });

  return <Form onSubmit={mutate} loading={isPending} error={error?.message} />;
}
```

**Benefits:**
- Automatic cache invalidation
- Optimistic updates support
- Loading/error states handled
- No manual refresh needed

---

## Table: Complex Grid

### Before (Vanilla)

```typescript
function DataTable({ data }: { data: User[] }) {
  const [sortField, setSortField] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const [filter, setFilter] = useState('');
  const [page, setPage] = useState(0);
  const pageSize = 10;

  // Sorting logic
  const sorted = useMemo(() => {
    if (!sortField) return data;
    return [...data].sort((a, b) => {
      const aVal = a[sortField as keyof User];
      const bVal = b[sortField as keyof User];
      const cmp = aVal < bVal ? -1 : aVal > bVal ? 1 : 0;
      return sortDir === 'asc' ? cmp : -cmp;
    });
  }, [data, sortField, sortDir]);

  // Filtering logic
  const filtered = useMemo(() => {
    if (!filter) return sorted;
    return sorted.filter(u =>
      u.name.toLowerCase().includes(filter.toLowerCase()) ||
      u.email.toLowerCase().includes(filter.toLowerCase())
    );
  }, [sorted, filter]);

  // Pagination logic
  const paged = filtered.slice(page * pageSize, (page + 1) * pageSize);
  const pageCount = Math.ceil(filtered.length / pageSize);

  // ... 100+ more lines of render logic
}
```

### After (TanStack Table)

```typescript
function DataTable({ data }: { data: User[] }) {
  const [sorting, setSorting] = useState<SortingState>([]);
  const [globalFilter, setGlobalFilter] = useState('');

  const columns = useMemo<ColumnDef<User>[]>(() => [
    { accessorKey: 'name', header: 'Name' },
    { accessorKey: 'email', header: 'Email' },
    { accessorKey: 'role', header: 'Role' },
  ], []);

  const table = useReactTable({
    data,
    columns,
    state: { sorting, globalFilter },
    onSortingChange: setSorting,
    onGlobalFilterChange: setGlobalFilter,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
  });

  return (
    <>
      <Input value={globalFilter} onChange={e => setGlobalFilter(e.target.value)} />
      <Table>
        <TableHeader>
          {table.getHeaderGroups().map(headerGroup => (
            <TableRow key={headerGroup.id}>
              {headerGroup.headers.map(header => (
                <TableHead
                  key={header.id}
                  onClick={header.column.getToggleSortingHandler()}
                >
                  {flexRender(header.column.columnDef.header, header.getContext())}
                </TableHead>
              ))}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {table.getRowModel().rows.map(row => (
            <TableRow key={row.id}>
              {row.getVisibleCells().map(cell => (
                <TableCell key={cell.id}>
                  {flexRender(cell.column.columnDef.cell, cell.getContext())}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <Pagination table={table} />
    </>
  );
}
```

**Benefits:**
- All table logic handled
- Consistent behavior
- Column definitions are declarative
- Easy to add features (selection, expansion, etc.)

---

## Virtual: Long List

### Before (Vanilla)

```typescript
function MessageList({ messages }: { messages: Message[] }) {
  // Renders ALL messages, causing lag with 1000+ items
  return (
    <div className="h-[500px] overflow-auto">
      {messages.map(msg => (
        <MessageItem key={msg.id} message={msg} />
      ))}
    </div>
  );
}
```

### After (TanStack Virtual)

```typescript
function MessageList({ messages }: { messages: Message[] }) {
  const parentRef = useRef<HTMLDivElement>(null);

  const virtualizer = useVirtualizer({
    count: messages.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 60,
    overscan: 5,
  });

  return (
    <div ref={parentRef} className="h-[500px] overflow-auto">
      <div style={{ height: `${virtualizer.getTotalSize()}px`, position: 'relative' }}>
        {virtualizer.getVirtualItems().map(virtualItem => (
          <div
            key={virtualItem.key}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              height: `${virtualItem.size}px`,
              transform: `translateY(${virtualItem.start}px)`,
            }}
          >
            <MessageItem message={messages[virtualItem.index]} />
          </div>
        ))}
      </div>
    </div>
  );
}
```

**Benefits:**
- Only renders visible items
- Smooth scrolling with 10k+ items
- Memory efficient
- Configurable overscan
