-- | The explicit list of static files the site needs.
--
-- Every file shipped to @dist/assets/@ is named here. Pages refer to assets
-- only through these values, and the build refuses to run if any listed file
-- is missing, unsafe, or resolves outside @assets/@, or if a stylesheet
-- references a file that is not listed (see "Site.Build").
module Site.Assets
  ( Asset
  , mkAsset
  , assetPath
  , assetUrl
  , assetOutput
  , allAssets
    -- * Assets referenced from the HTML
  , stylesheet
  , favicon
  , monogramSimple
  , displayFont
  , heroPlateLeft
  , heroPlateCentre
  , heroPlateRight
  , aboutTree
  , blackEmblem
  , workFilterScript
  ) where

import Data.Text qualified as T

import Brigid.Types qualified as B

import Site.Path (OutputPath, PathError, mkOutputPath)

-- | A file under the source @assets/@ directory, identified by its path
-- relative to that directory (always with forward slashes). The path is
-- validated by 'assetOutput' when the manifest is built, before any file is
-- read or written.
newtype Asset = Asset FilePath
  deriving (Eq, Ord, Show)

-- | Name an asset. Unvalidated: the build rejects unsafe paths (see
-- 'assetOutput') before touching the filesystem.
mkAsset :: FilePath -> Asset
mkAsset = Asset

assetPath :: Asset -> FilePath
assetPath (Asset path) = path

-- | Root-absolute URL of the asset in the generated site (see "Site.Routes"
-- for why URLs are root-absolute).
assetUrl :: Asset -> B.RawURL
assetUrl asset = B.mkRawURL (T.pack ("/assets/" <> assetPath asset))

-- | Where the asset is written, relative to the output root. The same
-- validation also guards the source side: a path that is a valid output path
-- cannot climb out of @assets/@ either.
assetOutput :: Asset -> Either PathError OutputPath
assetOutput asset = mkOutputPath ("assets/" <> assetPath asset)

stylesheet, favicon, monogramSimple, displayFont :: Asset
stylesheet = Asset "styles/site.css"
favicon = Asset "brand/favicon.svg"
monogramSimple = Asset "brand/monogram-simple.svg"
displayFont = Asset "fonts/cinzel-latin-400-normal.woff2"

-- | Hero plates reconstructed from the owner's approved render by
-- @tools/art/reconstruct.py@, and the About emblem prepared by
-- @tools/art/emblem.py@ (committed source assets; the site build only
-- copies them).
heroPlateLeft, heroPlateCentre, heroPlateRight, aboutTree :: Asset
heroPlateLeft = Asset "images/hero-plate-left.webp"
heroPlateCentre = Asset "images/hero-plate-centre.webp"
heroPlateRight = Asset "images/hero-plate-right.webp"
aboutTree = Asset "images/about-tree.webp"

-- | Project art is not here: it is content media, kept in the project's
-- directory under @content/projects/@ and published only with the project.
blackEmblem :: Asset
blackEmblem = Asset "images/black-emblem.svg"

-- | The Work index's search and filter enhancement (Phase 05): the site's
-- only script, loaded only on @/work/@. The page is complete without it.
workFilterScript :: Asset
workFilterScript = Asset "scripts/work-filter.js"

-- | Everything copied into @dist/assets/@, including files referenced only
-- from CSS (fonts, textures, ornaments) and the font licences, which must
-- travel with the font files.
allAssets :: [Asset]
allAssets =
  [ stylesheet
  , favicon
  , monogramSimple
  , Asset "brand/monogram-ornate.svg"
  , heroPlateLeft
  , heroPlateCentre
  , heroPlateRight
  , aboutTree
  , blackEmblem
  , workFilterScript
  , Asset "images/texture-grain.svg"
  , Asset "images/ornament-corner.svg"
  , Asset "images/ornament-rule.svg"
  , Asset "images/ornament-frame.svg"
  , displayFont
  , Asset "fonts/cinzel-latin-600-normal.woff2"
  , Asset "fonts/eb-garamond-latin-400-normal.woff2"
  , Asset "fonts/eb-garamond-latin-400-italic.woff2"
  , Asset "fonts/eb-garamond-latin-500-normal.woff2"
  , Asset "fonts/jetbrains-mono-latin-400-normal.woff2"
  , Asset "fonts/OFL-cinzel.txt"
  , Asset "fonts/OFL-eb-garamond.txt"
  , Asset "fonts/OFL-jetbrains-mono.txt"
  ]
