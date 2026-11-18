{-# LANGUAGE DataKinds #-}

-- | The About page: the personal profile (Phase 05).
--
-- About introduces the person; Contact (a section of the homepage, linked
-- from every page as @/#contact@) lists the ways to reach them. The two no
-- longer share a page or a section. About keeps the tree-and-eclipse
-- emblem, which appears nowhere else on the site.
--
-- The owner-approved About copy is a lede plus three prose paragraphs:
-- no repeated résumé, project list, or invented biographical details.
module Site.Pages.About
  ( page
  , Profile (..)
  , profile
  , aboutTitleId
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
import Site.Pages.Home (CopyStatus (..))
import Site.Routes (Route (About, Home), contactId, elementId, routeFragmentUrl)

-- | The owner's approved personal introduction.
data Profile =
  Profile
    { profileStatus :: CopyStatus
    , profileLede :: T.Text
    , profileParagraphs :: [T.Text]
    }

profile :: Profile
profile =
  Profile
    { profileStatus = FinalCopy
    , profileLede = "I've never had much success keeping my interests in separate boxes. I compose music—usually somewhere on the heavier and more experimental end of things—build fictional worlds, and get absorbed in subjects ranging from language and history to game design. A simple idea rarely stays simple for long. I can spend an unreasonable amount of time working out the implications of a detail that might never make it into the finished product."
    , profileParagraphs =
        [ "Software engineering is one of the places that curiosity has taken me. I enjoy understanding how things work, finding the assumptions they're built on, and occasionally questioning whether the whole approach makes sense in the first place. I have a particular fondness for unusual tools and programming languages, especially when they offer a genuinely different way of thinking about a problem."
        , "I'm fascinated by how much a single person can create with the right tools. Advances in AI have made that question considerably more interesting, and I've become increasingly interested in what it means to build software with autonomous systems rather than merely use them for assistance. There are enormous possibilities there, alongside some difficult questions about trust, responsibility, and knowing when something is actually finished."
        , "I'm quite comfortable starting a project without knowing exactly how I'll solve it. Sometimes that leads somewhere worthwhile. Other times I discover that the thing I wanted to make requires building three other things first. I've yet to find that particularly discouraging."
        ]
    }

page :: SiteConfig -> Page
page config =
  Page
    { pageRoute = About
    , pageTitle = sectionTitle config "About"
    , pageDescription = "About Tyler Baum, a software engineer working on programming languages, AI-assisted development, simulation and creative technical tools."
    , pageLayout = Interior
    , pageMain =
        [ E.section [ A.class_ "about about--profile", A.aria_labelledby (NEL.singleton aboutTitleId) ]
            [ pageHeading ["section-title--quiet"] aboutTitleId "About"
            , E.div [ A.class_ "about__body" ]
                [ aboutEmblem
                , E.div [ A.class_ "about__text" ]
                    ( [ E.p [ A.class_ "about__lede" ] [ E.text (profileLede profile) ] ]
                        <> [ E.p [ A.class_ "about__bio" ] [ E.text p ] | p <- profileParagraphs profile ]
                        <> [ E.p [ A.class_ "about__onward" ]
                               [ E.a [ A.href (routeFragmentUrl Home contactId) ]
                                   [ E.text "Get in touch"
                                   , E.span [ A.class_ "about__onward-arrow", A.aria_hidden True ] [ E.text " →" ]
                                   ]
                               ]
                           ]
                    )
                ]
            ]
        ]
    }

aboutTitleId :: B.Id
aboutTitleId = elementId "about-title"

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
        , A.decoding HTML.DecodeAsync
        ]
    ]
