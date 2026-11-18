## Overview

Black is an AI-first programming language designed to be equally approachable
to human programmers and autonomous coding agents.

Its premise is that AI-native development shouldn't require sacrificing
readable, expressive code. People should still be able to write programs by
hand, understand what agents produce, and take responsibility for the software
they deploy.

White, Black's compiler and developer toolchain, is written in Haskell. It
compiles a working subset of Black to native x86-64 Linux code through LLVM
and provides structured interfaces for inspecting program semantics,
verification evidence, and the consequences of changes.

The language is in active development. Its compiler, verification tools, and
agent-driven demonstrations are operational, while much of its intended type
system and language design remains under construction.

## Design principles

- **Human and agent authorship.** Black favors readable, declarative programs
  and Haskell-inspired syntax. Human programmers aren't an afterthought, even
  when an agent writes the implementation.
- **Canonical source.** White provides a formatter that establishes one
  accepted style. Automatic formatting as part of the complete build workflow
  is planned.
- **Compiler-authoritative semantics.** Agents can inspect types,
  declarations, dependencies, and verification obligations through structured
  compiler interfaces rather than inferring everything from source text.
- **Explicit guarantees.** Static types, contracts, and proof obligations
  establish what the compiler can actually verify. Unresolved obligations
  are not treated as success.
- **Protected requirements.** An agent authorized to modify an implementation
  should not be able to silently weaken the requirements used to judge it.

## The compiler pipeline

White resolves and type-checks Black source, establishes supported arithmetic
and contract obligations, and elaborates the result into a validated Core
representation before emitting LLVM IR.

Ordinary integer operations and exact conversions require static evidence
that their results fit. Function contracts support a limited predicate
language, checked through interval analysis or exhaustive enumeration of small
finite domains.

White currently produces Linux executables and native shared libraries. The
compiler is ahead-of-time; its internal evaluator is used for verification
and testing rather than as a public interpreter.

## A program White accepts

This example from White's conformance suite defines a nominal record type,
updates its fields, and matches the result.

White checks the nominal identity and record operations before compiling the
program. The conformance suite also executes the resulting native code.

## A program White rejects

Here, a function attempts to convert an arbitrary `Int32` into a `UInt8`.

White refuses the conversion because it cannot establish that every possible
input fits the destination type. The `CAST_UNPROVEN` diagnostic identifies the
failed obligation.

When conversion failure is expected, `tryCast` provides an explicit,
recoverable alternative.

## Semantic tooling for agents

White exposes content-addressed semantic snapshots and machine-readable
queries over declarations, types, dependencies, contracts, and verification
results.

An agent can inspect a declaration, identify affected dependencies, compare
revisions, and discover which existing obligations may require fresh
verification.

Structured diagnostics distinguish invalid programs, disproven properties,
and unresolved obligations. The semantic interface can also retain
information from compilation stages that completed before a failure.

## The Protected Change Gate

Black's supporting toolchain includes a prototype authorization system that
separates permission to modify code from permission to change its
requirements.

One adversarial test weakens a protected contract from `ensures s <= 7` to
`ensures s <= 15`.

The altered program verifies against its weakened contract and produces a
byte-for-byte identical native library. The Protected Change Gate
nevertheless rejects it because the protected obligation has changed.

The current prototype uses restricted fixture authority and operating-system
write boundaries. It demonstrates policy-protected changes, not a general
security guarantee against arbitrary malicious agents.

## The Uncheatable Boss

A playable boss encounter demonstrates the compiler and verification system
working together.

Its gameplay logic is written in Black and compiled into a native library.
A C host provides rendering, input, replay, and controlled runtime
replacement.

An AI agent can propose changes to selected attack functions, but the
resulting program must satisfy protected contracts and a finite survivability
requirement across nine attack configurations and 576 admissible starting
states per configuration.

In a recorded session, an agent repaired a deliberately seeded invalid
attack, evaluated the difficulty of its changes, and produced an authorized
replacement. The host installed the new native generation while the game
continued running, preserving its authoritative state.

The resulting session was reproduced through deterministic replay.

## Status and limitations

Black remains an early-stage implementation.

- The release-line compiler supports fixed-width integers, nominal types,
  records, variants, exhaustive matching, modules, and limited contracts.
- General polymorphism, higher-order functions, recursion, type classes,
  and many common data types are not yet implemented.
- Experimental native effect handlers exist on a separate development
  branch. Ownership and borrowing have preliminary static checks but are
  not supported by native compilation.
- White's verification uses restricted analyses, not a general SMT solver
  or proof kernel.
- Semantic tooling and stored-evidence revalidation have known defects and
  coverage limitations under investigation.
- Native hot replacement is enforced by a restricted host and ABI, not by
  language-level ownership guarantees.
- An interactive browser playground is planned but not yet available.

## Resources

- The Black and White source repository is currently private.
- [black-vim](https://github.com/AugmenTab/black-vim) provides Vim and Neovim
  syntax support.
- The code examples are drawn from White's conformance suite.
