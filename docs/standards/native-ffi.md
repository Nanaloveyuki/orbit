# Native FFI

> **Status: Reference only.** These rules describe the proposed native-boundary
> requirements for Orbit and its core dependencies. They are not a claim that all
> native paths have completed a beta audit.

## Boundary ownership

- Every native allocation, callback context, handle, and asynchronous operation
  MUST have one documented owner.
- The MoonBit side MUST know whether a value is borrowed, transferred, or owned.
  A borrowed value MUST NOT be retained after its callback or documented scope.
- A native value transferred into MoonBit MUST be released exactly once by the
  owning side, including all error and early-return paths.
- Native bridges MUST validate pointers, lengths, and required callbacks before
  dereferencing or invoking them.
- A null, allocation failure, invalid status, or platform failure MUST enter an
  explicit error path. It MUST NOT become an empty success value or an ignored
  timeout.

## Bytes and strings

- A `Bytes` value crossing the boundary MUST state who owns its storage and how
  long it remains valid.
- Native code MUST check allocation results before copying data or constructing a
  MoonBit value.
- String and byte lengths MUST be bounded before allocation or copying.
- Text decoding MUST use the documented strict or loss-tolerant policy; a decoder
  MUST NOT silently turn malformed protocol data into valid application input.
- A native callback MUST NOT retain a pointer to a temporary MoonBit string or
  byte buffer unless the bridge explicitly creates an owned copy.

## Callback lifetime and threads

- A callback context used after the initiating call returns MUST be retained for
  the entire asynchronous lifetime and released after the final callback.
- Callback installation, replacement, and removal MUST be synchronized with
  callback dispatch.
- A callback MUST run only on its documented thread. Native code MUST marshal to
  the UI thread or async executor when the callback touches an owner-bound value.
- Teardown MUST prevent new callback dispatch before releasing the callback
  context. It MUST wait for in-flight callbacks when the native API requires it.
- Reentrant callbacks MUST either be explicitly supported or rejected with a
  stable error; accidental reentrancy is not a supported contract.

## Async completion and shutdown

- Every native asynchronous request MUST have one terminal completion path.
- Completion, cancellation, timeout, native shutdown, and allocation failure MUST
  be safe to race and MUST not complete the same MoonBit request twice.
- A native worker MUST stop accepting new work after shutdown begins.
- Dynamic libraries MUST NOT be unloaded while a callback, worker, or native
  invocation can still execute code from that library.
- If a worker cannot be confirmed stopped, the owner MUST retain the library and
  return a shutdown failure instead of unloading unsafely.

## Error propagation

- Native status values and platform error codes MUST be checked at the boundary.
- Public MoonBit APIs MUST receive a stable Orbit/package-level error category.
- Native details MAY be attached as diagnostic data, but MUST NOT leak paths,
  secrets, or uncontrolled native text into untrusted IPC responses.
- Cleanup failures that affect ownership, data integrity, or unloading MUST remain
  observable to the caller or release diagnostics.

## Platform adapters

- Each platform adapter MUST document unsupported operations explicitly.
- A platform fallback MAY return `Unavailable` or an equivalent stable category,
  but MUST NOT report success without performing the requested operation.
- Platform-specific callback and resource rules MUST be tested at the adapter
  boundary, not inferred only from MoonBit-level unit tests.
- C/C++ FFI changes SHOULD include strict compiler warnings and focused failure
  tests where the local toolchain supports them.

## Verification reference

The future beta checklist SHOULD cover null callbacks, allocation failure, invalid
lengths, malformed text, callback-after-destroy, callback replacement races,
in-flight callback shutdown, double completion, worker stop failure, and attempted
library unload while work remains active.
