{-# LANGUAGE DataKinds #-}

-- | The static @404.html@ document. The host decides the HTTP status; this
-- is the body it serves. All its URLs are root-absolute, so it renders
-- correctly at whatever path it is served from.
module Site.Pages.NotFound
  ( page
  ) where

import Data.List.NonEmpty qualified as NEL

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E

import Site.Components (pageHeading)
import Site.Page (Layout (..), Page (..), SiteConfig, sectionTitle)
import Site.Routes (Route (Home, NotFound), elementId, routeUrl)

page :: SiteConfig -> Page
page config =
  Page
    { pageRoute = NotFound
    , pageTitle = sectionTitle config "Page not found"
    , pageDescription = "The requested page could not be found."
    , pageLayout = Interior
    , pageMain =
        [ E.section [ A.class_ "not-found", A.aria_labelledby (NEL.singleton titleId) ]
            [ pageHeading [] titleId "Page not found"
            , E.p [ A.class_ "page-lede" ]
                [ E.text "There is nothing at this address. The page may have moved, or the link may be mistyped." ]
            , E.p [ A.class_ "not-found__action" ]
                [ E.a [ A.class_ "button button--primary", A.href (routeUrl Home) ]
                    [ E.span [ A.class_ "button__label" ] [ E.text "Return to the homepage" ] ]
                ]
            ]
        ]
    }
  where
    titleId = elementId "not-found-title"
