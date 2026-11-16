## Overview

Black is a programming language, and White is its compiler and developer
command-line tool. White is written in Haskell and compiles Black to native
x86-64 Linux code, by way of textual LLVM IR and Clang.

The language’s focus is correctness that the compiler can establish rather
than assume. Today that means closed data types, exhaustive pattern
matching, and integer arithmetic and conversions that White must *prove*
fit their types before it will produce a program.

Black is an early-stage project. It is developed in phases, each ending in
a gate of automated checks run in Docker.

## Design principles

These are the rules White enforces today, not aspirations for later
versions.

- **Proved, not assumed.** An integer result must provably fit its type
  and a divisor must provably be nonzero, or the program does not compile.
- **Closed by default.** Records and variants are closed. Every match must
  be exhaustive, and an arm that can never run is an error.
- **Trust no earlier stage.** The checked program is elaborated into a
  small core language, and a validator re-derives the evidence recorded
  before it.
- **One canonical form.** `white fmt` rewrites source into the one
  canonical style, and an unused binding is an error unless its name
  starts with `_`.
- **Explicit boundaries.** Modules declare their exports, and imports are
  explicit, qualified or aliased. Native
  libraries are built against a versioned boundary descriptor that the host
  application owns.
- **Evidence as data.** Diagnostics carry stable codes, and `white verify`
  and the semantic queries report what was established as JSON.

## The compiler pipeline

Each stage of White has one responsibility, and only validated Core
reaches the back end. A failure in the front end never invokes Clang, and
a failed build leaves any existing output untouched.

## A program White accepts

This program is a case from White’s conformance suite, which is derived
from the language specification. It declares a nominal record type, swaps
its fields with a record update, and reads one back with a record pattern.

The suite expects White to accept it, and runs the result: given `0` or
`200`, the program returns the same value.

## A program White rejects

Also from the conformance suite. `cast` is an *exact* conversion, so it
must be proved to fit. An `Int32` may hold values that do not fit in a
`UInt8`, so White rejects `narrow` with the diagnostic code
`CAST_UNPROVEN`, at line 8, column 12.

An unresolved proof is not an accepted proof. To narrow a value that might
not fit, a program uses `tryCast`, which returns a `Result` that it must
handle.

## Language today

- Fixed-width integer types from `Int8` to `UInt64`, and `Boolean`.
- Nominal types, closed records, and variants with payloads.
- Exhaustive, nested pattern matching.
- Modules with explicit exports and qualified imports.
- Exact `cast` and checked `tryCast` conversions.
- `requires` and `ensures` contracts on functions, established at compile
  time for a limited fragment.
- `white fmt` and `white lint`, and semantic snapshot, query and diff
  commands with machine-readable output.
- A small demonstration game whose gameplay logic is written in Black and
  loaded by a C host.

## Status and limitations

Black is in active development, and much of its specification is not yet
implemented:

- There is no recursion, partial application, user-defined polymorphism or
  type classes yet, and arbitrary-precision integer types are rejected.
- Effects and handlers, and ownership and borrowing, are reserved in the
  syntax but **not implemented**. Black makes no resource-safety claims
  today.
- The contract grammar is provisional.
- White targets x86-64 Linux only.

An interactive playground is planned for this page, and is not available.

## Resources

- The source repository for Black and White is private.
- [black-vim](https://github.com/AugmenTab/black-vim): syntax highlighting
  and filetype support for Black in Vim and Neovim.
- Both programs above are verbatim from White’s conformance suite at
  commit `c1a45af`.
