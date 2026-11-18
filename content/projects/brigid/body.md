## Overview

Brigid is a Haskell library for constructing HTML as typed values, with the
compiler checking where elements and attributes are permitted. Rather than
allowing arbitrary markup and leaving the browser to repair mistakes, Brigid
encodes much of HTML's content model into Haskell's type system.

Its rules account for both parent and grandparent elements, allowing
context-sensitive behavior such as transparent content. Attribute values can
also be strongly typed, including URLs, language tags, integrity hashes, and
HTMX interactions.

Brigid is used to generate this website. Every page, including this one, is
assembled as typed Haskell markup and rendered to HTML.

The library is in active development, with separate packages for document
construction and property-based generation.

## Motivation

HTML is remarkably forgiving. Browsers routinely repair invalid nesting, and
most HTML construction libraries allow developers to assemble structures that
the specification doesn't permit.

That flexibility is convenient, but it means structural mistakes may go
unnoticed until the browser interprets the resulting document.

Brigid takes a different approach: encode the document's structural rules
into the types of its constructors, so invalid combinations can be rejected
during compilation.

The goal isn't merely to produce HTML from Haskell. It's to make the compiler
understand enough about HTML to catch mistakes before they reach the browser.

## How the types work

Brigid represents HTML elements using a GADT indexed by their parent and
grandparent types. A type family determines which elements may appear in each
context, using type-level representations of HTML content categories.

This allows rules such as excluding nested forms, restricting interactive
content inside buttons, and accounting for transparent elements like anchors.

Attributes are similarly indexed by the elements on which they are permitted.
Many values have dedicated types rather than being arbitrary strings.

For example, Brigid can distinguish between HTTP methods at the type level.
When constructing an HTMX request, the URL's method determines whether the
resulting attribute is `hx-get`, `hx-post`, or another supported operation.

The accompanying code excerpt is taken directly from this website. It renders
the facts in this project's overview, using a function whose type constrains
where the resulting description list may appear.

## Caught at compile time

When Brigid encounters a forbidden element or attribute combination, GHC
reports a custom error identifying the invalid relationship.

For example, a division element cannot be placed directly inside an
unordered list: that list requires list items. The exhibit contrasts a valid
list item with the rejected division, followed by the GHC diagnostic
reproduced during the November 2026 project audit.

The same mechanism rejects nested anchors and element-specific attributes
applied to the wrong elements.

This is compile-time checking of Brigid's encoded content rules, not a claim
that the library models every requirement of the HTML specification.

## What the types buy

- **Checked content models.** Element constructors enforce parent-child
  relationships using type-level HTML content categories. Forbidden
  combinations become compilation errors.
- **Context-sensitive nesting.** By tracking both parent and grandparent
  types, Brigid can enforce context-dependent rules for transparent elements
  such as anchors, within the ancestry depth it currently supports.
- **Readable diagnostics.** Custom GHC errors identify invalid elements and
  attributes by name instead of presenting an opaque type mismatch.
- **Typed attributes.** URLs, language tags, colors, HTTP methods,
  autocomplete tokens, and integrity hashes can be represented by
  domain-specific types.
- **HTMX integration.** Typed routing and structured triggers, targets, and
  swaps provide a Haskell interface to HTMX's browser interactions.
- **Escaping at the rendering boundary.** Normal HTML text and quoted
  attribute values are escaped during serialization, with regression tests
  for injection payloads and Unicode handling. Raw-content and custom-element
  paths have separate limitations.
- **Documents as Haskell values.** Pages can be composed, transformed, and
  reused through ordinary Haskell functions, then rendered to `ByteString`,
  `Text`, or `String`.
- **Generated test documents.** A companion package uses Hedgehog to
  construct randomized documents and check their conversion against Brigid's
  typed content model.
- **Hyperview XML.** Brigid also contains a partial HXML implementation for
  server-driven mobile interfaces, using a related approach to typed elements
  and attributes.

## Status and limitations

Brigid is a public, BSD-3-Clause-licensed project in active development.
Its API is not yet stable.

At the audited revision, the GHC 9.10 test run passed 735 core tests and 266
generator tests. Representative invalid nesting and attribute combinations
were also independently reproduced as compile-time failures.

The implementation has several important limitations:

- Content-model checks do not enforce every HTML rule, including required
  attributes, child ordering, cardinality, and context beyond the supported
  ancestor depth.
- Some encoded rules reject otherwise valid HTML, and explicit escape hatches
  can bypass structural checks.
- SVG support is limited to a small set of elements; MathML and general XML
  support remain planned.
- HXML rendering is incomplete and has known escaping and serialization
  defects.
- HTML comments, custom element names, and raw script/style content also
  require additional safety work.
- Historical benchmarks indicate rendering is slower than blaze-html and
  lucid, but the existing measurements have methodology and reproducibility
  limitations. No reliable current performance comparison is established.
- There is no published Hackage release or CI pipeline yet.

Brigid currently prioritizes expressive typed construction and
specification-aware correctness. Broader coverage, rendering safety, API
stabilization, and performance remain active development areas.

## Resources

- [Source code on GitHub](https://github.com/AugmenTab/brigid)
- Licensed under BSD-3-Clause.
- This site uses Brigid's core library, pinned at commit `e0f4d45`.
- The repository includes the `brigid-generation` companion package,
  conformance-oriented tests, and rendering benchmarks.
