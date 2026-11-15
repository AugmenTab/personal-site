-- | Phase 02: content loading, Markdown safety and publication filtering.
--
-- Every test drives the real pipeline: fixture files are written to a
-- temporary source tree, loaded with 'loadContent' / 'loadSite', rendered
-- through the real layout, and (where it matters) built with 'buildSite'.
-- Safety assertions inspect the final HTML, not an intermediate tree.
module ContentTests
  ( contentTests
    -- * Fixtures shared with HomeTests
  , withSource
  , projectJson
  , articleJson
  , svg
  , listFiles
  , readTree
  , slugOf
  ) where

import Control.Exception (try)
import Control.Monad (forM, forM_)
import Data.Aeson ((.=))
import Data.Aeson qualified as Json
import Data.Aeson.Key qualified as Key
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (isInfixOf, isSuffixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory qualified as Dir
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import Site.Assets (allAssets, assetPath)
import Site.Build
import Site.Content.Load (ContentError (..), loadContent)
import Site.Content.Markdown (Document (..), MarkdownError, Section (..), headingSlug, parseDocument)
import Site.Content.Types
import Site.Definition (siteFrom)
import Site.Layout (renderPage)
import Site.Page (Page (..), Site (..))
import Site.Routes
import Site.Validate (activeContent, attributeValues)

contentTests :: TestTree
contentTests =
  testGroup "content (Phase 02)"
    [ metadataTests
    , markdownTests
    , adversarialTests
    , filesystemTests
    , publishingTests
    , reliabilityTests
    ]

--------------------------------------------------------------------------------
-- Fixtures

-- | A complete, valid project.json; fields can be overridden or removed.
projectJson :: T.Text -> [(T.Text, Maybe Json.Value)] -> BS.ByteString
projectJson slug overrides =
  LBS.toStrict . Json.encode . Json.object $
    [ (Key.fromText k .= v) | (k, Just v) <- Map.toList fields ]
  where
    fields =
      Map.union (Map.fromList overrides) . Map.fromList $
        [ ("slug", Just (Json.String slug))
        , ("title", Just (Json.String ("Project " <> slug)))
        , ("summary", Just "A test project.")
        , ("category", Just "Test fixture")
        , ("development_status", Just "implemented")
        , ("publication_status", Just "published")
        , ("technologies", Just (Json.toJSON ["Haskell" :: T.Text]))
        , ("body", Just "body.md")
        ]

articleJson :: T.Text -> T.Text -> BS.ByteString
articleJson slug status =
  LBS.toStrict . Json.encode . Json.object $
    [ "slug" .= slug
    , "title" .= ("Article " <> slug)
    , "summary" .= ("An article." :: T.Text)
    , "publication_status" .= status
    , "date" .= ("2026-11-01" :: T.Text)
    , "body" .= ("body.md" :: T.Text)
    ]

svg :: BS.ByteString
svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\"/></svg>"

-- | A temporary source tree with the real assets and the given content files.
withSource :: [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withSource files action =
  withSystemTempDirectory "site-content" $ \root -> do
    forM_ allAssets $ \asset -> do
      let target = root </> "assets" </> assetPath asset
      Dir.createDirectoryIfMissing True (takeDirectory target)
      Dir.copyFile ("assets" </> assetPath asset) target
    forM_ files $ \(path, bytes) -> do
      Dir.createDirectoryIfMissing True (takeDirectory (root </> path))
      BS.writeFile (root </> path) bytes
    action root

-- | One valid project (@demo@) with the given body.
demoWithBody :: T.Text -> [(FilePath, BS.ByteString)]
demoWithBody body =
  [ ("content/projects/demo/project.json", projectJson "demo" [])
  , ("content/projects/demo/body.md", TE.encodeUtf8 body)
  ]

-- | All error messages for one loaded tree, joined.
loadErrors :: [(FilePath, BS.ByteString)] -> IO [ContentError]
loadErrors files =
  withSource files $ \root -> do
    loaded <- loadContent root
    pure (either id (const []) loaded)

expectContentError :: [(FilePath, BS.ByteString)] -> FilePath -> [String] -> Assertion
expectContentError files file needles = do
  errs <- loadErrors files
  let messages = concat [ ms | ContentError f ms <- errs, f == file ]
      shown = concatMap show errs
  assertBool ("expected an error for " <> file <> ", got:\n" <> shown) (not (null messages))
  forM_ needles $ \needle ->
    assertBool ("missing " <> show needle <> " in:\n" <> shown) (any (needle `isInfixOf`) messages)

-- | The rendered HTML of the demo project page for a Markdown body.
renderDemo :: T.Text -> [(FilePath, BS.ByteString)] -> IO (Either [ContentError] T.Text)
renderDemo body extra =
  withSource (demoWithBody body <> extra) $ \root -> do
    loaded <- loadContent root
    pure $ do
      content <- loaded
      let s = siteFrom content
          route = WorkDetail (slugOf "demo")
      case filter ((== route) . pageRoute) (sitePages s) of
        [page] -> Right (TE.decodeUtf8 (LBS.toStrict (renderPage (siteConfig s) page)))
        _ -> Left [ContentError "test" ["demo page not generated"]]

renderOk :: T.Text -> IO T.Text
renderOk body = do
  result <- renderDemo body []
  either (\errs -> assertFailure (concatMap show errs) >> pure "") pure result

-- | The part of a project page produced from Markdown (after the header).
contentPart :: T.Text -> T.Text
contentPart html = fst (T.breakOn "</article>" (snd (T.breakOn "class=\"project__header\"" html)))

slugOf :: T.Text -> Slug
slugOf = either (error . show) id . mkSlug

parseErrs :: T.Text -> [MarkdownError]
parseErrs = either id (const []) . parseDocument "test.md" ["main"]

--------------------------------------------------------------------------------
-- Metadata

metadataTests :: TestTree
metadataTests =
  testGroup "metadata validation"
    [ testCase "the real project content loads and is published" $ do
        loaded <- loadContent "."
        case loaded of
          Left errs -> assertFailure (concatMap show errs)
          Right content -> do
            map (slugText . projectSlug) (publishedProjects content) @?= ["black", "brigid", "lockdown"]
            map (slugText . projectSlug) (featuredProjects content) @?= ["black", "brigid", "lockdown"]
    , testCase "a missing required field" $
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("summary", Nothing)])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["missing required field \"summary\""]
    , testCase "a field of the wrong JSON type" $
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("technologies", Just "Haskell")])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["field \"technologies\": expected an array, got a string"]
    , testCase "an unknown status value names the allowed values" $
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("development_status", Just "complete-ish")])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json"
          ["invalid value \"complete-ish\"; expected one of: implemented, in_development, proposed"]
    , testCase "an unknown (misspelled) field is rejected" $
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("sumary", Just "typo")])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["unknown field \"sumary\""]
    , testCase "null is not a way to omit a field" $
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("featured_order", Just Json.Null)])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["null is not allowed"]
    , testCase "a missing body reference, and a body that does not exist" $ do
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("body", Nothing)]) ]
          "content/projects/demo/project.json" ["missing required field \"body\""]
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("body", Just "overview.md")]) ]
          "content/projects/demo/project.json" ["field \"body\": referenced file \"overview.md\" does not exist"]
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("body", Just "body.txt")])
          , ("content/projects/demo/body.txt", "") ]
          "content/projects/demo/project.json" ["must be a .md file"]
    , testCase "malformed JSON is reported with the parser's position" $
        expectContentError
          [ ("content/projects/demo/project.json", "{ \"slug\": \"demo\", }")
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["invalid JSON"]
    , testCase "invalid directory slugs and slug/directory mismatches" $ do
        expectContentError
          [ ("content/projects/Demo/project.json", projectJson "Demo" []) ]
          "content/projects/Demo" ["invalid slug \"Demo\""]
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "other" [])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["must equal the directory name \"demo\""]
    , testCase "two projects claiming one slug cannot both load" $ do
        errs <- loadErrors
          [ ("content/projects/demo/project.json", projectJson "demo" [])
          , ("content/projects/demo/body.md", "")
          , ("content/projects/demo-2/project.json", projectJson "demo" [])
          , ("content/projects/demo-2/body.md", "") ]
        [ f | ContentError f _ <- errs ] @?= ["content/projects/demo-2/project.json"]
    , testCase "duplicate featured order among published projects" $ do
        errs <- loadErrors
          [ ("content/projects/one/project.json", projectJson "one" [("featured_order", Just (Json.Number 1))])
          , ("content/projects/one/body.md", "")
          , ("content/projects/two/project.json", projectJson "two" [("featured_order", Just (Json.Number 1))])
          , ("content/projects/two/body.md", "")
          , ("content/projects/three/project.json", projectJson "three" [("featured_order", Just (Json.Number 1)), ("publication_status", Just "draft")])
          , ("content/projects/three/body.md", "") ]
        sort [ f | ContentError f _ <- errs ] @?= ["content/projects/one/project.json", "content/projects/two/project.json"]
    , testCase "an unsupported showcase kind, and an unrendered kind on a published project" $ do
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("showcase", Just (Json.object ["kind" .= ("hologram" :: T.Text)]))])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["unsupported showcase kind \"hologram\""]
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("showcase", Just (Json.object ["kind" .= ("audio" :: T.Text), "src" .= ("a.mp3" :: T.Text), "transcript" .= ("a.txt" :: T.Text)]))])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["kind \"audio\" is not supported for published projects yet"]
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("showcase", Just (Json.object ["kind" .= ("interactive" :: T.Text), "app" .= ("black-playground" :: T.Text)]))])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["unknown interactive application \"black-playground\""]
    , testCase "missing showcase properties" $
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("showcase", Just (Json.object ["kind" .= ("image" :: T.Text), "src" .= ("card.svg" :: T.Text)]))])
          , ("content/projects/demo/body.md", "")
          , ("content/projects/demo/card.svg", svg) ]
          "content/projects/demo/project.json" ["missing required field \"alt\""]
    , testCase "unsafe and broken media references" $ do
        forM_ ["../other/card.svg", "/etc/card.svg", "./card.svg", "media//card.svg"] $ \src ->
          expectContentError
            [ ("content/projects/demo/project.json", projectJson "demo" [("showcase", Just (image src))])
            , ("content/projects/demo/body.md", "") ]
            "content/projects/demo/project.json" ["field \"showcase\""]
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("showcase", Just (image "missing.svg"))])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["\"missing.svg\" does not exist"]
    , testCase "attribute-bound text may not contain a straight double quote" $
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("summary", Just "Say \"hi\" onmouseover=\"x")])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["field \"summary\": must not contain a straight double quote"]
    , testCase "external links must be https" $
        expectContentError
          [ ("content/projects/demo/project.json", projectJson "demo" [("links", Just (Json.toJSON [Json.object ["label" .= ("x" :: T.Text), "url" .= ("javascript:alert(1)" :: T.Text)]]))])
          , ("content/projects/demo/body.md", "") ]
          "content/projects/demo/project.json" ["field \"links\""]
    , testCase "independent errors are all reported in one run" $ do
        errs <- loadErrors
          [ ("content/projects/demo/project.json", projectJson "demo" [("title", Nothing), ("development_status", Just "done"), ("extra", Just "x")]) ]
        let messages = concat [ ms | ContentError _ ms <- errs ]
        assertBool (show errs) (length messages >= 3)
    ]
  where
    image src = Json.object ["kind" .= ("image" :: T.Text), "src" .= (src :: T.Text), "alt" .= ("A card" :: T.Text)]

--------------------------------------------------------------------------------
-- Markdown rendering

markdownTests :: TestTree
markdownTests =
  testGroup "markdown rendering"
    [ testCase "paragraphs, sections and nested headings" $ do
        html <- renderOk "Lead paragraph.\n\n## First part\n\nText.\n\n### Detail\n\nMore.\n\n## Second part\n\nEnd.\n"
        let body = contentPart html
        forM_ [ "<div class=\"project__lead prose\"><p>Lead paragraph.</p></div>"
              , "<h2 class=\"project__section-title\" id=\"first-part\">First part</h2><p>Text.</p><h3 id=\"detail\">Detail</h3><p>More.</p>"
              , "id=\"second-part\">Second part</h2>" ] $ \frag ->
          assertBool (T.unpack frag <> "\n" <> T.unpack body) (frag `T.isInfixOf` body)
        -- the sidebar lists the ## sections only, in order
        let sidebar = fst (T.breakOn "</nav>" (snd (T.breakOn "project-nav__sections" html)))
        assertBool (T.unpack sidebar) ("href=\"#first-part\">First part</a></li><li><a href=\"#second-part\">Second part</a>" `T.isInfixOf` sidebar)
        assertBool "h3 not in sidebar" (not ("#detail" `T.isInfixOf` sidebar))
    , testCase "nested lists, ordered lists and blockquotes" $ do
        html <- renderOk "## S\n\n- one\n  - nested\n- two\n\n1. first\n2. second\n\n> quoted *text*\n"
        let body = contentPart html
        forM_ [ "<ul><li>one<ul><li>nested</li></ul></li><li>two</li></ul>"
              , "<ol><li>first</li><li>second</li></ol>"
              , "<blockquote><p>quoted <em>text</em></p></blockquote>" ] $ \frag ->
          assertBool (T.unpack frag <> "\n" <> T.unpack body) (frag `T.isInfixOf` body)
    , testCase "emphasis, strong, links and inline code" $ do
        html <- renderOk "## S\n\nSome *em*, **strong**, `code <b>`, [site](/work/), [ext](https://example.com/a?b=1&c=2) and [here](#s).\n"
        let body = contentPart html
        forM_ [ "<em>em</em>", "<strong>strong</strong>", "<code>code &#60;b&#62;</code>"
              , "<a href=\"/work/\">site</a>", "<a href=\"https://example.com/a?b=1&", "<a href=\"#s\">here</a>" ] $ \frag ->
          assertBool (T.unpack frag <> "\n" <> T.unpack body) (frag `T.isInfixOf` body)
    , testCase "fenced code is escaped text with a validated language class" $ do
        html <- renderOk "## S\n\n```haskell\nmain = putStrLn \"<b>&\"\n```\n"
        assertBool (T.unpack (contentPart html))
          ("<pre class=\"code-block\"><code class=\"language-haskell\">main = putStrLn \"&#60;b&#62;&#38;\"\n</code></pre>" `T.isInfixOf` contentPart html)
        assertBool "invalid language rejected" (not (null (parseErrs "```bad\"lang\nx\n```\n")))
    , testCase "escaped characters and entities become plain text" $ do
        html <- renderOk "## S\n\n\\*not emphasis\\* &amp; &copy; 1 < 2 > 0\n"
        let body = contentPart html
        assertBool (T.unpack body) ("*not emphasis* &#38; © 1 &#60; 2 &#62; 0" `T.isInfixOf` body)
    , testCase "images resolve to the item's published media, with alt text" $ do
        result <- renderDemo "## S\n\n![A diagram](diagram.svg)\n" [("content/projects/demo/diagram.svg", svg)]
        html <- either (\e -> assertFailure (concatMap show e) >> pure "") pure result
        assertBool (T.unpack (contentPart html))
          ("<img src=\"/media/projects/demo/diagram.svg\" alt=\"A diagram\" loading=\"lazy\" decoding=\"async\"/>" `T.isInfixOf` contentPart html)
    , testCase "images need alt text" $
        assertBool "empty alt accepted" (not (null (parseErrs "![](a.svg)\n")))
    , testCase "duplicate and reserved headings get unique ids" $ do
        html <- renderOk "## Overview\n\nA\n\n## Overview\n\nB\n\n## Main\n\nC\n\n## Demo title\n\nD\n"
        forM_ ["id=\"overview\"", "id=\"overview-2\"", "id=\"main-2\"", "id=\"demo-title-2\""] $ \frag ->
          assertBool (T.unpack frag) (frag `T.isInfixOf` html)
        let ids = [ T.takeWhile (/= '"') rest | (_, r) <- T.breakOnAll " id=\"" html, let rest = T.drop 5 r ]
        sort ids @?= Map.keys (Map.fromList [ (i, ()) | i <- ids ])
    , testCase "heading ids handle punctuation, inline formatting, non-ASCII and empty text" $ do
        headingSlug "Limitations & Status!" @?= "limitations-status"
        headingSlug "Über *café* 2.0" @?= "über-café-2-0"
        headingSlug "!!!" @?= "section"
        case parseDocument "t.md" [] "## The `Brigid` *API*\n" of
          Right doc -> map sectionId (documentSections doc) @?= ["the-brigid-api"]
          Left errs -> assertFailure (show errs)
    , testCase "an empty document renders no sections and no sidebar list" $ do
        html <- renderOk ""
        assertBool "no section list" (not ("project-nav__sections" `T.isInfixOf` html))
        assertBool "no sections" (not ("project__section" `T.isInfixOf` html))
        assertBool "sidebar still present" ("project-nav__back" `T.isInfixOf` html)
    , testCase "non-ASCII text survives intact" $ do
        html <- renderOk "## Ελληνικά\n\nNaïve café — “quoted” 日本語.\n"
        assertBool (T.unpack (contentPart html)) ("<p>Naïve café — “quoted” 日本語.</p>" `T.isInfixOf` contentPart html)
    , testCase "heading policy: no #, no skipped levels, top-level only, no links" $ do
        forM_ [ "# Title\n", "### Too deep first\n", "## A\n\n#### Skip\n", "## A\n\n##### Five\n"
              , "- ## In a list\n", "> ## In a quote\n", "## [Link](/work/)\n" ] $ \md ->
          assertBool ("accepted: " <> show md) (not (null (parseErrs md)))
        parseErrs "## A\n\n### B\n\n#### C\n\n## D\n" @?= []
    , testCase "links inside emphasis are rejected (Brigid does not allow <a> in <em>)" $
        assertBool "accepted" (not (null (parseErrs "*see [here](/work/)*\n")))
    , testCase "errors carry line numbers" $
        case parseErrs "## A\n\nfine\n\n<div>raw</div>\n" of
          [err] -> assertBool (show err) ("line 5" `isInfixOf` show err)
          other -> assertFailure (show other)
    ]

--------------------------------------------------------------------------------
-- Adversarial Markdown

adversarialTests :: TestTree
adversarialTests =
  testGroup "adversarial markdown"
    [ testCase "raw HTML is rejected, inline and block" $
        forM_ [ "<script>alert(1)</script>\n"
              , "text <script>alert(1)</script>\n"
              , "<img src=x onerror=alert(1)>\n"
              , "a <b onclick=\"alert(1)\">b</b>\n"
              , "<iframe src=\"https://evil.example\"></iframe>\n"
              , "<!-- comment -->\n" ] $ \md -> do
          result <- renderDemo (T.pack md) []
          case result of
            Left errs -> assertBool (show errs) (any ("raw HTML" `isInfixOf`) (concat [ ms | ContentError _ ms <- errs ]))
            Right html -> assertFailure ("accepted raw HTML: " <> T.unpack (contentPart html))
    , testCase "dangerous and obfuscated link schemes are rejected" $
        forM_ [ "[x](javascript:alert(1))"
              , "[x](JaVaScRiPt:alert(1))"
              , "[x](&#106;avascript:alert(1))"
              , "[x](&#x6A;avascript:alert(1))"
              , "[x](java&#x09;script:alert(1))"
              , "[x](%6Aavascript:alert(1))"
              , "[x](vbscript:msgbox(1))"
              , "[x](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)"
              , "[x](http://insecure.example/)"
              , "[x](//evil.example/)"
              , "[x](/\\evil.example/)"
              , "[x](relative/page)"
              , "<javascript:alert(1)>"
              , "[x](<javascript:alert(1)>)"
              , "[x]: javascript:alert(1)\n\n[y][x]" ] $ \md -> do
          result <- renderDemo (T.pack md <> "\n") []
          case result of
            Left _ -> pure ()
            Right html -> assertFailure ("accepted " <> md <> ": " <> T.unpack (contentPart html))
    , testCase "dangerous image sources are rejected" $
        forM_ [ "![x](javascript:alert(1))", "![x](data:image/svg+xml;base64,PHN2Zz4=)"
              , "![x](https://tracker.example/pixel.png)", "![x](../../secret.png)", "![x](/etc/passwd.png)"
              , "![x](body.md)", "![x](project.json)" ] $ \md -> do
          result <- renderDemo (T.pack md <> "\n") []
          case result of
            Left _ -> pure ()
            Right html -> assertFailure ("accepted " <> md <> ": " <> T.unpack (contentPart html))
    , testCase "attribute-escaping attempts cannot break out of attributes" $ do
        -- quotes in a destination are refused outright
        forM_ [ "[x](/work/\"onmouseover=\"alert(1))", "[x](</work/\" onmouseover=\"alert(1)>)", "[x](https://a.example/'onfocus='x')" ] $ \md -> do
          result <- renderDemo (T.pack md <> "\n") []
          either (const (pure ())) (\html -> assertFailure ("accepted " <> md <> ": " <> T.unpack (contentPart html))) result
        -- Brigid does not escape '"' inside attribute values, so text bound
        -- for an attribute (alt text) may not contain one at all...
        refused <- renderDemo "## S\n\n![a\" onerror=\"alert(1)](d.svg)\n" [("content/projects/demo/d.svg", svg)]
        case refused of
          Left errs -> assertBool (concatMap show errs) ("straight double quote" `isInfixOf` concatMap show errs)
          Right html -> assertFailure ("accepted a quote in alt text: " <> T.unpack (contentPart html))
        -- ...while quotes in text content are harmless text.
        result <- renderDemo "## S\n\n[b\" onclick=\"x](/work/) and \"quoted\" text\n" []
        html <- either (\e -> assertFailure (concatMap show e) >> pure "") pure result
        let body = contentPart html
        assertBool (T.unpack body) ("<a href=\"/work/\">b\" onclick=\"x</a>" `T.isInfixOf` body)
        assertNoActiveContent body
    , testCase "HTML inside code is inert text" $ do
        html <- renderOk "## S\n\n```html\n<script>alert(1)</script>\n<img src=x onerror=alert(1)>\n```\n\nInline `<script>x</script>` too.\n"
        let body = contentPart html
        assertBool (T.unpack body) ("&#60;script&#62;alert(1)&#60;/script&#62;" `T.isInfixOf` body)
        assertNoActiveContent body
    , testCase "malformed link destinations are not links" $ do
        html <- renderOk "## S\n\n[x](java script:alert(1)) and [y](/work/ \"unterminated)\n"
        let body = contentPart html
        assertBool (T.unpack body) (not ("<a " `T.isInfixOf` body))
        assertNoActiveContent body
    ]

-- | No script-capable tags or event-handler attributes in any real tag (the
-- build's own check), and no script or data URLs in any href/src.
assertNoActiveContent :: T.Text -> Assertion
assertNoActiveContent html = do
  activeContent html @?= []
  forM_ (attributeValues "href" html <> attributeValues "src" html) $ \url -> do
    let lower = T.toLower (T.strip url)
    assertBool ("script URL " <> T.unpack url) (not (any (`T.isPrefixOf` lower) ["javascript:", "vbscript:", "data:"]))

--------------------------------------------------------------------------------
-- Filesystem boundaries

filesystemTests :: TestTree
filesystemTests =
  testGroup "filesystem boundaries"
    [ testCase "body paths cannot traverse or be absolute" $
        forM_ ["../other/body.md", "/etc/body.md", "sub/../body.md"] $ \path ->
          expectContentError
            [ ("content/projects/demo/project.json", projectJson "demo" [("body", Just (Json.String path))]) ]
            "content/projects/demo/project.json" ["field \"body\""]
    , testCase "symlinked bodies, media and directories cannot escape" $
        withSource
          [ ("content/projects/demo/project.json", projectJson "demo" [("showcase", Just (Json.object ["kind" .= ("image" :: T.Text), "src" .= ("card.svg" :: T.Text), "alt" .= ("A card" :: T.Text)]))])
          , ("outside/body.md", "## Leaked\n")
          , ("outside/card.svg", svg)
          , ("outside/project/project.json", projectJson "linked" []) ] $ \root -> do
            Dir.createFileLink (root </> "outside/body.md") (root </> "content/projects/demo/body.md")
            Dir.createFileLink (root </> "outside/card.svg") (root </> "content/projects/demo/card.svg")
            Dir.createDirectoryLink (root </> "outside/project") (root </> "content/projects/linked")
            loaded <- loadContent root
            case loaded of
              Right _ -> assertFailure "symlinks accepted"
              Left errs -> do
                let shown = concatMap show errs
                assertBool shown ("content/projects/linked" `isInfixOf` shown && "is a symlink" `isInfixOf` shown)
                assertBool shown ("outside its permitted directory" `isInfixOf` shown)
    , testCase "a content file cannot be published as media" $
        forM_ ["project.json", "body.md"] $ \src ->
          expectContentError
            [ ("content/projects/demo/project.json", projectJson "demo" [("showcase", Just (Json.object ["kind" .= ("image" :: T.Text), "src" .= (src :: T.Text), "alt" .= ("x" :: T.Text)]))])
            , ("content/projects/demo/body.md", "") ]
            "content/projects/demo/project.json" ["not an image file"]
    , testCase "stray files and dot-files in content/projects" $ do
        errs <- loadErrors [ ("content/projects/README.md", "notes"), ("content/projects/.DS_Store", "x") ]
        [ f | ContentError f _ <- errs ] @?= ["content/projects/README.md"]
    , testCase "no content directory means no projects, not an error" $
        withSource [] $ \root -> do
          loaded <- loadContent root
          case loaded of
            Right content -> length (contentProjects content) @?= 0
            Left errs -> assertFailure (concatMap show errs)
    , testCase "content slugs can never claim a fixed route" $
        forM_ ["about", "404", "index"] $ \s ->
          assertBool (T.unpack s) (routePath (WorkDetail (slugOf s)) `notElem` map routePath [Home, WorkIndex, About, NotFound])
    ]

--------------------------------------------------------------------------------
-- Publication

publishingTests :: TestTree
publishingTests =
  testGroup "publication"
    [ testCase "published projects get a route, a card and media; drafts get nothing" $
        withSource
          [ ("content/projects/live/project.json", projectJson "live" [("showcase", Just (art "live-art.svg"))])
          , ("content/projects/live/body.md", "## Live\n")
          , ("content/projects/live/live-art.svg", svg)
          , ("content/projects/secret/project.json", projectJson "secret" [("publication_status", Just "draft"), ("showcase", Just (art "secret-art.svg"))])
          , ("content/projects/secret/body.md", "## Secret\n\n![Secret diagram](diagram.svg)\n")
          , ("content/projects/secret/secret-art.svg", svg)
          , ("content/projects/secret/diagram.svg", svg) ] $ \root -> do
            s <- loadSite root
            let out = root </> "dist"
            _ <- buildSite BuildConfig { sourceRoot = root, outputDir = out } s
            files <- listFiles out
            assertBool "live page" ("work/live/index.html" `elem` files)
            assertBool "live media" ("media/projects/live/live-art.svg" `elem` files)
            assertBool ("no draft files: " <> show files) (not (any ("secret" `isInfixOf`) files))
            html <- concat <$> forM (filter (".html" `isSuffixOf`) files) (readFile . (out </>))
            assertBool "card for live" ("/work/live/" `isInfixOf` html)
            assertBool "nothing links to the draft" (not ("secret" `isInfixOf` html))
    , testCase "draft articles stay absent and no Writing section exists" $
        withSource
          [ ("content/writing/notes/article.json", articleJson "notes" "draft")
          , ("content/writing/notes/body.md", "## Draft\n") ] $ \root -> do
            s <- loadSite root
            let routes = map pageRoute (sitePages s)
            assertBool "no writing index" (WritingIndex `notElem` routes)
            assertBool "no article" (WritingArticle (slugOf "notes") `notElem` routes)
            forM_ [ p | p <- sitePages s, pageRoute p == Home ] $ \home ->
              assertBool "no Writing nav"
                (not ("/writing/" `T.isInfixOf` TE.decodeUtf8 (LBS.toStrict (renderPage (siteConfig s) home))))
    , testCase "one published article creates the Writing routes and nav entry" $
        withSource
          [ ("content/writing/first-post/article.json", articleJson "first-post" "published")
          , ("content/writing/first-post/body.md", "Intro.\n\n## Part one\n\nText.\n")
          , ("content/writing/draft-post/article.json", articleJson "draft-post" "draft")
          , ("content/writing/draft-post/body.md", "## Hidden\n") ] $ \root -> do
            s <- loadSite root
            let out = root </> "dist"
            _ <- buildSite BuildConfig { sourceRoot = root, outputDir = out } s
            files <- listFiles out
            assertBool (show files) ("writing/index.html" `elem` files)
            assertBool (show files) ("writing/first-post/index.html" `elem` files)
            assertBool (show files) (not (any ("draft-post" `isInfixOf`) files))
            home <- readFile (out </> "index.html")
            assertBool "Writing nav" ("class=\"site-nav__link\" href=\"/writing/\">Writing</a>" `isInfixOf` home)
            article <- readFile (out </> "writing/first-post/index.html")
            assertBool "article heading" ("id=\"part-one\">Part one</h2>" `isInfixOf` article)
    , testCase "the real site has no Writing section" $ do
        s <- loadSite "."
        assertBool "writing route" (WritingIndex `notElem` map pageRoute (sitePages s))
    , testCase "Work index order: featured by position, then by title, never by directory" $
        withSource
          [ ("content/projects/a-first/project.json", projectJson "a-first" [("title", Just "Zebra")])
          , ("content/projects/a-first/body.md", "")
          , ("content/projects/b-second/project.json", projectJson "b-second" [("title", Just "Apple")])
          , ("content/projects/b-second/body.md", "")
          , ("content/projects/c-third/project.json", projectJson "c-third" [("featured_order", Just (Json.Number 2))])
          , ("content/projects/c-third/body.md", "")
          , ("content/projects/d-fourth/project.json", projectJson "d-fourth" [("featured_order", Just (Json.Number 1))])
          , ("content/projects/d-fourth/body.md", "") ] $ \root -> do
            loaded <- loadContent root
            content <- either (\e -> assertFailure (concatMap show e) >> pure emptyContent) pure loaded
            map (slugText . projectSlug) (publishedProjects content) @?= ["d-fourth", "c-third", "b-second", "a-first"]
            map (slugText . projectSlug) (featuredProjects content) @?= ["d-fourth", "c-third"]
    , testCase "built output contains no Markdown or JSON sources" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          s <- loadSite "."
          _ <- buildSite BuildConfig { sourceRoot = ".", outputDir = tmp </> "dist" } s
          files <- listFiles (tmp </> "dist")
          assertBool (show files) (not (any (\f -> ".md" `isSuffixOf` f || ".json" `isSuffixOf` f) files))
    ]
  where
    art src = Json.object ["kind" .= ("image" :: T.Text), "src" .= (src :: T.Text), "alt" .= ("Project art" :: T.Text)]

--------------------------------------------------------------------------------
-- Reliability

reliabilityTests :: TestTree
reliabilityTests =
  testGroup "content build reliability"
    [ testCase "content errors, bad Markdown and malformed JSON preserve the previous output" $
        withSource (demoWithBody "## Fine\n") $ \root -> do
          let out = root </> "dist"
              config = BuildConfig { sourceRoot = root, outputDir = out }
          _ <- loadSite root >>= buildSite config
          before <- readTree out
          forM_
            [ ("content/projects/demo/body.md", "## Fine\n\n<script>alert(1)</script>\n")
            , ("content/projects/demo/project.json", "{ not json")
            , ("content/projects/demo/project.json", projectJson "demo" [("development_status", Just "done")]) ] $ \(file, bytes) -> do
              original <- BS.readFile (root </> file)
              BS.writeFile (root </> file) bytes
              result <- try (loadSite root >>= buildSite config)
              case result of
                Left (InvalidContent _) -> pure ()
                Left other -> assertFailure ("unexpected error: " <> show other)
                Right _ -> assertFailure ("built with broken " <> file)
              after <- readTree out
              after @?= before
              Dir.doesPathExist (out <> ".tmp") >>= assertBool "no staging left" . not
              BS.writeFile (root </> file) original
    , testCase "an invalid published project cannot partially publish" $
        withSource
          ( demoWithBody "## Fine\n"
              <> [ ("content/projects/broken/project.json", projectJson "broken" [])
                 , ("content/projects/broken/body.md", "## Bad\n\n[x](javascript:alert(1))\n") ] ) $ \root -> do
            result <- try (loadSite root)
            case result of
              Left (InvalidContent errs) ->
                [ f | ContentError f _ <- errs ] @?= ["content/projects/broken/body.md"]
              Left other -> assertFailure (show other)
              Right _ -> assertFailure "loaded"
            Dir.doesPathExist (root </> "dist") >>= assertBool "nothing written" . not
    , testCase "repeated content builds are byte-identical" $
        withSource (demoWithBody "## A\n\n- x\n\n```\ncode\n```\n") $ \root -> do
          s <- loadSite root
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = root </> "a" } s
          s' <- loadSite root
          _ <- buildSite BuildConfig { sourceRoot = root, outputDir = root </> "b" } s'
          a <- readTree (root </> "a")
          b <- readTree (root </> "b")
          a @?= b
    ]

--------------------------------------------------------------------------------
-- Helpers

listFiles :: FilePath -> IO [FilePath]
listFiles root = go ""
  where
    go rel = do
      entries <- Dir.listDirectory (root </> rel)
      concat <$> forM entries (\e -> do
        let relE = if null rel then e else rel </> e
        isDir <- Dir.doesDirectoryExist (root </> relE)
        if isDir then go relE else pure [relE])

readTree :: FilePath -> IO (Map.Map FilePath BS.ByteString)
readTree root = do
  files <- listFiles root
  Map.fromList <$> forM files (\f -> (,) f <$> BS.readFile (root </> f))
