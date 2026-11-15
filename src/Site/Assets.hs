-- | The explicit list of static files the page needs.
--
-- Every file shipped to @dist/assets/@ is named here. The page refers to
-- assets only through these values, and the build refuses to run if any
-- listed file is missing or if a stylesheet references a file that is not
-- listed (see "Site.Build").
module Site.Assets
  ( Asset
  , assetPath
  , assetUrl
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
  , cardBrigid
  , blackEmblem
  ) where

import Data.Text qualified as T

import Brigid.Types qualified as B

-- | A file under the source @assets/@ directory, identified by its path
-- relative to that directory (always with forward slashes).
newtype Asset = Asset FilePath
  deriving (Eq, Ord, Show)

assetPath :: Asset -> FilePath
assetPath (Asset path) = path

-- | Page-relative URL of the asset in the generated site.
assetUrl :: Asset -> B.RawURL
assetUrl asset = B.mkRawURL (T.pack ("assets/" <> assetPath asset))

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

cardBrigid, blackEmblem :: Asset
cardBrigid = Asset "images/card-brigid.svg"
blackEmblem = Asset "images/black-emblem.svg"

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
  , cardBrigid
  , blackEmblem
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
