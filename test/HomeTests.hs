-- | Phase 03: the complete scrolling homepage.
--
-- Fixture trees go through the real pipeline (load, 'siteFrom', render,
-- and where it matters 'buildSite'), so these assertions describe the
-- generated homepage, not an intermediate value.
module HomeTests (homeTests) where

import Control.Exception (try)
import Control.Monad (forM_)
import Data.Aeson ((.=))
import Data.Aeson qualified as Json
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Char (isDigit)
import Data.List (isInfixOf, sort)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory qualified as Dir
import System.FilePath ((</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import Site.Build
import Site.Content.Load (loadContent)
import Site.Content.Types
import Site.Definition (siteFrom)
import Site.Layout (ContactCopy (..), contactCopy, renderPage)
import Site.Page (Page (..), Site (..))
import Site.Pages.Home
import Site.Settings (contactHref, contacts, ownerSettings)
import Site.Routes
import Site.Validate (attributeValues)

import ContentTests (listFiles, projectJson, readTree, slugOf, svg, withSource)

homeTests :: TestTree
homeTests =
  testGroup "homepage (Phase 03)"
    [ realSiteTests
    , selectedWorkTests
    , blackTeaserTests
    , writingPreviewTests
    , structureTests
    , reliabilityTests
    ]

--------------------------------------------------------------------------------
-- Fixtures

-- | A featured, published project with card art.
featured :: T.Text -> Int -> [(FilePath, BS.ByteString)]
featured slug n = project slug [("featured_order", Just (Json.Number (fromIntegral n)))]

-- | A project directory with the given overrides, a body and card art.
project :: T.Text -> [(T.Text, Maybe Json.Value)] -> [(FilePath, BS.ByteString)]
project slug overrides =
  [ (dir </> "project.json", projectJson slug (("showcase", Just art) : overrides))
  , (dir </> "body.md", "## About\n\nText.\n")
  , (dir </> "card.svg", svg)
  ]
  where
    dir = "content/projects" </> T.unpack slug
    art = Json.object ["kind" .= ("image" :: T.Text), "src" .= ("card.svg" :: T.Text), "alt" .= ("Card art" :: T.Text)]

-- | An article with an optional date.
article :: T.Text -> T.Text -> Maybe T.Text -> [(FilePath, BS.ByteString)]
article slug status date =
  [ (dir </> "article.json", LBS.toStrict (Json.encode (Json.object fields)))
  , (dir </> "body.md", "## Part\n\nText.\n")
  ]
  where
    dir = "content/writing" </> T.unpack slug
    fields =
      [ "slug" .= slug
      , "title" .= ("Article " <> slug)
      , "summary" .= ("Summary of " <> slug <> ".")
      , "publication_status" .= status
      , "body" .= ("body.md" :: T.Text)
      ]
        <> [ "date" .= d | Just d <- [date] ]

-- | Load a fixture tree; fail the test on content errors.
loadFixture :: FilePath -> IO Content
loadFixture root = do
  loaded <- loadContent root
  either (\errs -> assertFailure (concatMap show errs) >> pure emptyContent) pure loaded

-- | The rendered homepage of a fixture tree, with the site it came from.
homeOf :: [(FilePath, BS.ByteString)] -> IO (Site, T.Text)
homeOf files =
  withSource files $ \root -> do
    content <- loadFixture root
    let s = siteFrom content
    pure (s, render s Home)

render :: Site -> Route -> T.Text
render s route =
  case filter ((== route) . pageRoute) (sitePages s) of
    [p] -> TE.decodeUtf8 (LBS.toStrict (renderPage (siteConfig s) p))
    _ -> error ("no page for " <> show route)

-- | The markup of one homepage section, from its opening tag to the next
-- top-level section of the page.
-- | The page's own content: everything inside @<main>@, without the shared
-- navigation and footer (which always link to /writing/).
mainOf :: T.Text -> T.Text
mainOf html = fst (T.breakOn "</main>" (snd (T.breakOn "<main" html)))

sectionOf :: T.Text -> T.Text -> T.Text
sectionOf sid html =
  let rest = snd (T.breakOn ("id=\"" <> sid <> "\"") html)
   in if T.null rest then "" else fst (T.breakOn "</section>" (T.drop 1 rest))

-- | The section, including nested sections (for Selected Work's cards, which
-- are articles, the first closing @</section>@ is the section's own).
cardHrefs :: T.Text -> [T.Text]
cardHrefs html =
  [ T.takeWhile (/= '"') (T.drop (T.length marker) rest)
  | (_, rest) <- T.breakOnAll marker (sectionOf "selected-work" html)
  ]
  where
    marker = "class=\"project-card__link\" href=\""

count :: T.Text -> T.Text -> Int
count needle haystack = length (T.breakOnAll needle haystack)

-- | Text content of some markup: tags dropped, Brigid's entities decoded.
textOf :: T.Text -> T.Text
textOf = decode . T.concat . map (T.drop 1 . T.dropWhile (/= '>')) . T.splitOn "<" . ("<>" <>)
  where
    decode =
      T.replace "&#38;" "&" . T.replace "&#62;" ">" . T.replace "&#60;" "<"
        . T.replace "&#34;" "\"" . T.replace "&#39;" "'"

realSite :: IO Site
realSite = loadSite "."

--------------------------------------------------------------------------------
-- The real content

realSiteTests :: TestTree
realSiteTests =
  testGroup "real content"
    [ testCase "Black leads the teaser; Selected Work is the other featured projects, in order" $ do
        content <- loadFixture "."
        let home = homeContent content
        fmap (slugText . projectSlug) (homeBlack home) @?= Just "black"
        map (slugText . projectSlug) (homeSelected home) @?= ["brigid", "paranoia-engine"]
        map (slugText . projectSlug) (featuredProjects content) @?= ["black", "brigid", "paranoia-engine"]
    , testCase "the homepage renders the cards in featured order, linking to generated pages" $ do
        s <- realSite
        let html = render s Home
            routes = map pageRoute (sitePages s)
        cardHrefs html @?= ["/work/brigid/", "/work/paranoia-engine/"]
        forM_ (cardHrefs html) $ \href ->
          assertBool (T.unpack href) (href `elem` map routePath routes)
    , testCase "the secondary hero CTA introduces the author" $ do
        s <- realSite
        let hero = sectionOf "top" (render s Home)
        assertBool "About destination" ("class=\"button button--secondary\" href=\"/about/\"" `T.isInfixOf` hero)
        assertBool "About label" ("About me" `T.isInfixOf` textOf hero)
        assertBool "no obsolete About and Contact label" (not ("About & contact" `T.isInfixOf` textOf hero))
    , testCase "the Black teaser links to the published Black page" $ do
        s <- realSite
        let teaser = sectionOf "black" (render s Home)
        attributeValues "href" teaser @?= ["/work/black/"]
        assertBool "status from the record" ("In development · Playground planned" `T.isInfixOf` teaser)
    , testCase "contact links (in the shared footer) are the verified destinations only, each one control" $ do
        map contactHref (contacts ownerSettings) @?= ["https://github.com/AugmenTab", "https://www.linkedin.com/in/thebaum/", "mailto:tyler.baum@protonmail.com"]
        s <- realSite
        let contact = sectionOf "contact" (render s Home)
        attributeValues "href" contact @?= ["https://github.com/AugmenTab", "https://www.linkedin.com/in/thebaum/", "mailto:tyler.baum@protonmail.com"]
        forM_ ["résumé", "resume", ".pdf", "/about/"] $ \frag ->
          assertBool (T.unpack frag) (not (frag `T.isInfixOf` T.toLower contact))
    , testCase "the real site has no Writing preview (the nav still links to Writing)" $ do
        s <- realSite
        let html = render s Home
        assertBool "no #writing" (not ("id=\"writing\"" `T.isInfixOf` html))
        assertBool "no /writing/ link in the page body" (not ("/writing/" `T.isInfixOf` mainOf html))
    ]

--------------------------------------------------------------------------------
-- Selected Work

selectedWorkTests :: TestTree
selectedWorkTests =
  testGroup "Selected Work"
    [ testCase "cards follow featured order, never directory order" $ do
        (_, html) <- homeOf (featured "a-third" 3 <> featured "b-first" 1 <> featured "c-second" 2)
        cardHrefs html @?= ["/work/b-first/", "/work/c-second/", "/work/a-third/"]
    , testCase "drafts and unfeatured projects never appear in Selected Work" $ do
        (s, html) <- homeOf
          ( featured "shown" 1
              <> project "hidden-draft" [("featured_order", Just (Json.Number 2)), ("publication_status", Just "draft")]
              <> project "unfeatured" [] )
        cardHrefs html @?= ["/work/shown/"]
        assertBool "no draft anywhere on the page" (not ("hidden-draft" `T.isInfixOf` html))
        assertBool "unfeatured is listed on the Work index" ("/work/unfeatured/" `T.isInfixOf` render s WorkIndex)
        assertBool "draft has no route" (WorkDetail (slugOf "hidden-draft") `notElem` map pageRoute (sitePages s))
    , testCase "the teaser's project is not repeated as a card" $ do
        (_, html) <- homeOf (featured "black" 1 <> featured "other" 2)
        cardHrefs html @?= ["/work/other/"]
        attributeValues "href" (sectionOf "black" html) @?= ["/work/black/"]
    , testCase "no featured projects: no Selected Work, and the primary CTA leads to /work/" $ do
        (_, html) <- homeOf (project "plain" [])
        assertBool "no section" (not ("id=\"selected-work\"" `T.isInfixOf` html))
        assertBool "fallback CTA" ("class=\"button button--primary\" href=\"/work/\"" `T.isInfixOf` html)
        assertBool "no dangling #selected-work" (not ("#selected-work" `T.isInfixOf` html))
    , testCase "with Selected Work, the primary CTA is the in-page anchor" $ do
        (_, html) <- homeOf (featured "one" 1)
        assertBool "anchor" ("class=\"button button--primary\" href=\"#selected-work\"" `T.isInfixOf` html)
        count "id=\"selected-work\"" html @?= 1
    ]

--------------------------------------------------------------------------------
-- Black teaser

blackTeaserTests :: TestTree
blackTeaserTests =
  testGroup "Black teaser"
    [ testCase "no simulated interactive controls or compiler output" $ do
        s <- realSite
        let teaser = sectionOf "black" (render s Home)
        assertBool "teaser found" (not (T.null teaser))
        forM_ ["<button", "<input", "<textarea", "<select", "<form", "contenteditable", "<script", "<iframe"] $ \frag ->
          assertBool ("control: " <> T.unpack frag) (not (frag `T.isInfixOf` teaser))
        -- the render's fake controls and output, as whole element texts
        forM_ [">Compile<", ">Run<", ">Output<", ">Diagnostics<", ">Examples<"] $ \label ->
          assertBool ("simulated control: " <> T.unpack label) (not (label `T.isInfixOf` teaser))
        forM_ ["Compiled successfully", "Running Main", "5.0"] $ \output ->
          assertBool ("simulated output: " <> T.unpack output) (not (output `T.isInfixOf` textOf teaser))
    , testCase "the excerpt is the verified program, unaltered" $ do
        s <- realSite
        let teaser = sectionOf "black" (render s Home)
            code = fst (T.breakOn "</code>" (snd (T.breakOn "<code>" teaser)))
        textOf code @?= exampleSource blackExample
        tokenText (exampleSource blackExample) @?= exampleSource blackExample
        assertBool "provenance recorded" ("conformance/NominalRecord.blk" `T.isInfixOf` exampleProvenance blackExample)
    , testCase "the old unverified excerpt and unsupported claims are gone" $ do
        s <- realSite
        let teaser = textOf (sectionOf "black" (render s Home))
        forM_ ["fn length", "IO Unit", "Vec2", "print(", "Effect and resource safety", "AI-native"] $ \frag ->
          assertBool (T.unpack frag) (not (frag `T.isInfixOf` teaser))
        forM_ (teaserPoints blackTeaser) $ \point ->
          assertBool (T.unpack point) (point `T.isInfixOf` teaser)
    , testCase "without a published Black record: no link, an honest status" $ do
        (_, html) <- homeOf (featured "other" 1)
        let teaser = sectionOf "black" html
        attributeValues "href" teaser @?= []
        assertBool "status" ("Project page in preparation" `T.isInfixOf` teaser)
    , testCase "a draft Black record is not linked" $ do
        (_, html) <- homeOf (project "black" [("publication_status", Just "draft")])
        attributeValues "href" (sectionOf "black" html) @?= []
        assertBool "no /work/black/" (not ("/work/black/" `T.isInfixOf` html))
    ]

--------------------------------------------------------------------------------
-- Writing preview

writingPreviewTests :: TestTree
writingPreviewTests =
  testGroup "Writing preview"
    [ testCase "no published articles: no section, heading or link (outside the nav)" $ do
        (_, html) <- homeOf (article "draft-only" "draft" (Just "2026-10-01"))
        forM_ ["id=\"writing\"", "writing-preview", ">Writing<", "/writing/"] $ \frag ->
          assertBool (T.unpack frag) (not (frag `T.isInfixOf` mainOf html))
    , testCase "one published article: one entry, linked, with its date" $ do
        (_, html) <- homeOf (article "first" "published" (Just "2026-10-01"))
        let preview = sectionOf "writing" html
        count "class=\"writing-preview__item\"" preview @?= 1
        assertBool "link" ("href=\"/writing/first/\"" `T.isInfixOf` preview)
        assertBool "date" ("2026-10-01" `T.isInfixOf` preview)
        assertBool "summary" ("Summary of first." `T.isInfixOf` preview)
        assertBool "all writing" ("href=\"/writing/\"" `T.isInfixOf` preview)
    , testCase "several: the newest three, newest first, undated last; drafts never" $ do
        (_, html) <- homeOf
          ( article "oldest" "published" (Just "2026-01-01")
              <> article "newest" "published" (Just "2026-09-01")
              <> article "middle" "published" (Just "2026-05-01")
              <> article "undated" "published" Nothing
              <> article "secret" "draft" (Just "2026-12-01") )
        let preview = sectionOf "writing" html
            links = filter ("/writing/" `T.isPrefixOf`) (filter (/= "/writing/") (attributeValues "href" preview))
        writingPreviewLimit @?= 3
        links @?= ["/writing/newest/", "/writing/middle/", "/writing/oldest/"]
        assertBool "draft absent" (not ("secret" `T.isInfixOf` html))
    , testCase "an undated article shows no invented date" $ do
        (_, html) <- homeOf (article "undated" "published" Nothing)
        let dateCell = fst (T.breakOn "</p>" (snd (T.breakOn "writing-preview__date" (sectionOf "writing" html))))
        assertBool ("no digits in " <> T.unpack dateCell) (not (T.any isDigit (T.drop 1 (T.dropWhile (/= '>') dateCell))))
    ]

--------------------------------------------------------------------------------
-- Structure

structureTests :: TestTree
structureTests =
  testGroup "structure"
    [ testCase "sections appear in the required order" $ do
        (_, html) <- homeOf (featured "one" 1 <> article "post" "published" (Just "2026-10-01"))
        let order = [ i | i <- ["top", "black", "selected-work", "philosophy", "writing", "contact"]
                        , ("id=\"" <> i <> "\"") `T.isInfixOf` html ]
            position i = T.length (fst (T.breakOn ("id=\"" <> i <> "\"") html))
        order @?= ["top", "black", "selected-work", "philosophy", "writing", "contact"]
        map position order @?= sort (map position order)
    , testCase "one h1, and heading levels never skip" $
        forM_ [[], featured "one" 1 <> article "post" "published" (Just "2026-10-01")] $ \files -> do
          (_, html) <- homeOf files
          let levels = [ read [c] :: Int | (_, rest) <- T.breakOnAll "<h" html
                                         , Just (c, _) <- [T.uncons (T.drop 2 rest)], c `elem` ("123456" :: String) ]
          length (filter (== 1) levels) @?= 1
          take 1 levels @?= [1]
          forM_ (zip levels (drop 1 levels)) $ \(a, b) ->
            assertBool ("h" <> show a <> " then h" <> show b) (b <= a + 1)
    , testCase "every section is labelled by its heading" $ do
        (_, html) <- homeOf (featured "one" 1 <> article "post" "published" (Just "2026-10-01"))
        forM_ ["hero-title", "black-title", "work-title", "philosophy-title", "writing-title", "contact-title"] $ \hid -> do
          assertBool (T.unpack hid) (("aria-labelledby=\"" <> hid <> "\"") `T.isInfixOf` html)
          count ("id=\"" <> hid <> "\"") html @?= 1
    , testCase "the philosophy section is complete and calm: no images, no frames" $ do
        s <- realSite
        let section = sectionOf "philosophy" (render s Home)
        assertBool "heading" (philosophyHeading philosophy `T.isInfixOf` textOf section)
        count "class=\"philosophy__principle\"" section @?= length (philosophyPrinciples philosophy)
        assertBool "three to five principles" (length (philosophyPrinciples philosophy) `elem` [3 .. 5])
        assertBool "no imagery" (not ("<img" `T.isInfixOf` section))
    , testCase "the four principles render in their intended order" $ do
        s <- realSite
        let section = sectionOf "philosophy" (render s Home)
            titles = map principleTitle (philosophyPrinciples philosophy)
            position t = T.length (fst (T.breakOn t section))
        titles @?= [ "Put the checks in the system.", "Define what finished means.", "Give agents responsibility with boundaries.", "Choose tools on merit, not familiarity." ]
        forM_ titles $ \t -> count ("<h3 class=\"philosophy__principle-title\">" <> t <> "</h3>") section @?= 1
        map position titles @?= sort (map position titles)
    , testCase "approved and draft copy statuses are tracked" $ do
        s <- realSite
        let section = sectionOf "philosophy" (render s Home)
        philosophyStatus philosophy @?= FinalCopy
        length (philosophyPrinciples philosophy) @?= 4
        assertBool "approved philosophy heading" ("Confidence isn't evidence." `T.isInfixOf` section)
        teaserStatus blackTeaser @?= FinalCopy
        introStatus introduction @?= FinalCopy
        contactStatus contactCopy @?= FinalCopy
    , testCase "the homepage has no About section, no tree emblem, and Contact only in the footer" $ do
        s <- realSite
        let html = render s Home
        count "id=\"contact\"" html @?= 1
        assertBool "no about section" (not ("id=\"about\"" `T.isInfixOf` html))
        assertBool "no tree" (not ("about-tree" `T.isInfixOf` html))
        assertBool "invitation" (contactInvitation contactCopy `T.isInfixOf` textOf (sectionOf "contact" html))
        -- no Contact section in main: the footer's is the only one
        assertBool "no contact in main" (not ("contact" `T.isInfixOf` mainOf html))
        assertBool "contact is in the footer" ("id=\"contact\"" `T.isInfixOf` snd (T.breakOn "<footer" html))
    ]

--------------------------------------------------------------------------------
-- Build reliability

reliabilityTests :: TestTree
reliabilityTests =
  testGroup "homepage build reliability"
    [ testCase "a missing project asset prevents publication and keeps the previous output" $
        withSource (featured "one" 1) $ \root -> do
          let out = root </> "dist"
              config = BuildConfig { sourceRoot = root, outputDir = out }
          _ <- loadSite root >>= buildSite config
          before <- readTree out
          Dir.removeFile (root </> "content/projects/one/card.svg")
          expectFailure (loadSite root >>= buildSite config)
          after <- readTree out
          after @?= before
    , testCase "invalid homepage content (duplicate featured order) prevents publication" $
        withSource (featured "one" 1 <> featured "two" 1) $ \root -> do
          expectFailure (loadSite root >>= buildSite BuildConfig { sourceRoot = root, outputDir = root </> "dist" })
          Dir.doesPathExist (root </> "dist") >>= assertBool "nothing written" . not
    , testCase "repeated homepage builds are byte-identical and leak no sources" $
        withSource (featured "one" 1 <> article "post" "published" (Just "2026-10-01")) $ \root -> do
          s <- loadSite root
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = root </> "a" } s
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = root </> "b" } s
          a <- readTree (root </> "a")
          b <- readTree (root </> "b")
          a @?= b
          files <- listFiles (root </> "a")
          assertBool (show files) (not (any (\f -> ".md" `isInfixOf` f || ".json" `isInfixOf` f) files))
    ]

expectFailure :: IO a -> Assertion
expectFailure action = do
  result <- try action
  case result of
    Left (_ :: BuildError) -> pure ()
    Right _ -> assertFailure "expected the build to fail"
