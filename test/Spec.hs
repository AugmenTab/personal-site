module Main (main) where

import Control.Exception (try)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory qualified as Dir
import System.FilePath ((</>), takeDirectory)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import Site.Assets (allAssets, assetPath)
import Site.Build (BuildConfig (..), BuildError (..), buildSite, cssReferences)
import Site.Proof (renderHomePage)

main :: IO ()
main =
  defaultMain $
    testGroup "personal-site"
      [ renderTests
      , buildTests
      ]

html :: T.Text
html = TE.decodeUtf8 (LBS.toStrict renderHomePage)

count :: T.Text -> T.Text -> Int
count needle haystack = length (T.breakOnAll needle haystack)

renderTests :: TestTree
renderTests =
  testGroup "Brigid render"
    [ testCase "is a complete HTML document" $ do
        assertBool "doctype" ("<!DOCTYPE html>" `T.isPrefixOf` html)
        assertBool "lang" ("<html lang=\"en\">" `T.isInfixOf` html)
        assertBool "closes html" ("</html>" `T.isSuffixOf` T.strip html)
    , testCase "has exactly one h1, and it is the name" $ do
        count "<h1" html @?= 1
        assertBool "name in h1" ("Tyler</span> <span class=\"hero__name-word\">Baum" `T.isInfixOf` html)
    , testCase "has main, nav, and the in-page anchors the CTAs target" $ do
        forM_ ["<main id=\"main\"", "<nav ", "id=\"selected-work\"", "id=\"about\"", "id=\"contact\"", "id=\"top\""] $ \frag ->
          assertBool (T.unpack frag) (frag `T.isInfixOf` html)
        forM_ ["href=\"#selected-work\"", "href=\"#about\"", "href=\"#contact\"", "href=\"#top\""] $ \frag ->
          assertBool (T.unpack frag) (frag `T.isInfixOf` html)
    , testCase "every <img> has an alt attribute" $
        forM_ (drop 1 (T.splitOn "<img " html)) $ \tag ->
          assertBool "img alt" ("alt=" `T.isInfixOf` T.takeWhile (/= '>') tag)
    , testCase "the Black teaser is static: no scripts, forms or controls" $
        forM_ ["<script", "<form", "<button", "<textarea", "<input"] $ \frag ->
          assertBool ("unexpected " <> T.unpack frag) (not (frag `T.isInfixOf` html))
    , testCase "the monogram appears only in the navigation medallion" $
        count "monogram" html @?= 1
    , testCase "the About section carries the tree emblem" $
        assertBool "tree in about" ("about__tree" `T.isInfixOf` snd (T.breakOn "id=\"about\"" html))
    , testCase "rendering is deterministic" $
        renderHomePage @?= renderHomePage
    ]

buildTests :: TestTree
buildTests =
  testGroup "build"
    [ testCase "writes index.html and every listed asset" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let out = tmp </> "dist"
          _ <- buildSite BuildConfig { sourceRoot = ".", outputDir = out }
          index <- BS.readFile (out </> "index.html")
          assertBool "non-empty html" (BS.length index > 1000)
          forM_ allAssets $ \asset -> do
            exists <- Dir.doesFileExist (out </> "assets" </> assetPath asset)
            assertBool ("copied " <> assetPath asset) exists
          staged <- Dir.doesDirectoryExist (out <> ".tmp")
          assertBool "staging directory removed" (not staged)
    , testCase "a second build produces byte-identical output" $
        withSystemTempDirectory "site-out" $ \tmp -> do
          let out = tmp </> "dist"
          _ <- buildSite BuildConfig { sourceRoot = ".", outputDir = out }
          first <- BS.readFile (out </> "index.html")
          _ <- buildSite BuildConfig { sourceRoot = ".", outputDir = out }
          second <- BS.readFile (out </> "index.html")
          first @?= second
    , testCase "fails clearly when a required asset is missing" $
        withSystemTempDirectory "site-src" $ \src -> do
          copyAssets "." src
          let victim = "images/hero-plate-centre.webp"
          Dir.removeFile (src </> "assets" </> victim)
          result <- try (buildSite BuildConfig { sourceRoot = src, outputDir = src </> "dist" })
          case result of
            Left err -> err @?= MissingAssets ["assets/" <> victim]
            Right _ -> assertFailure "build succeeded with a missing asset"
          wrote <- Dir.doesDirectoryExist (src </> "dist")
          assertBool "no output written on failure" (not wrote)
    , testCase "fails when a stylesheet references an unlisted file" $
        withSystemTempDirectory "site-src" $ \src -> do
          copyAssets "." src
          let css = src </> "assets" </> "styles" </> "site.css"
          BS.appendFile css "\n.x { background: url(\"../images/not-listed.png\"); }\n"
          result <- try (buildSite BuildConfig { sourceRoot = src, outputDir = src </> "dist" })
          case result of
            Left (UnlistedStylesheetReference _ ref) -> ref @?= "../images/not-listed.png"
            Left other -> assertFailure ("unexpected error: " <> show other)
            Right _ -> assertFailure "build succeeded with an unlisted CSS reference"
    , testCase "cssReferences ignores data URIs and absolute URLs" $
        cssReferences "a{b:url(\"x.svg\")} c{d:url(data:image/svg+xml,abc)} e{f:url(https://e.com/x)} g{h:url( '../y.woff2' )}"
          @?= ["x.svg", "../y.woff2"]
    ]

copyAssets :: FilePath -> FilePath -> IO ()
copyAssets from to =
  forM_ allAssets $ \asset -> do
    let target = to </> "assets" </> assetPath asset
    Dir.createDirectoryIfMissing True (takeDirectory target)
    Dir.copyFile (from </> "assets" </> assetPath asset) target
