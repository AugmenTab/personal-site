-- | Site-wide settings: the production origin, the owner's identity line,
-- and the verified contact destinations (README "Site configuration").
--
-- This is the one place these values live. Templates never spell out the
-- domain, the name or a contact URL themselves; they ask this module. The
-- settings are checked by 'settingsProblems' before every check and build,
-- so a malformed origin or contact fails the build instead of shipping.
--
-- Contact destinations are owner-verified facts. A destination that has not
-- been supplied is simply absent: nothing here guesses an address.
module Site.Settings
  ( -- * Settings
    Settings (..)
  , ownerSettings
  , settingsProblems
    -- * Origin and canonical URLs
  , canonicalUrl
  , absoluteUrl
    -- * Contact destinations
  , Contact (..)
  , contacts
  , contactLabel
  , contactKind
  , contactDisplay
  , contactHref
  , contactKey
  ) where

import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Function (on)
import Data.List (groupBy, sortOn)
import Data.Text qualified as T

import Site.Routes (Route, routePath)

data Settings =
  Settings
    { settingsOrigin :: T.Text
      -- ^ The production origin, e.g. @https://tylerbaum.dev@: scheme and
      -- host only, no trailing slash. Canonical URLs, Open Graph URLs, the
      -- sitemap and robots.txt are all built from it.
    , settingsName :: T.Text
      -- ^ The owner's name: page titles, the footer and the copyright line.
    , settingsThesis :: T.Text
      -- ^ The one-line thesis, shown under the name in the hero and the
      -- footer.
    , settingsCopyrightYears :: T.Text
      -- ^ The copyright line's year or range, e.g. @2026@ or @2026–2027@.
      -- A fixed value, never the build's clock, so builds stay
      -- byte-for-byte reproducible. Update it by hand in January.
    , settingsContacts :: [Contact]
      -- ^ Verified contact destinations. Each kind at most once; they are
      -- always shown in the order GitHub, LinkedIn, Email.
    }

-- | The site's settings.
--
-- To add a contact destination once it is verified, add it to the list,
-- e.g. @LinkedIn "your-profile-slug"@ or @Email "name\@example.com"@ (the
-- address must already receive mail). See README "Site configuration".
ownerSettings :: Settings
ownerSettings =
  Settings
    { settingsOrigin = "https://tylerbaum.dev"
    , settingsName = "Tyler Baum"
    , settingsThesis = "Building precise systems for ambitious ideas."
    , settingsCopyrightYears = "2026"
    , settingsContacts =
        [ GitHub "AugmenTab"
        ]
    }

-- | A verified way to reach the owner. Each constructor holds only the
-- part that varies; the URL scheme and host are fixed here, so a contact
-- can never point anywhere unexpected.
data Contact
  = GitHub T.Text
    -- ^ A GitHub username: @https://github.com/{name}@.
  | LinkedIn T.Text
    -- ^ A LinkedIn public profile id: @https://www.linkedin.com/in/{id}/@.
  | Email T.Text
    -- ^ An address that receives mail: @mailto:{address}@.
  deriving (Eq, Show)

-- | The configured contacts in display order: GitHub, LinkedIn, Email.
contacts :: Settings -> [Contact]
contacts = sortOn contactKey . settingsContacts

-- | The fixed display order (and identity for duplicate checks).
contactKey :: Contact -> Int
contactKey contact =
  case contact of
    GitHub _ -> 0
    LinkedIn _ -> 1
    Email _ -> 2

contactLabel :: Contact -> T.Text
contactLabel contact =
  case contact of
    GitHub _ -> "GitHub"
    LinkedIn _ -> "LinkedIn"
    Email _ -> "Email"

-- | A stable lowercase name for the destination's kind, used for its icon
-- class (@contact__icon--github@).
contactKind :: Contact -> T.Text
contactKind contact =
  case contact of
    GitHub _ -> "github"
    LinkedIn _ -> "linkedin"
    Email _ -> "email"

-- | The destination written out, e.g. @github.com/AugmenTab@.
contactDisplay :: Contact -> T.Text
contactDisplay contact =
  case contact of
    GitHub name -> "github.com/" <> name
    LinkedIn profile -> "linkedin.com/in/" <> profile
    Email address -> address

-- | The link target.
contactHref :: Contact -> T.Text
contactHref contact =
  case contact of
    GitHub name -> "https://github.com/" <> name
    LinkedIn profile -> "https://www.linkedin.com/in/" <> profile <> "/"
    Email address -> "mailto:" <> address

-- | The absolute production URL of a route, e.g.
-- @https://tylerbaum.dev/work/brigid/@.
canonicalUrl :: Settings -> Route -> T.Text
canonicalUrl settings route = absoluteUrl settings (routePath route)

-- | The absolute production URL of a root-absolute path.
absoluteUrl :: Settings -> T.Text -> T.Text
absoluteUrl settings path = settingsOrigin settings <> path

-- | Everything wrong with the settings; empty when they are usable.
settingsProblems :: Settings -> [String]
settingsProblems settings =
  originProblems (settingsOrigin settings)
    <> [ "settingsName must not be empty" | T.null (T.strip (settingsName settings)) ]
    <> [ "settingsThesis must not be empty" | T.null (T.strip (settingsThesis settings)) ]
    <> yearProblems (settingsCopyrightYears settings)
    <> concatMap contactProblems (settingsContacts settings)
    <> [ "settingsContacts lists " <> T.unpack (contactLabel c) <> " more than once"
       | c : _ : _ <- groupBy ((==) `on` contactKey) (sortOn contactKey (settingsContacts settings)) ]

originProblems :: T.Text -> [String]
originProblems origin =
  case T.stripPrefix "https://" origin of
    Nothing -> [ "settingsOrigin " <> show origin <> " must start with https://" ]
    Just host
      | T.null host -> [ "settingsOrigin has no host" ]
      | not (T.all hostChar host) ->
          [ "settingsOrigin " <> show origin <> " must be a scheme and host only (no path, port, query or trailing slash)" ]
      | any T.null (T.splitOn "." host) || length (T.splitOn "." host) < 2 ->
          [ "settingsOrigin " <> show origin <> " is not a valid host name" ]
      | otherwise -> []
  where
    hostChar c = isAsciiLower c || isDigit c || c == '-' || c == '.'

yearProblems :: T.Text -> [String]
yearProblems years =
  case T.splitOn "–" years of
    [y] | isYear y -> []
    [a, b] | isYear a, isYear b, a < b -> []
    _ -> [ "settingsCopyrightYears " <> show years <> " must be a year (2026) or a range (2026–2027, with an en dash)" ]
  where
    isYear y = T.length y == 4 && T.all isDigit y

contactProblems :: Contact -> [String]
contactProblems contact =
  case contact of
    GitHub name
      | T.null name || T.length name > 39 || not (T.all (\c -> asciiAlphaNum c || c == '-') name)
          || "-" `T.isPrefixOf` name || "-" `T.isSuffixOf` name ->
          [ "GitHub username " <> show name <> " is not valid (1–39 letters, digits or inner hyphens)" ]
      | otherwise -> []
    LinkedIn profile
      | T.length profile < 3 || T.length profile > 100 || not (T.all (\c -> asciiAlphaNum c || c == '-') profile) ->
          [ "LinkedIn profile id " <> show profile <> " is not valid (3–100 letters, digits or hyphens; the part after linkedin.com/in/)" ]
      | otherwise -> []
    Email address ->
      case T.splitOn "@" address of
        [local, domain]
          | not (T.null local), T.length address <= 254
          , T.all (\c -> asciiAlphaNum c || c `elem` ("._+-" :: String)) local
          , not ("." `T.isPrefixOf` local), not ("." `T.isSuffixOf` local), not (".." `T.isInfixOf` local)
          , labels <- T.splitOn "." domain, length labels >= 2
          , all (\l -> not (T.null l) && T.all (\c -> isAsciiLower c || isDigit c || c == '-') l) labels ->
              []
        _ -> [ "Email address " <> show address <> " is not a plain address such as name@example.com (lowercase domain, no display name or query)" ]
  where
    asciiAlphaNum c = isAsciiLower c || isAsciiUpper c || isDigit c
