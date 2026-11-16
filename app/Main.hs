module Main (main) where

import Control.Exception (try)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import Site.Build (BuildConfig (..), BuildError, BuildReport (..), CheckReport (..), buildSite, checkSite, loadSite)
import Site.Manifest (Entry (..), describeSource, manifestEntries)
import Site.Page (Site (..))
import Site.Path (outputText)

usage :: String
usage =
  unlines
    [ "usage: site build [--root SRC] [--out DIR]   validate content, render and publish the site into DIR (default: dist)"
    , "       site check [--root SRC]              validate content, routes, assets and rendered pages; write nothing"
    , ""
    , "SRC is the source tree holding content/ and assets/ (default: the current directory)."
    , "Use another root only for development previews (README \"Previewing a hero\")."
    ]

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["build"] -> build "." "dist"
    ["build", "--out", dir] -> build "." dir
    ["build", "--root", root, "--out", dir] -> build root dir
    ["check"] -> check "."
    ["check", "--root", root] -> check root
    _ -> do
      hPutStrLn stderr usage
      exitFailure

-- | Load the site and print its content warnings (they never fail a build).
loadAndWarn :: FilePath -> IO Site
loadAndWarn root = do
  s <- loadSite root
  mapM_ (hPutStrLn stderr . ("warning: " <>)) (siteWarnings s)
  pure s

check :: FilePath -> IO ()
check root = do
  result <- try $ do
    s <- loadAndWarn root
    checkSite BuildConfig { sourceRoot = root, outputDir = "dist" } s
  case result of
    Left err -> failWith err
    Right report -> do
      let entries = manifestEntries (checkManifest report)
          width = 2 + maximum (0 : map (length . outputText . entryOutput) entries)
      mapM_ (putStrLn . describeEntry width) entries
      putStrLn $
        "OK: " <> show (length (checkPages report)) <> " pages and "
          <> show (length entries - length (checkPages report))
          <> " files validated; nothing written."

build :: FilePath -> FilePath -> IO ()
build root dir = do
  result <- try $ do
    s <- loadAndWarn root
    buildSite BuildConfig { sourceRoot = root, outputDir = dir } s
  case result of
    Left err -> failWith err
    Right report ->
      putStrLn $
        "Wrote " <> show (reportPageCount report) <> " pages (" <> show (reportHtmlBytes report)
          <> " bytes of HTML) and " <> show (reportAssetCount report) <> " assets and media files to " <> dir <> "/."

describeEntry :: Int -> Entry -> String
describeEntry width entry = "  " <> padRight width (outputText (entryOutput entry)) <> describeSource (entrySource entry)
  where
    padRight n str = str <> replicate (n - length str) ' '

failWith :: BuildError -> IO a
failWith err = do
  hPutStrLn stderr (show err)
  exitFailure
