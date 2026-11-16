-- | The site: every page and file, derived from the loaded content.
--
-- Publication filtering happens here and only here. Draft projects and
-- articles produce no route, card, navigation entry or media file. The
-- writing section exists only when at least one article is published.
-- Fixed pages (home, about, 404) and the asset list are explicit.
module Site.Definition
  ( siteFrom
  , siteConfiguration
  ) where

import Ogma qualified

import Site.Assets (allAssets)
import Site.Content.Types
import Site.Page (Site (..), SiteConfig (..))
import Site.Pages.About qualified as About
import Site.Pages.Home qualified as Home
import Site.Pages.NotFound qualified as NotFound
import Site.Pages.Work qualified as Work
import Site.Pages.Writing qualified as Writing

siteConfiguration :: Content -> SiteConfig
siteConfiguration content =
  SiteConfig
    { siteName = "Tyler Baum"
    , siteLanguage = Ogma.simpleBCP_47 Ogma.English
    , siteHasWriting = not (null (publishedArticles content))
    }

siteFrom :: Content -> Site
siteFrom content =
  Site
    { siteConfig = config
    , sitePages =
        [ Home.page config (Home.homeContent content)
        , Work.indexPage config projects
        ]
          <> map (Work.projectPage config) projects
          <> writingPages
          <> [ About.page config
             , NotFound.page config
             ]
    , siteAssets = allAssets
    , siteMedia = concatMap projectMedia projects <> concatMap articleMedia articles
    , siteWarnings = contentWarnings content
    }
  where
    config = siteConfiguration content
    projects = publishedProjects content
    articles = publishedArticles content
    writingPages
      | null articles = []
      | otherwise = Writing.indexPage config articles : map (Writing.articlePage config) articles
