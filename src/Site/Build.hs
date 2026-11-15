{-# LANGUAGE ScopedTypeVariables #-}

-- | Validate the site, render it into a staging directory, and promote the
-- staged tree into the output directory only if every step succeeded.
--
-- @
-- checkSite   1. manifest: routes and asset paths valid, no collisions
--             2. sources:  every asset exists, is a regular file, and
--                          resolves (after symlinks) inside assets/
--             3. styles:   every stylesheet url(...) is a listed asset
--             4. pages:    render in memory; structure, ids and links valid
-- buildSite   5. output directory is missing, empty, or carries this
--                generator's ownership marker (see 'ownershipMarker')
--             6. write pages, copy assets and write the marker into DIR.tmp/
--             7. the staged tree contains exactly the manifest's files plus
--                the marker
--             8. promote DIR.tmp/ into DIR/, keeping the old tree in
--                DIR.old/ until the swap completes; roll back on failure
-- @
--
-- Filesystem assumptions: @DIR.tmp@ and @DIR.old@ are siblings of @DIR@, so
-- all three are on one filesystem and each move is a @rename(2)@. Each
-- rename is atomic; the swap as a whole is not, but it either completes or
-- is rolled back. @DIR@ itself is never renamed, only its children, so a
-- bind mount of @DIR@ (the preview container) stays valid.
module Site.Build
  ( BuildConfig (..)
  , BuildError (..)
  , CheckReport (..)
  , BuildReport (..)
  , loadSite
  , checkSite
  , buildSite
  , renderSite
  , promoteWith
  , ownershipMarker
  , ownershipMarkerContents
  , cssReferences
  ) where

import Control.Exception (Exception, SomeException, onException, throwIO, try)
import Control.Monad (forM, forM_, unless, when)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isSuffixOf, sort)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory qualified as Dir
import System.FilePath (dropTrailingPathSeparator, joinPath, splitDirectories, takeDirectory, (</>))

import Site.Assets (Asset, assetPath)
import Site.Content.Load (ContentError, loadContent)
import Site.Content.Types (MediaFile (..))
import Site.Definition (siteFrom)
import Site.Layout (renderPage)
import Site.Manifest (Entry (..), Manifest, ManifestError, manifestAssets, manifestEntries, manifestMedia, manifestPages, mkManifest)
import Site.Page (Page (..), Site (..))
import Site.Path (OutputPath, isWithin, mkOutputPath, outputFilePath, resolveUnder)
import Site.Source (SourceProblem (..), describeSourceProblem, sourceFileProblem)
import Site.Routes (Route)
import Site.Validate (PageProblem, validatePages)

data BuildConfig =
  BuildConfig
    { sourceRoot :: FilePath
      -- ^ Directory containing @assets/@ (the repository root).
    , outputDir :: FilePath
      -- ^ Directory to (re)populate, e.g. @dist@.
    }

data BuildError
  = InvalidContent [ContentError]
    -- ^ Content metadata or Markdown failed validation.
  | InvalidManifest [ManifestError]
  | MissingAssets [FilePath]
    -- ^ Listed in the manifest but absent from the source tree.
  | UnsafeAsset FilePath String
    -- ^ Not a regular file, or resolves outside @assets/@ (e.g. a symlink).
  | UnlistedStylesheetReference FilePath T.Text
    -- ^ A stylesheet @url(...)@ that does not resolve to a listed asset.
  | InvalidMedia [String]
    -- ^ Published media that is missing, not a file, or escapes its directory.
  | InvalidPages [PageProblem]
  | UnsafeOutputDirectory FilePath String
  | StagedOutputMismatch [FilePath] [FilePath]
    -- ^ Files missing from, and unexpected in, the staged tree.
  | InterruptedPromotion FilePath
    -- ^ A backup directory from an interrupted promotion still exists.
  | PromotionFailed String
    -- ^ Promotion failed and the previous output was restored.
  | RollbackFailed FilePath String
    -- ^ Promotion and its rollback both failed; the previous output is in
    -- the named backup directory.
  deriving (Eq)

instance Show BuildError where
  show err =
    "Build failed: " <>
    case err of
      InvalidContent errs ->
        "invalid content:\n" <> concatMap show errs
      InvalidMedia problems ->
        "published media cannot be copied:\n" <> bullets problems
      InvalidManifest errs ->
        "invalid routes or output paths:\n" <> bullets (map show errs)
      MissingAssets paths ->
        "required asset(s) missing from the source tree:\n" <> bullets paths
          <> "Restore the file(s), or remove them from Site.Assets.allAssets."
      UnsafeAsset path why -> path <> " " <> why
      UnlistedStylesheetReference css ref ->
        css <> " references " <> show (T.unpack ref)
          <> ", which is not a listed asset (see Site.Assets.allAssets)."
      InvalidPages problems -> "generated pages failed validation:\n" <> bullets (map show problems)
      UnsafeOutputDirectory dir why -> "refusing to write to " <> show dir <> ": " <> why
      StagedOutputMismatch missing extra ->
        "the staged output does not match the manifest:\n"
          <> bullets (map ("missing: " <>) missing <> map ("unexpected: " <>) extra)
      InterruptedPromotion backup ->
        show backup <> " exists, so an earlier build was interrupted while publishing. "
          <> "It may hold the last good output: inspect it, then delete it and rebuild."
      PromotionFailed why -> "could not publish the new output (" <> why <> "); the previous output was restored."
      RollbackFailed backup why ->
        "could not publish the new output, and restoring the previous output also failed ("
          <> why <> "). The previous output is in " <> show backup <> "."
    where
      bullets = unlines . map ("  - " <>)

instance Exception BuildError

-- | What 'checkSite' validated, ready to be written.
data CheckReport =
  CheckReport
    { checkManifest :: Manifest
    , checkPages :: [(Route, OutputPath, LBS.ByteString)]
    }

data BuildReport =
  BuildReport
    { reportEntries :: [Entry]
    , reportPageCount :: Int
    , reportAssetCount :: Int
    , reportHtmlBytes :: Int
    }

-- | Load and validate @content/@ under the source root, and derive the
-- site from it. Throws 'InvalidContent' with every content problem found.
loadSite :: FilePath -> IO Site
loadSite root = do
  loaded <- loadContent root
  either (throwIO . InvalidContent) (pure . siteFrom) loaded

-- | Render every page, in manifest (output path) order.
renderSite :: Site -> Manifest -> [(Route, OutputPath, LBS.ByteString)]
renderSite s manifest =
  [ (pageRoute page, path, renderPage (siteConfig s) page)
  | (route, path) <- manifestPages manifest
  , page <- filter ((== route) . pageRoute) (sitePages s)
  ]

-- | Validate everything that does not require writing output.
checkSite :: BuildConfig -> Site -> IO CheckReport
checkSite config s = do
  manifest <-
    either (throwIO . InvalidManifest) pure $
      mkManifest (map pageRoute (sitePages s)) (siteAssets s) (siteMedia s)

  let assetsRoot = sourceRoot config </> "assets"
      sourceOf asset = assetsRoot </> assetPath asset
      assets = map fst (manifestAssets manifest)

  -- Assets and media go through the same source check ("Site.Source").
  assetProblems <- forM assets $ \asset ->
    case mkOutputPath (assetPath asset) of
      Left err -> pure (asset, Just (Left (show err)))
      Right rel -> (,) asset . fmap Right <$> sourceFileProblem assetsRoot rel
  let missing = [ asset | (asset, Just (Right SourceMissing)) <- assetProblems ]
  unless (null missing) $
    throwIO (MissingAssets (map (("assets/" <>) . assetPath) missing))
  forM_ assetProblems $ \(asset, problem) ->
    forM_ problem $ \p ->
      throwIO (UnsafeAsset ("assets/" <> assetPath asset) (either id describeSourceProblem p))

  mediaProblems <- forM (manifestMedia manifest) $ \(m, _) -> do
    problem <- sourceFileProblem (sourceRoot config </> mediaRoot m) (mediaPath m)
    pure [ mediaRoot m </> outputFilePath (mediaPath m) <> " " <> describeSourceProblem p | Just p <- [problem] ]
  unless (null (concat mediaProblems)) $
    throwIO (InvalidMedia (concat mediaProblems))

  forM_ (filter isStylesheet assets) $ \css -> do
    contents <- TE.decodeUtf8 <$> BS.readFile (sourceOf css)
    forM_ (cssReferences contents) $ \ref ->
      unless (resolvesToListedAsset assets css ref) $
        throwIO (UnlistedStylesheetReference ("assets/" <> assetPath css) ref)

  let pages = renderSite s manifest
      problems =
        validatePages manifest
          [ (route, TE.decodeUtf8 (LBS.toStrict html)) | (route, _, html) <- pages ]
  unless (null problems) $ throwIO (InvalidPages problems)

  pure CheckReport { checkManifest = manifest, checkPages = pages }

-- | Check, stage and publish the site. On any failure the previous contents
-- of the output directory are left in place and no staging files remain.
buildSite :: BuildConfig -> Site -> IO BuildReport
buildSite config s = do
  let outDir = dropTrailingPathSeparator (outputDir config)
      staging = outDir <> ".tmp"
      backup = outDir <> ".old"

  report <- checkSite config s
  checkOutputDirectory (sourceRoot config) outDir

  interrupted <- Dir.doesPathExist backup
  when interrupted $ throwIO (InterruptedPromotion backup)

  let manifest = checkManifest report
      assetsRoot = sourceRoot config </> "assets"

  Dir.removePathForcibly staging
  flip onException (Dir.removePathForcibly staging) $ do
    Dir.createDirectoryIfMissing True staging
    forM_ (checkPages report) $ \(_, path, html) -> do
      let target = resolveUnder staging path
      Dir.createDirectoryIfMissing True (takeDirectory target)
      LBS.writeFile target html
    forM_ (manifestAssets manifest) $ \(asset, path) -> do
      let target = resolveUnder staging path
      Dir.createDirectoryIfMissing True (takeDirectory target)
      Dir.copyFile (assetsRoot </> assetPath asset) target
    forM_ (manifestMedia manifest) $ \(m, path) -> do
      let target = resolveUnder staging path
      Dir.createDirectoryIfMissing True (takeDirectory target)
      Dir.copyFile (sourceRoot config </> mediaRoot m </> outputFilePath (mediaPath m)) target
    BS.writeFile (staging </> ownershipMarker) ownershipMarkerContents

    staged <- listFilesRecursive staging
    let expected = sort (ownershipMarker : map (outputFilePath . entryOutput) (manifestEntries manifest))
    unless (staged == expected) $
      throwIO (StagedOutputMismatch (filter (`notElem` staged) expected) (filter (`notElem` expected) staged))

  promoteWith Dir.renamePath staging backup outDir

  pure
    BuildReport
      { reportEntries = manifestEntries manifest
      , reportPageCount = length (checkPages report)
      , reportAssetCount = length (manifestAssets manifest) + length (manifestMedia manifest)
      , reportHtmlBytes = sum [ fromIntegral (LBS.length html) | (_, _, html) <- checkPages report ]
      }

-- | The file that marks a directory as owned by this generator. Every build
-- writes it, with exactly 'ownershipMarkerContents', at the root of the
-- output; an existing non-empty output directory is replaced only if it
-- carries this file, byte for byte. It is the only non-page, non-asset file
-- in the output (a static host deploy should exclude it).
ownershipMarker :: FilePath
ownershipMarker = ".personal-site-output"

ownershipMarkerContents :: BS.ByteString
ownershipMarkerContents =
  "personal-site generated output, format 1\n\
  \This directory is managed by `site build`, which replaces its entire contents.\n\
  \Do not keep other files here.\n"

-- | Refuse output directories whose replacement could destroy anything the
-- generator does not own:
--
-- * the source tree or any directory containing it, or anything inside
--   @assets/@;
-- * an existing file;
-- * an existing non-empty directory without a valid ownership marker (a
--   regular file, not a symlink, with exactly the expected contents).
--
-- A missing or empty output directory is always accepted.
checkOutputDirectory :: FilePath -> FilePath -> IO ()
checkOutputDirectory src out = do
  srcCanonical <- Dir.canonicalizePath src
  outCanonical <- Dir.canonicalizePath out
  when (srcCanonical `isWithin` outCanonical) $
    throwIO (UnsafeOutputDirectory out "it contains the source tree")
  when (outCanonical `isWithin` (srcCanonical </> "assets")) $
    throwIO (UnsafeOutputDirectory out "it is inside the assets directory")
  isFile <- Dir.doesFileExist out
  when isFile $ throwIO (UnsafeOutputDirectory out "it is a file")
  isDir <- Dir.doesDirectoryExist out
  when isDir $ do
    entries <- Dir.listDirectory out
    unless (null entries) $ do
      problem <- markerProblem (out </> ownershipMarker)
      forM_ problem $ \why ->
        throwIO . UnsafeOutputDirectory out $
          "it is not empty and is not a directory this generator manages (" <> why
            <> "). Use an empty or new directory, or remove this one yourself"

-- | Why a path is not a valid ownership marker, if it is not.
markerProblem :: FilePath -> IO (Maybe String)
markerProblem path = do
  exists <- Dir.doesPathExist path
  if not exists
    then pure (Just ("no " <> ownershipMarker <> " marker"))
    else do
      isLink <- Dir.pathIsSymbolicLink path
      isFile <- Dir.doesFileExist path
      if isLink || not isFile
        then pure (Just (ownershipMarker <> " is not a regular file"))
        else do
          size <- Dir.getFileSize path
          contents <-
            if size == fromIntegral (BS.length ownershipMarkerContents)
              then BS.readFile path
              else pure BS.empty
          pure $
            if contents == ownershipMarkerContents
              then Nothing
              else Just (ownershipMarker <> " has unexpected contents")

-- | Swap the children of @staging@ into @outDir@, parking the previous
-- children in @backup@ until the swap completes. The rename function is a
-- parameter only so tests can inject a failure; the build passes
-- 'Dir.renamePath'. Rollback always uses 'Dir.renamePath'.
promoteWith :: (FilePath -> FilePath -> IO ()) -> FilePath -> FilePath -> FilePath -> IO ()
promoteWith rename staging backup outDir = do
  Dir.createDirectoryIfMissing True outDir
  Dir.createDirectory backup
  old <- sort <$> Dir.listDirectory outDir
  new <- sort <$> Dir.listDirectory staging
  parked <- newIORef []
  placed <- newIORef []
  result <- try $ do
    forM_ old $ \entry -> do
      rename (outDir </> entry) (backup </> entry)
      modifyIORef' parked (entry :)
    forM_ new $ \entry -> do
      rename (staging </> entry) (outDir </> entry)
      modifyIORef' placed (entry :)
  case result of
    Right () -> do
      Dir.removePathForcibly backup
      Dir.removePathForcibly staging
    Left (failure :: SomeException) -> do
      rolledBack <- try $ do
        readIORef placed >>= mapM_ (\entry -> Dir.removePathForcibly (outDir </> entry))
        readIORef parked >>= mapM_ (\entry -> Dir.renamePath (backup </> entry) (outDir </> entry))
        Dir.removeDirectory backup
      Dir.removePathForcibly staging
      case rolledBack of
        Left (rollbackFailure :: SomeException) -> throwIO (RollbackFailed backup (show rollbackFailure))
        Right () -> throwIO (PromotionFailed (show failure))

-- | Every regular file under a directory, relative to it, sorted.
listFilesRecursive :: FilePath -> IO [FilePath]
listFilesRecursive root = sort <$> go ""
  where
    go rel = do
      entries <- Dir.listDirectory (root </> rel)
      fmap concat . forM entries $ \entry -> do
        let relEntry = if null rel then entry else rel </> entry
        isDir <- Dir.doesDirectoryExist (root </> relEntry)
        if isDir then go relEntry else pure [relEntry]

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

resolvesToListedAsset :: [Asset] -> Asset -> T.Text -> Bool
resolvesToListedAsset assets css ref =
  case collapse (splitDirectories (takeDirectory (assetPath css) </> T.unpack ref)) of
    Nothing -> False
    Just parts -> joinPath parts `elem` map assetPath assets
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
      | p == "/" = Nothing
      | otherwise = go (p : acc) ps
