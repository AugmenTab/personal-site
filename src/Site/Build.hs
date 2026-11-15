-- | Writes the Phase 00 proof page and its assets to an output directory.
--
-- The build is all-or-nothing: inputs are validated first, output is staged
-- in a sibling directory, and only a complete staging tree replaces the
-- previous contents of the output directory.
module Site.Build
  ( BuildConfig (..)
  , BuildError (..)
  , BuildReport (..)
  , buildSite
  , cssReferences
  ) where

import Control.Exception (Exception, throwIO)
import Control.Monad (filterM, forM_, unless)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (isPrefixOf, isSuffixOf)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory qualified as Dir
import System.FilePath ((</>), takeDirectory, splitDirectories, joinPath, dropTrailingPathSeparator)

import Site.Assets (Asset, allAssets, assetPath)
import Site.Proof (renderHomePage)

data BuildConfig =
  BuildConfig
    { sourceRoot :: FilePath
      -- ^ Directory containing @assets/@ (the repository root).
    , outputDir :: FilePath
      -- ^ Directory to (re)populate, e.g. @dist@.
    }

data BuildError
  = MissingAssets [FilePath]
    -- ^ Listed in the manifest but absent from the source tree.
  | UnlistedStylesheetReference FilePath T.Text
    -- ^ A stylesheet @url(...)@ that does not resolve to a listed asset.
  deriving (Eq)

instance Show BuildError where
  show err =
    case err of
      MissingAssets paths ->
        "Build failed: required asset(s) missing from the source tree:\n"
          <> unlines (map ("  - " <>) paths)
      UnlistedStylesheetReference css ref ->
        "Build failed: " <> css <> " references " <> show (T.unpack ref)
          <> ", which is not a listed asset (see Site.Assets.allAssets)."

instance Exception BuildError

data BuildReport =
  BuildReport
    { reportHtmlBytes :: Int
    , reportAssetCount :: Int
    }

buildSite :: BuildConfig -> IO BuildReport
buildSite config = do
  let assetsRoot = sourceRoot config </> "assets"
      sourceOf asset = assetsRoot </> assetPath asset

  missing <- filterM (fmap not . Dir.doesFileExist . sourceOf) allAssets
  unless (null missing) $
    throwIO (MissingAssets (map (("assets/" <>) . assetPath) missing))

  forM_ (filter isStylesheet allAssets) $ \css -> do
    contents <- TE.decodeUtf8 <$> BS.readFile (sourceOf css)
    forM_ (cssReferences contents) $ \ref ->
      unless (resolvesToListedAsset css ref) $
        throwIO (UnlistedStylesheetReference ("assets/" <> assetPath css) ref)

  let outDir = dropTrailingPathSeparator (outputDir config)
      staging = outDir <> ".tmp"
      html = renderHomePage

  Dir.removePathForcibly staging
  Dir.createDirectoryIfMissing True staging
  LBS.writeFile (staging </> "index.html") html
  forM_ allAssets $ \asset -> do
    let target = staging </> "assets" </> assetPath asset
    Dir.createDirectoryIfMissing True (takeDirectory target)
    Dir.copyFile (sourceOf asset) target

  promote staging outDir

  pure
    BuildReport
      { reportHtmlBytes = fromIntegral (LBS.length html)
      , reportAssetCount = length allAssets
      }

-- | Replace the contents of @outDir@ with the contents of @staging@.
--
-- The output directory itself is kept (only its children are replaced), so a
-- running preview container's bind mount of @dist/@ stays valid.
promote :: FilePath -> FilePath -> IO ()
promote staging outDir = do
  exists <- Dir.doesDirectoryExist outDir
  if exists
    then do
      old <- Dir.listDirectory outDir
      forM_ old $ \entry -> Dir.removePathForcibly (outDir </> entry)
    else Dir.createDirectoryIfMissing True outDir
  new <- Dir.listDirectory staging
  forM_ new $ \entry -> Dir.renamePath (staging </> entry) (outDir </> entry)
  Dir.removeDirectory staging

isStylesheet :: Asset -> Bool
isStylesheet = (".css" `isSuffixOf`) . assetPath

-- | Local file references made with @url(...)@ in a stylesheet. Data URIs,
-- absolute URLs and fragment-only references are ignored.
cssReferences :: T.Text -> [T.Text]
cssReferences =
  filter isLocal . map (unquote . T.strip . T.takeWhile (/= ')')) . drop 1 . T.splitOn "url("
  where
    unquote = T.dropAround (\c -> c == '"' || c == '\'')
    isLocal ref =
      not (T.null ref)
        && not (any (`T.isPrefixOf` ref) ["data:", "http:", "https:", "#", "/"])

resolvesToListedAsset :: Asset -> T.Text -> Bool
resolvesToListedAsset css ref =
  case collapse (splitDirectories (takeDirectory (assetPath css) </> T.unpack ref)) of
    Nothing -> False
    Just parts -> joinPath parts `elem` map assetPath allAssets
  where
    -- Resolve "." and ".." without touching the filesystem; reject paths that
    -- climb out of the assets directory.
    collapse = go []
    go acc [] = Just (reverse acc)
    go acc (p : ps)
      | p == "." = go acc ps
      | p == ".." = case acc of
          [] -> Nothing
          (_ : rest) -> go rest ps
      | "/" `isPrefixOf` p = Nothing
      | otherwise = go (p : acc) ps
