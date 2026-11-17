-- | Phase 04: project dossiers, symbolic heroes and the five section
-- layouts.
--
-- As elsewhere, fixture trees go through the real pipeline (load,
-- 'siteFrom', render, and 'buildSite' where files matter), and assertions
-- inspect the generated HTML.
module DossierTests (dossierTests) where

import Control.Exception (try)
import Control.Monad (forM_)
import Data.Aeson ((.=))
import Data.Aeson qualified as Json
import Data.Aeson.Key qualified as Key
import Data.ByteString qualified as BS
import Data.List (isInfixOf, isPrefixOf, sort, tails)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.ByteString.Lazy qualified as LBS
import System.FilePath ((</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import Site.Build
import Site.Content.Load (ContentError (..), HeroSizePolicy (..), defaultHeroSizePolicy, loadContent, loadContentWith)
import Site.Content.Markdown (inlineText)
import Site.Content.Types
import Site.Definition (siteFrom)
import Site.Layout (renderPage)
import Site.Page (Layout (..), Page (..), Site (..))
import Site.Pages.Home (BlackExample (..), blackExample)
import Site.Routes

import ContentTests (listFiles, projectJson, slugOf, svg, withSource)

dossierTests :: TestTree
dossierTests =
  testGroup "dossiers (Phase 04)"
    [ realContentTests
    , layoutTests
    , sectionValidationTests
    , heroTests
    , sidebarTests
    , publicationTests
    ]

--------------------------------------------------------------------------------
-- Fixtures

dir :: FilePath
dir = "content/projects/demo"

-- | The demo project with a body and the given extra project.json fields.
demo :: T.Text -> [(T.Text, Maybe Json.Value)] -> [(FilePath, BS.ByteString)]
demo body overrides =
  [ (dir </> "project.json", projectJson "demo" overrides)
  , (dir </> "body.md", TE.encodeUtf8 body)
  ]

-- | A body with one section of each kind, in this order.
fullBody :: T.Text
fullBody =
  T.unlines
    [ "Lead paragraph."
    , ""
    , "## Overview"
    , ""
    , "Overview text."
    , ""
    , "## Pipeline"
    , ""
    , "Caption text."
    , ""
    , "## Example"
    , ""
    , "Explanation."
    , ""
    , "## Principles"
    , ""
    , "Intro."
    , ""
    , "- **First.** One `code`."
    , "- **Second.** Two."
    , "- **Third.** Three."
    , ""
    , "## Resources"
    , ""
    , "- [Source](https://example.com/src)"
    ]

object :: [(T.Text, Json.Value)] -> Json.Value
object kvs = Json.object [ (Key.fromText k, v) | (k, v) <- kvs ]

sections :: [(T.Text, Json.Value)] -> (T.Text, Maybe Json.Value)
sections kvs = ("sections", Just (object kvs))

layout :: T.Text -> [(T.Text, Json.Value)] -> Json.Value
layout name extra = object (("layout", Json.String name) : extra)

codeArtifact :: T.Text -> Json.Value
codeArtifact src = Json.object [ "kind" .= ("code" :: T.Text), "src" .= src, "label" .= ("Example.hs" :: T.Text), "language" .= ("haskell" :: T.Text) ]

imageArtifact :: T.Text -> T.Text -> Json.Value
imageArtifact kind src = Json.object [ "kind" .= kind, "src" .= src, "alt" .= ("A diagram" :: T.Text) ]

-- | Every layout, as project.json for 'fullBody'.
fullSections :: (T.Text, Maybe Json.Value)
fullSections =
  sections
    [ ("overview", layout "overview" [("facts", Json.toJSON [ Json.object ["label" .= ("Language" :: T.Text), "value" .= ("Haskell" :: T.Text)] ])])
    , ("pipeline", layout "wide-exhibit" [("artifact", imageArtifact "diagram" "pipeline.svg")])
    , ("example", layout "split" [("artifact_side", "start"), ("artifact", codeArtifact "examples/Example.hs")])
    , ("principles", layout "grid" [])
    , ("resources", layout "resources" [])
    ]

fullFiles :: [(FilePath, BS.ByteString)]
fullFiles =
  demo fullBody [fullSections]
    <> [ (dir </> "pipeline.svg", svg)
       , (dir </> "examples/Example.hs", "main :: IO ()\nmain = putStrLn \"<script>alert(1)</script> & done\"\n")
       ]

-- | A hero field.
hero :: [(T.Text, Json.Value)] -> (T.Text, Maybe Json.Value)
hero kvs = ("hero", Just (object kvs))

-- | A small valid WebP-named file (the build checks names and sizes, not
-- image contents).
heroBytes :: BS.ByteString
heroBytes = "RIFF0000WEBPVP8 hero"

load :: [(FilePath, BS.ByteString)] -> IO (Either [ContentError] Content)
load files = withSource files loadContent

loaded :: [(FilePath, BS.ByteString)] -> IO Project
loaded files = do
  result <- load files
  case result of
    Left errs -> assertFailure (concatMap show errs) >> error "unreachable"
    Right content ->
      case [ p | p <- contentProjects content, projectSlug p == slugOf "demo" ] of
        [p] -> pure p
        _ -> assertFailure "demo not loaded" >> error "unreachable"

-- | The rendered demo page.
render :: [(FilePath, BS.ByteString)] -> IO (Page, T.Text)
render files =
  withSource files $ \root -> do
    result <- loadContent root
    case result of
      Left errs -> assertFailure (concatMap show errs) >> error "unreachable"
      Right content -> do
        let s = siteFrom content
        case filter ((== WorkDetail (slugOf "demo")) . pageRoute) (sitePages s) of
          [p] -> pure (p, TE.decodeUtf8 (LBS.toStrict (renderPage (siteConfig s) p)))
          _ -> assertFailure "demo page not generated" >> error "unreachable"

expectError :: [(FilePath, BS.ByteString)] -> FilePath -> [String] -> Assertion
expectError files file needles = do
  result <- load files
  case result of
    Right _ -> assertFailure ("loaded; expected an error in " <> file)
    Left errs -> do
      let messages = concat [ ms | ContentError f ms <- errs, f == file ]
          shown = concatMap show errs
      assertBool ("expected an error for " <> file <> ", got:\n" <> shown) (not (null messages))
      forM_ needles $ \needle ->
        assertBool ("missing " <> show needle <> " in:\n" <> shown) (any (needle `isInfixOf`) messages)

has :: T.Text -> T.Text -> Assertion
has html needle = assertBool ("missing " <> T.unpack needle) (needle `T.isInfixOf` html)

hasNot :: T.Text -> T.Text -> Assertion
hasNot html needle = assertBool ("unexpected " <> T.unpack needle) (not (needle `T.isInfixOf` html))

-- | Position of the first occurrence (for order checks).
position :: T.Text -> T.Text -> Int
position html needle = T.length (fst (T.breakOn needle html))

--------------------------------------------------------------------------------
-- Real content

realContentTests :: TestTree
realContentTests =
  testGroup "real content"
    [ testCase "Black and Brigid are dossiers with varied layouts; Lockdown keeps the default" $ do
        content <- realProjects
        let kinds slug = [ (dossierId d, layoutKind (dossierBody d)) | p <- content, projectSlug p == slugOf slug, d <- projectSections p ]
        kinds "black"
          @?= [ ("overview", OverviewKind), ("design-principles", GridKind), ("the-compiler-pipeline", WideExhibitKind)
              , ("a-program-white-accepts", SplitKind), ("a-program-white-rejects", SplitKind)
              , ("language-today", OverviewKind), ("status-and-limitations", ResourcesKind), ("resources", ResourcesKind) ]
        kinds "brigid"
          @?= [ ("overview", OverviewKind), ("motivation", OverviewKind), ("how-the-types-work", SplitKind)
              , ("caught-at-compile-time", SplitKind), ("what-the-types-buy", GridKind)
              , ("status-and-limitations", ResourcesKind), ("resources", ResourcesKind) ]
        assertBool "lockdown: every section is an overview" $
          all ((== OverviewKind) . snd) (kinds "lockdown") && not (null (kinds "lockdown"))
    , testCase "every real hero declared is a published, sized image (Crest is not published)" $ do
        content <- realProjects
        forM_ content $ \p ->
          forM_ (projectHero p) $ \h ->
            assertBool (show (projectSlug p)) (MediaFile (ProjectMedia (projectSlug p)) (projectSource p) (heroImage h) `elem` projectMedia p)
        assertBool "crest withheld" (slugOf "crest" `notElem` map projectSlug content)
    , testCase "nothing new is published: the same three projects, no stand-in art, no warnings" $ do
        content <- realProjects
        sort (map (slugText . projectSlug) content) @?= ["black", "brigid", "lockdown"]
        files <- listFiles "content"
        assertBool (show files) (not (any (\f -> any (`isInfixOf` f) ["stand-in", "standin", "stand_in"]) files))
        result <- loadContent "."
        either (assertFailure . concatMap show) (\c -> contentWarnings c @?= []) result
    , testCase "the Black excerpts are the verified programs: the accepted one is the homepage's" $ do
        accepted <- readText "content/projects/black/examples/NominalRecord.blk"
        T.stripEnd accepted @?= T.stripEnd (exampleSource blackExample)
        rejected <- readText "content/projects/black/examples/CastUnresolved.blk"
        -- CAST_UNPROVEN at 8:12 (the conformance MANIFEST): line 8 is `narrow x = cast x`,
        -- and column 12 is the `cast`.
        let line8 = T.lines rejected !! 7
        line8 @?= "narrow x = cast x"
        T.take 4 (T.drop 11 line8) @?= "cast"
    , testCase "the Brigid excerpt is verbatim from this site's source" $ do
        excerpt <- T.lines . T.stripEnd <$> readText "content/projects/brigid/examples/fact-list.hs"
        source <- T.lines <$> readText "src/Site/Pages/Work.hs"
        assertBool "excerpt not found in src/Site/Pages/Work.hs" (any (excerpt `isPrefixOf`) (tails source))
    ]
  where
    readText f = TE.decodeUtf8 <$> BS.readFile f

-- | The repository's published projects.
realProjects :: IO [Project]
realProjects = do
  result <- loadContent "."
  case result of
    Left errs -> assertFailure (concatMap show errs) >> error "unreachable"
    Right content -> pure (publishedProjects content)

--------------------------------------------------------------------------------
-- Layouts

layoutTests :: TestTree
layoutTests =
  testGroup "section layouts"
    [ testCase "each layout renders its own structure, in body order" $ do
        (_, html) <- render fullFiles
        -- overview: prose then a fact cluster
        has html "<section class=\"project__section dossier-section dossier-section--overview prose\" aria-labelledby=\"overview\"><h2 class=\"project__section-title\" id=\"overview\">Overview</h2><p>Overview text.</p><dl class=\"dossier-facts\"><dt>Language</dt><dd>Haskell</dd></dl></section>"
        -- wide exhibit: the artifact, then the copy as its caption
        has html "<figure class=\"dossier-exhibit\"><div class=\"artifact artifact--diagram\">"
        has html "<figcaption class=\"dossier-exhibit__caption prose\"><p>Caption text.</p></figcaption>"
        -- split, artifact first
        has html "dossier-section--split dossier-section--artifact-start"
        assertBool "artifact before text" (position html "dossier-split__artifact" < position html "dossier-split__text")
        -- grid: intro, then items with their titles (full stop dropped) as h3
        has html "<div class=\"dossier-grid__intro prose\"><p>Intro.</p></div><ul class=\"dossier-grid dossier-grid--count-3\">"
        has html "<li class=\"dossier-grid__item\"><h3 class=\"dossier-grid__title\">First</h3><p class=\"dossier-grid__text\">One <code>code</code>.</p></li>"
        -- resources
        has html "dossier-section--resources prose"
        let order = map (position html) ["id=\"overview\"", "id=\"pipeline\"", "id=\"example\"", "id=\"principles\"", "id=\"resources\""]
        order @?= sort order
    , testCase "sections without an entry default to overview, and the order is the body's" $ do
        p <- loaded (demo "## B part\n\nx\n\n## A part\n\ny\n" [sections [("a-part", layout "resources" [])]])
        map (\d -> (dossierId d, layoutKind (dossierBody d))) (projectSections p)
          @?= [("b-part", OverviewKind), ("a-part", ResourcesKind)]
    , testCase "a split defaults to the artifact at the end" $ do
        (_, html) <- render
          ( demo "## Example\n\nText.\n" [sections [("example", layout "split" [("artifact", codeArtifact "Example.hs")])]]
              <> [ (dir </> "Example.hs", "x = 1\n") ] )
        has html "dossier-section--artifact-end"
        assertBool "text before artifact" (position html "dossier-split__text" < position html "dossier-split__artifact")
    , testCase "code artifacts are escaped text, one span per line, labelled, never published" $ do
        (_, html) <- render fullFiles
        has html "<span class=\"artifact__label\">Example.hs</span><span class=\"artifact__language\">haskell</span>"
        has html "<code class=\"language-haskell\"><span class=\"artifact__line\">main :: IO ()</span>\n<span class=\"artifact__line\">main = putStrLn "
        has html "&#60;script&#62;alert(1)&#60;/script&#62; &#38; done"
        has html "</span>\n</code></pre>"
        hasNot html "<script>"
        withSource fullFiles $ \root -> do
          s <- loadSite root
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = root </> "dist" } s
          files <- listFiles (root </> "dist")
          assertBool (show files) (not (any ("Example.hs" `isInfixOf`) files))
          assertBool (show files) (("media/projects/demo/pipeline.svg") `elem` files)
    , testCase "image artifacts scale; diagrams scroll and link to the full-size file" $ do
        (_, html) <- render fullFiles
        -- Phase 06: the scrolling viewport is keyboard-focusable (WCAG
        -- 2.1.1) and named, as a group rather than a landmark.
        has html "<div class=\"artifact__viewport\" tabindex=\"0\" role=\"group\" aria-label=\"Diagram (scrolls sideways on narrow screens)\"><img src=\"/media/projects/demo/pipeline.svg\" alt=\"A diagram\""
        has html "<p class=\"artifact__open\"><a href=\"/media/projects/demo/pipeline.svg\">Open the diagram at full size</a></p>"
        (_, html') <- render
          ( demo "## Figure\n" [sections [("figure", layout "wide-exhibit" [("artifact", imageArtifact "image" "figure.svg")])]]
              <> [ (dir </> "figure.svg", svg) ] )
        has html' "<div class=\"artifact artifact--image\"><img src=\"/media/projects/demo/figure.svg\" alt=\"A diagram\""
        hasNot html' "artifact__open"
        -- An image never scrolls, so it adds no focus stop.
        hasNot html' "tabindex"
    ]

--------------------------------------------------------------------------------
-- Section validation

sectionValidationTests :: TestTree
sectionValidationTests =
  testGroup "section validation"
    [ testCase "unknown layouts, unknown fields and wrong types name the allowed values" $ do
        expectError (demo "## A\n" [sections [("a", layout "carousel" [])]]) (dir </> "project.json")
          ["unknown layout \"carousel\"; expected one of: overview, wide-exhibit, split, grid, resources"]
        expectError (demo "## A\n" [sections [("a", layout "grid" [("facts", Json.toJSON ([] :: [Int]))])]]) (dir </> "project.json")
          ["unknown field \"facts\" (allowed: layout, sidebar)"]
        expectError (demo "## A\n" [sections [("a", layout "overview" [("sidebar", "no")])]]) (dir </> "project.json")
          ["field \"sidebar\": expected true or false"]
        expectError (demo "## A\n" [sections [("a", Json.object [])]]) (dir </> "project.json")
          ["missing required field \"layout\""]
        expectError (demo "## A\n" [("sections", Just (Json.toJSON ["a" :: T.Text]))]) (dir </> "project.json")
          ["expected an object from section ids to layouts"]
    , testCase "a sections entry must name a ## section of the body" $
        expectError (demo "## Real part\n" [sections [("imagined", layout "grid" [])]]) (dir </> "project.json")
          ["\"imagined\" is not a ## section of the body; its sections are: real-part"]
    , testCase "exhibits and splits need a valid artifact" $ do
        expectError (demo "## A\n" [sections [("a", layout "wide-exhibit" [])]]) (dir </> "project.json")
          ["missing required field \"artifact\""]
        expectError (demo "## A\n" [sections [("a", layout "split" [("artifact", Json.object ["kind" .= ("video" :: T.Text)])])]]) (dir </> "project.json")
          ["unsupported artifact kind \"video\"; expected one of: image, diagram, code"]
        expectError (demo "## A\n" [sections [("a", layout "split" [("artifact", codeArtifact "missing.hs")])]]) (dir </> "project.json")
          ["artifact code file \"missing.hs\" does not exist"]
        expectError (demo "## A\n" [sections [("a", layout "wide-exhibit" [("artifact", imageArtifact "image" "missing.svg")])]]) (dir </> "project.json")
          ["\"missing.svg\" does not exist"]
        expectError (demo "## A\n" [sections [("a", layout "wide-exhibit" [("artifact", imageArtifact "image" "body.md")])]]) (dir </> "project.json")
          ["not an image file"]
        expectError (demo "## A\n" [sections [("a", layout "wide-exhibit" [("artifact", imageArtifact "image" "../other/x.svg")])]]) (dir </> "project.json")
          ["field \"artifact\""]
        expectError (demo "## A\n" [sections [("a", layout "split" [("artifact", codeArtifact "bad.hs")])]] <> [ (dir </> "bad.hs", "\xff\xfe") ]) (dir </> "project.json")
          ["is not valid UTF-8"]
        expectError (demo "## A\n" [sections [("a", layout "split" [("artifact", codeArtifact "big.hs")])]] <> [ (dir </> "big.hs", BS.replicate 40000 120) ]) (dir </> "project.json")
          ["is larger than 32768 bytes"]
        expectError (demo "## A\n" [sections [("a", layout "split" [("artifact_side", "left"), ("artifact", codeArtifact "x.hs")])]] <> [ (dir </> "x.hs", "x") ]) (dir </> "project.json")
          ["invalid value \"left\"; expected one of: start, end"]
    , testCase "a grid is an optional introduction then one list of **Title.** items" $ do
        let grid body = demo body [sections [("g", layout "grid" [])]]
            bodyFile = dir </> "body.md"
        expectError (grid "## G\n\nOnly prose.\n") bodyFile ["needs a bullet list of items"]
        expectError (grid "## G\n\n- **A.** a\n- b without a title\n") bodyFile ["item 2: must be one paragraph starting with **Title.**"]
        expectError (grid "## G\n\n- **A.** a\n- **B.**\n") bodyFile ["item 2: needs text after its **title**"]
        expectError (grid "## G\n\n- **A.** a\n") bodyFile ["has 1 items; a grid holds 2 to 9"]
        expectError (grid "## G\n\n- **A.** a\n- **B.** b\n\nAfter.\n") bodyFile ["must end with its bullet list"]
    , testCase "resources sections close the dossier" $
        expectError (demo "## Links\n\n## Later\n" [sections [("links", layout "resources" [])]]) (dir </> "project.json")
          ["\"later\" (layout \"overview\") follows the resources section \"links\""]
    , testCase "facts are label and value pairs" $
        expectError (demo "## A\n" [sections [("a", layout "overview" [("facts", Json.toJSON [Json.object ["label" .= ("L" :: T.Text)]])])]]) (dir </> "project.json")
          ["missing required field \"value\""]
    ]

--------------------------------------------------------------------------------
-- Heroes

heroTests :: TestTree
heroTests =
  testGroup "heroes"
    [ testCase "a hero opens the main column, beside the sidebar, with the real title, summary and tags over it" $ do
        (page, html) <- render (demo "## A\n\nText.\n" [hero [("src", "hero.webp"), ("alt", "A gothic window")], showcaseArt] <> heroFiles)
        pageLayout page @?= Dossier
        -- one article is the layout: hero, then sidebar, then dossier body
        has html "<main id=\"main\" class=\"interior interior--dossier\"><article class=\"project project-layout project--hero\" aria-labelledby=\"demo-title\"><header class=\"project-hero project-hero--x-50 project-hero--y-50 project-hero--mx-50 project-hero--my-50\"><div class=\"project-hero__art\"><img class=\"project-hero__img\" src=\"/media/projects/demo/hero.webp\" alt=\"A gothic window\" fetchpriority=\"high\"/></div><div class=\"project-hero__inner\"><div class=\"project__header\">"
        has html "<h1 class=\"project__title\" id=\"demo-title\">Project demo</h1>"
        has html "</div></div></header><nav class=\"project-nav\" aria-label=\"Project\">"
        has html "</nav><div class=\"project__body\"><section class=\"project__section dossier-section dossier-section--overview prose\""
        assertBool "hero, sidebar and body all inside the article"
          (position html "</article>" > position html "class=\"project__body\"")
        -- the card art is the card's; the hero page does not repeat it
        hasNot html "project__showcase"
        T.count "<h1" html @?= 1
        T.count "<header class=\"project-hero" html @?= 1
    , testCase "decorative heroes have empty alt and are hidden from assistive technology" $ do
        (_, html) <- render (demo "## A\n" [hero [("src", "hero.webp"), ("decorative", Json.Bool True)]] <> heroFiles)
        has html "<div class=\"project-hero__art\" aria-hidden=\"true\"><img class=\"project-hero__img\" src=\"/media/projects/demo/hero.webp\" alt=\"\""
        -- the hero itself is not focusable
        hasNot html "tabindex"
    , testCase "without a hero, the header opens the same layout and the dossier follows directly (no orphaned card art)" $ do
        (page, html) <- render (demo "## A\n" [showcaseArt] <> [ (dir </> "card.svg", svg) ])
        pageLayout page @?= Interior
        hasNot html "project-hero"
        has html "<main id=\"main\" class=\"interior\"><article class=\"project project-layout\" aria-labelledby=\"demo-title\"><div class=\"project__header\">"
        has html "</nav><div class=\"project__body\"><section class=\"project__section"
        -- Phase 05: the card art is the card's alone; the dossier shows no
        -- stand-alone figure in its place
        hasNot html "project__showcase"
        hasNot html "card.svg"
        hasNot html "<figure"
    , testCase "adding a hero does not move the sidebar: the same nav, between the opening and the body" $ do
        let body = "Lead.\n\n## One\n\n## Two\n"
        (_, withHero) <- render (demo body [hero [("src", "hero.webp"), ("alt", "x")], showcaseArt] <> heroFiles)
        (_, without) <- render (demo body [showcaseArt] <> heroFiles)
        let navOf html = fst (T.breakOn "</nav>" (snd (T.breakOn "<nav class=\"project-nav\"" html)))
        navOf withHero @?= navOf without
        assertBool "nav present" (not (T.null (navOf withHero)))
        forM_ [withHero, without] $ \html -> do
          has html "</nav><div class=\"project__body\">"
          assertBool "the opening precedes the sidebar" (position html "class=\"project__header\"" < position html "<nav class=\"project-nav\"")
        -- and the sections and their anchors are identical
        let bodyOf html = fst (T.breakOn "</article>" (snd (T.breakOn "<div class=\"project__lead" html)))
        bodyOf withHero @?= bodyOf without
    , testCase "focus: omitted, legacy keywords, one point, and separate desktop and mobile points" $ do
        let classesFor focus = do
              (_, html) <- render (demo "## A\n" [hero ([("src", "hero.webp"), ("alt", "x")] <> [ ("focus", f) | Just f <- [focus] ])] <> heroFiles)
              pure (fst (T.breakOn "\"" (snd (T.breakOn "project-hero--x" html))))
            point x y = Json.object [ k .= (v :: Int) | (k, Just v) <- [("x", x), ("y", y)] ]
        c0 <- classesFor Nothing
        c0 @?= "project-hero--x-50 project-hero--y-50 project-hero--mx-50 project-hero--my-50"
        c1 <- classesFor (Just "top")
        c1 @?= "project-hero--x-50 project-hero--y-10 project-hero--mx-50 project-hero--my-10"
        c2 <- classesFor (Just "bottom")
        c2 @?= "project-hero--x-50 project-hero--y-90 project-hero--mx-50 project-hero--my-90"
        c3 <- classesFor (Just (point (Just 65) (Just 35)))
        c3 @?= "project-hero--x-65 project-hero--y-35 project-hero--mx-65 project-hero--my-35"
        c4 <- classesFor (Just (Json.object ["desktop" .= point (Just 65) (Just 35), "mobile" .= point (Just 80) Nothing]))
        c4 @?= "project-hero--x-65 project-hero--y-35 project-hero--mx-80 project-hero--my-50"
        c5 <- classesFor (Just (Json.object ["mobile" .= point (Just 80) (Just 45)]))
        c5 @?= "project-hero--x-50 project-hero--y-50 project-hero--mx-80 project-hero--my-45"
        c6 <- classesFor (Just (Json.object ["desktop" .= point (Just 100) (Just 0)]))
        c6 @?= "project-hero--x-100 project-hero--y-0 project-hero--mx-100 project-hero--my-0"
    , testCase "malformed focus is rejected with the field and the reason" $ do
        let json = dir </> "project.json"
            withFocus f = demo "## A\n" [hero [("src", "hero.webp"), ("alt", "x"), ("focus", f)]] <> heroFiles
            point kvs = Json.object [ (Key.fromText k, v) | (k, v) <- kvs ]
            n :: Double -> Json.Value
            n = Json.toJSON
        expectError (withFocus "left") json ["field \"focus\": invalid value \"left\"; expected one of: center, top, bottom"]
        expectError (withFocus (point [("x", n 101)])) json ["field \"x\": must be from 0 to 100, got 101"]
        expectError (withFocus (point [("y", n (-5))])) json ["field \"y\": must be from 0 to 100, got -5"]
        expectError (withFocus (point [("x", n 62)])) json ["field \"x\": must be a multiple of 5 (e.g. 60 or 65), got 62"]
        expectError (withFocus (point [("x", n 12.5)])) json ["field \"x\": expected a whole number from 0 to 100"]
        expectError (withFocus (point [("x", "65")])) json ["field \"x\": expected a number, got a string"]
        expectError (withFocus (point [])) json ["give \"x\", \"y\" or both"]
        expectError (withFocus (point [("x", n 50), ("z", n 1)])) json ["unknown field \"z\""]
        expectError (withFocus (point [("desktop", point [("x", n 50)]), ("x", n 50)])) json ["unknown field \"x\""]
        expectError (withFocus (point [("mobile", point [("y", n 200)])])) json ["field \"mobile\": field \"y\": must be from 0 to 100, got 200"]
        expectError (withFocus (point [("desktop", "top")])) json ["field \"desktop\": must be a JSON object"]
        expectError (withFocus (n 50)) json ["field \"focus\": expected a keyword or an object, got a number"]
    , testCase "the alt text policy is explicit: exactly one of alt and decorative" $ do
        let json = dir </> "project.json"
        expectError (demo "## A\n" [hero [("src", "hero.webp")]] <> heroFiles) json
          ["missing \"alt\" (a short description of the artwork) or \"decorative\": true"]
        expectError (demo "## A\n" [hero [("src", "hero.webp"), ("alt", "x"), ("decorative", Json.Bool True)]] <> heroFiles) json
          ["give either \"alt\" or \"decorative\", not both"]
        expectError (demo "## A\n" [hero [("src", "hero.webp"), ("decorative", Json.Bool False)]] <> heroFiles) json
          ["false is not allowed; describe the artwork with \"alt\" instead"]
        expectError (demo "## A\n" [hero [("src", "hero.webp"), ("alt", "x"), ("credit", "me")]] <> heroFiles) json
          ["unknown field \"credit\""]
        expectError (demo "## A\n" [("hero", Just "hero.webp")] <> heroFiles) json
          ["field \"hero\": must be a JSON object"]
    , testCase "missing, misplaced and non-image hero files are errors" $ do
        let json = dir </> "project.json"
            withSrc src = demo "## A\n" [hero [("src", src), ("alt", "x")]]
        expectError (withSrc "hero.webp") json ["field \"hero\": image \"hero.webp\" does not exist"]
        expectError (withSrc "body.md") json ["field \"hero\": image \"body.md\": not an image file"]
        expectError (withSrc "../brigid/hero.webp") json ["field \"hero\""]
        expectError (withSrc "/hero.webp") json ["field \"hero\""]
    , testCase "size policy: silent within the budget, a warning over it, an error over the ceiling" $ do
        let files size = demo "## A\n" [hero [("src", "hero.webp"), ("alt", "x")]] <> [ (dir </> "hero.webp", BS.replicate size 0) ]
            small = HeroSizePolicy { heroBudgetBytes = 100, heroCeilingBytes = 200 }
            loadWith policy fs = withSource fs (loadContentWith policy)
        atBudget <- loadWith small (files 100)
        either (assertFailure . concatMap show) (\c -> contentWarnings c @?= []) atBudget
        overBudget <- loadWith small (files 150)
        case overBudget of
          Left errs -> assertFailure (concatMap show errs)
          Right c -> do
            length (contentWarnings c) @?= 1
            forM_ ["content/projects/demo/project.json: field \"hero\": image \"hero.webp\" is 0.00 MiB (150 bytes), over the 0.00 MiB (100 bytes) budget (accepted up to 0.00 MiB (200 bytes))"] $ \needle ->
              assertBool (show (contentWarnings c)) (any (needle `isInfixOf`) (contentWarnings c))
            -- and the site carries the warning to the CLI
            siteWarnings (siteFrom c) @?= contentWarnings c
        atCeiling <- loadWith small (files 200)
        either (assertFailure . concatMap show) (const (pure ())) atCeiling
        overCeiling <- loadWith small (files 201)
        case overCeiling of
          Right _ -> assertFailure "a hero over the ceiling loaded"
          Left errs -> assertBool (concatMap show errs) ("is 0.00 MiB (201 bytes); the ceiling is 0.00 MiB (200 bytes) (budget 0.00 MiB (100 bytes))" `isInfixOf` concatMap show errs)
    , testCase "default size policy: 1 MiB budget, 8 MiB ceiling" $ do
        defaultHeroSizePolicy @?= HeroSizePolicy { heroBudgetBytes = 1024 * 1024, heroCeilingBytes = 8 * 1024 * 1024 }
        let json = dir </> "project.json"
            files size = demo "## A\n" [hero [("src", "hero.webp"), ("alt", "x")]] <> [ (dir </> "hero.webp", BS.replicate size 0) ]
        -- over the old 1 MiB limit: now accepted, with a warning
        overBudget <- load (files (1024 * 1024 + 1))
        case overBudget of
          Left errs -> assertFailure (concatMap show errs)
          Right c -> assertBool (show (contentWarnings c)) (any ("over the 1.00 MiB (1048576 bytes) budget" `isInfixOf`) (contentWarnings c))
        expectError (files (8 * 1024 * 1024 + 1)) json
          ["is 8.00 MiB (8388609 bytes); the ceiling is 8.00 MiB (8388608 bytes)", "tools/art/promote_hero.py"]
    , testCase "a hero over the ceiling fails the build and leaves the previous output in place" $
        withSource (demo "## A\n" []) $ \root -> do
          let out = root </> "dist"
          s <- loadSite root
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = out } s
          before <- listFiles out
          BS.writeFile (root </> dir </> "project.json") (projectJson "demo" [hero [("src", "hero.webp"), ("alt", "x")]])
          BS.writeFile (root </> dir </> "hero.webp") (BS.replicate (8 * 1024 * 1024 + 1) 0)
          result <- try (loadSite root >>= buildSite BuildConfig { sourceRoot = root, outputDir = out })
          case result of
            Left (InvalidContent _) -> pure ()
            Left other -> assertFailure ("unexpected " <> show other)
            Right _ -> assertFailure "built with an oversized hero"
          after <- listFiles out
          after @?= before
    , testCase "hero pages render deterministically" $ do
        let files = demo "Lead.\n\n## A\n" [hero [("src", "hero.webp"), ("alt", "x"), ("focus", Json.object ["x" .= (65 :: Int)])]] <> heroFiles
        (_, first) <- render files
        (_, second) <- render files
        first @?= second
    ]
  where
    heroFiles = [ (dir </> "hero.webp", heroBytes), (dir </> "card.svg", svg) ]
    showcaseArt = ("showcase", Just (Json.object ["kind" .= ("image" :: T.Text), "src" .= ("card.svg" :: T.Text), "alt" .= ("Card art" :: T.Text)]))

--------------------------------------------------------------------------------
-- Sidebar

sidebarTests :: TestTree
sidebarTests =
  testGroup "sidebar"
    [ testCase "the sidebar lists exactly the sections marked for it, in order, and every link resolves" $ do
        (_, html) <- render
          ( demo "## One\n\n## Two\n\n## Three\n" [sections [("two", layout "overview" [("sidebar", Json.Bool False)])]] )
        let nav = fst (T.breakOn "</nav>" (snd (T.breakOn "class=\"project-nav\"" html)))
        has nav "<a href=\"#one\">One</a>"
        has nav "<a href=\"#three\">Three</a>"
        hasNot nav "#two"
        has html "id=\"two\">Two</h2>"
        assertBool "order" (position nav "#one" < position nav "#three")
    , testCase "a dossier with no sidebar sections renders no section list" $ do
        (_, html) <- render (demo "## Only\n" [sections [("only", layout "overview" [("sidebar", Json.Bool False)])]])
        hasNot html "project-nav__sections"
    , testCase "every real project's sidebar matches its sections" $ do
        s <- loadSite "."
        projects <- realProjects
        forM_ projects $ \p -> do
          page <- case [ pg | pg <- sitePages s, pageRoute pg == WorkDetail (projectSlug p) ] of { [pg] -> pure pg; _ -> assertFailure "no page" >> error "unreachable" }
          let
              html = TE.decodeUtf8 (LBS.toStrict (renderPage (siteConfig s) page))
              nav = fst (T.breakOn "</nav>" (snd (T.breakOn "class=\"project-nav\"" html)))
          forM_ (projectSections p) $ \d -> do
            let link = "<a href=\"#" <> dossierId d <> "\">" <> inlineText (dossierHeading d) <> "</a>"
            assertBool (T.unpack link) ((link `T.isInfixOf` nav) == dossierInSidebar d)
            has html ("id=\"" <> dossierId d <> "\"")
    ]

--------------------------------------------------------------------------------
-- Publication

publicationTests :: TestTree
publicationTests =
  testGroup "publication"
    [ testCase "a draft dossier publishes no hero, artifact or page; a published one publishes them" $ do
        let files status =
              [ (dir </> "project.json", projectJson "demo" [("publication_status", Just status), hero [("src", "hero.webp"), ("alt", "x")], sectionsJson])
              , (dir </> "body.md", "## Pipeline\n")
              , (dir </> "hero.webp", heroBytes)
              , (dir </> "pipeline.svg", svg)
              ]
            sectionsJson = sections [("pipeline", layout "wide-exhibit" [("artifact", imageArtifact "diagram" "pipeline.svg")])]
        withSource (files "draft") $ \root -> do
          s <- loadSite root
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = root </> "dist" } s
          out <- listFiles (root </> "dist")
          assertBool (show out) (not (any ("demo" `isInfixOf`) out))
        withSource (files "published") $ \root -> do
          s <- loadSite root
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = root </> "dist" } s
          out <- listFiles (root </> "dist")
          forM_ ["media/projects/demo/hero.webp", "media/projects/demo/pipeline.svg", "work/demo/index.html"] $ \f ->
            assertBool (f <> " in " <> show out) (f `elem` out)
    , testCase "a draft is still validated: a broken hero fails the build" $
        expectError
          [ (dir </> "project.json", projectJson "demo" [("publication_status", Just "draft"), hero [("src", "missing.webp"), ("alt", "x")]])
          , (dir </> "body.md", "") ]
          (dir </> "project.json") ["\"missing.webp\" does not exist"]
    ]
