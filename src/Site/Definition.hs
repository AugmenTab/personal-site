-- | The site: every page and asset, listed explicitly.
--
-- To add a page in Phase 01: add a 'Route' constructor (and its URL in
-- 'Site.Routes.routePath'), write a @Site.Pages.*@ module returning a
-- 'Page', and list it here. The build rejects duplicate or colliding outputs
-- and links to anything that is not generated.
module Site.Definition
  ( site
  , siteConfiguration
  ) where

import Ogma qualified

import Site.Assets (allAssets)
import Site.Page (Site (..), SiteConfig (..))
import Site.Pages.About qualified as About
import Site.Pages.Home qualified as Home
import Site.Pages.NotFound qualified as NotFound
import Site.Pages.Work qualified as Work
import Site.Projects qualified as Projects
import Site.Routes (RouteError, mkSlug)

siteConfiguration :: SiteConfig
siteConfiguration =
  SiteConfig
    { siteName = "Tyler Baum"
    , siteLanguage = Ogma.simpleBCP_47 Ogma.English
    }

-- | 'Left' if a slug is invalid.
site :: Either RouteError Site
site = do
  brigid <- Projects.brigid <$> mkSlug "brigid"
  let config = siteConfiguration
      projects = [brigid]
  pure
    Site
      { siteConfig = config
      , sitePages =
          [ Home.page config projects
          , Work.indexPage config projects
          ]
            <> map (Work.projectPage config) projects
            <> [ About.page config
               , NotFound.page config
               ]
      , siteAssets = allAssets
      }
