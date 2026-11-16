-- | Phase 04: project dossiers, symbolic heroes and the five section
-- layouts.
--
-- As elsewhere, fixture trees go through the real pipeline (load,
-- 'siteFrom', render, and 'buildSite' where files matter), and assertions
-- inspect the generated HTML.
module DossierTests (dossierTests) where

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
import Site.Content.Load (ContentError (..), loadContent)
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
        has html "<div class=\"artifact__viewport\"><img src=\"/media/projects/demo/pipeline.svg\" alt=\"A diagram\""
        has html "<p class=\"artifact__open\"><a href=\"/media/projects/demo/pipeline.svg\">Open the diagram at full size</a></p>"
        (_, html') <- render
          ( demo "## Figure\n" [sections [("figure", layout "wide-exhibit" [("artifact", imageArtifact "image" "figure.svg")])]]
              <> [ (dir </> "figure.svg", svg) ] )
        has html' "<div class=\"artifact artifact--image\"><img src=\"/media/projects/demo/figure.svg\" alt=\"A diagram\""
        hasNot html' "artifact__open"
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
    [ testCase "a hero page opens on the art, with the real title, summary and tags over it" $ do
        (page, html) <- render (demo "## A\n\nText.\n" [hero [("src", "hero.webp"), ("alt", "A gothic window")], showcaseArt] <> heroFiles)
        pageLayout page @?= Dossier
        has html "<main id=\"main\" class=\"interior interior--dossier\"><article class=\"project project--hero\" aria-labelledby=\"demo-title\"><header class=\"project-hero project-hero--focus-center\"><div class=\"project-hero__art\"><img class=\"project-hero__img\" src=\"/media/projects/demo/hero.webp\" alt=\"A gothic window\" fetchpriority=\"high\"/></div><div class=\"project-hero__inner\"><div class=\"project__header\">"
        has html "<h1 class=\"project__title\" id=\"demo-title\">Project demo</h1>"
        -- then the shared shell: sidebar beside the sections
        assertBool "sidebar after the hero" (position html "project-hero" < position html "class=\"project-nav\"")
        -- the card art is the card's; the hero page does not repeat it
        hasNot html "project__showcase"
        T.count "<h1" html @?= 1
    , testCase "decorative heroes have empty alt and are hidden; focus picks the crop" $ do
        (_, html) <- render (demo "## A\n" [hero [("src", "hero.webp"), ("decorative", Json.Bool True), ("focus", "top")]] <> heroFiles)
        has html "<header class=\"project-hero project-hero--focus-top\"><div class=\"project-hero__art\" aria-hidden=\"true\"><img class=\"project-hero__img\" src=\"/media/projects/demo/hero.webp\" alt=\"\""
    , testCase "without a hero, the Phase 02 header and card art remain" $ do
        (page, html) <- render (demo "## A\n" [showcaseArt] <> [ (dir </> "card.svg", svg) ])
        pageLayout page @?= Interior
        hasNot html "project-hero"
        has html "<figure class=\"project__showcase\">"
    , testCase "the alt text policy is explicit: exactly one of alt and decorative" $ do
        let json = dir </> "project.json"
        expectError (demo "## A\n" [hero [("src", "hero.webp")]] <> heroFiles) json
          ["missing \"alt\" (a short description of the artwork) or \"decorative\": true"]
        expectError (demo "## A\n" [hero [("src", "hero.webp"), ("alt", "x"), ("decorative", Json.Bool True)]] <> heroFiles) json
          ["give either \"alt\" or \"decorative\", not both"]
        expectError (demo "## A\n" [hero [("src", "hero.webp"), ("decorative", Json.Bool False)]] <> heroFiles) json
          ["false is not allowed; describe the artwork with \"alt\" instead"]
        expectError (demo "## A\n" [hero [("src", "hero.webp"), ("alt", "a \"quoted\" alt")]] <> heroFiles) json
          ["straight double quote"]
        expectError (demo "## A\n" [hero [("src", "hero.webp"), ("alt", "x"), ("focus", "left")]] <> heroFiles) json
          ["invalid value \"left\"; expected one of: center, top, bottom"]
        expectError (demo "## A\n" [hero [("src", "hero.webp"), ("alt", "x"), ("credit", "me")]] <> heroFiles) json
          ["unknown field \"credit\""]
    , testCase "missing, misplaced, non-image and oversized hero files are errors" $ do
        let json = dir </> "project.json"
            withSrc src = demo "## A\n" [hero [("src", src), ("alt", "x")]]
        expectError (withSrc "hero.webp") json ["field \"hero\": image \"hero.webp\" does not exist"]
        expectError (withSrc "body.md") json ["field \"hero\": image \"body.md\": not an image file"]
        expectError (withSrc "../brigid/hero.webp") json ["field \"hero\""]
        expectError (withSrc "/hero.webp") json ["field \"hero\""]
        expectError (withSrc "hero.webp" <> [ (dir </> "hero.webp", BS.replicate (1024 * 1024 + 1) 0) ]) json
          ["is 1048577 bytes; the limit is 1048576"]
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
