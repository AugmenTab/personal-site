module Main (main) where

import Control.Exception (try)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import Site.Build (BuildConfig (..), BuildError, BuildReport (..), buildSite)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["build"] -> build "dist"
    ["build", "--out", dir] -> build dir
    _ -> do
      hPutStrLn stderr "usage: site build [--out DIR]   (default DIR: dist)"
      exitFailure

build :: FilePath -> IO ()
build dir = do
  result <- try (buildSite BuildConfig { sourceRoot = ".", outputDir = dir })
  case result of
    Left err -> do
      hPutStrLn stderr (show (err :: BuildError))
      exitFailure
    Right report ->
      putStrLn $
        "Wrote " <> dir <> "/index.html (" <> show (reportHtmlBytes report)
          <> " bytes) and " <> show (reportAssetCount report) <> " assets."
