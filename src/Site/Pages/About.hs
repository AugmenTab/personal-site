{-# LANGUAGE DataKinds #-}

-- | The standalone About page, and the biography pieces the homepage's About
-- section shares with it.
module Site.Pages.About
  ( page
  , aboutEmblem
  , aboutLede
  , contactId
  , contactLinks
  ) where

import Data.List.NonEmpty qualified as NEL
import Integer (Positive)

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Types qualified as HTML
import Brigid.Types qualified as B

import Site.Assets qualified as Asset
import Site.Components (pageHeading)
import Site.Page (Layout (..), Page (..), SiteConfig, sectionTitle)
import Site.Routes (Route (About), elementId)

page :: SiteConfig -> Page
page config =
  Page
    { pageRoute = About
    , pageTitle = sectionTitle config "About"
    , pageDescription = "About Tyler Baum, a software engineer who designs programming languages and builds the libraries and tools around them."
    , pageLayout = Interior
    , pageMain =
        [ E.section [ A.class_ "about", A.aria_labelledby (NEL.singleton titleId) ]
            [ pageHeading ["section-title--quiet"] titleId "About"
            , E.div [ A.class_ "about__body" ]
                [ aboutEmblem
                , E.div [ A.class_ "about__text" ]
                    [ aboutLede
                    , E.p [ A.class_ "about__note" ]
                        [ E.text "This site is an early design preview of a portfolio in progress." ]
                    , E.h2 [ A.class_ "about__subhead", A.id contactId ] [ E.text "Contact" ]
                    , contactLinks
                    ]
                ]
            ]
        ]
    }
  where
    titleId = elementId "about-title"

-- | The tree-and-eclipse emblem: a symbolic accompaniment to the biography
-- (Baum = tree). Decorative; the monogram remains the personal signature.
aboutEmblem :: E.ValidChild E.Division parent grandparent => E.ChildHTML parent grandparent
aboutEmblem =
  E.div [ A.class_ "about__emblem", A.aria_hidden True ]
    [ E.img
        [ A.class_ "about__tree"
        , A.src (Asset.assetUrl Asset.aboutTree)
        , A.alt ""
        , A.width (680 :: Positive)
        , A.height (696 :: Positive)
        , A.loading HTML.Lazy
        , A.decoding HTML.DecodeAsync
        ]
    ]

-- | DRAFT biography.
aboutLede :: E.ValidChild E.Paragraph parent grandparent => E.ChildHTML parent grandparent
aboutLede =
  E.p [ A.class_ "about__lede" ]
    [ E.text "I design programming languages and build the libraries and tools around them, with a bias toward correctness that stays practical." ]

-- | Target of the navigation's Contact link (on the About page) and of the
-- homepage's in-page contact heading.
contactId :: B.Id
contactId = elementId "contact"

contactLinks :: E.ValidChild E.UnorderedList parent grandparent => E.ChildHTML parent grandparent
contactLinks =
  E.ul [ A.class_ "about__links" ]
    [ E.li []
        [ E.a [ A.href (B.mkRawURL "https://github.com/AugmenTab") ] [ E.text "GitHub" ] ]
    ]
