{-# LANGUAGE DataKinds #-}

-- | The homepage: the approved Phase 00 arrival, then a scrolling
-- composition that grows quieter as it goes (Phase 03):
--
-- 1. the cinematic stage: hero and the static Black teaser, over the
--    reconstructed artwork;
-- 2. Selected Work: the remaining featured projects, from content;
-- 3. Engineering Philosophy: a short typographic statement;
-- 4. Writing: recent published articles, only when there are any;
-- 5. Contact (Phase 05): a short invitation and the verified destinations.
--    The personal profile is the About page; the two are separate.
--
-- Everything shown about a project comes from its published content record
-- ("Site.Content.Types"); the only copy kept here is the introduction, the
-- Black teaser's differentiators, the philosophy and the contact invitation.
-- Copy whose 'CopyStatus' is 'DraftCopy' awaits owner review (see README
-- "Homepage copy").
module Site.Pages.Home
  ( -- * The page
    page
  , HomeContent (..)
  , homeContent
    -- * Editorial copy (exported for review and tests)
  , CopyStatus (..)
  , Introduction (..)
  , introduction
  , Philosophy (..)
  , Principle (..)
  , philosophy
  , Teaser (..)
  , blackTeaser
  , tokenText
  , blackSlug
  , blackExample
  , BlackExample (..)
  , writingPreviewLimit
  , ContactCopy (..)
  , contactCopy
  ) where

import Data.Char (isAlpha, isAlphaNum, isDigit, isUpper)
import Data.List (find)
import Data.List.NonEmpty qualified as NEL
import Data.Text qualified as T
import Integer (Positive)

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Types qualified as HTML
import Brigid.Types qualified as B

import Site.Assets qualified as Asset
import Site.Components (HeadingLevel (..), decorativeImage, projectCard, sectionHeading)
import Site.Content.Types
import Site.Page (Layout (..), Page (..), SiteConfig (..))
import Site.Routes (Route (Home, WorkDetail, WorkIndex, WritingArticle, WritingIndex), Slug, contactId, elementId, mkSlug, routeUrl)
import Site.Settings (Settings (..), contactDisplay, contactHref, contactLabel, contacts, ownerSettings)

--------------------------------------------------------------------------------
-- Content

-- | Whether a piece of homepage copy has been approved by the owner.
data CopyStatus = DraftCopy | FinalCopy
  deriving (Eq, Show)

-- | What the homepage shows, derived from the loaded content.
data HomeContent =
  HomeContent
    { homeBlack :: Maybe Project
      -- ^ Black's published record, if there is one: the teaser then links
      -- to its page and shows its development status.
    , homeSelected :: [Project]
      -- ^ Published featured projects in featured order, without the one
      -- the Black teaser already presents.
    , homeArticles :: [Article]
      -- ^ The most recent published articles (at most 'writingPreviewLimit').
    }

-- | The slug of the project the teaser presents.
blackSlug :: Slug
blackSlug = either (error . show) id (mkSlug "black")

-- | How many articles the Writing preview lists.
writingPreviewLimit :: Int
writingPreviewLimit = 3

-- | The homepage's view of the content. Publication filtering and ordering
-- come from "Site.Content.Types"; nothing here re-sorts or re-filters.
homeContent :: Content -> HomeContent
homeContent content =
  HomeContent
    { homeBlack = find ((== blackSlug) . projectSlug) (publishedProjects content)
    , homeSelected = filter ((/= blackSlug) . projectSlug) (featuredProjects content)
    , homeArticles = take writingPreviewLimit (publishedArticles content)
    }

--------------------------------------------------------------------------------
-- The page

page :: SiteConfig -> HomeContent -> Page
page config home =
  Page
    { pageRoute = Home
    , pageTitle = "Tyler Baum — Software Engineer"
    , pageDescription = "Tyler Baum builds precise systems: programming languages, libraries, and tools."
    , pageLayout = Stage
    , pageMain =
        [ stage hasSelectedWork (homeBlack home) ]
          <> [ selectedWork (homeSelected home) | hasSelectedWork ]
          <> [ philosophySection ]
          <> [ writingPreview (homeArticles home) | not (null (homeArticles home)) ]
          <> [ contactSection (siteSettings config) ]
    }
  where
    hasSelectedWork = not (null (homeSelected home))

--------------------------------------------------------------------------------
-- Introduction (hero copy)

-- | The homepage introduction: the one place its copy is maintained. The
-- hero's layout is approved and frozen; only this copy may change.
data Introduction =
  Introduction
    { introStatus :: CopyStatus
    , introRole :: T.Text
    , introGivenName :: T.Text
    , introFamilyName :: T.Text
    , introThesis :: T.Text
      -- ^ Working copy, from the approved homepage render.
    , introDisciplines :: [T.Text]
    }

introduction :: Introduction
introduction =
  Introduction
    { introStatus = DraftCopy
    , introRole = "Software Engineer"
    , introGivenName = "Tyler"
    , introFamilyName = "Baum"
    , introThesis = settingsThesis ownerSettings
    , introDisciplines = [ "Language design", "Systems engineering", "Audio technology", "Simulation" ]
    }

--------------------------------------------------------------------------------
-- Stage: hero and Black teaser

-- | The opening "stage": the approved render's artwork (eclipse, cloud banks,
-- both architectural clusters, corner fans), reconstructed with all text and
-- UI removed and cut into three feathered plates. At 1100px and wider they
-- tile back into the original composition; narrower, the side plates slide
-- inward. One art layer sits behind both the hero and the Black teaser.
stage :: Bool -> Maybe Project -> E.ChildHTML E.Main grandparent
stage hasSelectedWork black =
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
    , blackFeature black
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
        , -- Both targets exist: Selected Work on this page, or the Work index
          -- when there is no Selected Work; Contact is always on this page.
          -- (The secondary label is part of the frozen hero, so it is kept;
          -- since Phase 05 it leads to the Contact section. Relabelling it
          -- is left to the owner.)
          E.div [ A.class_ "hero__actions" ]
            [ E.a
                [ A.class_ "button button--primary"
                , if hasSelectedWork then A.href selectedWorkId else A.href (routeUrl WorkIndex)
                ]
                [ E.span [ A.class_ "button__label" ] [ E.text "Explore selected work" ] ]
            , E.a [ A.class_ "button button--secondary", A.href contactId ]
                [ E.span [ A.class_ "button__label" ] [ E.text "About & contact" ] ]
            ]
        ]
    ]

-- | The Black teaser: a static presentation, never a compiler. No editor,
-- no buttons, no output; the only control is a link to the project page,
-- and only when that page is published.
blackFeature :: Maybe Project -> E.ChildHTML E.Division grandparent
blackFeature black =
  E.section [ A.class_ "feature", A.id blackId, A.aria_labelledby (NEL.singleton blackTitleId) ]
    [ E.div [ A.class_ "feature__frame" ]
        [ E.div [ A.class_ "feature__intro" ]
            ( [ E.p [ A.class_ "feature__kicker" ] [ E.text "Featured project · Programming language" ]
              , E.div [ A.class_ "feature__heading" ]
                  [ decorativeImage "feature__emblem" Asset.blackEmblem 64 64
                  , E.h2 [ A.class_ "feature__title", A.id blackTitleId ] [ E.text "Black" ]
                  ]
              , E.p [ A.class_ "feature__summary" ] [ E.text (teaserSummary blackTeaser) ]
              , E.ul [ A.class_ "feature__points" ]
                  (map (\point -> E.li [] [ E.text point ]) (teaserPoints blackTeaser))
              , E.p [ A.class_ "feature__status" ] [ E.text status ]
              ]
                <> [ E.a [ A.class_ "button button--primary feature__action", A.href (routeUrl (WorkDetail (projectSlug p))) ]
                       [ E.span [ A.class_ "button__label" ] [ E.text "Explore Black" ] ]
                   | Just p <- [black]
                   ]
            )
        , E.figure [ A.class_ "feature__code" ]
            [ E.div [ A.class_ "feature__code-bar", A.aria_hidden True ]
                [ E.span [ A.class_ "feature__code-file" ] [ E.text (exampleFile blackExample) ]
                , E.span [ A.class_ "feature__code-tag" ] [ E.text "Black · accepted by White" ]
                ]
            , E.pre [ A.class_ "feature__pre" ]
                [ E.code [] (concatMap codeLine (map tokenizeLine (T.lines (exampleSource blackExample)))) ]
            , E.figcaption [ A.class_ "feature__caption" ]
                [ E.text "From the compiler’s conformance suite. Shown as text: nothing is compiled or run on this page." ]
            ]
        ]
    ]
  where
    status =
      case black of
        Just p -> developmentLabel (projectDevelopment p) <> " · Playground planned"
        Nothing -> "Project page in preparation"

-- | The teaser's own copy. Each point is an implemented capability of the
-- compiler, verified against its repository (README "Homepage copy").
data Teaser =
  Teaser
    { teaserStatus :: CopyStatus
    , teaserSummary :: T.Text
    , teaserPoints :: [T.Text]
    }

blackTeaser :: Teaser
blackTeaser =
  Teaser
    { teaserStatus = DraftCopy
    , teaserSummary = "A correctness-focused programming language, compiled to native code by its Haskell compiler, White."
    , teaserPoints =
        [ "Closed types and exhaustive matching"
        , "Integer arithmetic proved to fit its types"
        , "Compile-time contracts, for a first fragment"
        ]
    }

-- | A Black program shown verbatim in the teaser.
data BlackExample =
  BlackExample
    { exampleFile :: T.Text
    , exampleProvenance :: T.Text
    , exampleSource :: T.Text
    }

-- | Verified, not illustrative: this is
-- @white/test/conformance/NominalRecord.blk@ from the Black repository
-- (identical on @origin/main@ at @c1a45af@), listed in that suite's
-- MANIFEST as an @accept@ case run on both back ends. Replace it only with
-- another program the compiler accepts.
blackExample :: BlackExample
blackExample =
  BlackExample
    { exampleFile = "NominalRecord.blk"
    , exampleProvenance = "AugmenTab/black@c1a45af:white/test/conformance/NominalRecord.blk (accept)"
    , exampleSource =
        T.unlines
          [ "module NominalRecord"
          , "  ( main"
          , "  )"
          , ""
          , "-- Spec section 7: nominality applies to structural records. Construction,"
          , "-- projection, update and record patterns keep the nominal identity."
          , "nominal type Position = { x :: UInt8, y :: UInt8 }"
          , ""
          , "swap :: Position -> Position"
          , "swap position = position { x = position.y, y = position.x }"
          , ""
          , "main :: UInt8 -> UInt8"
          , "main v ="
          , "  case swap (Position { x = v, y = 9 }) of"
          , "    Position { y } -> y"
          ]
    }

-- | One token of the static excerpt, classified only for colouring.
data Tok = Kw T.Text | Ty T.Text | Num T.Text | Com T.Text | Pl T.Text

-- | A deliberately small lexer for colouring Black source: keywords,
-- capitalised names, numbers and line comments. Everything else is plain,
-- and the concatenated tokens always equal the input line.
tokenizeLine :: T.Text -> [Tok]
tokenizeLine = merge . go
  where
    go t =
      case T.uncons t of
        Nothing -> []
        Just (c, _)
          | "--" `T.isPrefixOf` t -> [Com t]
          | isAlpha c ->
              let (word, rest) = T.span (\x -> isAlphaNum x || x == '_' || x == '\'') t
               in classify word : go rest
          | isDigit c ->
              let (digits, rest) = T.span isDigit t
               in Num digits : go rest
          | otherwise ->
              let (other, rest) = T.break (\x -> isAlpha x || isDigit x || x == '-') (T.drop 1 t)
               in Pl (T.cons c other) : go rest
    classify word
      | word `elem` blackKeywords = Kw word
      | maybe False (isUpper . fst) (T.uncons word) = Ty word
      | otherwise = Pl word
    merge (Pl a : Pl b : rest) = merge (Pl (a <> b) : rest)
    merge (x : rest) = x : merge rest
    merge [] = []

-- | The text the lexer's tokens spell out, line by line. Equal to its input
-- (tested), so colouring can never alter the verified program.
tokenText :: T.Text -> T.Text
tokenText = T.unlines . map (T.concat . map text . tokenizeLine) . T.lines
  where
    text tok =
      case tok of
        Kw t -> t
        Ty t -> t
        Num t -> t
        Com t -> t
        Pl t -> t

-- | Reserved words of Black that the excerpt can contain (White's parser).
blackKeywords :: [T.Text]
blackKeywords = [ "module", "nominal", "type", "case", "of", "let", "in", "where", "import", "as" ]

codeLine :: [Tok] -> [E.ChildHTML E.Code grandparent]
codeLine toks =
  [ E.span [ A.class_ "code-line" ] (map tok toks)
  , E.text "\n"
  ]
  where
    tok (Kw t) = E.span [ A.class_ "tok-kw" ] [ E.text t ]
    tok (Ty t) = E.span [ A.class_ "tok-ty" ] [ E.text t ]
    tok (Num t) = E.span [ A.class_ "tok-num" ] [ E.text t ]
    tok (Com t) = E.span [ A.class_ "tok-com" ] [ E.text t ]
    tok (Pl t) = E.text t

--------------------------------------------------------------------------------
-- Selected Work

selectedWork :: [Project] -> E.ChildHTML E.Main grandparent
selectedWork projects =
  E.section [ A.class_ "work work--home", A.id selectedWorkId, A.aria_labelledby (NEL.singleton workTitleId) ]
    [ sectionHeading [] workTitleId "Selected Work"
    , E.ul [ A.class_ (HTML.Class ("work__list work__list--home work__list--count-" <> T.pack (show (min 3 (length projects))))) ]
        (map (\project -> E.li [ A.class_ "work__item" ] [ projectCard Level3 project ]) projects)
    , E.p [ A.class_ "work__more" ]
        [ E.a [ A.href (routeUrl WorkIndex) ]
            [ E.text "All projects"
            , E.span [ A.class_ "work__more-arrow", A.aria_hidden True ] [ E.text " →" ]
            ]
        ]
    ]

--------------------------------------------------------------------------------
-- Engineering Philosophy

data Principle =
  Principle
    { principleTitle :: T.Text
    , principleText :: T.Text
    }

data Philosophy =
  Philosophy
    { philosophyStatus :: CopyStatus
    , philosophyLabel :: T.Text
    , philosophyHeading :: T.Text
    , philosophyLede :: T.Text
    , philosophyPrinciples :: [Principle]
    }

-- | DRAFT: proposed editorial copy, for owner review before launch.
philosophy :: Philosophy
philosophy =
  Philosophy
    { philosophyStatus = DraftCopy
    , philosophyLabel = "Engineering philosophy"
    , philosophyHeading = "Correctness enables creativity."
    , philosophyLede = "The more a tool can check for me, the further I can afford to reach. Rigour is not the opposite of ambition; it is what makes ambition affordable."
    , philosophyPrinciples =
        [ Principle "Make correctness practical"
            "Guarantees only help if people keep them switched on. I want checks that run on every build, explain themselves plainly, and cost less than the bugs they prevent."
        , Principle "Say where the guarantees end"
            "A system should be honest about its limits. Black’s compiler rejects a conversion it cannot prove, and its documentation lists what it does not yet claim."
        , Principle "Keep judgement human"
            "I use AI to explore and write code. What ships is still decided by people, and confirmed by tests, types and proofs that give the same answer every time."
        ]
    }

philosophySection :: E.ChildHTML E.Main grandparent
philosophySection =
  E.section [ A.class_ "philosophy", A.id philosophyId, A.aria_labelledby (NEL.singleton philosophyTitleId) ]
    [ E.div [ A.class_ "philosophy__inner" ]
        [ E.p [ A.class_ "philosophy__label" ] [ E.text (philosophyLabel philosophy) ]
        , E.h2 [ A.class_ "philosophy__title", A.id philosophyTitleId ] [ E.text (philosophyHeading philosophy) ]
        , E.div [ A.class_ "philosophy__rule", A.aria_hidden True ] [ E.span [ A.class_ "philosophy__rule-diamond" ] [] ]
        , E.p [ A.class_ "philosophy__lede" ] [ E.text (philosophyLede philosophy) ]
        , E.ul [ A.class_ "philosophy__principles" ]
            (zipWith principle [ "I", "II", "III", "IV", "V" ] (philosophyPrinciples philosophy))
        ]
    ]
  where
    principle numeral p =
      E.li [ A.class_ "philosophy__principle" ]
        [ E.span [ A.class_ "philosophy__numeral", A.aria_hidden True ] [ E.text numeral ]
        , E.h3 [ A.class_ "philosophy__principle-title" ] [ E.text (principleTitle p) ]
        , E.p [ A.class_ "philosophy__principle-text" ] [ E.text (principleText p) ]
        ]

--------------------------------------------------------------------------------
-- Writing preview (only with published articles)

writingPreview :: [Article] -> E.ChildHTML E.Main grandparent
writingPreview articles =
  E.section [ A.class_ "writing-preview", A.id writingId, A.aria_labelledby (NEL.singleton writingTitleId) ]
    [ sectionHeading ["section-title--quiet"] writingTitleId "Writing"
    , E.ul [ A.class_ "writing-preview__list" ] (map entry articles)
    , E.p [ A.class_ "work__more" ]
        [ E.a [ A.href (routeUrl WritingIndex) ]
            [ E.text "All writing"
            , E.span [ A.class_ "work__more-arrow", A.aria_hidden True ] [ E.text " →" ]
            ]
        ]
    ]
  where
    entry article =
      E.li [ A.class_ "writing-preview__item" ]
        [ E.p [ A.class_ "writing-preview__date" ] [ E.text (maybe "" id (articleDate article)) ]
        , E.div [ A.class_ "writing-preview__body" ]
            [ E.h3 [ A.class_ "writing-preview__title" ] [ E.text (articleTitle article) ]
            , E.p [ A.class_ "writing-preview__summary" ] [ E.text (articleSummary article) ]
            , E.a [ A.class_ "writing-preview__link", A.href (routeUrl (WritingArticle (articleSlug article))) ]
                [ E.text "Read"
                , E.span [ A.class_ "visually-hidden" ] [ E.text (": " <> articleTitle article) ]
                , E.span [ A.class_ "work__more-arrow", A.aria_hidden True ] [ E.text " →" ]
                ]
            ]
        ]

--------------------------------------------------------------------------------
-- Contact (target of the navigation's Contact link and the secondary CTA)

-- | The Contact section's own copy.
data ContactCopy =
  ContactCopy
    { contactStatus :: CopyStatus
    , contactInvitation :: T.Text
    }

-- | DRAFT: a short invitation, for the owner's content pass.
contactCopy :: ContactCopy
contactCopy =
  ContactCopy
    { contactStatus = DraftCopy
    , contactInvitation = "Questions about a project, or an idea worth building? I’d be glad to hear from you."
    }

-- | A short invitation and the verified destinations ("Site.Settings"),
-- each exactly one link. No form and no backend.
contactSection :: Settings -> E.ChildHTML E.Main grandparent
contactSection settings =
  E.section [ A.class_ "contact", A.id contactId, A.aria_labelledby (NEL.singleton contactTitleId) ]
    [ sectionHeading ["section-title--quiet"] contactTitleId "Contact"
    , E.p [ A.class_ "contact__invitation" ] [ E.text (contactInvitation contactCopy) ]
    , E.ul [ A.class_ "contact__links" ]
        [ E.li [ A.class_ "contact__item" ]
            [ E.a [ A.class_ "contact__link", A.href (B.mkRawURL (contactHref c)) ]
                [ E.span [ A.class_ "contact__label" ] [ E.text (contactLabel c) ]
                , E.span [ A.class_ "contact__display" ] [ E.text (contactDisplay c) ]
                ]
            ]
        | c <- contacts settings
        ]
    ]

--------------------------------------------------------------------------------
-- Ids

topId, heroTitleId, blackId, blackTitleId, selectedWorkId, workTitleId, philosophyId, philosophyTitleId, writingId, writingTitleId, contactTitleId :: B.Id
topId = elementId "top"
heroTitleId = elementId "hero-title"
blackId = elementId "black"
blackTitleId = elementId "black-title"
selectedWorkId = elementId "selected-work"
workTitleId = elementId "work-title"
philosophyId = elementId "philosophy"
philosophyTitleId = elementId "philosophy-title"
writingId = elementId "writing"
writingTitleId = elementId "writing-title"
contactTitleId = elementId "contact-title"
