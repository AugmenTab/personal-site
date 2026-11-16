-- | The small vocabulary the generator works in: site-wide settings, a page
-- (route, metadata and @<main>@ content), generated text files, and the
-- site as a whole.
module Site.Page
  ( SiteConfig (..)
  , Page (..)
  , Layout (..)
  , GeneratedFile (..)
  , Site (..)
  , sectionTitle
  ) where

import Data.Text qualified as T
import Ogma qualified

import Brigid.HTML.Elements qualified as E
import Brigid.Types qualified as B

import Site.Assets (Asset)
import Site.Content.Types (MediaFile)
import Site.Routes (Route)
import Site.Settings (Settings)

data SiteConfig =
  SiteConfig
    { siteSettings :: Settings
      -- ^ Origin, identity and verified contacts ("Site.Settings").
    , siteName :: T.Text
      -- ^ Used in page titles and the footer.
    , siteLanguage :: Ogma.BCP_47
    , siteHasWriting :: Bool
      -- ^ Whether published writing exists; only then does the navigation
      -- link to it.
    , siteResumeUrl :: Maybe B.RawURL
      -- ^ The published résumé PDF, when one exists; only then do the
      -- navigation and footer link to it.
    }

-- | How the shell frames a page's @<main>@.
data Layout
  = Stage
    -- ^ The homepage: content starts under the header, over the hero art.
  | Interior
    -- ^ Every other page: content is pushed below the header.
  | Dossier
    -- ^ A project page with a hero: spaced as 'Interior' (the sidebar and
    -- the hero both start under the header), without the interior glow,
    -- since the artwork brings its own light.
  deriving (Eq, Show)

data Page =
  Page
    { pageRoute :: Route
    , pageTitle :: T.Text
      -- ^ The complete @<title>@ text (also the Open Graph title).
    , pageDescription :: T.Text
      -- ^ The @<meta name="description">@ text (also the Open Graph
      -- description).
    , pageLayout :: Layout
    , pageMain :: [E.ChildHTML E.Main E.Body]
      -- ^ Contents of @<main>@. Must contain the page's single @<h1>@.
    }

-- | A text file the build writes besides the pages (the sitemap and
-- robots.txt). Its contents are derived from the site, never hand-written
-- output.
data GeneratedFile =
  GeneratedFile
    { generatedPath :: FilePath
      -- ^ Relative to the output root, e.g. @sitemap.xml@.
    , generatedDescription :: T.Text
    , generatedContents :: T.Text
    }

data Site =
  Site
    { siteConfig :: SiteConfig
    , sitePages :: [Page]
    , siteAssets :: [Asset]
    , siteMedia :: [MediaFile]
      -- ^ Media of published content only; drafts' files are never listed.
    , siteGenerated :: [GeneratedFile]
    , siteWarnings :: [String]
      -- ^ Content problems that do not fail the build (see
      -- 'Site.Content.Types.contentWarnings').
    }

-- | A title of the form @"Work — Tyler Baum"@.
sectionTitle :: SiteConfig -> T.Text -> T.Text
sectionTitle config section = section <> " — " <> siteName config
