{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}

-- | Validated Markdown ("Site.Content.Markdown") rendered as Brigid
-- elements. This is the structured rendering boundary: there is no HTML
-- string, no raw fragment and no unescaped text anywhere in this module.
-- Every node becomes a typed Brigid element, text goes through 'E.text'
-- (escaped by Brigid), and URLs have already passed the Markdown URL
-- policy. The output then goes through the same page validation as
-- everything else (internal links and fragments must resolve).
module Site.Content.Render
  ( MediaUrl
  , PhrasingParent
  , InlineParent
  , BlockParent
  , renderPhrasing
  , renderInlines
  , renderBlocks
  ) where

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Types qualified as HTML
import Brigid.Types qualified as B

import Site.Content.Markdown (Block (..), Inline (..), LinkTarget (..), inlineText)
import Site.Path (OutputPath)
import Site.Routes (elementId)

-- | Where a content item's media file is published.
type MediaUrl = OutputPath -> B.RawURL

-- | Elements that may hold Markdown phrasing content without links (the
-- inside of emphasis and of headings: Brigid does not accept @<a>@ there,
-- so the Markdown validator rejects links in those positions).
type PhrasingParent parent grandparent =
  ( E.ValidChild E.Text parent grandparent
  , E.ValidChild E.Emphasis parent grandparent
  , E.ValidChild E.Strong parent grandparent
  , E.ValidChild E.Code parent grandparent
  , E.ValidChild E.Image parent grandparent
  , E.ValidChild E.LineBreak parent grandparent
  )

-- | Elements that may hold Markdown inline content including links
-- (paragraphs and list items).
type InlineParent parent grandparent =
  ( PhrasingParent parent grandparent
  , E.ValidChild E.Anchor parent grandparent
  , E.ValidChild E.Text E.Anchor parent
  )

-- | Elements that may hold Markdown block content.
type BlockParent parent grandparent =
  ( E.ValidChild E.Paragraph parent grandparent
  , E.ValidChild E.H3 parent grandparent
  , E.ValidChild E.H4 parent grandparent
  , E.ValidChild E.UnorderedList parent grandparent
  , E.ValidChild E.OrderedList parent grandparent
  , E.ValidChild E.Blockquote parent grandparent
  , E.ValidChild E.PreformattedText parent grandparent
  , E.ValidChild E.HorizontalRule parent grandparent
  )

-- | Inline content where links are allowed.
renderInlines :: InlineParent parent grandparent => MediaUrl -> [Inline] -> [E.ChildHTML parent grandparent]
renderInlines media = concatMap inline
  where
    inline i =
      case i of
        -- Link text is rendered as plain text: formatting inside links is
        -- not supported (and images inside links are rejected earlier).
        Link target xs ->
          [ E.a [ A.href (linkUrl target) ] [ E.text (inlineText xs) ] ]
        other -> renderPhrasing media [ other ]

-- | Inline content without links. The validator guarantees there are none
-- here; a link that somehow arrived would be rendered as its plain text.
renderPhrasing :: PhrasingParent parent grandparent => MediaUrl -> [Inline] -> [E.ChildHTML parent grandparent]
renderPhrasing media = concatMap inline
  where
    inline i =
      case i of
        Str t -> [ E.text t ]
        SoftBreak -> [ E.text "\n" ]
        LineBreak -> [ E.br [] ]
        Emph xs -> [ E.em [] (renderPhrasing media xs) ]
        Strong xs -> [ E.strong [] (renderPhrasing media xs) ]
        Code t -> [ E.code [] [ E.text t ] ]
        Link _ xs -> [ E.text (inlineText xs) ]
        Image path alt ->
          [ E.img
              [ A.src (media path)
              , A.alt alt
              , A.loading HTML.Lazy
              , A.decoding HTML.DecodeAsync
              ]
          ]

linkUrl :: LinkTarget -> B.RawURL
linkUrl target =
  B.mkRawURL $
    case target of
      External url -> url
      SitePath path -> path
      Fragment fragment -> "#" <> fragment

renderBlocks :: BlockParent parent grandparent => MediaUrl -> [Block] -> [E.ChildHTML parent grandparent]
renderBlocks media = concatMap block
  where
    block b =
      case b of
        Para xs -> [ E.p [] (renderInlines media xs) ]
        Plain xs -> [ E.p [] (renderInlines media xs) ]
        Heading 3 ident xs -> [ E.h3 [ A.id (elementId ident) ] (renderPhrasing media xs) ]
        Heading _ ident xs -> [ E.h4 [ A.id (elementId ident) ] (renderPhrasing media xs) ]
        BulletList items -> [ E.ul [] (map (E.li [] . item) items) ]
        OrderedList _ items -> [ E.ol [] (map (E.li [] . item) items) ]
        Quote bs -> [ E.blockquote [] (renderBlocks media bs) ]
        CodeBlock language code ->
          [ E.pre [ A.class_ "code-block" ]
              [ E.code (maybe [] (\l -> [ A.class_ (HTML.Class ("language-" <> l)) ]) language)
                  [ E.text code ]
              ]
          ]
        Rule -> [ E.hr [] ]

    -- A tight list item's text renders without a paragraph.
    item :: [Block] -> [E.ChildHTML E.ListItem p]
    item = concatMap itemPart
      where
        itemPart b =
          case b of
            Plain xs -> renderInlines media xs
            other -> renderBlocks media [ other ]
