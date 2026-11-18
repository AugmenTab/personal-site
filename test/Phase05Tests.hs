-- | Phase 05: discovery, information architecture and the shared shell.
--
-- As elsewhere, fixture trees go through the real pipeline (load,
-- 'siteFrom', render, and 'buildSite' where files matter), and assertions
-- inspect the generated output.
module Phase05Tests (phase05Tests) where

import Control.Exception (try)
import Control.Monad (forM_)
import Data.Aeson ((.=))
import Data.Aeson qualified as Json
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (isInfixOf, isSuffixOf, sort)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory qualified as Dir
import System.FilePath ((</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import Site.Assets (allAssets, assetPath)
import Site.Build
import Site.Content.Load (ContentError (..), loadContent)
import Site.Content.Types
import Site.Definition (siteFrom)
import Site.Discovery (robotsTxt, sitemapRoutes, sitemapXml)
import Site.Layout (renderPage)
import Site.Page (GeneratedFile (..), Page (..), Site (..), SiteConfig (..))
import Site.Pages.About qualified as About
import Site.Pages.Home qualified as Home
import Site.Routes
import Site.Settings
import Site.Taxonomy
import Site.Validate (activeContent, attributeValues)

import ContentTests (articleJson, listFiles, projectJson, slugOf, svg, withSource)

phase05Tests :: TestTree
phase05Tests =
  testGroup "Phase 05"
    [ taxonomyTests
    , workIndexTests
    , navigationTests
    , resumeTests
    , projectNavTests
    , footerTests
    , settingsTests
    , metadataTests
    , discoveryTests
    , scriptPolicyTests
    ]

--------------------------------------------------------------------------------
-- Fixtures

-- | A project directory: project.json with overrides, a body and card art.
project :: T.Text -> [(T.Text, Maybe Json.Value)] -> [(FilePath, BS.ByteString)]
project slug overrides =
  [ (dir </> "project.json", projectJson slug (("showcase", Just art) : overrides))
  , (dir </> "body.md", "## About\n\nText.\n")
  , (dir </> "card.svg", svg)
  ]
  where
    dir = "content/projects" </> T.unpack slug
    art = Json.object ["kind" .= ("image" :: T.Text), "src" .= ("card.svg" :: T.Text), "alt" .= ("Card art" :: T.Text)]

article :: T.Text -> T.Text -> [(FilePath, BS.ByteString)]
article slug status =
  [ ("content/writing" </> T.unpack slug </> "article.json", articleJson slug status)
  , ("content/writing" </> T.unpack slug </> "body.md", "## Part\n\nText.\n")
  ]

pdf :: BS.ByteString
pdf = "%PDF-1.4\n% test fixture, not a real resume\n%%EOF\n"

strings :: [T.Text] -> Maybe Json.Value
strings = Just . Json.toJSON

-- | Load a fixture tree into a site (failing the test on content errors)
-- and hand it, with the tree's root, to the action.
withSite :: [(FilePath, BS.ByteString)] -> (FilePath -> Site -> IO a) -> IO a
withSite files action =
  withSource files $ \root -> do
    s <- loadSite root
    action root s

render :: Site -> Route -> T.Text
render s route =
  case filter ((== route) . pageRoute) (sitePages s) of
    [p] -> TE.decodeUtf8 (LBS.toStrict (renderPage (siteConfig s) p))
    _ -> error ("no page for " <> show route)

realSite :: IO Site
realSite = loadSite "."

loadErrors :: [(FilePath, BS.ByteString)] -> IO [ContentError]
loadErrors files = withSource files $ \root -> either id (const []) <$> loadContent root

expectError :: [(FilePath, BS.ByteString)] -> FilePath -> [String] -> Assertion
expectError files file needles = do
  errs <- loadErrors files
  let messages = concat [ ms | ContentError f ms <- errs, f == file ]
      shown = concatMap show errs
  assertBool ("expected an error for " <> file <> ", got:\n" <> shown) (not (null messages))
  forM_ needles $ \needle ->
    assertBool ("missing " <> show needle <> " in:\n" <> shown) (any (needle `isInfixOf`) messages)

count :: T.Text -> T.Text -> Int
count needle haystack = length (T.breakOnAll needle haystack)

between :: T.Text -> T.Text -> T.Text -> T.Text
between start end html = fst (T.breakOn end (snd (T.breakOn start html)))

headerOf, footerOf :: T.Text -> T.Text
headerOf = between "<header class=\"site-header\"" "</header>"
footerOf = between "<footer class=\"site-footer\"" "</footer>"

realRoutes :: Site -> [Route]
realRoutes = map pageRoute . sitePages

--------------------------------------------------------------------------------
-- Taxonomy

taxonomyTests :: TestTree
taxonomyTests =
  testGroup "taxonomy"
    [ testCase "the real projects use the controlled vocabulary" $ do
        result <- loadContent "."
        content <- either (\e -> assertFailure (concatMap show e) >> pure emptyContent) pure result
        [ (slugText (projectSlug p), projectCategory p, projectTopics p, projectTechnologies p) | p <- publishedProjects content ]
          @?= [ ("black", ProgrammingLanguages, [TypeSystems, CompilerEngineering, FormalVerification], ["Haskell", "LLVM IR"])
              , ("brigid", LibrariesTooling, [TypeSystems, WebDevelopment], ["Haskell", "HTML"])
              , ("paranoia-engine", SimulationGames, [AIAgents, DeterministicSimulation, GameEngines], ["Rust", "Bevy"])
              ]
    , testCase "ids and labels are unique, and ids round-trip" $ do
        let unique xs = length xs == length (sort xs) && and (zipWith (/=) (sort xs) (drop 1 (sort xs)))
        assertBool "category ids" (unique (map categoryId allCategories))
        assertBool "category labels" (unique (map categoryLabel allCategories))
        assertBool "topic ids" (unique (map topicId allTopics))
        assertBool "topic labels" (unique (map topicLabel allTopics))
        forM_ allCategories $ \c -> parseCategory (categoryId c) @?= Right c
        forM_ allTopics $ \t -> parseTopic (topicId t) @?= Right t
    , testCase "a legacy free-text or unknown category names the vocabulary" $
        forM_ ["Haskell library", "Programming Languages", "games", ""] $ \bad ->
          expectError (project "demo" [("category", Just (Json.String bad))]) "content/projects/demo/project.json"
            (if T.null bad then ["field \"category\": must not be empty"]
             else ["field \"category\": invalid value", "expected one of: programming-languages, libraries-tooling", "controlled vocabulary"])
    , testCase "topics are optional: a record without them still loads (backward compatible)" $ do
        withSource (project "demo" []) $ \root -> do
          result <- loadContent root
          case result of
            Left errs -> assertFailure (concatMap show errs)
            Right c -> map projectTopics (contentProjects c) @?= [[]]
    , testCase "topics come out in vocabulary order, whatever order they were written in" $
        withSource (project "demo" [("topics", strings ["game-engines", "type-systems", "compiler-engineering"])]) $ \root -> do
          result <- loadContent root
          either (assertFailure . concatMap show) (\c -> map projectTopics (contentProjects c) @?= [[TypeSystems, CompilerEngineering, GameEngines]]) result
    , testCase "unknown, duplicate, empty and too many topics are rejected" $ do
        let file = "content/projects/demo/project.json"
        expectError (project "demo" [("topics", strings ["type-sytems"])]) file ["unknown topic \"type-sytems\"", "expected one of: type-systems"]
        expectError (project "demo" [("topics", strings ["Type Systems"])]) file ["unknown topic \"Type Systems\""]
        expectError (project "demo" [("topics", strings ["type-systems", "type-systems"])]) file ["lists \"type-systems\" more than once"]
        expectError (project "demo" [("topics", strings [""])]) file ["must not be empty"]
        expectError (project "demo" [("topics", Just "type-systems")]) file ["field \"topics\": expected an array"]
        expectError (project "demo" [("topics", strings (take 6 (map topicId allTopics)))]) file ["has 6 topics; at most 5"]
    , testCase "duplicate technologies (ignoring case) and misfiled topics or categories are rejected" $ do
        let file = "content/projects/demo/project.json"
        expectError (project "demo" [("technologies", strings ["Haskell", "haskell"])]) file ["\"haskell\" more than once (ignoring case)"]
        expectError (project "demo" [("technologies", strings ["Haskell", "Type systems"])]) file ["\"Type systems\" is the topic \"type-systems\"; list it under \"topics\""]
        expectError (project "demo" [("technologies", strings ["Rust", "Simulation & Games"])]) file ["is a category"]
        expectError (project "demo" [("technologies", strings ["Rust", ""])]) file ["must not be empty"]
    , testCase "cards and dossiers show the category label and the topics" $ do
        s <- realSite
        let black = render s (WorkDetail (slugOf "black"))
        assertBool "kicker" ("<p class=\"project__kicker\">Programming Languages · In development</p>" `T.isInfixOf` black)
        assertBool "topics" ("<ul class=\"project__topics\" aria-label=\"Topics\"><li>Type Systems</li><li>Compiler Engineering</li><li>Formal Verification</li></ul>" `T.isInfixOf` black)
        assertBool "card category" ("<span class=\"project-card__category\">Libraries &#38; Tooling</span>" `T.isInfixOf` render s WorkIndex)
        assertBool "card tags are labelled technologies" (count "class=\"project-card__tags\" aria-label=\"Technologies\"" (render s WorkIndex) == 3)
    ]

--------------------------------------------------------------------------------
-- Work index

workIndexTests :: TestTree
workIndexTests =
  testGroup "Work index"
    [ testCase "every published project is an item with its category and search text, in index order" $ do
        s <- realSite
        let html = render s WorkIndex
            list = between "<ul class=\"work__list work__list--index\" id=\"work-list\">" "</ul></section>" html
        attributeValues "data-category" list @?= ["programming-languages", "libraries-tooling", "simulation-games"]
        [ T.takeWhile (/= ' ') t | t <- attributeValues "data-search" list ] @?= ["black", "brigid", "paranoia-engine"]
        let brigid = attributeValues "data-search" list !! 1
        forM_ ["brigid", "type-safe html", "libraries &#38; tooling", "haskell", "type systems", "web development"] $ \needle ->
          assertBool (T.unpack needle) (needle `T.isInfixOf` brigid)
        assertBool "lowercase" (T.toLower brigid == brigid)
        assertBool "single spaces" (not ("  " `T.isInfixOf` brigid))
    , testCase "without JavaScript every card is shown and no control is: the controls and empty message are hidden" $ do
        s <- realSite
        let html = render s WorkIndex
        assertBool "controls hidden" ("<search class=\"work-filter\" id=\"work-filter\" hidden" `T.isInfixOf` html)
        assertBool "empty message hidden" ("<div class=\"work-filter__empty\" id=\"work-empty\" hidden>" `T.isInfixOf` html)
        count "<li class=\"work__item\"" html @?= 3
        assertBool "no item starts hidden" (not ("work__item\" hidden" `T.isInfixOf` html))
        count "class=\"project-card__link\"" html @?= 3
    , testCase "the controls: a labelled search field, All plus one chip per used category, a live count" $ do
        s <- realSite
        let html = render s WorkIndex
            controls = between "<search class=\"work-filter\"" "</search>" html
        assertBool "label" ("<label class=\"work-filter__label\" for=\"work-search\">Search projects</label>" `T.isInfixOf` controls)
        assertBool "search input" ("<input type=\"search\" class=\"work-filter__input\" id=\"work-search\"" `T.isInfixOf` controls)
        attributeValues "data-category" controls @?= ["", "programming-languages", "libraries-tooling", "simulation-games"]
        attributeValues "aria-pressed" controls @?= ["true", "false", "false", "false"]
        assertBool "group" ("role=\"group\" aria-label=\"Filter by category\"" `T.isInfixOf` controls)
        assertBool "live count" ("<p class=\"work-filter__status\" id=\"work-status\" aria-live=\"polite\">3 projects</p>" `T.isInfixOf` controls)
    , testCase "chips list only the categories in use, in vocabulary order; drafts are not listed or searchable" $
        withSite
          ( project "zeta" [("category", Just "creative-technology")]
              <> project "alpha" [("category", Just "ai-automation")]
              <> project "hidden" [("category", Just "programming-languages"), ("publication_status", Just "draft"), ("title", Just "Secret engine")] ) $ \_ s -> do
          let html = render s WorkIndex
          attributeValues "data-category" (between "<search" "</search>" html) @?= ["", "ai-automation", "creative-technology"]
          attributeValues "data-category" (between "id=\"work-list\"" "</ul></section>" html) @?= ["ai-automation", "creative-technology"]
          forM_ ["/work/hidden/", "hidden-title", "secret engine", "programming-languages"] $ \needle ->
            assertBool (T.unpack needle) (not (needle `T.isInfixOf` T.toLower html))
    , testCase "with no published projects there are no controls and no script" $
        withSite [] $ \_ s -> do
          let html = render s WorkIndex
          forM_ ["<search", "<script", "work-filter", "id=\"work-list\""] $ \needle ->
            assertBool (T.unpack needle) (not (needle `T.isInfixOf` html))
    , testCase "the index grid is scoped: the homepage keeps its own list classes" $ do
        s <- realSite
        let work = render s WorkIndex
            home = render s Home
        assertBool "index modifier" ("work__list--index" `T.isInfixOf` work)
        assertBool "index has no home modifier" (not ("work__list--home" `T.isInfixOf` work))
        assertBool "home modifier" ("work__list work__list--home work__list--count-2" `T.isInfixOf` home)
        assertBool "home has no index modifier" (not ("work__list--index" `T.isInfixOf` home))
    ]

--------------------------------------------------------------------------------
-- Navigation

navigationTests :: TestTree
navigationTests =
  testGroup "navigation"
    [ testCase "every page: Home, Work, Writing | monogram | About, Resume, Contact (/#contact); the target exists on the homepage" $ do
        s <- realSite
        forM_ (realRoutes s) $ \r -> do
          let header = headerOf (render s r)
          attributeValues "href" header @?= ["/", "/work/", "/writing/", "/", "/about/", "/resume.pdf", "/#contact"]
        count "id=\"contact\"" (render s Home) @?= 1
    , testCase "on the homepage only Home is current, never Contact" $ do
        s <- realSite
        let header = headerOf (render s Home)
        count "aria-current=\"page\"" header @?= 1
        assertBool "home current" ("href=\"/\" aria-current=\"page\">Home</a>" `T.isInfixOf` header)
        assertBool "contact not current" ("href=\"/#contact\">Contact</a>" `T.isInfixOf` header)
    , testCase "Writing is always in the nav, before the monogram, with or without published writing" $ do
        withSite (article "draft-only" "draft") $ \_ s ->
          attributeValues "href" (headerOf (render s Home)) @?= ["/", "/work/", "/writing/", "/", "/about/", "/#contact"]
        withSite (article "first" "published") $ \_ s ->
          attributeValues "href" (headerOf (render s Home)) @?= ["/", "/work/", "/writing/", "/", "/about/", "/#contact"]
    , testCase "the real Writing page: heading, Coming soon, valid metadata, no list or fake entries" $ do
        s <- realSite
        let html = render s WritingIndex
            main = between "<main" "</main>" html
        assertBool "heading" ("<span class=\"section-title__text\">Writing</span></h1>" `T.isInfixOf` main)
        assertBool "coming soon" ("<p class=\"page-lede writing__empty\">Coming soon.</p>" `T.isInfixOf` main)
        forM_ ["writing__list", "writing__item", "<ul", "<article", "href="] $ \needle ->
          assertBool ("empty state has " <> T.unpack needle) (not (needle `T.isInfixOf` main))
        assertBool "canonical" ("<link rel=\"canonical\" href=\"https://tylerbaum.dev/writing/\"/>" `T.isInfixOf` html)
        assertBool "og:url" ("content=\"https://tylerbaum.dev/writing/\"" `T.isInfixOf` html)
        assertBool "description" ("<meta name=\"description\" content=\"Technical writing by Tyler Baum.\"/>" `T.isInfixOf` html)
        assertBool "current page" ("href=\"/writing/\" aria-current=\"page\">Writing</a>" `T.isInfixOf` headerOf html)
    , testCase "final order with every destination: Home Work Writing | monogram | About Resume Contact" $
        withSite (("content/resume.pdf", pdf) : article "first" "published") $ \_ s -> do
          let header = headerOf (render s About)
              labels = [ T.strip (fst (T.breakOn "<" (T.drop 1 (snd (T.breakOn ">" rest)))))
                       | rest <- drop 1 (T.splitOn "class=\"site-nav__link\"" header) ]
          attributeValues "href" header @?= ["/", "/work/", "/writing/", "/", "/about/", "/resume.pdf", "/#contact"]
          labels @?= ["Home", "Work", "Writing", "About", "Resume", "Contact"]
          assertBool "monogram between Writing and About"
            (T.isInfixOf "/writing/" (fst (T.breakOn "site-nav__mark" header)) && T.isInfixOf "/about/" (snd (T.breakOn "site-nav__mark" header)))
    , testCase "the About page is a profile: no contact destinations, but a way to Contact" $ do
        s <- realSite
        let about = render s About
            main = between "<main" "</main>" about
        assertBool "no github in the profile" (not ("github.com" `T.isInfixOf` main))
        attributeValues "href" main @?= ["/#contact"]
        assertBool "emblem" ("about-tree.webp" `T.isInfixOf` main)
        About.profileStatus About.profile @?= Home.FinalCopy
        assertBool "approved personal lede" ("I've never had much success keeping my interests in separate boxes." `T.isInfixOf` main)
        assertBool "three prose paragraphs" (count "class=\"about__bio\"" main == 3)
        assertBool "no old portfolio-in-progress note" (not ("This site is a portfolio in progress." `T.isInfixOf` main))
    ]

--------------------------------------------------------------------------------
-- Résumé

resumeTests :: TestTree
resumeTests =
  testGroup "résumé"
    [ testCase "the real site publishes content/resume.pdf and links it from every nav and footer" $ do
        s <- realSite
        assertBool "a résumé URL" (siteResumeUrl (siteConfig s) /= Nothing)
        forM_ (realRoutes s) $ \r -> do
          let html = render s r
              link = "href=\"/resume.pdf\">Resume<span class=\"visually-hidden\"> (PDF)</span></a>"
          assertBool (show r <> " nav") (link `T.isInfixOf` headerOf html)
          assertBool (show r <> " footer") (link `T.isInfixOf` footerOf html)
          assertBool (show r <> " no accent") (not ("Résumé" `T.isInfixOf` html))
    , testCase "a valid content/resume.pdf is published at /resume.pdf and linked from the nav and footer" $
        withSite (("content/resume.pdf", pdf) : project "demo" []) $ \root s -> do
          forM_ (realRoutes s) $ \r -> do
            let html = render s r
            assertBool (show r <> " nav") ("href=\"/resume.pdf\">Resume<span class=\"visually-hidden\"> (PDF)</span></a>" `T.isInfixOf` headerOf html)
            assertBool (show r <> " footer") ("href=\"/resume.pdf\">Resume<span class=\"visually-hidden\"> (PDF)</span></a>" `T.isInfixOf` footerOf html)
            assertBool (show r <> " no accented label") (not ("Résumé" `T.isInfixOf` html))
          let out = root </> "dist"
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = out } s
          BS.readFile (out </> "resume.pdf") >>= (@?= pdf)
          sitemap <- TE.decodeUtf8 <$> BS.readFile (out </> "sitemap.xml")
          assertBool "the PDF is not a sitemap page" (not ("resume" `T.isInfixOf` sitemap))
    , testCase "a résumé that is not a PDF, is too large, or escapes content/ is rejected" $ do
        expectError [("content/resume.pdf", "<html>not a pdf</html>")] "content/resume.pdf" ["is not a PDF"]
        expectError [("content/resume.pdf", "%PDF-" <> BS.replicate (10 * 1024 * 1024) 0)] "content/resume.pdf" ["a résumé may be at most 10.00 MiB"]
        withSource [("outside.pdf", pdf), ("content/projects/.keep", "")] $ \root -> do
          Dir.createFileLink (root </> "outside.pdf") (root </> "content/resume.pdf")
          result <- loadContent root
          case result of
            Left errs -> assertBool (concatMap show errs) ("outside its permitted directory" `isInfixOf` concatMap show errs)
            Right _ -> assertFailure "a symlinked résumé loaded"
    , testCase "an invalid résumé fails the build and keeps the previous output" $
        withSource (project "demo" []) $ \root -> do
          let out = root </> "dist"
              config = BuildConfig { sourceRoot = root, outputDir = out }
          _ <- loadSite root >>= buildSite config
          before <- listFiles out
          BS.writeFile (root </> "content/resume.pdf") "not a pdf"
          result <- try (loadSite root >>= buildSite config)
          case result of
            Left (InvalidContent _) -> pure ()
            Left other -> assertFailure (show other)
            Right _ -> assertFailure "built with an invalid résumé"
          listFiles out >>= (@?= before)
    ]

--------------------------------------------------------------------------------
-- Compact project navigation

projectNavTests :: TestTree
projectNavTests =
  testGroup "compact project navigation"
    [ testCase "every real project: the mobile index lists exactly the sidebar's links, collapsed" $ do
        s <- realSite
        forM_ [ r | r@(WorkDetail _) <- realRoutes s ] $ \r -> do
          let html = render s r
              nav = between "<nav class=\"project-nav\"" "</nav>" html
              desktop = between "<ul class=\"project-nav__sections\"" "</ul>" nav
              compact = between "<details class=\"project-nav__index\">" "</details>" nav
          assertBool (show r <> " has links") (not (null (attributeValues "href" desktop)))
          attributeValues "href" compact @?= attributeValues "href" desktop
          assertBool "summary" ("<summary class=\"project-nav__summary\"><span class=\"project-nav__summary-label\">On this page</span>" `T.isInfixOf` compact)
          assertBool "collapsed by default" (not ("<details class=\"project-nav__index\" open" `T.isInfixOf` nav))
          -- every link has its target, once
          forM_ (attributeValues "href" desktop) $ \href -> count ("id=\"" <> T.drop 1 href <> "\"") html @?= 1
          -- one current-project tab (hidden by CSS below 900px), no second title
          count "project-nav__current" nav @?= 1
          count "<h1" html @?= 1
    , testCase "short and long titles, few and many sections, long and nested headings" $ do
        let longTitle = "An Exceptionally Long Project Title For Wrapping Tests"
            longHeading = "A very long section heading that must wrap rather than overflow the index"
            body = T.unlines (concat [ ["## Section " <> T.pack (show n), "", "Text.", "", "### Nested " <> T.pack (show n), "", "More."] | n <- [1 .. 12 :: Int] ] <> ["## " <> longHeading, "", "End."])
        withSite (project "many" [("title", Just (Json.String longTitle))] <> [("content/projects/many/body.md", TE.encodeUtf8 body)] <> project "few" [("title", Just "Ox")]) $ \_ s -> do
          let many = render s (WorkDetail (slugOf "many"))
              compact = between "<details class=\"project-nav__index\">" "</details>" many
              links = attributeValues "href" compact
          length links @?= 13
          assertBool "count" (">13 sections</span>" `T.isInfixOf` compact)
          assertBool "long heading" (longHeading `T.isInfixOf` compact)
          assertBool "nested headings are not listed" (not ("nested" `T.isInfixOf` T.toLower compact))
          assertBool "nested headings are on the page" ("id=\"nested-3\">Nested 3</h3>" `T.isInfixOf` many)
          -- the h1 and the desktop tab (not displayed below 900px)
          count longTitle (between "<main" "</main>" many) @?= 2
          let few = render s (WorkDetail (slugOf "few"))
          assertBool "one section" (">1 section</span>" `T.isInfixOf` few)
    , testCase "a dossier without listed sections has no index at all" $
        withSite (project "bare" [] <> [("content/projects/bare/body.md", "Just a lead.\n")]) $ \_ s -> do
          let html = render s (WorkDetail (slugOf "bare"))
          forM_ ["<details", "project-nav__sections", "project-nav__index"] $ \needle ->
            assertBool (T.unpack needle) (not (needle `T.isInfixOf` html))
          assertBool "All projects" ("class=\"project-nav__back\" href=\"/work/\"" `T.isInfixOf` html)
    , testCase "hero-less dossiers open with the header and go straight to the content" $ do
        s <- realSite
        forM_ ["black", "brigid", "paranoia-engine"] $ \slug -> do
          let html = render s (WorkDetail (slugOf (T.pack slug)))
          assertBool slug ("</nav><div class=\"project__body\"><" `T.isInfixOf` html)
          assertBool (slug <> ": no showcase figure") (not ("project__showcase" `T.isInfixOf` html))
          assertBool (slug <> ": no card art") (not ("card.svg" `T.isInfixOf` html))
        -- meaningful exhibits stay: Black's pipeline diagram and code panels
        let black = render s (WorkDetail (slugOf "black"))
        assertBool "diagram" ("/media/projects/black/pipeline.svg" `T.isInfixOf` black)
        count "artifact--code" black @?= 2
    ]

--------------------------------------------------------------------------------
-- Footer

footerTests :: TestTree
footerTests =
  testGroup "footer"
    [ testCase "every page has the footer: identity, site links, copyright and an accurate colophon" $ do
        s <- realSite
        forM_ (realRoutes s) $ \r -> do
          let footer = footerOf (render s r)
          forM_ [ "<p class=\"site-footer__name\">Tyler Baum</p>"
                , "<p class=\"site-footer__thesis\">Building precise systems for ambitious ideas.</p>"
                , "<nav class=\"site-footer__nav\" aria-label=\"Footer\">"
                , "<p class=\"site-footer__copyright\">© 2026 Tyler Baum</p>"
                , "<p class=\"site-footer__colophon\">Built with Haskell &#38; Brigid.</p>" ] $ \needle ->
            assertBool (show r <> ": " <> T.unpack needle) (needle `T.isInfixOf` footer)
          attributeValues "href" (between "site-footer__nav" "</nav>" footer) @?= ["/work/", "/writing/", "/about/", "/resume.pdf"]
          forM_ ["monogram", "about-tree", "<img"] $ \needle ->
            assertBool (show r <> ": footer has " <> T.unpack needle) (not (needle `T.isInfixOf` footer))
    , testCase "contact destinations: in the footer everywhere except the homepage, where Contact sits directly above" $ do
        s <- realSite
        forM_ (realRoutes s) $ \r -> do
          let footer = footerOf (render s r)
          if r == Home
            then assertBool "home: no contact column" (not ("site-footer__contact" `T.isInfixOf` footer))
            else attributeValues "href" (between "site-footer__contact" "</ul>" footer) @?= ["https://github.com/AugmenTab", "https://www.linkedin.com/in/thebaum/", "mailto:tyler.baum@protonmail.com"]
        -- each destination is one control within the homepage's Contact section
        count "https://github.com/AugmenTab" (render s Home) @?= 1
    , testCase "optional destinations appear only when configured" $
        withSite (("content/resume.pdf", pdf) : article "post" "published") $ \_ s -> do
          let footer = footerOf (render s About)
          attributeValues "href" (between "site-footer__nav" "</nav>" footer) @?= ["/work/", "/writing/", "/about/", "/resume.pdf"]
    ]

--------------------------------------------------------------------------------
-- Settings

settingsTests :: TestTree
settingsTests =
  testGroup "settings"
    [ testCase "the real settings are valid: production origin and verified contacts" $ do
        settingsProblems ownerSettings @?= []
        settingsOrigin ownerSettings @?= "https://tylerbaum.dev"
        settingsContacts ownerSettings @?= [GitHub "AugmenTab", LinkedIn "thebaum", Email "tyler.baum@protonmail.com"]
    , testCase "malformed origins, years and contacts are reported" $ do
        let with f = settingsProblems (f ownerSettings)
            bad label problems = assertBool (label <> ": " <> show problems) (not (null problems))
        bad "http" (with (\s -> s { settingsOrigin = "http://tylerbaum.dev" }))
        bad "trailing slash" (with (\s -> s { settingsOrigin = "https://tylerbaum.dev/" }))
        bad "path" (with (\s -> s { settingsOrigin = "https://tylerbaum.dev/site" }))
        bad "no dot" (with (\s -> s { settingsOrigin = "https://localhost" }))
        bad "year" (with (\s -> s { settingsCopyrightYears = "26" }))
        bad "range" (with (\s -> s { settingsCopyrightYears = "2027–2026" }))
        forM_ [ Email "no-at-sign", Email "a@b", Email "Name <a@example.com>", Email "a@example.com?subject=x", Email "a@Example.com"
              , GitHub "", GitHub "-x", GitHub "a/b", LinkedIn "x", LinkedIn "a b c" ] $ \c ->
          bad (show c) (with (\s -> s { settingsContacts = [c] }))
        bad "duplicate kind" (with (\s -> s { settingsContacts = [GitHub "a", GitHub "b"] }))
        with (\s -> s { settingsCopyrightYears = "2026–2027" }) @?= []
        with (\s -> s { settingsContacts = [Email "first.last+site@example.co.uk", LinkedIn "first-last-123", GitHub "AugmenTab"] }) @?= []
    , testCase "configured LinkedIn and Email render as single controls, in a fixed order" $ do
        result <- loadContent "."
        content <- either (\e -> assertFailure (concatMap show e) >> pure emptyContent) pure result
        let s = siteFrom content
            settings = ownerSettings { settingsContacts = [Email "name@example.com", GitHub "AugmenTab", LinkedIn "some-profile"] }
            config = (siteConfig s) { siteSettings = settings }
            home = TE.decodeUtf8 (LBS.toStrict (renderPage config (Home.page config (Home.homeContent content))))
            about = TE.decodeUtf8 (LBS.toStrict (renderPage config (About.page config)))
            section = between "id=\"contact\"" "</section>" home
            expected = ["https://github.com/AugmenTab", "https://www.linkedin.com/in/some-profile/", "mailto:name@example.com"]
        attributeValues "href" section @?= expected
        attributeValues "href" (between "site-footer__contact" "</ul>" (footerOf about)) @?= expected
        forM_ expected $ \href -> count ("href=\"" <> href <> "\"") home @?= 1
        -- Phase 05 update 1: each card is one link holding an icon and the
        -- label; the address is screen-reader text only
        assertBool "email card"
          ("<a class=\"contact__link\" href=\"mailto:name@example.com\"><span class=\"contact__icon contact__icon--email\" aria-hidden=\"true\"></span><span class=\"contact__label\">Email</span><span class=\"visually-hidden\">: name@example.com</span></a>" `T.isInfixOf` section)
        forM_ ["github", "linkedin", "email"] $ \kind -> count ("contact__icon--" <> kind) section @?= 1
        count "<a " section @?= 3
    , testCase "contact cards show an icon and the label, never the URL (Phase 05 update 1)" $ do
        s <- realSite
        let section = between "id=\"contact\"" "</section>" (render s Home)
            visible = T.concat [ fst (T.breakOn "<" t) | t <- drop 1 (T.splitOn ">" (foldr (\(from, to) acc -> T.replace from to acc) section [ ("<span class=\"visually-hidden\">: github.com/AugmenTab</span>", ""), ("<span class=\"visually-hidden\">: linkedin.com/in/thebaum</span>", ""), ("<span class=\"visually-hidden\">: tyler.baum@protonmail.com</span>", "") ])) ]
        assertBool "card" ("<a class=\"contact__link\" href=\"https://github.com/AugmenTab\"><span class=\"contact__icon contact__icon--github\" aria-hidden=\"true\"></span><span class=\"contact__label\">GitHub</span><span class=\"visually-hidden\">: github.com/AugmenTab</span></a>" `T.isInfixOf` section)
        assertBool ("no visible URL in: " <> T.unpack visible) (not (any (`T.isInfixOf` visible) ["github.com", "linkedin.com", "protonmail.com"]))
        assertBool "no display span" (not ("contact__display" `T.isInfixOf` section))
        -- the icon is decorative and the card is the only control
        count "<a " section @?= 3
        count "<img" section @?= 0
    , testCase "every contact icon is a listed asset referenced by the stylesheet" $ do
        css <- TE.decodeUtf8 <$> BS.readFile "assets/styles/site.css"
        forM_ ["github", "linkedin", "email"] $ \kind -> do
          assertBool (T.unpack kind) (("images/icon-" <> T.unpack kind <> ".svg") `elem` map assetPath allAssets)
          assertBool (T.unpack kind) (("url(\"../images/icon-" <> kind <> ".svg\")") `T.isInfixOf` css)
    , testCase "invalid settings are reported as a build failure naming the file" $
        -- loadSite runs settingsProblems on the compiled settings before
        -- loading anything; this is the message the CLI prints.
        show (InvalidSettings ["settingsOrigin \"http://x\" must start with https://"])
          @?= "Build failed: invalid site settings (src/Site/Settings.hs):\n  - settingsOrigin \"http://x\" must start with https://\n"
    ]

--------------------------------------------------------------------------------
-- Metadata

metadataTests :: TestTree
metadataTests =
  testGroup "metadata"
    [ testCase "indexable pages: canonical and og:url are the production URL; title and description match" $ do
        s <- realSite
        forM_ (sitePages s) $ \p -> do
          let html = render s (pageRoute p)
              headHtml = between "<head>" "</head>" html
              url = "https://tylerbaum.dev" <> routePath (pageRoute p)
          if pageRoute p == NotFound
            then do
              assertBool "noindex" ("<meta name=\"robots\" content=\"noindex\"/>" `T.isInfixOf` headHtml)
              forM_ ["rel=\"canonical\"", "og:url"] $ \needle -> assertBool ("404 " <> T.unpack needle) (not (needle `T.isInfixOf` headHtml))
            else do
              count "rel=\"canonical\"" headHtml @?= 1
              assertBool "canonical" (("<link rel=\"canonical\" href=\"" <> url <> "\"/>") `T.isInfixOf` headHtml)
              assertBool "og:url" (("<meta property=\"og:url\" content=\"" <> url <> "\"/>") `T.isInfixOf` headHtml)
              assertBool "indexable" (not ("noindex" `T.isInfixOf` headHtml))
          forM_ [ ("og:title", pageTitle p), ("og:description", pageDescription p), ("og:site_name", "Tyler Baum"), ("og:type", "website"), ("og:locale", "en_US") ] $ \(prop, value) ->
            assertBool (show (pageRoute p) <> " " <> T.unpack prop)
              (("<meta property=\"" <> prop <> "\" content=\"" <> T.replace "&" "&#38;" value <> "\"/>") `T.isInfixOf` headHtml)
          assertBool "twitter card" ("<meta name=\"twitter:card\" content=\"summary\"/>" `T.isInfixOf` headHtml)
          assertBool "icon" ("rel=\"icon\" href=\"/assets/brand/favicon.svg\"" `T.isInfixOf` headHtml)
          -- no fabricated preview artwork
          forM_ ["og:image", "twitter:image"] $ \needle -> assertBool (T.unpack needle) (not (needle `T.isInfixOf` headHtml))
    , testCase "articles are og:type article; draft articles are in no metadata" $
        withSite (article "public-post" "published" <> article "secret-post" "draft") $ \root s -> do
          let html = render s (WritingArticle (slugOf "public-post"))
          assertBool "article type" ("<meta property=\"og:type\" content=\"article\"/>" `T.isInfixOf` html)
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = root </> "dist" } s
          files <- listFiles (root </> "dist")
          everything <- mapM (\f -> BS.readFile (root </> "dist" </> f)) files
          assertBool "no draft anywhere in the output" (not (any ("secret-post" `BS.isInfixOf`) everything))
    ]

--------------------------------------------------------------------------------
-- Sitemap and robots

discoveryTests :: TestTree
discoveryTests =
  testGroup "sitemap and robots"
    [ testCase "the real sitemap lists every page but the 404, sorted by path" $ do
        s <- realSite
        let sitemap = contentsOf s "sitemap.xml"
        urls sitemap @?= map ("https://tylerbaum.dev" <>) ["/", "/about/", "/work/", "/work/black/", "/work/brigid/", "/work/paranoia-engine/", "/writing/"]
        assertBool "xml declaration" ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" `T.isPrefixOf` sitemap)
        assertBool "namespace" ("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">" `T.isInfixOf` sitemap)
        assertBool "no 404" (not ("404" `T.isInfixOf` sitemap))
        sitemapRoutes [NotFound, About, Home] @?= [Home, About]
    , testCase "robots.txt allows everything and names the production sitemap" $ do
        robotsTxt ownerSettings @?= "User-agent: *\nAllow: /\n\nSitemap: https://tylerbaum.dev/sitemap.xml\n"
        s <- realSite
        contentsOf s "robots.txt" @?= robotsTxt ownerSettings
        assertBool "no disallow" (not ("Disallow" `T.isInfixOf` robotsTxt ownerSettings))
    , testCase "drafts never reach the sitemap; published writing does" $
        withSite (project "live" [] <> project "hidden" [("publication_status", Just "draft")] <> article "post" "published" <> article "secret" "draft") $ \_ s -> do
          let sitemap = contentsOf s "sitemap.xml"
          urls sitemap @?= map ("https://tylerbaum.dev" <>) ["/", "/about/", "/work/", "/work/live/", "/writing/", "/writing/post/"]
    , testCase "the build writes both files, byte-identically on every run, and no sources" $
        withSite (project "one" [("featured_order", Just (Json.Number 1))] <> article "post" "published") $ \root s -> do
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = root </> "a" } s
          s' <- loadSite root
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = root </> "b" } s'
          a <- listFiles (root </> "a")
          forM_ ["sitemap.xml", "robots.txt"] $ \f -> do
            assertBool f (f `elem` a)
            x <- BS.readFile (root </> "a" </> f)
            y <- BS.readFile (root </> "b" </> f)
            x @?= y
          sitemap <- TE.decodeUtf8 <$> BS.readFile (root </> "a" </> "sitemap.xml")
          sitemap @?= sitemapXml ownerSettings (map pageRoute (sitePages s))
          assertBool (show a) (not (any (\f -> ".md" `isSuffixOf` f || ".json" `isSuffixOf` f) a))
    ]
  where
    contentsOf s path =
      case [ generatedContents g | g <- siteGenerated s, generatedPath g == path ] of
        [c] -> c
        _ -> error ("no generated " <> path)
    urls sitemap = [ T.takeWhile (/= '<') (T.drop 5 rest) | line <- T.lines sitemap, let rest = snd (T.breakOn "<loc>" line), not (T.null rest) ]

--------------------------------------------------------------------------------
-- Script policy

scriptPolicyTests :: TestTree
scriptPolicyTests =
  testGroup "script policy"
    [ testCase "only the external module script from /assets/scripts/ is allowed" $ do
        activeContent "<script type=\"module\" src=\"/assets/scripts/work-filter.js\"></script>" @?= []
        activeContent "<script src=\"/assets/scripts/work-filter.js\" type=\"module\"></script>" @?= []
        forM_
          [ "<script>alert(1)</script>"
          , "<script type=\"module\" src=\"/assets/scripts/work-filter.js\">alert(1)</script>"
          , "<script type=\"module\" src=\"https://evil.example/x.js\"></script>"
          , "<script type=\"module\" src=\"/media/projects/x/evil.js\"></script>"
          , "<script src=\"/assets/scripts/work-filter.js\"></script>"
          , "<script type=\"module\" src=\"/assets/scripts/work-filter.js\" onload=\"x()\"></script>"
          , "<script type=\"module\" src=\"/assets/scripts/../x.js\"></script>"
          , "<script type=\"text/javascript\" src=\"/assets/scripts/work-filter.js\"></script>"
          ] $ \tag -> assertBool (T.unpack tag) (not (null (activeContent tag)))
    , testCase "the real Work index passes the scan, and the script file is a listed asset" $ do
        s <- realSite
        activeContent (render s WorkIndex) @?= []
        assertBool "listed" ("scripts/work-filter.js" `elem` map assetPath (siteAssets s))
        exists <- Dir.doesFileExist "assets/scripts/work-filter.js"
        assertBool "script file" exists
        -- no other page loads it
        forM_ (filter (/= WorkIndex) (realRoutes s)) $ \r ->
          assertBool (show r) (not ("work-filter.js" `T.isInfixOf` render s r))
    ]
