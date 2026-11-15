-- | The one check for reading a source file: assets, content metadata,
-- Markdown bodies and media all go through 'sourceFileProblem'.
--
-- The relative path is an 'OutputPath', so it is already canonical (no
-- @..@, no absolute path, no hidden files). This adds the filesystem side:
-- the file must exist, be a regular file, and resolve (following symlinks)
-- inside its permitted root.
module Site.Source
  ( SourceProblem (..)
  , sourceFileProblem
  , describeSourceProblem
  ) where

import System.Directory qualified as Dir
import System.FilePath ((</>))

import Site.Path (OutputPath, isWithin, outputFilePath)

data SourceProblem
  = SourceMissing
  | SourceNotRegularFile
  | SourceOutsideRoot FilePath
    -- ^ Where it actually resolves.
  deriving (Eq, Show)

-- | 'Nothing' if @root/path@ is a regular file that resolves inside @root@.
sourceFileProblem :: FilePath -> OutputPath -> IO (Maybe SourceProblem)
sourceFileProblem root path = do
  let file = root </> outputFilePath path
  exists <- Dir.doesPathExist file
  if not exists
    then pure (Just SourceMissing)
    else do
      isFile <- Dir.doesFileExist file
      if not isFile
        then pure (Just SourceNotRegularFile)
        else do
          rootCanonical <- Dir.canonicalizePath root
          resolved <- Dir.canonicalizePath file
          pure $
            if resolved `isWithin` rootCanonical && resolved /= rootCanonical
              then Nothing
              else Just (SourceOutsideRoot resolved)

describeSourceProblem :: SourceProblem -> String
describeSourceProblem problem =
  case problem of
    SourceMissing -> "does not exist"
    SourceNotRegularFile -> "is not a regular file"
    SourceOutsideRoot resolved -> "resolves to " <> resolved <> ", outside its permitted directory (symlink escape)"
