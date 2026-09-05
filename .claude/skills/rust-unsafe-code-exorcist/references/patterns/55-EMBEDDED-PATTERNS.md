# 55-EMBEDDED-PATTERNS.md — Volatile MMIO, PAC, embedded-hal

Embedded Rust has a distinctive unsafe surface: memory-mapped I/O, interrupt handlers, no-allocator targets. The patterns are well-established; the audit's job is to ensure they're applied.

---

## The four classes of embedded unsafe

| Class | Example | Bucket |
|-------|---------|--------|
| Volatile MMIO | `core::ptr::write_volatile(0x4000_0000 as *mut u32, 0x42)` | (A) per [00-CANONICAL-UNAVOIDABLE.md § 10](00-CANONICAL-UNAVOIDABLE.md) |
| Interrupt handlers | `extern "C" fn TIM0_irq()` | (A) — async-signal-safety required |
| Inline `asm!` | `asm!("dmb sy")` for memory barriers | (A) — language primitive |
| Static-mut / `Cell` for shared state with ISR | `static mut COUNTER: u32 = 0;` accessed by both main + ISR | (C) opportunity — almost always |

---

## Pattern E-1 — Use `volatile-register` instead of raw `read_volatile`

The `volatile-register` crate provides typed `RW<T>` / `RO<T>` / `WO<T>` types that encapsulate the volatile-MMIO pattern:

```rust
// Before — raw
unsafe {
    let p = 0x4000_0000 as *mut u32;
    core::ptr::write_volatile(p, 0x42);
}

// After — typed
use volatile_register::RW;

#[repr(C)]
struct UartRegisters {
    data: RW<u32>,
    status: RO<u32>,
    control: RW<u32>,
}

let uart = unsafe { &*(0x4000_0000 as *const UartRegisters) };  // (A) — single point of trust
unsafe { uart.data.write(0x42); }  // method, not raw ptr
```

The (A) is concentrated at the register-block construction; the per-field methods are typed.

**Refactor (C):** identify every raw `read_volatile` / `write_volatile`; cluster by register block; introduce a `#[repr(C)]` struct per device.

---

## Pattern E-2 — Use a PAC (Peripheral Access Crate)

For ARM Cortex-M / RISC-V, the vendor or community provides a PAC (e.g., `stm32f4xx-pac`, `nrf52833-pac`). The PAC auto-generates safe-ish wrappers for every register.

```rust
// With PAC
let p = stm32f4xx_pac::Peripherals::take().unwrap();
p.GPIOA.moder.write(|w| w.moder5().output());
```

**Audit position.** The PAC's internals contain (A) volatile MMIO; the project trusts the PAC. The per-call site is safe.

**Refactor (C):** if the project uses raw `read_volatile` and a PAC is available for the target MCU, switch to the PAC.

---

## Pattern E-3 — Use `embedded-hal` traits

`embedded-hal` defines abstract trait interfaces for I/O. Projects implement the traits using PAC / HAL underneath; consumer code is generic + safe.

```rust
use embedded_hal::digital::OutputPin;

fn blink<P: OutputPin>(pin: &mut P, delay_ms: u32) {
    pin.set_high().ok();
    delay(delay_ms);
    pin.set_low().ok();
}
```

The consumer code has no unsafe. The trait impl in the HAL crate has the unsafe (the (A) for volatile MMIO).

**Refactor (C):** generic-ize consumer code over `embedded-hal` traits where it currently hard-codes a specific MCU.

---

## Pattern E-4 — `cortex-m::interrupt::free` for ISR-shared state

Static-mut shared between main and ISR is a classic data-race source:

```rust
// Unsound — main and ISR both touch COUNTER
static mut COUNTER: u32 = 0;

fn main_loop() {
    unsafe { COUNTER += 1; }
}

#[interrupt]
fn TIM0() {
    unsafe { COUNTER += 1; }
}
```

**Refactor (C):** wrap in `cortex_m::interrupt::Mutex<RefCell<T>>` and access via `cortex_m::interrupt::free`:

```rust
use cortex_m::interrupt::{free, Mutex};
use core::cell::RefCell;

static COUNTER: Mutex<RefCell<u32>> = Mutex::new(RefCell::new(0));

fn main_loop() {
    free(|cs| *COUNTER.borrow(cs).borrow_mut() += 1);
}

#[interrupt]
fn TIM0() {
    free(|cs| *COUNTER.borrow(cs).borrow_mut() += 1);
}
```

`cortex_m::interrupt::free` disables interrupts for the duration of the closure; the `RefCell` is single-thread-safe inside.

Alternatively, use `AtomicU32` for primitive counters:

```rust
use core::sync::atomic::{AtomicU32, Ordering};
static COUNTER: AtomicU32 = AtomicU32::new(0);

fn main_loop() {
    COUNTER.fetch_add(1, Ordering::Relaxed);
}
#[interrupt]
fn TIM0() {
    COUNTER.fetch_add(1, Ordering::Relaxed);
}
```

---

## Pattern E-5 — `singleton!` macro for one-shot peripheral ownership

`cortex-m-rt::singleton!` provides a way to construct a peripheral exactly once:

```rust
use cortex_m_rt::singleton;

fn setup() -> &'static mut [u8; 1024] {
    singleton!(: [u8; 1024] = [0; 1024]).unwrap()
}
```

Eliminates the static-mut + manual-takeonce pattern.

---

## Allocator on embedded

Many embedded targets have no allocator by default. If you need one:

- `linked-list-allocator` — heap with linked-free-list
- `alloc-cortex-m` — newer alternative
- `talc` — pluggable allocator framework

These crates impl `GlobalAlloc`, which is (A) per [00-CANONICAL-UNAVOIDABLE.md § 7](00-CANONICAL-UNAVOIDABLE.md). Trust the crate; the audit just verifies the allocator-init code is correct.

---

## DMA buffers

DMA shares memory between CPU and peripheral; the peripheral may write to the buffer asynchronously. The buffer pointer's borrow checker doesn't model this.

Pattern:

```rust
use embedded_dma::WriteBuffer;

// The DMA controller asynchronously writes to `buf`; main code must not
// access `buf` during the transfer.
let buf: &'static mut [u8] = singleton!(: [u8; 256] = [0; 256]).unwrap();
let transfer = dma_channel.read(peripheral, buf);
// transfer holds the buffer; we can't access it.
let (peripheral, buf, dma_channel) = transfer.wait();
// transfer dropped; buf is ours again.
```

The (A) lives in the DMA controller's impl; consumer code uses the transfer-handle pattern safely.

---

## Audit checklist for embedded

For each crate / module touching MMIO:

- [ ] Volatile MMIO is wrapped in `volatile-register` (or a PAC).
- [ ] Static-mut shared with ISR uses `cortex_m::interrupt::Mutex` or `AtomicXxx`.
- [ ] Interrupt handlers are `extern "C"`; document panic discipline (abort).
- [ ] `singleton!` is used for one-shot peripheral ownership where applicable.
- [ ] DMA buffers use the transfer-handle pattern.
- [ ] `#[no_mangle]` exports have panic-converting wrappers if linked into C.
- [ ] `panic = "abort"` in all profiles (unwinding on embedded is usually unworkable).

---

## Exemplar precedent

`/dp/pi_agent_rust/src/uart.rs` — uses `volatile-register` for UART access; per-peripheral `Uart` ownership type; `cortex_m::interrupt::free` for ISR coordination. `[E-030]` and `[E-031]` in EXEMPLAR-CATALOG.

---

## Acceptance signal

An embedded site passes when:

1. Volatile MMIO is wrapped (or the (A) is justified per `00-CANONICAL-UNAVOIDABLE.md § 10`).
2. Shared state with ISRs uses `cortex_m::interrupt::Mutex` / atomic / equivalent.
3. Interrupt handlers' panic policy is `abort` and documented.
4. DMA buffers use transfer-handle ownership.
5. Allocator (if used) is from an audited crate.
6. The PAC / embedded-hal abstractions are used where they apply.
