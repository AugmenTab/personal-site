-- | The site's routes, and the single place URLs and output files are derived.
--
-- | Route                | URL               | Output file                 |
-- |----------------------|-------------------|-----------------------------|
-- | 'Home'               | @/@               | @index.html@                |
-- | 'WorkIndex'          | @/work/@          | @work/index.html@           |
-- | @'WorkDetail' slug@  | @/work/{slug}/@   | @work/{slug}/index.html@    |
-- | 'WritingIndex'       | @/writing/@       | @writing/index.html@        |
-- | @'WritingArticle' s@ | @/writing/{s}/@   | @writing/{s}/index.html@    |
-- | 'About'              | @/about/@         | @about/index.html@          |
-- | 'NotFound'           | @/404.html@       | @404.html@                  |
--
-- URLs are root-absolute so that the same markup works at any depth, and in
-- @404.html@, which a static host serves at arbitrary request paths. The site
-- therefore assumes it is served from the root of its origin.
module Site.Routes
  ( -- * Slugs
    Slug
  , RouteError (..)
  , mkSlug
  , slugText
    -- * Routes
  , Route (..)
  , routePath
  , routeUrl
  , routeFragmentUrl
  , routeOutput
  , urlPathOutput
    -- * Fragment identifiers
  , elementId
  , mainId
  ) where

import Data.Char (isAsciiLower, isDigit)
import Data.NonEmptyText qualified as NET
import Data.Text qualified as T

import Brigid.Types qualified as B

import Site.Path (OutputPath, PathError (..), mkOutputPath)

-- | A URL- and filesystem-safe identifier: lowercase ASCII letters and
-- digits in hyphen-separated words, at most 64 characters (e.g. @brigid@,
-- @black-compiler@). Spellings that a server or filesystem might treat as
-- equivalent (case, Unicode, trailing hyphens, dots) are rejected outright.
newtype Slug = Slug T.Text
  deriving (Eq, Ord)

instance Show Slug where
  show = show . slugText

data RouteError = InvalidSlug T.Text String
  deriving (Eq)

instance Show RouteError where
  show (InvalidSlug raw why) = "invalid slug " <> show (T.unpack raw) <> ": " <> why

mkSlug :: T.Text -> Either RouteError Slug
mkSlug raw
  | T.null raw = bad "empty"
  | T.length raw > 64 = bad "longer than 64 characters"
  | not (T.all allowed raw) = bad "only lowercase ASCII letters, digits and '-' are allowed"
  | any T.null (T.splitOn "-" raw) = bad "hyphens must separate words (no leading, trailing or doubled '-')"
  | otherwise = Right (Slug raw)
  where
    allowed c = isAsciiLower c || isDigit c || c == '-'
    bad = Left . InvalidSlug raw

slugText :: Slug -> T.Text
slugText (Slug t) = t

data Route
  = Home
  | WorkIndex
  | WorkDetail Slug
  | WritingIndex
    -- ^ Generated only when published writing exists.
  | WritingArticle Slug
  | About
  | NotFound
  deriving (Eq, Ord, Show)

-- | The root-absolute URL path of a route. Content slugs only ever appear
-- below @/work/@ or @/writing/@, so content can never claim a fixed route
-- such as @/about/@ or @/404.html@.
routePath :: Route -> T.Text
routePath route =
  case route of
    Home -> "/"
    WorkIndex -> "/work/"
    WorkDetail slug -> "/work/" <> slugText slug <> "/"
    WritingIndex -> "/writing/"
    WritingArticle slug -> "/writing/" <> slugText slug <> "/"
    About -> "/about/"
    NotFound -> "/404.html"

routeUrl :: Route -> B.RawURL
routeUrl = B.mkRawURL . routePath

-- | A link to an element on another page, e.g. @/about/#contact@.
routeFragmentUrl :: Route -> B.Id -> B.RawURL
routeFragmentUrl route (B.Id fragment) =
  B.mkRawURL (routePath route <> "#" <> NET.toText fragment)

-- | The file a route is written to. Derived from 'routePath' with the same
-- rule the link checker uses ('urlPathOutput'), so a route's URL and its file
-- cannot disagree.
routeOutput :: Route -> Either PathError OutputPath
routeOutput = urlPathOutput . routePath

-- | The output file a root-absolute URL path is served from: @/a/@ is
-- @a/index.html@ and @/a.html@ is itself. Relative URLs are rejected.
urlPathOutput :: T.Text -> Either PathError OutputPath
urlPathOutput urlPath =
  case T.stripPrefix "/" urlPath of
    Nothing -> Left (NotRootRelative (T.unpack urlPath))
    Just rest
      | T.null rest || "/" `T.isSuffixOf` rest -> mkOutputPath (T.unpack rest <> "index.html")
      | otherwise -> mkOutputPath (T.unpack rest)

-- | Element ids are compile-time constants; an empty one is a programming
-- error that the tests would surface immediately. The build's link checker
-- verifies that every @#fragment@ link names an id on its target page.
elementId :: T.Text -> B.Id
elementId txt =
  case NET.fromText txt of
    Just net -> B.Id net
    Nothing -> error "elementId: empty id"

-- | The @<main>@ landmark on every page (the skip link's target).
mainId :: B.Id
mainId = elementId "main"
