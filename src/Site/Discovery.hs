-- | Site discovery files: @/sitemap.xml@ and @/robots.txt@ (README
-- "Metadata and discovery").
--
-- Both are derived from the site's actual routes and the configured origin
-- ("Site.Settings"). The sitemap lists every generated page except the 404
-- document, in path order, with no dates (so builds stay reproducible).
-- Draft content has no route, so it can never appear. robots.txt allows
-- everything and names the sitemap.
module Site.Discovery
  ( discoveryFiles
  , sitemapRoutes
  , sitemapXml
  , robotsTxt
  ) where

import Data.List (sortOn)
import Data.Text qualified as T

import Site.Page (GeneratedFile (..))
import Site.Routes (Route (NotFound), routePath)
import Site.Settings (Settings, absoluteUrl, canonicalUrl)

discoveryFiles :: Settings -> [Route] -> [GeneratedFile]
discoveryFiles settings routes =
  [ GeneratedFile "robots.txt" "robots.txt" (robotsTxt settings)
  , GeneratedFile "sitemap.xml" "sitemap" (sitemapXml settings routes)
  ]

-- | The routes a sitemap lists: every page but the 404 document, by path.
sitemapRoutes :: [Route] -> [Route]
sitemapRoutes = sortOn routePath . filter (/= NotFound)

sitemapXml :: Settings -> [Route] -> T.Text
sitemapXml settings routes =
  T.unlines $
    [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    , "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">"
    ]
      <> [ "  <url><loc>" <> escape (canonicalUrl settings route) <> "</loc></url>" | route <- sitemapRoutes routes ]
      <> [ "</urlset>" ]
  where
    -- Origins and slugs are validated to plain URL characters already; the
    -- escape keeps the document well formed regardless.
    escape = T.replace "<" "&lt;" . T.replace ">" "&gt;" . T.replace "&" "&amp;"

robotsTxt :: Settings -> T.Text
robotsTxt settings =
  T.unlines
    [ "User-agent: *"
    , "Allow: /"
    , ""
    , "Sitemap: " <> absoluteUrl settings "/sitemap.xml"
    ]
