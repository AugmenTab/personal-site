-- | The generated-output manifest: every file the build will write, with
-- where it comes from. Built purely, before anything is rendered or copied.
--
-- 'mkManifest' rejects:
--
-- * route or asset paths that are not valid 'OutputPath's (traversal,
--   absolute paths, unsafe characters, non-canonical spellings);
-- * two outputs with the same path, compared case-insensitively, whether
--   page/page, asset/asset or page/asset;
-- * an output whose path is used as a directory by another output
--   (e.g. a file @work@ next to @work/index.html@).
module Site.Manifest
  ( Source (..)
  , Entry (..)
  , Manifest
  , ManifestError (..)
  , mkManifest
  , fromEntries
  , manifestEntries
  , manifestPages
  , manifestAssets
  , manifestMedia
  , lookupOutput
  , describeSource
  ) where

import Data.List (inits, intercalate, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text qualified as T
import System.FilePath ((</>))

import Site.Assets (Asset, assetOutput, assetPath)
import Site.Content.Types (MediaFile (..), mediaOutput)
import Site.Path (OutputPath, PathError, collisionKey, outputFilePath, outputText)
import Site.Routes (Route, routeOutput, routePath)

data Source
  = PageSource Route
  | AssetSource Asset
  | MediaSource MediaFile
    -- ^ A published content item's media file.
  deriving (Eq, Show)

data Entry =
  Entry
    { entryOutput :: OutputPath
    , entrySource :: Source
    }
  deriving (Eq, Show)

-- | Entries sorted by output path. Only constructed by 'fromEntries', so it
-- is always collision-free.
newtype Manifest = Manifest [Entry]
  deriving (Eq, Show)

data ManifestError
  = InvalidRouteOutput Route PathError
  | InvalidAssetPath Asset PathError
  | InvalidMediaPath MediaFile String
  | OutputCollision [Entry]
    -- ^ Outputs that would be the same file (case-insensitively).
  | FileUsedAsDirectory Entry Entry
    -- ^ The first entry's path is a directory prefix of the second's.
  deriving (Eq)

instance Show ManifestError where
  show err =
    case err of
      InvalidRouteOutput route pathErr ->
        "route " <> T.unpack (routePath route) <> " has an invalid output path: " <> show pathErr
      InvalidAssetPath asset pathErr ->
        "asset assets/" <> assetPath asset <> " has an invalid path: " <> show pathErr
      InvalidMediaPath m why ->
        "media " <> mediaRoot m </> outputFilePath (mediaPath m) <> " has an invalid output path: " <> why
      OutputCollision entries ->
        "output collision: " <> intercalate ", " (map describe entries)
          <> " would all be written to the same file"
      FileUsedAsDirectory file other ->
        "output conflict: " <> describe file <> " is a file, but " <> describe other
          <> " needs it to be a directory"
    where
      describe e = describeSource (entrySource e) <> " -> " <> outputText (entryOutput e)

describeSource :: Source -> String
describeSource source =
  case source of
    PageSource route -> "page " <> T.unpack (routePath route)
    AssetSource asset -> "asset assets/" <> assetPath asset
    MediaSource m -> "media " <> mediaRoot m </> outputFilePath (mediaPath m)

-- | The manifest for a set of page routes, assets and published media.
mkManifest :: [Route] -> [Asset] -> [MediaFile] -> Either [ManifestError] Manifest
mkManifest routes assets media =
  -- Report every problem at once: invalid paths, and collisions among the
  -- entries whose paths are valid.
  case (pathErrors, fromEntries entries) of
    ([], result) -> result
    (_, Left collisions) -> Left (pathErrors <> collisions)
    (_, Right _) -> Left pathErrors
  where
    pageResults = [ (route, routeOutput route) | route <- routes ]
    assetResults = [ (asset, assetOutput asset) | asset <- assets ]
    mediaResults = [ (m, mediaOutput (mediaOwner m) (mediaPath m)) | m <- media ]
    pathErrors =
      [ InvalidRouteOutput route e | (route, Left e) <- pageResults ]
        <> [ InvalidAssetPath asset e | (asset, Left e) <- assetResults ]
        <> [ InvalidMediaPath m e | (m, Left e) <- mediaResults ]
    entries =
      [ Entry path (PageSource route) | (route, Right path) <- pageResults ]
        <> [ Entry path (AssetSource asset) | (asset, Right path) <- assetResults ]
        <> [ Entry path (MediaSource m) | (m, Right path) <- mediaResults ]

-- | Check a list of entries for collisions and sort it into a manifest.
fromEntries :: [Entry] -> Either [ManifestError] Manifest
fromEntries entries =
  case collisions <> conflicts of
    [] -> Right (Manifest (sortOn entryOutput entries))
    errs -> Left errs
  where
    byKey = Map.fromListWith (flip (<>)) [ (collisionKey (entryOutput e), [e]) | e <- entries ]
    collisions = [ OutputCollision group | group <- Map.elems byKey, length group > 1 ]
    conflicts =
      [ FileUsedAsDirectory file e
      | e <- entries
      , prefix <- drop 1 (init (inits (collisionKey (entryOutput e))))
      , file : _ <- [Map.findWithDefault [] prefix byKey]
      ]

manifestEntries :: Manifest -> [Entry]
manifestEntries (Manifest entries) = entries

manifestPages :: Manifest -> [(Route, OutputPath)]
manifestPages = mapMaybe page . manifestEntries
  where
    page (Entry path (PageSource route)) = Just (route, path)
    page _ = Nothing

manifestAssets :: Manifest -> [(Asset, OutputPath)]
manifestAssets = mapMaybe asset . manifestEntries
  where
    asset (Entry path (AssetSource a)) = Just (a, path)
    asset _ = Nothing

manifestMedia :: Manifest -> [(MediaFile, OutputPath)]
manifestMedia = mapMaybe media . manifestEntries
  where
    media (Entry path (MediaSource m)) = Just (m, path)
    media _ = Nothing

-- | Exact (case-sensitive) lookup, as a static host on Linux resolves URLs.
lookupOutput :: OutputPath -> Manifest -> Maybe Entry
lookupOutput path (Manifest entries) =
  case filter ((== path) . entryOutput) entries of
    e : _ -> Just e
    [] -> Nothing
