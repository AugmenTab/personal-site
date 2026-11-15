module Main (main) where

import Control.Exception (try)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import Site.Build (BuildConfig (..), BuildError, BuildReport (..), CheckReport (..), buildSite, checkSite)
import Site.Definition (site)
import Site.Manifest (Entry (..), describeSource, manifestEntries)
import Site.Page (Site)
import Site.Path (outputText)

usage :: String
usage =
  unlines
    [ "usage: site build [--out DIR]   validate, render and publish the site into DIR (default: dist)"
    , "       site check               validate routes, assets and rendered pages; write nothing"
    ]

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["build"] -> build "dist"
    ["build", "--out", dir] -> build dir
    ["check"] -> check
    _ -> do
      hPutStrLn stderr usage
      exitFailure

loadSite :: IO Site
loadSite =
  case site of
    Right s -> pure s
    Left err -> do
      hPutStrLn stderr ("Build failed: " <> show err)
      exitFailure

check :: IO ()
check = do
  s <- loadSite
  result <- try (checkSite BuildConfig { sourceRoot = ".", outputDir = "dist" } s)
  case result of
    Left err -> failWith err
    Right report -> do
      let entries = manifestEntries (checkManifest report)
      let width = 2 + maximum (0 : map (length . outputText . entryOutput) entries)
      mapM_ (putStrLn . describeEntry width) entries
      putStrLn $
        "OK: " <> show (length (checkPages report)) <> " pages and "
          <> show (length entries - length (checkPages report))
          <> " assets validated; nothing written."

build :: FilePath -> IO ()
build dir = do
  s <- loadSite
  result <- try (buildSite BuildConfig { sourceRoot = ".", outputDir = dir } s)
  case result of
    Left err -> failWith err
    Right report ->
      putStrLn $
        "Wrote " <> show (reportPageCount report) <> " pages (" <> show (reportHtmlBytes report)
          <> " bytes of HTML) and " <> show (reportAssetCount report) <> " assets to " <> dir <> "/."

describeEntry :: Int -> Entry -> String
describeEntry width entry = "  " <> padRight width (outputText (entryOutput entry)) <> describeSource (entrySource entry)
  where
    padRight n str = str <> replicate (n - length str) ' '

failWith :: BuildError -> IO a
failWith err = do
  hPutStrLn stderr (show err)
  exitFailure
