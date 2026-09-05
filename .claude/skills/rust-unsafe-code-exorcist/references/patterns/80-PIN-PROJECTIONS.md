# 80-PIN-PROJECTIONS.md — Pin, Self-Referential Types, Async Runtimes

`Pin<P>` is one of the trickiest parts of Rust to audit. This file covers when hand-written `Pin::new_unchecked` is correct, when it can be replaced with `pin-project-lite`, and when the (A) classification is justified.

---

## What Pin actually does

`Pin<&mut T>` says: "this `&mut T` will never move the `T` until `T` is dropped." A type that's `Unpin` ignores the pin guarantee (most types). A type that's `!Unpin` honors it (`std::pin::PhantomPinned`-bearing types, generated async state machines).

The pin guarantee enables self-referential types: a struct can hold a `&'self Field` to its own field, IFF the struct is pinned (so the field's address doesn't change).

Constructing `Pin<&mut T>` from a raw `&mut T` requires unsafe (`Pin::new_unchecked`) because the compiler can't verify the "never moves" promise.

---

## Pattern P-1: `pin-project-lite` covers most cases (C)

Common pattern: a struct with a `#[pin]` field that's a Future.

```rust
// Before (hand-written)
pub struct MyFuture {
    inner: SomeFuture,
    state: State,
}

impl Future for MyFuture {
    type Output = Result<(), Error>;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        // SAFETY: we never move self.inner.
        let inner = unsafe { Pin::new_unchecked(&mut self.get_unchecked_mut().inner) };
        match inner.poll(cx) { ... }
    }
}

// After (using pin-project-lite)
pin_project_lite::pin_project! {
    pub struct MyFuture {
        #[pin]
        inner: SomeFuture,
        state: State,
    }
}

impl Future for MyFuture {
    type Output = Result<(), Error>;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        let this = self.project();
        match this.inner.poll(cx) { ... }
    }
}
```

`pin-project-lite` generates the unsafe internally with field-by-field correctness checks. Adopt this everywhere unless the type has a true self-reference (Pattern P-3).

---

## Pattern P-2: stack-pinning with `tokio::pin!`

For local pin-projections of stack-allocated futures:

```rust
// Before
let fut = some_async_fn();
let mut fut = fut;
let fut = unsafe { Pin::new_unchecked(&mut fut) };
fut.await;

// After
let fut = some_async_fn();
tokio::pin!(fut);   // or std::pin::pin! on nightly
fut.await;
```

`tokio::pin!` (or `std::pin::pin!` on Rust 1.68+) expands to a safe stack-pinning macro. Zero call-site unsafe.

---

## Pattern P-3: True self-reference (A)

When `pin-project` cannot express the projection (typically because the projection has a lifetime tied to ANOTHER field of the same struct), the (A) is justified:

```rust
pub struct WsStream {
    socket: TcpStream,
    buffer: Vec<u8>,
    // Buffer-slice reference into self.buffer; lifetime tied to self.
    reader_view: &'static mut [u8],   // 'static is a lie — really 'self
    _pin: PhantomPinned,
}
```

`pin-project` can pin-project to `&mut self.socket` and `&mut self.buffer`, but it CAN'T express the self-lifetime of `reader_view`.

The (A) hardening:

```rust
impl WsStream {
    /// SAFETY: After construction (via `WsStream::open`), the WsStream is wrapped
    /// in `Box::pin` and never moved. The `reader_view` points into
    /// `self.buffer[read_pos..]` and remains valid for the lifetime of the stream.
    ///
    /// Moving a constructed WsStream would dangle `reader_view` and cause UB. The
    /// type is `!Unpin` (via PhantomPinned), so the move is statically prevented
    /// in any context where the user holds `&mut WsStream` or pinned access.
    fn refresh_reader_view(self: Pin<&mut Self>) {
        // SAFETY: see type-level comment.
        unsafe {
            let this = self.get_unchecked_mut();
            this.reader_view = std::mem::transmute(&mut this.buffer[this.read_pos..]);
        }
    }
}
```

The constructor MUST return `Pin<Box<WsStream>>` (not `WsStream`) so the caller can't accidentally move:

```rust
impl WsStream {
    pub fn open(socket: TcpStream) -> Pin<Box<Self>> {
        let mut boxed = Box::pin(WsStream {
            socket,
            buffer: vec![0; 4096],
            reader_view: &mut [],
            _pin: PhantomPinned,
        });
        boxed.as_mut().refresh_reader_view();
        boxed
    }
}
```

---

## Async cancellation and Pin

A pinned future being dropped (cancellation) runs the future's `Drop`. The Drop must restore all invariants:

- Any temporary resource acquired (mmap, fd, lock guard) must release.
- Any in-progress write to shared state must reach a consistent point or roll back.
- Any awaiting task waiting on this future must see "cancelled" rather than hang.

Operator 🔁 Async-Cancellation-Trace applies here. The (A) write-up for a Pin-projected future must enumerate every `.await` point and what happens if the future is dropped there.

---

## Common Pin (A) misclassifications

### Misclassification M-1: "We need Pin because it's a Future"

A `Future` impl on a struct does NOT require `unsafe`. Use `pin-project-lite`. The (A) → (C) refactor is straightforward.

### Misclassification M-2: "We need Pin::new_unchecked to convert &mut T to Pin<&mut T>"

If `T: Unpin`, just use `Pin::new(&mut t)`. The unsafe `_unchecked` form is only needed when `T: !Unpin`.

### Misclassification M-3: "We need !Unpin because of a future field"

A struct containing a `!Unpin` field is itself `!Unpin` automatically. You don't need to write `unsafe impl !Unpin`; the compiler will figure it out. The `PhantomPinned` zero-sized marker is the safe way to force `!Unpin` if you need to.

---

## Acceptance signal for Pin sites

A Pin site classification passes when:

1. The type is correctly `Unpin` / `!Unpin` per its actual constraints.
2. `pin-project-lite` is used wherever applicable (most cases → (C)).
3. True self-referential cases have hardened SAFETY comments naming the pin invariant + the construction discipline.
4. Async cancellation paths are traced.
5. Loom model (if the future interacts with multi-thread synchronization).
6. The constructor returns `Pin<Box<Self>>` for `!Unpin` self-referential types.

If any of these is missing, the site goes back to refactor-planner.

---

## Resources

- The Rust nomicon §pin: https://doc.rust-lang.org/nomicon/aliasing.html (read in full)
- `pin-project-lite` docs (mantissa of how the safe wrapper works internally)
- `/dp/mcp_agent_mail_rust/src/ws/stream.rs` for the exemplar self-referential case
- `/dp/asupersync` and `/dp/franken_engine` for async-runtime-level Pin patterns
