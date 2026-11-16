## Overview

Brigid is a Haskell library for constructing and rendering HTML, and HXML,
with the structure of the document checked by the type system. Its own
description is “type-safe and (mostly) spec-compliant HTML”.

This site is its first portfolio-scale user: every page here is generated
by a small Haskell program that builds its markup with Brigid, including
this page, whose text is written in Markdown and converted into Brigid
elements.

## Motivation

HTML is forgiving. A browser repairs a misplaced element instead of
reporting it, so markup assembled from strings, or from combinators that do
not track which element may contain which, can be wrong without anything
failing.

Brigid moves those mistakes to the compiler. A document that places an
element where the library’s rules do not allow it is not a document that
renders badly; it is a program that does not compile.

## How the types work

Each element states which children it may contain, through a constraint
on its parent. A function that builds part of a page says where that part
may go, and the compiler checks every place it is used.

The excerpt is verbatim from this site’s source: it renders the small
cluster of facts in this page’s overview. Its type says it produces a child
of any element that accepts a description list. Attributes are typed the
same way, so `A.class_` takes a class and an attribute is accepted only on
the elements it applies to.

## Caught at compile time

While this page’s fact cluster was being written, the first version
grouped each label and value in a `<div>`. GHC refused to compile it; its
output, verbatim, is shown here.

This is also the “(mostly)” in the description. HTML allows that grouping
inside a description list, but Brigid’s rules are stricter here than the
specification, so the site was changed to fit them. The comment in the
excerpt above records why.

## What the types buy

- **Valid nesting.** Each element accepts only the children its rules
  allow; anything else is a type error, reported with both element names.
- **Valid attributes.** An attribute is accepted only on elements it
  applies to, with a typed value, such as `A.loading HTML.Lazy` rather
  than a string.
- **Escaping at the boundary.** Text and attribute values are escaped when
  the document is rendered, so content cannot become markup.
- **Documents as values.** A page is an ordinary Haskell value, assembled
  from functions and checked as a whole.
- **Several outputs.** The same document renders to `ByteString`, `Text`
  or `String`.
- **htmx and HXML.** Typed attributes for htmx, and HXML documents
  alongside HTML.

## Status and limitations

Brigid is in active development, and its API is not yet stable.

- The types capture many of the HTML specification’s content rules, not
  yet all of them.
- Some rules are stricter than the specification, as above. A link inside
  emphasis or inside a level-three heading is another example: valid HTML,
  but rejected, so this site’s Markdown rejects those combinations too.
- SVG support is partial (the `svg`, `g` and `path` elements so far), and
  MathML and further “safe” element builders are listed in the project’s
  plans rather than finished.

## Resources

- [Source code and README on GitHub](https://github.com/AugmenTab/brigid)
- The library is released under the BSD-3-Clause licence.
- This site pins Brigid at commit `e0f4d45` and builds only its core
  `brigid` package.
