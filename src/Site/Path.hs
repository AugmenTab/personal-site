-- | Validated, output-root-relative file paths.
--
-- Every file the build writes (pages and assets alike) is addressed by an
-- 'OutputPath'. One can only be made by 'mkOutputPath', which accepts a
-- single canonical spelling: forward-slash separated, relative, with no
-- empty, @.@ or @..@ segments and only a small safe character set. Paths are
-- rejected rather than normalised, so two different spellings can never
-- silently become the same file.
module Site.Path
  ( OutputPath
  , PathError (..)
  , mkOutputPath
  , outputSegments
  , outputText
  , outputFilePath
  , resolveUnder
  , collisionKey
  , isWithin
  ) where

import Data.Char (isAsciiLower, isAsciiUpper, isDigit, toLower)
import Data.List (intercalate, isPrefixOf)
import System.FilePath (joinPath, splitDirectories, (</>))

newtype OutputPath = OutputPath [String]
  deriving (Eq, Ord)

instance Show OutputPath where
  show = show . outputText

data PathError
  = EmptyPath
  | AbsolutePath String
  | NonCanonicalPath String
    -- ^ Empty segments, e.g. @a\/\/b@ or a trailing slash.
  | UnsafeSegment String String
    -- ^ The whole path and the offending segment (@..@, @.@, a hidden file,
    -- or characters outside @[A-Za-z0-9._-]@).
  | NotRootRelative String
    -- ^ An internal URL that does not start with @/@.
  deriving (Eq)

instance Show PathError where
  show err =
    case err of
      EmptyPath -> "empty path"
      AbsolutePath p -> show p <> " is absolute; output paths must be relative"
      NonCanonicalPath p -> show p <> " has an empty segment (doubled or trailing slash)"
      UnsafeSegment p s ->
        show p <> " contains the unsafe segment " <> show s
          <> " (allowed: letters, digits, '.', '_', '-'; no '.', '..' or leading dot)"
      NotRootRelative p -> show p <> " is a relative URL; internal links must start with '/'"

mkOutputPath :: String -> Either PathError OutputPath
mkOutputPath raw
  | null raw = Left EmptyPath
  | "/" `isPrefixOf` raw = Left (AbsolutePath raw)
  | any null segments = Left (NonCanonicalPath raw)
  | otherwise = OutputPath <$> traverse checkSegment segments
  where
    segments = splitOn '/' raw
    checkSegment s
      | s == "." || s == ".." = Left (UnsafeSegment raw s)
      | "." `isPrefixOf` s = Left (UnsafeSegment raw s)
      | not (all safeChar s) = Left (UnsafeSegment raw s)
      | otherwise = Right s
    safeChar c = isAsciiLower c || isAsciiUpper c || isDigit c || c `elem` ("._-" :: String)

outputSegments :: OutputPath -> [String]
outputSegments (OutputPath segs) = segs

-- | The path as written in URLs and diagnostics, e.g. @work/brigid/index.html@.
outputText :: OutputPath -> String
outputText (OutputPath segs) = intercalate "/" segs

-- | The path relative to the output root, with the platform separator.
outputFilePath :: OutputPath -> FilePath
outputFilePath (OutputPath segs) = joinPath segs

-- | The destination of an output path under a root directory. Because every
-- segment is validated, the result can never leave @root@.
resolveUnder :: FilePath -> OutputPath -> FilePath
resolveUnder root path = root </> outputFilePath path

-- | Case-folded segments. Two outputs with the same key would be the same
-- file on a case-insensitive filesystem (macOS, Windows), so the manifest
-- treats them as a collision.
collisionKey :: OutputPath -> [String]
collisionKey (OutputPath segs) = map (map toLower) segs

-- | @child `isWithin` parent@: segment-wise containment of two absolute,
-- canonicalised paths (a path is within itself).
isWithin :: FilePath -> FilePath -> Bool
isWithin child parent = splitDirectories parent `isPrefixOf` splitDirectories child

splitOn :: Char -> String -> [String]
splitOn sep s =
  case break (== sep) s of
    (chunk, []) -> [chunk]
    (chunk, _ : rest) -> chunk : splitOn sep rest
