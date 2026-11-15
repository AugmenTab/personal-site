{-# LANGUAGE DataKinds #-}

-- | The homepage: the approved Phase 00 design, ported into the shared shell.
--
-- The cinematic stage (hero over the reconstructed artwork, and the static
-- Black teaser), Selected Work, and the About/Contact section. All copy is
-- real HTML text; artwork is decorative and hidden from assistive technology.
--
-- Copy marked DRAFT is placeholder editorial text awaiting owner review.
module Site.Pages.Home
  ( page
  ) where

import Data.List.NonEmpty qualified as NEL
import Data.Text qualified as T
import Integer (Positive)

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Types qualified as HTML
import Brigid.Types qualified as B

import Site.Assets qualified as Asset
import Site.Components (HeadingLevel (..), decorativeImage, projectCard, sectionHeading)
import Site.Page (Layout (..), Page (..), SiteConfig)
import Site.Pages.About (aboutEmblem, aboutLede, contactId, contactLinks)
import Site.Content.Types (Project)
import Site.Routes (Route (Home, WorkIndex), elementId, routeUrl)

-- | The homepage introduction: the one place its copy is maintained. The
-- hero's layout is approved and frozen; only this copy may change.
data Introduction =
  Introduction
    { introRole :: T.Text
    , introGivenName :: T.Text
    , introFamilyName :: T.Text
    , introThesis :: T.Text
      -- ^ DRAFT, taken from the approved homepage render.
    , introDisciplines :: [T.Text]
    }

introduction :: Introduction
introduction =
  Introduction
    { introRole = "Software Engineer"
    , introGivenName = "Tyler"
    , introFamilyName = "Baum"
    , introThesis = "Building precise systems for ambitious ideas."
    , introDisciplines = [ "Language design", "Systems engineering", "Audio technology", "Simulation" ]
    }

-- | The homepage, with the published featured projects (in order) as
-- Selected Work. Without any, the section is left out and the primary call
-- to action leads to the Work index instead.
page :: SiteConfig -> [Project] -> Page
page _config featured =
  Page
    { pageRoute = Home
    , pageTitle = "Tyler Baum — Software Engineer"
    , pageDescription = "Tyler Baum builds precise systems: programming languages, libraries, and tools."
    , pageLayout = Stage
    , pageMain =
        [ stage (not (null featured)) ]
          <> [ selectedWork featured | not (null featured) ]
          <> [ aboutSection ]
    }

--------------------------------------------------------------------------------
-- Hero

-- | The opening "stage": the approved render's artwork (eclipse, cloud banks,
-- both architectural clusters, corner fans), reconstructed with all text and
-- UI removed and cut into three feathered plates. At 1100px and wider they
-- tile back into the original composition; narrower, the side plates slide
-- inward. One art layer sits behind both the hero and the Black teaser.
stage :: Bool -> E.ChildHTML E.Main grandparent
stage hasSelectedWork =
  E.div [ A.class_ "stage" ]
    [ E.div [ A.class_ "stage__art", A.aria_hidden True ]
        [ E.img
            [ A.class_ "stage__plate stage__plate--centre"
            , A.src (Asset.assetUrl Asset.heroPlateCentre)
            , A.alt ""
            , A.width (646 :: Positive)
            , A.height (800 :: Positive)
            , A.fetchpriority HTML.FetchHigh
            ]
        , decorativeImage "stage__plate stage__plate--left" Asset.heroPlateLeft 640 800
        , decorativeImage "stage__plate stage__plate--right" Asset.heroPlateRight 640 800
        , E.div [ A.class_ "stage__veil" ] []
        ]
    , hero hasSelectedWork
    , blackFeature
    ]

hero :: Bool -> E.ChildHTML E.Division grandparent
hero hasSelectedWork =
  E.section [ A.class_ "hero", A.id topId, A.aria_labelledby (NEL.singleton heroTitleId) ]
    [ E.div [ A.class_ "hero__content" ]
        [ E.p [ A.class_ "hero__role" ] [ E.text (introRole introduction) ]
        , E.h1 [ A.class_ "hero__name", A.id heroTitleId ]
            [ E.span [ A.class_ "hero__name-word" ] [ E.text (introGivenName introduction) ]
            , E.text " "
            , E.span [ A.class_ "hero__name-word" ] [ E.text (introFamilyName introduction) ]
            ]
        , -- Art Deco rule with a central diamond (CSS); the monogram appears
          -- only in the navigation medallion.
          E.div [ A.class_ "hero__divider", A.aria_hidden True ]
            [ E.span [ A.class_ "hero__divider-diamond" ] [] ]
        , E.p [ A.class_ "hero__thesis" ] [ E.text (introThesis introduction) ]
        , E.ul [ A.class_ "hero__disciplines", A.aria_label "Areas of work" ]
            (map (\d -> E.li [] [ E.text d ]) (introDisciplines introduction))
        , -- Same-page anchors: both targets are sections of this page (the
          -- primary one falls back to the Work index without Selected Work).
          E.div [ A.class_ "hero__actions" ]
            [ E.a
                [ A.class_ "button button--primary"
                , if hasSelectedWork then A.href selectedWorkId else A.href (routeUrl WorkIndex)
                ]
                [ E.span [ A.class_ "button__label" ] [ E.text "Explore selected work" ] ]
            , E.a [ A.class_ "button button--secondary", A.href aboutId ]
                [ E.span [ A.class_ "button__label" ] [ E.text "About & contact" ] ]
            ]
        ]
    ]

--------------------------------------------------------------------------------
-- Black feature teaser
--
-- A static presentation component only: no editor, no compiler, no output.
-- All copy and the excerpt are DRAFT and need owner verification.

blackFeature :: E.ChildHTML E.Division grandparent
blackFeature =
  E.section [ A.class_ "feature", A.id blackId, A.aria_labelledby (NEL.singleton blackTitleId) ]
    [ E.div [ A.class_ "feature__frame" ]
        [ E.div [ A.class_ "feature__intro" ]
            [ E.p [ A.class_ "feature__kicker" ] [ E.text "Featured project · Programming language" ]
            , E.div [ A.class_ "feature__heading" ]
                [ decorativeImage "feature__emblem" Asset.blackEmblem 64 64
                , E.h2 [ A.class_ "feature__title", A.id blackTitleId ] [ E.text "Black" ]
                ]
            , -- DRAFT description and differentiators, from the approved render.
              E.p [ A.class_ "feature__summary" ]
                [ E.text "A modern, correctness-focused programming language for ambitious systems." ]
            , E.ul [ A.class_ "feature__points" ]
                [ E.li [] [ E.text "Strong static guarantees" ]
                , E.li [] [ E.text "Effect and resource safety" ]
                , E.li [] [ E.text "A foundation for AI-native development" ]
                ]
            , E.p [ A.class_ "feature__status" ]
                [ E.text "Project page and playground in preparation" ]
            ]
        , E.figure [ A.class_ "feature__code" ]
            [ E.div [ A.class_ "feature__code-bar", A.aria_hidden True ]
                [ E.span [ A.class_ "feature__code-file" ] [ E.text "Main" ]
                , E.span [ A.class_ "feature__code-tag" ] [ E.text "Black · experimental" ]
                ]
            , E.pre [ A.class_ "feature__pre" ]
                [ E.code [] (concatMap codeLine blackExcerpt) ]
            , E.figcaption [ A.class_ "feature__caption" ]
                [ E.text "Illustrative excerpt; syntax may change. Nothing is compiled or run on this page." ]
            ]
        ]
    ]

-- | One token of the static excerpt, classified only for colouring.
data Tok = Kw T.Text | Ty T.Text | Num T.Text | Pl T.Text

-- | DRAFT excerpt, transcribed from the approved homepage render. It has not
-- been checked against the Black compiler and must be replaced or verified
-- by the owner before publication.
blackExcerpt :: [[Tok]]
blackExcerpt =
  [ [ Kw "module", Pl " ", Ty "Main" ]
  , []
  , [ Kw "type", Pl " ", Ty "Vec2", Pl " = { x : ", Ty "F64", Pl ", y : ", Ty "F64", Pl " }" ]
  , []
  , [ Kw "fn", Pl " length(v : ", Ty "Vec2", Pl ") : ", Ty "F64", Pl " =" ]
  , [ Pl "    sqrt(v.x * v.x + v.y * v.y)" ]
  , []
  , [ Kw "fn", Pl " main() : ", Ty "IO", Pl " ", Ty "Unit", Pl " =" ]
  , [ Pl "    ", Kw "let", Pl " v = { x = ", Num "3.0", Pl ", y = ", Num "4.0", Pl " }" ]
  , [ Pl "    print(length(v))" ]
  ]

codeLine :: [Tok] -> [E.ChildHTML E.Code grandparent]
codeLine toks =
  [ E.span [ A.class_ "code-line" ] (map tok toks)
  , E.text "\n"
  ]
  where
    tok (Kw t) = E.span [ A.class_ "tok-kw" ] [ E.text t ]
    tok (Ty t) = E.span [ A.class_ "tok-ty" ] [ E.text t ]
    tok (Num t) = E.span [ A.class_ "tok-num" ] [ E.text t ]
    tok (Pl t) = E.text t

--------------------------------------------------------------------------------
-- Selected Work

selectedWork :: [Project] -> E.ChildHTML E.Main grandparent
selectedWork projects =
  E.section [ A.class_ "work", A.id selectedWorkId, A.aria_labelledby (NEL.singleton workTitleId) ]
    [ sectionHeading [] workTitleId "Selected Work"
    , E.ul [ A.class_ "work__list" ]
        (map (\project -> E.li [ A.class_ "work__item" ] [ projectCard Level3 project ]) projects)
    ]

--------------------------------------------------------------------------------
-- About / contact (target of the secondary call to action)

aboutSection :: E.ChildHTML E.Main grandparent
aboutSection =
  E.section [ A.class_ "about", A.id aboutId, A.aria_labelledby (NEL.singleton aboutTitleId) ]
    [ sectionHeading ["section-title--quiet"] aboutTitleId "About"
    , E.div [ A.class_ "about__body" ]
        [ aboutEmblem
        , E.div [ A.class_ "about__text" ]
            [ aboutLede
            , E.p [ A.class_ "about__note" ]
                [ E.text "This page is an early design preview of a portfolio in progress." ]
            , E.h3 [ A.class_ "about__subhead", A.id contactId ] [ E.text "Contact" ]
            , contactLinks
            ]
        ]
    ]

--------------------------------------------------------------------------------
-- Ids

topId, heroTitleId, blackId, blackTitleId, selectedWorkId, workTitleId, aboutId, aboutTitleId :: B.Id
topId = elementId "top"
heroTitleId = elementId "hero-title"
blackId = elementId "black"
blackTitleId = elementId "black-title"
selectedWorkId = elementId "selected-work"
workTitleId = elementId "work-title"
aboutId = elementId "about"
aboutTitleId = elementId "about-title"
