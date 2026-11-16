{-# LANGUAGE DataKinds #-}

-- | The About page: the personal profile (Phase 05).
--
-- About introduces the person; Contact (a section of the homepage, linked
-- from every page as @/#contact@) lists the ways to reach them. The two no
-- longer share a page or a section. About keeps the tree-and-eclipse
-- emblem, which appears nowhere else on the site.
--
-- The profile's copy is the owner's verified Phase 03 biography, arranged
-- as a lede, titled sections and a closing note. It is draft copy awaiting
-- the owner's content pass: nothing here may invent biographical facts.
-- More sections (background, motivations) slot into 'profileSections'
-- when the owner supplies them.
module Site.Pages.About
  ( page
  , Profile (..)
  , ProfileSection (..)
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
import Site.Pages.Home (CopyStatus (..), Introduction (..), introduction)
import Site.Routes (Route (About, Home), contactId, elementId, routeFragmentUrl)

-- | The profile's copy.
data Profile =
  Profile
    { profileStatus :: CopyStatus
    , profileLede :: T.Text
    , profileSections :: [ProfileSection]
    , profileNote :: T.Text
    }

-- | A titled part of the profile.
data ProfileSection =
  ProfileSection
    { profileSectionId :: T.Text
    , profileSectionHeading :: T.Text
    , profileSectionParagraphs :: [T.Text]
    , profileSectionList :: [T.Text]
      -- ^ An optional short list after the paragraphs.
    }

-- | DRAFT: the Phase 03 biography (verified), for the owner's content
-- pass. The areas of focus are the homepage's disciplines, so the two
-- cannot drift apart.
profile :: Profile
profile =
  Profile
    { profileStatus = DraftCopy
    , profileLede = "I’m a software engineer who builds the precise foundations that ambitious work depends on."
    , profileSections =
        [ ProfileSection
            { profileSectionId = "work-and-interests"
            , profileSectionHeading = "Work and interests"
            , profileSectionParagraphs =
                [ "My work spans programming languages and type systems, AI-assisted development, simulation and game technology, and tools for creative work. What connects it is a preference for systems whose behaviour can be understood, checked and trusted." ]
            , profileSectionList = introDisciplines introduction
            }
        ]
    , profileNote = "This site is a portfolio in progress."
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
                        <> concatMap profileSection (profileSections profile)
                        <> [ E.p [ A.class_ "about__note" ] [ E.text (profileNote profile) ]
                           , E.p [ A.class_ "about__onward" ]
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

profileSection :: ProfileSection -> [E.ChildHTML E.Division grandparent]
profileSection s =
  [ E.h2 [ A.class_ "about__subhead", A.id sid ] [ E.text (profileSectionHeading s) ] ]
    <> [ E.p [ A.class_ "about__bio" ] [ E.text p ] | p <- profileSectionParagraphs s ]
    <> [ E.ul [ A.class_ "about__list", A.aria_labelledby (NEL.singleton sid) ]
           [ E.li [] [ E.text item ] | item <- profileSectionList s ]
       | not (null (profileSectionList s))
       ]
  where
    sid = elementId (profileSectionId s)

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
