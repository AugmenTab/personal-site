-- | Post-Phase 05 technical remediation (update 2).
--
-- * Attribute-bound content (summaries, alt text) may contain straight
--   quotation marks: Brigid escapes attribute values when it serializes
--   the page (fixed upstream at the pinned commit e0f4d45), so the old
--   quote bans were removed. These tests render through the portfolio's
--   real Brigid pipeline and re-read the output with an independent
--   HTML-style attribute tokenizer ('startTags'), so they check what a
--   browser would see: the value stays inside its attribute, no attribute
--   is added, and the value decodes back to the original text.
-- * Publication dates are checked against the Gregorian calendar.
module RemediationTests (remediationTests) where

import Control.Exception (try)
import Control.Monad (forM_)
import Data.Aeson ((.=))
import Data.Aeson qualified as Json
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Char (chr, isAsciiLower, isAsciiUpper, isDigit, isSpace)
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Lazy qualified as TL
import Numeric (readHex)
import System.Directory qualified as Dir
import System.FilePath ((</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Render.ByteString qualified as RenderBS
import Brigid.HTML.Render.Text qualified as RenderText
import Brigid.Types qualified as B

import Site.Build
import Site.Content.Load (ContentError (..), loadContent)
import Site.Content.Types
import Site.Definition (siteFrom)
import Site.Layout (pageDocument, renderPage)
import Site.Page (Page (..), Site (..))
import Site.Routes
import Site.Validate (PageProblem (..))

import ContentTests (projectJson, readTree, slugOf, svg, withSource)

remediationTests :: TestTree
remediationTests =
  testGroup "technical remediation (post-Phase 05)"
    [ quoteTests
    , dateTests
    , tokenizerTests
    ]

--------------------------------------------------------------------------------
-- Fixtures

quotedSummary :: T.Text
quotedSummary = "A \"correctness-first\" programming language."

quotedAlt :: T.Text
quotedAlt = "The window is called \"Brigid\" in the diagram."

-- | The adversarial regression input from the remediation plan.
injection :: T.Text
injection = "description\" onerror=\"alert(1)"

-- | Other punctuation that must survive an attribute round trip.
punctuation :: T.Text
punctuation = "Fish & chips: <b>not</b> a tag, 'single', \"double\", = and > too"

projectDir :: FilePath
projectDir = "content/projects/demo"

-- | The demo project with a quoted summary, a Markdown image and a hero,
-- each attribute-bound value given separately.
demoFiles :: T.Text -> T.Text -> T.Text -> [(FilePath, BS.ByteString)]
demoFiles summary bodyAlt heroAlt =
  [ ( projectDir </> "project.json"
    , projectJson "demo"
        [ ("summary", Just (Json.String summary))
        , ("hero", Just (Json.object ["src" .= ("hero.webp" :: T.Text), "alt" .= heroAlt]))
        ]
    )
  , (projectDir </> "body.md", TE.encodeUtf8 ("## Diagram\n\n![" <> escapeMarkdown bodyAlt <> "](d.svg)\n"))
  , (projectDir </> "d.svg", svg)
  , (projectDir </> "hero.webp", "RIFF0000WEBPVP8 hero")
  ]
  where
    -- alt text is Markdown inline content: escape the characters that are
    -- Markdown syntax so the alt text arrives as written
    escapeMarkdown = T.concatMap (\c -> if c `elem` ("\\[]*_`<>&!" :: String) then T.pack ['\\', c] else T.singleton c)

articleFiles :: T.Text -> T.Text -> Maybe T.Text -> [(FilePath, BS.ByteString)]
articleFiles slug summary date =
  [ (dir </> "article.json", LBS.toStrict (Json.encode (Json.object fields)))
  , (dir </> "body.md", "## Part\n\nText.\n")
  ]
  where
    dir = "content/writing" </> T.unpack slug
    fields =
      [ "slug" .= slug
      , "title" .= ("Article " <> slug)
      , "summary" .= summary
      , "publication_status" .= ("published" :: T.Text)
      , "body" .= ("body.md" :: T.Text)
      ]
        <> [ "date" .= d | Just d <- [date] ]

-- | Load a fixture tree, failing the test on content errors.
loadOk :: FilePath -> IO Content
loadOk root =
  loadContent root >>= either (\errs -> assertFailure (concatMap show errs) >> fail "unreachable") pure

-- | One route's page, rendered both ways the portfolio's Brigid offers:
-- the lazy ByteString renderer the build uses, and the Text renderer.
-- The two must agree byte for byte.
renderBoth :: Site -> Route -> IO T.Text
renderBoth s route =
  case filter ((== route) . pageRoute) (sitePages s) of
    [page] -> do
      let viaBytes = TE.decodeUtf8 (LBS.toStrict (renderPage (siteConfig s) page))
          viaText = RenderText.renderHTML (pageDocument (siteConfig s) page)
      viaText @?= viaBytes
      pure viaBytes
    other -> assertFailure ("expected one page for " <> show route <> ", got " <> show (length other)) >> pure ""

--------------------------------------------------------------------------------
-- An independent attribute tokenizer (test-side, not the site's validator)

-- | A start tag as an HTML tokenizer reads it: lowercase name, then each
-- attribute (double-quoted, single-quoted or unquoted) with character
-- references decoded.
data Tag = Tag {tagName :: T.Text, tagAttrs :: [(T.Text, T.Text)]}
  deriving (Eq, Show)

startTags :: T.Text -> [Tag]
startTags html =
  case T.breakOn "<" html of
    (_, rest)
      | T.null rest -> []
      | otherwise ->
          let after = T.drop 1 rest
           in case T.uncons after of
                Just (c, _)
                  | isAsciiLower c || isAsciiUpper c ->
                      let name = T.takeWhile (\x -> not (isSpace x) && x /= '/' && x /= '>') after
                          (attrs, remaining) = attributes (T.drop (T.length name) after) []
                       in Tag (T.toLower name) attrs : startTags remaining
                _ -> startTags after
  where
    attributes t acc =
      let t' = T.dropWhile (\c -> isSpace c || c == '/') t
       in case T.uncons t' of
            Nothing -> (reverse acc, t')
            Just ('>', r) -> (reverse acc, r)
            Just _ ->
              let (n, r1) = T.span (\c -> not (isSpace c) && c /= '=' && c /= '>' && c /= '/') t'
                  r2 = T.dropWhile isSpace r1
               in if T.null n
                    then attributes (T.drop 1 t') acc
                    else case T.uncons r2 of
                      Just ('=', r3) ->
                        let r4 = T.dropWhile isSpace r3
                            (v, r5) =
                              case T.uncons r4 of
                                Just (q, r)
                                  | q == '"' || q == '\'' ->
                                      let (a, b) = T.break (== q) r in (a, T.drop 1 b)
                                _ -> T.break (\c -> isSpace c || c == '>') r4
                         in attributes r5 ((T.toLower n, decodeReferences v) : acc)
                      _ -> attributes r2 ((T.toLower n, "") : acc)

-- | Decode numeric (decimal and hex) and the common named character
-- references; anything else is left as written.
decodeReferences :: T.Text -> T.Text
decodeReferences t =
  case T.breakOn "&" t of
    (a, b)
      | T.null b -> a
      | otherwise ->
          let (ref, rest) = T.breakOn ";" (T.drop 1 b)
           in case reference (T.unpack ref) of
                Just c | not (T.null rest) -> a <> T.singleton c <> decodeReferences (T.drop 1 rest)
                _ -> a <> "&" <> decodeReferences (T.drop 1 b)
  where
    reference r =
      case r of
        '#' : x : hex | x `elem` ("xX" :: String), [(n, "")] <- readHex hex -> Just (chr n)
        '#' : dec | not (null dec), all isDigit dec -> Just (chr (read dec))
        "quot" -> Just '"'
        "amp" -> Just '&'
        "lt" -> Just '<'
        "gt" -> Just '>'
        "apos" -> Just '\''
        _ -> Nothing

-- | Tags with the given name whose attribute @key@ has value @val@.
tagsWith :: T.Text -> T.Text -> T.Text -> T.Text -> [Tag]
tagsWith name key val html =
  [ tag | tag <- startTags html, tagName tag == name, lookup key (tagAttrs tag) == Just val ]

-- | Exactly one such tag, with exactly these attribute names (in order).
oneTag :: T.Text -> T.Text -> T.Text -> [T.Text] -> T.Text -> IO Tag
oneTag name key val names html =
  case tagsWith name key val html of
    [tag] -> do
      map fst (tagAttrs tag) @?= names
      pure tag
    other -> assertFailure ("expected one <" <> T.unpack name <> " " <> T.unpack key <> "=" <> show val <> ">, got " <> show other) >> fail "unreachable"

-- | No tag anywhere on the page has an event-handler attribute.
noHandlers :: T.Text -> Assertion
noHandlers html =
  forM_ (startTags html) $ \tag ->
    forM_ (map fst (tagAttrs tag)) $ \n ->
      assertBool ("handler attribute " <> T.unpack n <> " on <" <> T.unpack (tagName tag) <> ">")
        (not ("on" `T.isPrefixOf` n && T.length n > 2))

tokenizerTests :: TestTree
tokenizerTests =
  testGroup "the test tokenizer reads attributes the way a browser does"
    [ testCase "quoted, single-quoted, unquoted and bare attributes; references decoded" $
        startTags "<!DOCTYPE html><p>x</p><img src=\"/a.svg\" alt='it&#39;s' data-x=1 hidden/>"
          @?= [ Tag "p" []
              , Tag "img" [("src", "/a.svg"), ("alt", "it's"), ("data-x", "1"), ("hidden", "")]
              ]
    , testCase "an unescaped quote really would inject an attribute (so the checks below can fail)" $
        map fst (concatMap tagAttrs (startTags "<img alt=\"description\" onerror=\"alert(1)\">"))
          @?= ["alt", "onerror"]
    ]

--------------------------------------------------------------------------------
-- Quotes in attribute-bound content

quoteTests :: TestTree
quoteTests =
  testGroup "quotation marks in attribute-bound content"
    [ testCase "the plan's examples decode unchanged (summary, Markdown alt, hero alt)" $
        withSource (demoFiles quotedSummary quotedAlt quotedAlt) $ \root -> do
          content <- loadOk root
          case contentProjects content of
            [p] -> do
              projectSummary p @?= quotedSummary
              fmap heroAltText (projectHero p) @?= Just (Just quotedAlt)
            other -> assertFailure (show (length other) <> " projects")
    , testCase "they render inside their attributes, adding none, and parse back to the original" $
        forM_ [(quotedSummary, quotedAlt), (punctuation, punctuation)] $ \(summary, alt) ->
          withSource (demoFiles summary alt alt) $ \root -> do
            s <- siteFrom <$> loadOk root
            html <- renderBoth s (WorkDetail (slugOf "demo"))
            _ <- oneTag "meta" "name" "description" ["name", "content"] html
            lookup "content" . tagAttrs =<< headMay (tagsWith "meta" "name" "description" html) @?=? summary
            lookup "content" . tagAttrs =<< headMay (tagsWith "meta" "property" "og:description" html) @?=? summary
            _ <- oneTag "img" "src" "/media/projects/demo/d.svg" ["src", "alt", "loading", "decoding"] html
            lookup "alt" . tagAttrs =<< headMay (tagsWith "img" "src" "/media/projects/demo/d.svg" html) @?=? alt
            let heroes = (tagsWith "img" "src" "/media/projects/demo/hero.webp" html)
            case heroes of
              [tag] -> lookup "alt" (tagAttrs tag) @?= Just alt
              other -> assertFailure ("hero tags: " <> show other)
            noHandlers html
            -- the summary is also the card text on the Work index: text, not markup
            work <- renderBoth s WorkIndex
            assertBool "summary escaped as text" (not ("<b>not</b>" `T.isInfixOf` work))
            noHandlers work
    , testCase "an article summary with quotes stays inside the meta description" $
        withSource (articleFiles "quoted" quotedSummary (Just "2026-11-01")) $ \root -> do
          s <- siteFrom <$> loadOk root
          html <- renderBoth s (WritingArticle (slugOf "quoted"))
          _ <- oneTag "meta" "name" "description" ["name", "content"] html
          lookup "content" . tagAttrs =<< headMay (tagsWith "meta" "name" "description" html) @?=? quotedSummary
          noHandlers html
    , testCase "an injected attribute stays part of the original value (site pipeline)" $
        withSource (demoFiles injection injection injection) $ \root -> do
          s <- siteFrom <$> loadOk root
          html <- renderBoth s (WorkDetail (slugOf "demo"))
          -- (the summary is also shown as body text, where a literal quote is
          -- harmless; what matters is that no tag gains an attribute)
          assertBool "the value is escaped inside the attribute" ("content=\"description&#34; onerror=&#34;alert(1)\"" `T.isInfixOf` html)
          _ <- oneTag "meta" "name" "description" ["name", "content"] html
          lookup "content" . tagAttrs =<< headMay (tagsWith "meta" "name" "description" html) @?=? injection
          _ <- oneTag "img" "src" "/media/projects/demo/d.svg" ["src", "alt", "loading", "decoding"] html
          lookup "alt" . tagAttrs =<< headMay (tagsWith "img" "src" "/media/projects/demo/d.svg" html) @?=? injection
          noHandlers html
    , testCase "an injected attribute stays part of the original value (Brigid, Text and ByteString)" $ do
        let element :: E.ChildHTML E.Main E.Body
            element = E.img [A.src (B.mkRawURL "/x.svg"), A.alt injection]
            viaText = RenderText.renderHTML element
            viaBytes = TE.decodeUtf8 (RenderBS.renderHTML element)
            viaLazyText = TL.toStrict (RenderText.renderLazyHTML element)
            viaLazyBytes = TE.decodeUtf8 (LBS.toStrict (RenderBS.renderLazyHTML element))
        viaText @?= viaBytes
        viaLazyText @?= viaBytes
        viaLazyBytes @?= viaBytes
        startTags viaText @?= [Tag "img" [("src", "/x.svg"), ("alt", injection)]]
    , testCase "the build still refuses the injection outright (defence in depth, fails closed)" $
        withSource (demoFiles injection "A diagram" "A hero") $ \root -> do
          let out = root </> "dist"
          result <- try (loadSite root >>= buildSite BuildConfig {sourceRoot = root, outputDir = out})
          case result of
            Left (InvalidPages problems) ->
              assertBool (show problems) (not (null [ () | ActiveContent _ _ <- problems ]))
            Left other -> assertFailure ("unexpected error: " <> show other)
            Right _ -> assertFailure "built a page whose text looks like an event handler"
          Dir.doesPathExist out >>= assertBool "no output written" . not
    , testCase "ordinary quoted content builds, and site check accepts it" $
        withSource (demoFiles quotedSummary quotedAlt quotedAlt) $ \root -> do
          let config = BuildConfig {sourceRoot = root, outputDir = root </> "dist"}
          s <- loadSite root
          _ <- checkSite config s
          _ <- buildSite config s
          files <- readTree (root </> "dist")
          assertBool "project page written" (any ("work/demo/index.html" `isInfixOf`) (Map.keys files))
    ]
  where
    heroAltText h =
      case heroDescription h of
        HeroDescribed t -> Just t
        HeroDecorative -> Nothing
    headMay xs = case xs of
      x : _ -> Just x
      [] -> Nothing
    actual @?=? expected = actual @?= Just expected
    infix 0 @?=?

--------------------------------------------------------------------------------
-- Calendar dates

dateTests :: TestTree
dateTests =
  testGroup "publication dates are real calendar days"
    [ testCase "valid days, including leap days, are accepted unchanged" $
        forM_ ["2024-02-29", "2000-02-29", "2026-12-31", "2026-01-01", "2026-04-30"] $ \d ->
          withSource (articleFiles "dated" "An article." (Just d)) $ \root -> do
            content <- loadOk root
            map articleDate (contentArticles content) @?= [Just d]
    , testCase "impossible, out-of-range and malformed dates are rejected, naming the file" $
        forM_
          [ ("2026-02-29", "does not exist")
          , ("2026-02-31", "does not exist")
          , ("2026-04-31", "does not exist")
          , ("1900-02-29", "does not exist")
          , ("2026-00-10", "does not exist")
          , ("2026-13-01", "does not exist")
          , ("2026-01-00", "does not exist")
          , ("2026-1-01", "expected YYYY-MM-DD")
          , ("2026-01", "expected YYYY-MM-DD")
          , ("2026/01/01", "expected YYYY-MM-DD")
          , ("26-01-01", "expected YYYY-MM-DD")
          , ("2026-01-01T00:00", "expected YYYY-MM-DD")
          , ("+026-01-01", "expected YYYY-MM-DD")
          , ("２０２６-01-01", "expected YYYY-MM-DD")
          , ("", "must not be empty")
          ]
          $ \(d, why) -> do
            errs <- withSource (articleFiles "dated" "An article." (Just d)) $ \root ->
              either id (const []) <$> loadContent root
            let messages = concat [ ms | ContentError f ms <- errs, f == "content/writing/dated/article.json" ]
            assertBool ("accepted " <> show d <> ": " <> show errs) (any (\m -> "field \"date\"" `isInfixOf` m && why `isInfixOf` m) messages)
    , testCase "a date of the wrong JSON type is rejected" $ do
        let json = LBS.toStrict (Json.encode (Json.object
              [ "slug" .= ("dated" :: T.Text), "title" .= ("Dated" :: T.Text), "summary" .= ("A." :: T.Text)
              , "publication_status" .= ("published" :: T.Text), "body" .= ("body.md" :: T.Text), "date" .= (20260101 :: Int) ]))
        errs <- withSource [("content/writing/dated/article.json", json), ("content/writing/dated/body.md", "Text.\n")] $ \root ->
          either id (const []) <$> loadContent root
        assertBool (show errs) (any ("field \"date\": expected a string" `isInfixOf`) (concat [ ms | ContentError _ ms <- errs ]))
    , testCase "articles still sort newest first, undated last, deterministically" $
        withSource
          ( articleFiles "leap" "A." (Just "2024-02-29")
              <> articleFiles "march" "A." (Just "2024-03-01")
              <> articleFiles "older" "A." (Just "2023-12-31")
              <> articleFiles "undated" "A." Nothing )
          $ \root -> do
            first <- siteFrom <$> loadOk root
            second <- siteFrom <$> loadOk root
            index <- renderBoth first WritingIndex
            again <- renderBoth second WritingIndex
            index @?= again
            let order = [ slug | Tag "a" attrs <- startTags index, Just href <- [lookup "href" attrs]
                               , Just slug <- [T.stripSuffix "/" =<< T.stripPrefix "/writing/" href], not (T.null slug) ]
            dedupe order @?= ["march", "leap", "older", "undated"]
    , testCase "an impossible date fails the build and keeps the previous output" $
        withSource (articleFiles "dated" "An article." (Just "2026-02-28")) $ \root -> do
          let out = root </> "dist"
              config = BuildConfig {sourceRoot = root, outputDir = out}
              json = root </> "content/writing/dated/article.json"
          _ <- loadSite root >>= buildSite config
          before <- readTree out
          original <- BS.readFile json
          BS.writeFile json (TE.encodeUtf8 (T.replace "2026-02-28" "2026-02-31" (TE.decodeUtf8 original)))
          result <- try (loadSite root >>= buildSite config)
          case result of
            Left (InvalidContent _) -> pure ()
            Left other -> assertFailure ("unexpected error: " <> show other)
            Right _ -> assertFailure "built with an impossible date"
          after <- readTree out
          after @?= before
    ]
  where
    dedupe xs = case xs of
      a : b : rest | a == b -> dedupe (b : rest)
      a : rest -> a : dedupe rest
      [] -> []
