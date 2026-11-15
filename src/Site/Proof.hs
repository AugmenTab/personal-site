{-# LANGUAGE DataKinds #-}

-- | The Phase 00 visual proof: one page rendered with Brigid.
--
-- Header + navigation, the cinematic hero, the transition into Selected Work,
-- one finished project card, and the About/Contact anchor the calls to action
-- point at. All copy is real HTML text; artwork is decorative and hidden from
-- assistive technology.
--
-- Copy marked DRAFT is placeholder editorial text awaiting owner review.
module Site.Proof
  ( homePage
  , renderHomePage
  ) where

import Data.ByteString.Lazy qualified as LBS
import Data.List.NonEmpty qualified as NEL
import Data.NonEmptyText qualified as NET
import Data.Text qualified as T
import Integer (Positive)
import Ogma qualified

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Elements.Safe qualified as Safe
import Brigid.HTML.Render.ByteString (renderLazyHTML)
import Brigid.HTML.Types qualified as HTML
import Brigid.Types qualified as B

import Site.Assets qualified as Asset

renderHomePage :: LBS.ByteString
renderHomePage = renderLazyHTML homePage

homePage :: E.HTML
homePage =
  E.html [ A.lang (Just (Ogma.simpleBCP_47 Ogma.English)) ]
    [ E.head [] headContent
    , E.body [ A.class_ "page" ]
        [ E.a [ A.class_ "skip-link", A.href mainId ] [ E.text "Skip to content" ]
        , siteHeader
        , E.main [ A.id mainId ]
            [ stage
            , selectedWork
            , aboutSection
            ]
        , siteFooter
        ]
    ]

headContent :: [E.ChildHTML E.Head E.Html]
headContent =
  [ Safe.meta Safe.Charset
  , E.meta [ A.name HTML.Viewport, A.content "width=device-width, initial-scale=1" ]
  , E.title [] [ E.text "Tyler Baum — Software Engineer" ]
  , E.meta
      [ A.name HTML.Description
      , A.content "Tyler Baum builds precise systems: programming languages, libraries, and tools."
      ]
  , Safe.meta . Safe.Name . Safe.ColorScheme . Safe.Palettes $ NEL.singleton Safe.Dark
  , E.link
      [ A.rel HTML.Rel_Icon
      , A.href (Asset.assetUrl Asset.favicon)
      , A.type_ (HTML.mkRawTypeOption "image/svg+xml")
      ]
  , E.link
      [ A.rel HTML.Rel_Stylesheet
      , A.href (Asset.assetUrl Asset.stylesheet)
      ]
  ]

--------------------------------------------------------------------------------
-- Header

siteHeader :: E.ChildHTML E.Body grandparent
siteHeader =
  E.header [ A.class_ "site-header" ]
    [ E.nav [ A.class_ "site-nav", A.aria_label "Primary" ]
        [ E.ul [ A.class_ "site-nav__list site-nav__list--start" ]
            [ navItem True topId "Home"
            , navItem False selectedWorkId "Work"
            ]
        , E.a [ A.class_ "site-nav__mark", A.href topId, A.aria_label "Tyler Baum — home" ]
            [ decorativeImage "site-nav__mark-img" Asset.monogramSimple 66 42 ]
        , E.ul [ A.class_ "site-nav__list site-nav__list--end" ]
            [ navItem False aboutId "About"
            , navItem False contactId "Contact"
            ]
        ]
    ]

navItem :: Bool -> B.Id -> T.Text -> E.ChildHTML E.UnorderedList grandparent
navItem current target label =
  E.li [ A.class_ "site-nav__item" ]
    [ E.a ( [ A.class_ "site-nav__link", A.href target ]
            <> [ A.aria_current HTML.CurrentPage | current ]
          )
        [ E.text label ]
    ]

--------------------------------------------------------------------------------
-- Hero

-- | The opening "stage": the approved render's artwork (eclipse, cloud banks,
-- both architectural clusters, corner fans), reconstructed with all text and
-- UI removed and cut into three feathered plates. At 1100px and wider they
-- tile back into the original composition; narrower, the side plates slide
-- inward. One art layer sits behind both the hero and the Black teaser.
stage :: E.ChildHTML E.Main grandparent
stage =
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
    , hero
    , blackFeature
    ]

hero :: E.ChildHTML E.Division grandparent
hero =
  E.section [ A.class_ "hero", A.id topId, A.aria_labelledby (NEL.singleton heroTitleId) ]
    [ E.div [ A.class_ "hero__content" ]
        [ E.p [ A.class_ "hero__role" ] [ E.text "Software Engineer" ]
        , E.h1 [ A.class_ "hero__name", A.id heroTitleId ]
            [ E.span [ A.class_ "hero__name-word" ] [ E.text "Tyler" ]
            , E.text " "
            , E.span [ A.class_ "hero__name-word" ] [ E.text "Baum" ]
            ]
        , -- Art Deco rule with a central diamond (CSS); the monogram appears
          -- only in the navigation medallion.
          E.div [ A.class_ "hero__divider", A.aria_hidden True ]
            [ E.span [ A.class_ "hero__divider-diamond" ] [] ]
        , -- DRAFT thesis, taken from the approved homepage render.
          E.p [ A.class_ "hero__thesis" ]
            [ E.text "Building precise systems for ambitious ideas." ]
        , E.ul [ A.class_ "hero__disciplines", A.aria_label "Areas of work" ]
            [ E.li [] [ E.text "Language design" ]
            , E.li [] [ E.text "Systems engineering" ]
            , E.li [] [ E.text "Audio technology" ]
            , E.li [] [ E.text "Simulation" ]
            ]
        , E.div [ A.class_ "hero__actions" ]
            [ E.a [ A.class_ "button button--primary", A.href selectedWorkId ]
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

selectedWork :: E.ChildHTML E.Main grandparent
selectedWork =
  E.section [ A.class_ "work", A.id selectedWorkId, A.aria_labelledby (NEL.singleton workTitleId) ]
    [ E.h2 [ A.class_ "section-title", A.id workTitleId ]
        [ E.span [ A.class_ "section-title__text" ] [ E.text "Selected Work" ] ]
    , E.ul [ A.class_ "work__list" ]
        [ E.li [ A.class_ "work__item" ] [ brigidCard ] ]
    ]

brigidCard :: E.ChildHTML E.ListItem grandparent
brigidCard =
  E.article [ A.class_ "project-card", A.aria_labelledby (NEL.singleton brigidTitleId) ]
    [ E.div [ A.class_ "project-card__visual", A.aria_hidden True ]
        [ decorativeImage "project-card__art" Asset.cardBrigid 360 360 ]
    , E.div [ A.class_ "project-card__body" ]
        [ E.p [ A.class_ "project-card__kicker" ] [ E.text "Haskell library · In development" ]
        , E.h3 [ A.class_ "project-card__title", A.id brigidTitleId ] [ E.text "Brigid" ]
        , E.p [ A.class_ "project-card__summary" ]
            [ E.text "Type-safe, (mostly) spec-compliant HTML for Haskell. This page is rendered with it." ]
        , E.div [ A.class_ "project-card__footer" ]
            [ E.ul [ A.class_ "project-card__tags", A.aria_label "Topics" ]
                [ E.li [] [ E.text "Haskell" ]
                , E.li [] [ E.text "HTML" ]
                , E.li [] [ E.text "Type safety" ]
                ]
            , -- The card's single link; CSS stretches its hit area over the card.
              E.a
                [ A.class_ "project-card__link"
                , A.href (B.mkRawURL "https://github.com/AugmenTab/brigid")
                ]
                [ E.text "View source"
                , E.span [ A.class_ "visually-hidden" ] [ E.text " of Brigid on GitHub" ]
                , E.span [ A.class_ "project-card__arrow", A.aria_hidden True ] [ E.text "→" ]
                ]
            ]
        ]
    ]

--------------------------------------------------------------------------------
-- About / contact (target of the secondary call to action)

aboutSection :: E.ChildHTML E.Main grandparent
aboutSection =
  E.section [ A.class_ "about", A.id aboutId, A.aria_labelledby (NEL.singleton aboutTitleId) ]
    [ E.h2 [ A.class_ "section-title section-title--quiet", A.id aboutTitleId ]
        [ E.span [ A.class_ "section-title__text" ] [ E.text "About" ] ]
    , E.div [ A.class_ "about__body" ]
        [ -- The tree-and-eclipse emblem: a symbolic accompaniment to the
          -- biography (Baum = tree). Decorative; the monogram remains the
          -- personal signature.
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
        , E.div [ A.class_ "about__text" ]
            [ -- DRAFT biography.
              E.p [ A.class_ "about__lede" ]
                [ E.text "I design programming languages and build the libraries and tools around them, with a bias toward correctness that stays practical." ]
            , E.p [ A.class_ "about__note" ]
                [ E.text "This page is an early design preview of a portfolio in progress." ]
            , E.h3 [ A.class_ "about__subhead", A.id contactId ] [ E.text "Contact" ]
            , E.ul [ A.class_ "about__links" ]
                [ E.li []
                    [ E.a [ A.href (B.mkRawURL "https://github.com/AugmenTab") ]
                        [ E.text "GitHub" ]
                    ]
                ]
            ]
        ]
    ]

--------------------------------------------------------------------------------
-- Footer

siteFooter :: E.ChildHTML E.Body grandparent
siteFooter =
  E.footer [ A.class_ "site-footer" ]
    [ E.span [ A.class_ "site-footer__ornament", A.aria_hidden True ] []
    , E.p [] [ E.text "Tyler Baum" ]
    ]

--------------------------------------------------------------------------------
-- Helpers

decorativeImage :: E.ValidChild E.Image parent grandparent
                => HTML.Class -> Asset.Asset -> Positive -> Positive -> E.ChildHTML parent grandparent
decorativeImage cls asset w h =
  E.img
    [ A.class_ cls
    , A.src (Asset.assetUrl asset)
    , A.alt ""
    , A.width w
    , A.height h
    , A.decoding HTML.DecodeAsync
    ]

mainId, topId, heroTitleId, blackId, blackTitleId, selectedWorkId, workTitleId, brigidTitleId, aboutId, aboutTitleId, contactId :: B.Id
mainId = elementId "main"
topId = elementId "top"
heroTitleId = elementId "hero-title"
blackId = elementId "black"
blackTitleId = elementId "black-title"
selectedWorkId = elementId "selected-work"
workTitleId = elementId "work-title"
brigidTitleId = elementId "brigid-title"
aboutId = elementId "about"
aboutTitleId = elementId "about-title"
contactId = elementId "contact"

-- | Element ids are compile-time constants; an empty one is a programming
-- error that the smoke tests would surface immediately.
elementId :: T.Text -> B.Id
elementId txt =
  case NET.fromText txt of
    Just net -> B.Id net
    Nothing -> error "elementId: empty id"
