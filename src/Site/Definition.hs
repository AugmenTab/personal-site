-- | The site: every page and file, derived from the loaded content.
--
-- Publication filtering happens here and only here. Draft projects and
-- articles produce no route, card, navigation entry, sitemap entry or
-- media file. The writing section exists only when at least one article is
-- published; the résumé link only when @content/resume.pdf@ exists. Fixed
-- pages (home, about, 404), the asset list and the discovery files
-- (sitemap, robots.txt) are explicit.
module Site.Definition
  ( siteFrom
  , siteConfiguration
  ) where

import Ogma qualified

import Site.Assets (allAssets)
import Site.Content.Types
import Site.Discovery (discoveryFiles)
import Site.Page (Page (..), Site (..), SiteConfig (..))
import Site.Pages.About qualified as About
import Site.Pages.Home qualified as Home
import Site.Pages.NotFound qualified as NotFound
import Site.Pages.Work qualified as Work
import Site.Pages.Writing qualified as Writing
import Site.Settings (Settings (..), ownerSettings)

siteConfiguration :: Content -> SiteConfig
siteConfiguration content =
  SiteConfig
    { siteSettings = ownerSettings
    , siteName = settingsName ownerSettings
    , siteLanguage = Ogma.simpleBCP_47 Ogma.English
    , siteHasWriting = not (null (publishedArticles content))
    , siteResumeUrl = fmap (\m -> mediaUrl (mediaOwner m) (mediaPath m)) (contentResume content)
    }

siteFrom :: Content -> Site
siteFrom content =
  Site
    { siteConfig = config
    , sitePages = pages
    , siteAssets = allAssets
    , siteMedia =
        concatMap projectMedia projects <> concatMap articleMedia articles
          <> maybe [] pure (contentResume content)
    , siteGenerated = discoveryFiles ownerSettings (map pageRoute pages)
    , siteWarnings = contentWarnings content
    }
  where
    config = siteConfiguration content
    projects = publishedProjects content
    articles = publishedArticles content
    pages =
      [ Home.page config (Home.homeContent content)
      , Work.indexPage config projects
      ]
        <> map (Work.projectPage config) projects
        <> writingPages
        <> [ About.page config
           , NotFound.page config
           ]
    writingPages
      | null articles = []
      | otherwise = Writing.indexPage config articles : map (Writing.articlePage config) articles
