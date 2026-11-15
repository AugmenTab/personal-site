{-# LANGUAGE DataKinds #-}

-- | The standalone About page, and the biography pieces the homepage's About
-- section shares with it.
module Site.Pages.About
  ( page
  , aboutEmblem
  , aboutLede
  , biography
  , ContactLink (..)
  , contacts
  , contactId
  , contactLinks
  ) where

import Data.List.NonEmpty qualified as NEL
import Data.Text qualified as T
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
    , pageDescription = "About Tyler Baum, a software engineer working on programming languages, AI-assisted development, simulation and creative technical tools."
    , pageLayout = Interior
    , pageMain =
        [ E.section [ A.class_ "about", A.aria_labelledby (NEL.singleton titleId) ]
            [ pageHeading ["section-title--quiet"] titleId "About"
            , E.div [ A.class_ "about__body" ]
                [ aboutEmblem
                , E.div [ A.class_ "about__text" ]
                    ( aboutLede
                        <> [ E.h2 [ A.class_ "about__subhead", A.id contactId ] [ E.text "Contact" ]
                           , contactLinks
                           ]
                    )
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

-- | DRAFT biography (Phase 03 revision), for owner review. The first
-- paragraph is the lede; the rest is quieter. An introduction, not a
-- professional history.
biography :: [T.Text]
biography =
  [ "I’m a software engineer who builds the precise foundations that ambitious work depends on."
  , "My work spans programming languages and type systems, AI-assisted development, simulation and game technology, and tools for creative work. What connects it is a preference for systems whose behaviour can be understood, checked and trusted."
  , "This site is a portfolio in progress."
  ]

aboutLede :: E.ValidChild E.Paragraph parent grandparent => [E.ChildHTML parent grandparent]
aboutLede =
  zipWith paragraph [0 :: Int ..] biography
  where
    paragraph i text = E.p [ A.class_ (classFor i) ] [ E.text text ]
    classFor i
      | i == 0 = "about__lede"
      | i == length biography - 1 = "about__note"
      | otherwise = "about__bio"

-- | Target of the navigation's Contact link (on the About page) and of the
-- homepage's in-page contact heading.
contactId :: B.Id
contactId = elementId "contact"

-- | A verified contact destination. Only destinations confirmed by the owner
-- belong here; a missing one is simply left out (README "Homepage copy").
data ContactLink =
  ContactLink
    { contactLabel :: T.Text
    , contactDisplay :: T.Text
      -- ^ The destination as shown, e.g. @github.com/AugmenTab@.
    , contactUrl :: T.Text
      -- ^ @https://@ only.
    }

contacts :: [ContactLink]
contacts =
  [ ContactLink "GitHub" "github.com/AugmenTab" "https://github.com/AugmenTab"
  ]

contactLinks :: E.ValidChild E.UnorderedList parent grandparent => E.ChildHTML parent grandparent
contactLinks =
  E.ul [ A.class_ "about__links" ] (map link contacts)
  where
    link c =
      E.li [ A.class_ "about__link" ]
        [ E.a [ A.href (B.mkRawURL (contactUrl c)) ]
            [ E.span [ A.class_ "about__link-label" ] [ E.text (contactLabel c) ]
            , E.span [ A.class_ "about__link-display" ] [ E.text (contactDisplay c) ]
            ]
        ]
