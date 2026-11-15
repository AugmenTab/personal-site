{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Exception (throwIO, try)
import Control.Monad (forM, forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isLeft)
import Data.IORef (atomicModifyIORef', newIORef)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory qualified as Dir
import System.FilePath (normalise, takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.Types qualified as B

import Site.Assets (Asset, allAssets, assetPath, mkAsset)
import Site.Build
import Site.Layout (renderPage)
import Site.Manifest
import Site.Page (Layout (..), Page (..), Site (..))
import Site.Pages.About (contactId)
import Site.Path
import Site.Routes
import Site.Validate (PageProblem (..), activeContent, attributeValues, validatePages)
import System.IO.Unsafe (unsafePerformIO)

import ContentTests (contentTests)

main :: IO ()
main =
  defaultMain $
    testGroup "personal-site"
      [ routeTests
      , manifestTests
      , renderTests
      , validationTests
      , buildTests
      , contentTests
      ]

--------------------------------------------------------------------------------
-- Fixtures

-- | The real site, loaded from this repository's @content/@ exactly as the
-- CLI loads it. Loaded once; a content error fails every test that uses it.
theSite :: Site
theSite = unsafePerformIO (loadSite ".")
{-# NOINLINE theSite #-}

slug :: T.Text -> Slug
slug = either (error . show) id . mkSlug

brigidRoute :: Route
brigidRoute = WorkDetail (slug "brigid")

allRoutes :: [Route]
allRoutes = [Home, WorkIndex, brigidRoute, About, NotFound]

pageFor :: Route -> Page
pageFor route =
  case filter ((== route) . pageRoute) (sitePages theSite) of
    [p] -> p
    _ -> error ("expected exactly one page for " <> show route)

htmlOf :: Route -> T.Text
htmlOf = TE.decodeUtf8 . LBS.toStrict . renderPage (siteConfig theSite) . pageFor

count :: T.Text -> T.Text -> Int
count needle haystack = length (T.breakOnAll needle haystack)

-- | A minimal valid page for synthetic sites. It carries the @#contact@
-- id, which the shared navigation links to on the About page.
stubPage :: Route -> [E.ChildHTML E.Main E.Body] -> Page
stubPage route body =
  Page
    { pageRoute = route
    , pageTitle = "Stub"
    , pageDescription = "Stub page."
    , pageLayout = Interior
    , pageMain = E.h1 [] [ E.text "Stub" ] : E.p [ A.id contactId ] [] : body
    }

withPages :: [Page] -> Site
withPages pages = theSite { sitePages = pages }

outputOf :: Route -> String
outputOf = either (error . show) outputText . routeOutput

--------------------------------------------------------------------------------
-- 01.1 Routes and output paths

routeTests :: TestTree
routeTests =
  testGroup "routes"
    [ testCase "route URLs and output files" $ do
        map routePath allRoutes @?= ["/", "/work/", "/work/brigid/", "/about/", "/404.html"]
        map outputOf allRoutes
          @?= ["index.html", "work/index.html", "work/brigid/index.html", "about/index.html", "404.html"]
    , testCase "the site defines exactly the required routes" $
        sort (map pageRoute (sitePages theSite)) @?= sort allRoutes
    , testCase "valid slugs are accepted unchanged" $
        forM_ ["brigid", "black", "black-compiler", "r3", "a"] $ \s ->
          fmap slugText (mkSlug s) @?= Right s
    , testCase "invalid or non-canonical slugs are rejected" $
        forM_ [ "", "Brigid", "BRIGID", "brigid-", "-brigid", "bri--gid", "bri_gid", "brigid/"
              , " brigid", "brigid.html", "..", ".", "a/../b", "brígid", "work%2F", T.replicate 65 "a" ] $ \s ->
          assertBool ("accepted " <> show s) (isLeft (mkSlug s))
    , testCase "output paths reject traversal, absolute and non-canonical spellings" $
        forM_ [ "", "/etc/passwd", "../x", "a/../../x", "a/./b", "./a", "a//b", "a/", "..", "."
              , ".hidden", "a/.git/config", "a\\b", "a b", "a?b", "a#b", "ü" ] $ \p ->
          assertBool ("accepted " <> show p) (isLeft (mkOutputPath p))
    , testCase "accepted output paths cannot escape the output root" $
        forM_ ["index.html", "work/brigid/index.html", "assets/fonts/OFL-cinzel.txt", "a..b", "x.y.z"] $ \p ->
          case mkOutputPath p of
            Left err -> assertFailure (show err)
            Right path -> do
              let root = "/srv/dist"
              assertBool "contained" (normalise (resolveUnder root path) `isWithin` root)
              assertBool "strictly inside" (normalise (resolveUnder root path) /= root)
    , testCase "URL paths map to output files by one rule" $ do
        fmap outputText (urlPathOutput "/") @?= Right "index.html"
        fmap outputText (urlPathOutput "/work/") @?= Right "work/index.html"
        fmap outputText (urlPathOutput "/assets/styles/site.css") @?= Right "assets/styles/site.css"
        assertBool "relative" (isLeft (urlPathOutput "work/"))
        assertBool "traversal" (isLeft (urlPathOutput "/work/../../etc/"))
        assertBool "doubled slash" (isLeft (urlPathOutput "//work/"))
    , testCase "every route's output agrees with its URL" $
        forM_ allRoutes $ \r -> fmap outputText (urlPathOutput (routePath r)) @?= Right (outputOf r)
    ]

manifestTests :: TestTree
manifestTests =
  testGroup "manifest"
    [ testCase "the site's manifest is valid and sorted" $
        case mkManifest (map pageRoute (sitePages theSite)) (siteAssets theSite) (siteMedia theSite) of
          Left errs -> assertFailure (show errs)
          Right m -> do
            let paths = map entryOutput (manifestEntries m)
            paths @?= sort paths
            length paths @?= length allRoutes + length allAssets + length (siteMedia theSite)
            map outputText [ p | (_, p) <- manifestMedia m ] @?= ["media/projects/brigid/card.svg"]
    , testCase "two pages with the same route are rejected" $
        assertCollision (mkManifest [Home, About, Home] [] [])
    , testCase "two project pages with the same slug are rejected" $
        assertCollision (mkManifest [brigidRoute, WorkDetail (slug "brigid")] [] [])
    , testCase "assets differing only in case collide" $
        assertCollision (mkManifest [] [mkAsset "fonts/OFL-cinzel.txt", mkAsset "fonts/ofl-cinzel.txt"] [])
    , testCase "a page and an asset with the same destination collide" $ do
        let entry p src = Entry (either (error . show) id (mkOutputPath p)) src
        assertCollision $
          fromEntries
            [ entry "index.html" (PageSource Home)
            , entry "Index.html" (AssetSource (mkAsset "Index.html"))
            ]
        assertCollision $
          fromEntries
            [ entry "work/index.html" (PageSource WorkIndex)
            , entry "work/index.html" (AssetSource (mkAsset "work/index.html"))
            ]
    , testCase "a file cannot also be needed as a directory" $ do
        let entry p src = Entry (either (error . show) id (mkOutputPath p)) src
        case fromEntries [entry "work/index.html" (PageSource WorkIndex), entry "work" (AssetSource (mkAsset "work"))] of
          Left [FileUsedAsDirectory _ _] -> pure ()
          other -> assertFailure ("expected a file/directory conflict, got " <> show other)
    , testCase "path errors and collisions are reported together" $
        case mkManifest [Home, Home] [mkAsset "../x"] [] of
          Left [InvalidAssetPath _ _, OutputCollision _] -> pure ()
          other -> assertFailure ("expected both problems, got " <> show other)
    , testCase "unsafe asset paths are rejected before any file is touched" $
        forM_ ["../README.md", "/etc/passwd", "images/../../x", "images//x.svg", ".env"] $ \p ->
          case mkManifest [] [mkAsset p] [] of
            Left [InvalidAssetPath _ _] -> pure ()
            other -> assertFailure (p <> ": expected InvalidAssetPath, got " <> show other)
    ]
  where
    assertCollision result =
      case result of
        Left errs -> assertBool (show errs) (any isCollision errs)
        Right _ -> assertFailure "collision accepted"
    isCollision e = case e of OutputCollision _ -> True; _ -> False

--------------------------------------------------------------------------------
-- 01.2 / 01.3 Rendering

renderTests :: TestTree
renderTests =
  testGroup "Brigid render"
    [ testCase "every page is a complete HTML document" $
        forM_ allRoutes $ \r -> do
          let html = htmlOf r
          assertBool (show r <> " doctype") ("<!DOCTYPE html>" `T.isPrefixOf` html)
          assertBool (show r <> " lang") ("<html lang=\"en\">" `T.isInfixOf` html)
          assertBool (show r <> " closes html") ("</html>" `T.isSuffixOf` T.strip html)
          assertBool (show r <> " stylesheet") ("href=\"/assets/styles/site.css\"" `T.isInfixOf` html)
          assertBool (show r <> " favicon") ("href=\"/assets/brand/favicon.svg\"" `T.isInfixOf` html)
          assertBool (show r <> " description") ("<meta name=\"description\" content=\"" `T.isInfixOf` html)
    , testCase "titles and the single h1 of each page" $
        forM_
          [ (Home, "Tyler Baum — Software Engineer", "Tyler</span> <span class=\"hero__name-word\">Baum")
          , (WorkIndex, "Work — Tyler Baum", ">Work</span></h1>")
          , (brigidRoute, "Brigid — Tyler Baum", "id=\"brigid-title\">Brigid</h1>")
          , (About, "About — Tyler Baum", ">About</span></h1>")
          , (NotFound, "Page not found — Tyler Baum", ">Page not found</span></h1>")
          ] $ \(r, title, h1) -> do
            let html = htmlOf r
            assertBool (show r <> " title") (("<title>" <> title <> "</title>") `T.isInfixOf` html)
            count "<h1" html @?= 1
            assertBool (show r <> " h1 text") (h1 `T.isInfixOf` html)
    , testCase "every page has the skip link, header nav, main and footer landmarks" $
        forM_ allRoutes $ \r -> do
          let html = htmlOf r
          forM_ ["href=\"#main\"", "<header class=\"site-header\"", "<nav class=\"site-nav\" aria-label=\"Primary\"", "<main id=\"main\"", "<footer class=\"site-footer\""] $ \frag ->
            assertBool (show r <> ": " <> T.unpack frag) (frag `T.isInfixOf` html)
          count "<main" html @?= 1
    , testCase "shared navigation links to routes, marking only the current page" $
        forM_ allRoutes $ \r -> do
          let html = htmlOf r
          forM_ ["/\"", "/work/\"", "/about/\"", "/about/#contact\""] $ \href ->
            assertBool (show r <> " nav " <> T.unpack href) (("class=\"site-nav__link\" href=\"" <> href) `T.isInfixOf` html)
          let header = fst (T.breakOn "</header>" html)
              current = [ label | (label, route) <- [("Home", Home), ("Work", WorkIndex), ("About", About)], route == r ]
          count "aria-current=\"page\"" header @?= length current
          forM_ current $ \label ->
            assertBool (show r <> " current " <> T.unpack label) (("aria-current=\"page\">" <> label <> "</a>") `T.isInfixOf` header)
    , testCase "the homepage keeps its approved major sections and same-page CTAs" $ do
        let html = htmlOf Home
        forM_ [ "class=\"stage\"", "class=\"stage__art\"", "hero-plate-centre.webp", "hero-plate-left.webp", "hero-plate-right.webp"
              , "class=\"hero__divider\"", "id=\"top\"", "id=\"black\"", "class=\"feature__code\"", "id=\"selected-work\""
              , "class=\"project-card\"", "id=\"about\"", "id=\"contact\"" ] $ \frag ->
          assertBool (T.unpack frag) (frag `T.isInfixOf` html)
        forM_ ["href=\"#selected-work\"", "href=\"#about\""] $ \frag ->
          assertBool (T.unpack frag) (frag `T.isInfixOf` html)
    , testCase "every <img> has an alt attribute" $
        forM_ allRoutes $ \r ->
          forM_ (drop 1 (T.splitOn "<img " (htmlOf r))) $ \tag ->
            assertBool (show r <> " img alt") ("alt=" `T.isInfixOf` T.takeWhile (/= '>') tag)
    , testCase "pages are static: no scripts, forms or controls" $
        forM_ allRoutes $ \r ->
          forM_ ["<script", "<form", "<button", "<textarea", "<input", "<iframe"] $ \frag ->
            assertBool (show r <> ": unexpected " <> T.unpack frag) (not (frag `T.isInfixOf` htmlOf r))
    , testCase "the monogram appears once per page, inside the navigation medallion" $
        forM_ allRoutes $ \r -> do
          let html = htmlOf r
          count "monogram" html @?= 1
          let nav = fst (T.breakOn "</nav>" (snd (T.breakOn "<nav " html)))
          assertBool (show r <> " monogram in nav") ("site-nav__mark-img\" src=\"/assets/brand/monogram-simple.svg\"" `T.isInfixOf` nav)
    , testCase "the tree emblem is in About content only" $ do
        assertBool "home about" ("about__tree" `T.isInfixOf` snd (T.breakOn "id=\"about\"" (htmlOf Home)))
        assertBool "home: not before about" (not ("about__tree" `T.isInfixOf` fst (T.breakOn "id=\"about\"" (htmlOf Home))))
        assertBool "about page" ("about__tree" `T.isInfixOf` htmlOf About)
        forM_ [WorkIndex, brigidRoute, NotFound] $ \r ->
          assertBool (show r <> " has no tree") (not ("about__tree" `T.isInfixOf` htmlOf r))
    , testCase "the Brigid page has its content, source link and a way back to Work" $ do
        let html = htmlOf brigidRoute
        forM_ [ "href=\"https://github.com/AugmenTab/brigid\"", "href=\"/work/\"", "BSD-3-Clause", "Haskell"
              , "<pre class=\"code-block\"><code class=\"language-haskell\">"
              , "src=\"/media/projects/brigid/card.svg\" alt=\"Gold line drawing" ] $ \frag ->
          assertBool (T.unpack frag) (frag `T.isInfixOf` html)
    , testCase "project pages have the project sidebar beside the content" $ do
        let html = htmlOf brigidRoute
            sidebar = fst (T.breakOn "</nav>" (snd (T.breakOn "<nav class=\"project-nav\"" html)))
        assertBool "sidebar present" (not (T.null sidebar))
        assertBool "sidebar inside main" ("<nav class=\"project-nav\"" `T.isInfixOf` snd (T.breakOn "<main " html))
        assertBool "All projects link" ("class=\"project-nav__back\" href=\"/work/\"" `T.isInfixOf` sidebar)
        assertBool "All projects label" ("All projects</a>" `T.isInfixOf` sidebar)
        assertBool "current project" ("class=\"project-nav__current\" href=\"/work/brigid/\" aria-current=\"page\">Brigid</a>" `T.isInfixOf` sidebar)
        assertBool "sidebar before content" (T.breakOn "<nav class=\"project-nav\"" html < T.breakOn "<article class=\"project\"" html)
    , testCase "every sidebar section link has a section, and every section a link" $ do
        let html = htmlOf brigidRoute
            sidebar = fst (T.breakOn "</nav>" (snd (T.breakOn "<nav class=\"project-nav\"" html)))
            sectionList = snd (T.breakOn "project-nav__sections" sidebar)
            links = [ T.drop 1 h | h <- attributeValues "href" sectionList ]
            sectionIds = [ i | (_, rest) <- T.breakOnAll "<h2 class=\"project__section-title\" id=\"" html
                             , let i = T.takeWhile (/= '"') (T.drop (T.length "<h2 class=\"project__section-title\" id=\"") rest) ]
        links @?= ["overview", "technical-approach", "current-capabilities", "limitations-and-status", "resources"]
        links @?= sectionIds
        forM_ links $ \l -> count ("id=\"" <> l <> "\"") html @?= 1
    , testCase "non-project pages have no project sidebar" $
        forM_ [Home, WorkIndex, About, NotFound] $ \r ->
          assertBool (show r) (not ("project-nav" `T.isInfixOf` htmlOf r))
    , testCase "cards on Home and Work link to the project page" $
        forM_ [Home, WorkIndex] $ \r ->
          assertBool (show r) ("class=\"project-card__link\" href=\"/work/brigid/\"" `T.isInfixOf` htmlOf r)
    , testCase "the 404 page links back to the homepage" $
        assertBool "home link" ("class=\"button button--primary\" href=\"/\"" `T.isInfixOf` htmlOf NotFound)
    , testCase "rendering is deterministic" $
        forM_ allRoutes $ \r -> htmlOf r @?= htmlOf r
    ]

--------------------------------------------------------------------------------
-- Output validation (internal links and document structure)

validationTests :: TestTree
validationTests =
  testGroup "output validation"
    [ testCase "the real site's pages and links validate" $ do
        m <- either (assertFailure . show) pure (mkManifest (map pageRoute (sitePages theSite)) (siteAssets theSite) (siteMedia theSite))
        validatePages m [ (route, TE.decodeUtf8 (LBS.toStrict html)) | (route, _, html) <- renderSite theSite m ] @?= []
    , testCase "links to missing pages, missing fragments and relative URLs are caught" $ do
        let bad =
              stubPage About
                [ E.p []
                    [ E.a [ A.href (B.mkRawURL "/nowhere/") ] [ E.text "a" ]
                    , E.a [ A.href (B.mkRawURL "/about/#missing") ] [ E.text "b" ]
                    , E.a [ A.href (B.mkRawURL "work/") ] [ E.text "c" ]
                    , E.a [ A.href (B.mkRawURL "/assets/missing.png") ] [ E.text "d" ]
                    , E.a [ A.href (elementId "nope") ] [ E.text "e" ]
                    , E.a [ A.href (B.mkRawURL "https://example.com/") ] [ E.text "external" ]
                    ]
                ]
            pages = [stubPage Home [], stubPage WorkIndex [], bad]
        m <- either (assertFailure . show) pure (mkManifest (map pageRoute pages) allAssets [])
        let problems = validatePages m [ (route, TE.decodeUtf8 (LBS.toStrict html)) | (route, _, html) <- renderSite (withPages pages) m ]
        sort [ url | BrokenLink _ url _ <- problems ] @?= sort ["/nowhere/", "/about/#missing", "work/", "/assets/missing.png", "#nope"]
    , testCase "an attribute value that breaks out of its quotes is caught" $ do
        -- Brigid does not escape '"' in attribute values: reproduce the
        -- injection directly and check that the build's validator stops it.
        let injected = stubPage About [ E.p [ A.title "x\" onmouseover=\"alert(1)" ] [ E.text "x" ] ]
            pages = [stubPage Home [], stubPage WorkIndex [], injected]
        m <- either (assertFailure . show) pure (mkManifest (map pageRoute pages) allAssets [])
        let problems = validatePages m [ (route, TE.decodeUtf8 (LBS.toStrict html)) | (route, _, html) <- renderSite (withPages pages) m ]
        [ r | ActiveContent r _ <- problems ] @?= [About]
    , testCase "harmless look-alikes in text and attribute values are not flagged" $ do
        activeContent "<p class=\"a\">x onclick=y &#60;script&#62;</p><a href=\"/a?on=1\">z</a>" @?= []
        activeContent "<img src=\"/x.svg\" alt=\"\" onerror=\"alert(1)\"/>" @?= ["img src=\"/x.svg\" alt=\"\" onerror=\"alert(1)\"/"]
        length (activeContent "<script>x</script><iframe src=\"/\"></iframe>") @?= 2
    , testCase "a page without exactly one h1 is caught" $ do
        let noH1 = (stubPage About []) { pageMain = [] }
            twoH1 = stubPage WorkIndex [ E.h1 [] [ E.text "again" ] ]
            pages = [stubPage Home [], noH1, twoH1]
        m <- either (assertFailure . show) pure (mkManifest (map pageRoute pages) allAssets [])
        let problems = validatePages m [ (route, TE.decodeUtf8 (LBS.toStrict html)) | (route, _, html) <- renderSite (withPages pages) m ]
        sort [ (r, n) | HeadingCount r n <- problems ] @?= [(WorkIndex, 2), (About, 0)]
    ]

--------------------------------------------------------------------------------
-- 01.4 Build pipeline

buildTests :: TestTree
buildTests =
  testGroup "build"
    [ testCase "a clean build writes exactly the manifest's files" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let out = tmp </> "dist"
          report <- buildSite (config "." out) theSite
          files <- listTree out
          sort files @?= sort (ownershipMarker : map (outputFilePath . entryOutput) (reportEntries report))
          BS.readFile (out </> ownershipMarker) >>= (@?= ownershipMarkerContents)
          forM_ allRoutes $ \r -> do
            bytes <- BS.readFile (out </> outputOf r)
            assertBool (show r <> " non-empty") (BS.length bytes > 1000)
          forM_ allAssets $ \asset ->
            Dir.doesFileExist (out </> "assets" </> assetPath asset) >>= assertBool ("copied " <> assetPath asset)
          assertNoScratch out
    , testCase "repeated builds produce byte-identical trees" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          _ <- buildSite (config "." (tmp </> "a")) theSite
          _ <- buildSite (config "." (tmp </> "b")) theSite
          _ <- buildSite (config "." (tmp </> "b")) theSite
          a <- readTree (tmp </> "a")
          b <- readTree (tmp </> "b")
          Map.keys a @?= Map.keys b
          a @?= b
    , testCase "site check validates without writing anything" $
        withSystemTempDirectory "site-src" $ \src -> do
          copyAssets "." src
          report <- checkSite (config src (src </> "dist")) theSite
          length (checkPages report) @?= length allRoutes
          Dir.doesPathExist (src </> "dist") >>= assertBool "no output" . not
          Dir.doesPathExist (src </> "dist.tmp") >>= assertBool "no staging" . not
    , testCase "fails clearly when a required asset is missing, keeping prior output" $
        withSystemTempDirectory "site-src" $ \src -> do
          copyAssets "." src
          let out = src </> "dist"
          _ <- buildSite (config src out) theSite
          before <- readTree out
          let victim = "images/hero-plate-centre.webp"
          Dir.removeFile (src </> "assets" </> victim)
          expectError (buildSite (config src out) theSite) $ \err ->
            err @?= MissingAssets ["assets/" <> victim]
          readTree out >>= (@?= before)
          assertNoScratch out
    , testCase "a missing asset on a first build writes no output" $
        withSystemTempDirectory "site-src" $ \src -> do
          copyAssets "." src
          Dir.removeFile (src </> "assets" </> "styles" </> "site.css")
          expectError (buildSite (config src (src </> "dist")) theSite) $ \err ->
            err @?= MissingAssets ["assets/styles/site.css"]
          Dir.doesPathExist (src </> "dist") >>= assertBool "no output written on failure" . not
    , testCase "fails when a stylesheet references an unlisted file" $
        withSystemTempDirectory "site-src" $ \src -> do
          copyAssets "." src
          let css = src </> "assets" </> "styles" </> "site.css"
          BS.appendFile css "\n.x { background: url(\"../images/not-listed.png\"); }\n"
          expectError (buildSite (config src (src </> "dist")) theSite) $ \err ->
            case err of
              UnlistedStylesheetReference _ ref -> ref @?= "../images/not-listed.png"
              other -> assertFailure ("unexpected error: " <> show other)
    , testCase "duplicate routes fail the build, keeping prior output" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let out = tmp </> "dist"
          _ <- buildSite (config "." out) theSite
          before <- readTree out
          let dup = theSite { sitePages = sitePages theSite <> [pageFor About] }
          expectError (buildSite (config "." out) dup) $ \err ->
            case err of
              InvalidManifest [OutputCollision _] -> pure ()
              other -> assertFailure ("unexpected error: " <> show other)
          readTree out >>= (@?= before)
          assertNoScratch out
    , testCase "an unsafe asset path fails the build" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let s = theSite { siteAssets = siteAssets theSite <> [mkAsset "../package.yaml"] }
          expectError (buildSite (config "." (tmp </> "dist")) s) $ \err ->
            case err of
              InvalidManifest [InvalidAssetPath _ _] -> pure ()
              other -> assertFailure ("unexpected error: " <> show other)
    , testCase "an asset symlinked outside assets/ is rejected" $
        withSystemTempDirectory "site-src" $ \src -> do
          copyAssets "." src
          writeFile (src </> "secret.txt") "not for publication"
          let link = src </> "assets" </> "images" </> "leak.svg"
          Dir.createFileLink (src </> "secret.txt") link
          let s = theSite { siteAssets = siteAssets theSite <> [mkAsset "images/leak.svg"] }
          expectError (buildSite (config src (src </> "dist")) s) $ \err ->
            case err of
              UnsafeAsset path _ -> path @?= "assets/images/leak.svg"
              other -> assertFailure ("unexpected error: " <> show other)
          Dir.doesPathExist (src </> "dist") >>= assertBool "no output" . not
    , testCase "an asset that is a directory is rejected" $
        withSystemTempDirectory "site-src" $ \src -> do
          copyAssets "." src
          Dir.createDirectory (src </> "assets" </> "extras")
          let s = theSite { siteAssets = siteAssets theSite <> [mkAsset "extras"] }
          expectError (checkSite (config src (src </> "dist")) s) $ \err ->
            case err of
              UnsafeAsset path _ -> path @?= "assets/extras"
              other -> assertFailure ("unexpected error: " <> show other)
    , testCase "a page with a broken internal link fails the build, keeping prior output" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let out = tmp </> "dist"
          _ <- buildSite (config "." out) theSite
          before <- readTree out
          let broken = stubPage About [ E.p [] [ E.a [ A.href (B.mkRawURL "/work/missing/") ] [ E.text "x" ] ] ]
              s = theSite { sitePages = filter ((/= About) . pageRoute) (sitePages theSite) <> [broken] }
          expectError (buildSite (config "." out) s) $ \err ->
            case err of
              InvalidPages [BrokenLink About "/work/missing/" _] -> pure ()
              other -> assertFailure ("unexpected error: " <> show other)
          readTree out >>= (@?= before)
          assertNoScratch out
    , testCase "refuses output directories that would destroy sources" $
        withSystemTempDirectory "site-src" $ \src -> do
          copyAssets "." src
          Dir.createDirectoryIfMissing True (src </> "notes")
          writeFile (src </> "notes" </> "todo.txt") "keep me"
          forM_ [src, takeDirectory src, src </> "assets", src </> "assets" </> "images", src </> "notes"] $ \out ->
            expectError (buildSite (config src out) theSite) $ \err ->
              case err of
                UnsafeOutputDirectory _ _ -> pure ()
                other -> assertFailure (out <> ": unexpected error: " <> show other)
          readFile (src </> "notes" </> "todo.txt") >>= (@?= "keep me")
          Dir.doesFileExist (src </> "assets" </> "styles" </> "site.css") >>= assertBool "assets intact"
    , testCase "an existing empty output directory is accepted" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let out = tmp </> "dist"
          Dir.createDirectory out
          _ <- buildSite (config "." out) theSite
          Dir.doesFileExist (out </> "index.html") >>= assertBool "built"
    , testCase "a generator-managed directory can be rebuilt" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let out = tmp </> "dist"
          _ <- buildSite (config "." out) theSite
          writeFile (out </> "stale.html") "left over from an older build"
          _ <- buildSite (config "." out) theSite
          Dir.doesPathExist (out </> "stale.html") >>= assertBool "stale file replaced" . not
    , testCase "a foreign directory is refused even when it contains index.html" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let out = tmp </> "foreign"
          Dir.createDirectory out
          writeFile (out </> "index.html") "someone else's site"
          writeFile (out </> "notes.txt") "keep me"
          expectOwnershipRefusal out
          readFile (out </> "notes.txt") >>= (@?= "keep me")
          readFile (out </> "index.html") >>= (@?= "someone else's site")
    , testCase "a malformed, misplaced or symlinked marker cannot authorize replacement" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let fresh name = do
                let out = tmp </> name
                Dir.createDirectory out
                writeFile (out </> "keep.txt") "keep me"
                pure out
          -- wrong contents (a prefix of the real marker)
          wrong <- fresh "wrong"
          BS.writeFile (wrong </> ownershipMarker) (BS.take 20 ownershipMarkerContents)
          expectOwnershipRefusal wrong
          -- right contents plus extra bytes
          extra <- fresh "extra"
          BS.writeFile (extra </> ownershipMarker) (ownershipMarkerContents <> "x")
          expectOwnershipRefusal extra
          -- empty marker
          empty <- fresh "empty"
          BS.writeFile (empty </> ownershipMarker) ""
          expectOwnershipRefusal empty
          -- a directory with the marker's name
          asDir <- fresh "as-dir"
          Dir.createDirectory (asDir </> ownershipMarker)
          expectOwnershipRefusal asDir
          -- a symlink to a valid marker elsewhere
          BS.writeFile (tmp </> "real-marker") ownershipMarkerContents
          linked <- fresh "linked"
          Dir.createFileLink (tmp </> "real-marker") (linked </> ownershipMarker)
          expectOwnershipRefusal linked
          -- a marker in a subdirectory does not count
          nested <- fresh "nested"
          Dir.createDirectory (nested </> "sub")
          BS.writeFile (nested </> "sub" </> ownershipMarker) ownershipMarkerContents
          expectOwnershipRefusal nested
          forM_ [wrong, extra, empty, asDir, linked, nested] $ \out ->
            readFile (out </> "keep.txt") >>= (@?= "keep me")
    , testCase "an interrupted earlier promotion stops the build" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let out = tmp </> "dist"
          Dir.createDirectoryIfMissing True (out <> ".old")
          expectError (buildSite (config "." out) theSite) $ \err ->
            err @?= InterruptedPromotion (out <> ".old")
          Dir.doesPathExist (out <> ".tmp") >>= assertBool "staging removed" . not
    , testCase "a failed promotion restores the previous output" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let out = tmp </> "dist"
              staging = tmp </> "dist.tmp"
              backup = tmp </> "dist.old"
          _ <- buildSite (config "." out) theSite
          before <- readTree out
          -- A new tree with different content, then a rename that fails
          -- part-way through moving it in.
          Dir.createDirectoryIfMissing True (staging </> "work")
          writeFile (staging </> "index.html") "new"
          writeFile (staging </> "work" </> "index.html") "new"
          writeFile (staging </> "zzz.html") "new"
          -- Moving the old entries out succeeds; the second move of a new
          -- entry in (\"work\", after \"index.html\") fails.
          stagedMoves <- newIORef (0 :: Int)
          let flaky from to = do
                n <- if takeDirectory from == staging
                       then atomicModifyIORef' stagedMoves (\c -> (c + 1, c + 1))
                       else pure 0
                if n == 2
                  then throwIO (userError "simulated rename failure")
                  else Dir.renamePath from to
          expectError (promoteWith flaky staging backup out) $ \err ->
            case err of
              PromotionFailed _ -> pure ()
              other -> assertFailure ("unexpected error: " <> show other)
          readTree out >>= (@?= before)
          assertNoScratch out
    , testCase "cssReferences ignores data URIs and absolute URLs" $
        cssReferences "a{b:url(\"x.svg\")} c{d:url(data:image/svg+xml,abc)} e{f:url(https://e.com/x)} g{h:url( '../y.woff2' )}"
          @?= ["x.svg", "../y.woff2"]
    ]

config :: FilePath -> FilePath -> BuildConfig
config src out = BuildConfig { sourceRoot = src, outputDir = out }

expectError :: IO a -> (BuildError -> Assertion) -> Assertion
expectError action check = do
  result <- try action
  case result of
    Left err -> check err
    Right _ -> assertFailure "expected the build to fail"

expectOwnershipRefusal :: FilePath -> Assertion
expectOwnershipRefusal out = do
  expectError (buildSite (config "." out) theSite) $ \err ->
    case err of
      UnsafeOutputDirectory _ _ -> pure ()
      other -> assertFailure (out <> ": unexpected error: " <> show other)
  assertNoScratch out

assertNoScratch :: FilePath -> Assertion
assertNoScratch out = do
  Dir.doesPathExist (out <> ".tmp") >>= assertBool "staging directory removed" . not
  Dir.doesPathExist (out <> ".old") >>= assertBool "backup directory removed" . not

listTree :: FilePath -> IO [FilePath]
listTree root = go ""
  where
    go rel = do
      entries <- Dir.listDirectory (root </> rel)
      concat <$> forM entries (\e -> do
        let relE = if null rel then e else rel </> e
        isDir <- Dir.doesDirectoryExist (root </> relE)
        if isDir then go relE else pure [relE])

readTree :: FilePath -> IO (Map.Map FilePath BS.ByteString)
readTree root = do
  files <- listTree root
  Map.fromList <$> forM files (\f -> (,) f <$> BS.readFile (root </> f))

-- | Copy the assets and the content files the real site uses (its published
-- media included) into a temporary source tree.
copyAssets :: FilePath -> FilePath -> IO ()
copyAssets from to = do
  forM_ (allAssets :: [Asset]) $ \asset -> do
    let target = to </> "assets" </> assetPath asset
    Dir.createDirectoryIfMissing True (takeDirectory target)
    Dir.copyFile (from </> "assets" </> assetPath asset) target
  forM_ ["content/projects/brigid/project.json", "content/projects/brigid/body.md", "content/projects/brigid/card.svg"] $ \file -> do
    Dir.createDirectoryIfMissing True (takeDirectory (to </> file))
    Dir.copyFile (from </> file) (to </> file)
