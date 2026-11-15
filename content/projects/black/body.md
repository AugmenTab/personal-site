## Overview

Black is a programming language, and White is its compiler and developer
command-line tool. White is written in Haskell and compiles Black to native
x86-64 Linux code, by way of textual LLVM IR and Clang.

The language’s focus is correctness that the compiler can establish rather
than assume. Today that means closed data types, exhaustive pattern
matching, and integer arithmetic and conversions that White must *prove*
fit their types before it will produce a program.

Black is an early-stage project. It is developed in phases, each ending
in a gate of automated checks.

## Technical approach

White is a sequence of stages, each with one responsibility:

1. **Front end.** Parsing, the canonical formatter, name resolution, unused
   binding checks, then type and exhaustiveness checking.
2. **Proof of fit.** Interval reasoning establishes that every integer
   result fits its type and that every divisor is nonzero. A `cast` that
   cannot be proved is a compile-time error; `tryCast` returns a `Result`
   instead.
3. **Core.** The checked program is elaborated into a small core language,
   and a validator re-derives the evidence the earlier stages recorded,
   rather than trusting them.
4. **Back end.** Core is lowered to textual LLVM IR and compiled with
   `clang-19` into an executable, or into a shared library that a C host
   program loads.

A program from White’s conformance suite, which the compiler accepts. It
shows a nominal record type, a record update and a record pattern:

```black
module NominalRecord
  ( main
  )

-- Spec section 7: nominality applies to structural records. Construction,
-- projection, update and record patterns keep the nominal identity.
nominal type Position = { x :: UInt8, y :: UInt8 }

swap :: Position -> Position
swap position = position { x = position.y, y = position.x }

main :: UInt8 -> UInt8
main v =
  case swap (Position { x = v, y = 9 }) of
    Position { y } -> y
```

## Current capabilities

- Fixed-width integer types from `Int8` to `UInt64`, and `Boolean`.
- Nominal types, closed records, and variants with payloads.
- Exhaustive, nested pattern matching; unreachable arms are errors.
- Modules with explicit exports and qualified imports.
- Compile-time proof that integer arithmetic fits its type and that
  divisors are nonzero, with exact `cast` and checked `tryCast`
  conversions.
- `requires` and `ensures` contracts on functions, established at compile
  time for a limited fragment, with `white verify` reporting the evidence
  as JSON.
- `white fmt` and `white lint`, and semantic snapshot, query and diff
  commands with machine-readable output.
- A conformance suite derived from the language specification.
- A small demonstration game whose gameplay logic is written in Black and
  loaded by a C host.

## Limitations and status

Black is in active development, and much of its specification is not yet
implemented:

- There is no recursion, partial application, user-defined polymorphism or
  type classes yet, and arbitrary-precision integer types are rejected.
- Effects and handlers, and ownership and borrowing, are reserved in the
  syntax but **not implemented**. Black makes no resource-safety claims
  today.
- The contract grammar is provisional.
- White targets x86-64 Linux only.

The source repository is not public yet. An interactive playground is
planned for this page, and is not available.
