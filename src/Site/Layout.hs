{-# LANGUAGE DataKinds #-}

-- | The shared page shell: document, head, header navigation and footer.
--
-- Every page is rendered through 'renderPage'; pages supply only their
-- metadata and the contents of @<main>@ (see "Site.Page").
module Site.Layout
  ( renderPage
  , pageDocument
  , NavItem (..)
  , navItems
  ) where

import Data.ByteString.Lazy qualified as LBS
import Data.List.NonEmpty qualified as NEL
import Data.Text qualified as T

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Elements.Safe qualified as Safe
import Brigid.HTML.Render.ByteString (renderLazyHTML)
import Brigid.HTML.Types qualified as HTML
import Brigid.Types qualified as B

import Site.Assets qualified as Asset
import Site.Components (decorativeImage)
import Site.Page (Layout (..), Page (..), SiteConfig (..))
import Site.Pages.About (contactId)
import Site.Routes (Route (..), mainId, routeFragmentUrl, routeUrl)

renderPage :: SiteConfig -> Page -> LBS.ByteString
renderPage config = renderLazyHTML . pageDocument config

pageDocument :: SiteConfig -> Page -> E.HTML
pageDocument config page =
  E.html [ A.lang (Just (siteLanguage config)) ]
    [ E.head [] (headContent page)
    , E.body [ A.class_ "page" ]
        [ E.a [ A.class_ "skip-link", A.href mainId ] [ E.text "Skip to content" ]
        , siteHeader config (pageRoute page)
        , E.main (A.id mainId : layoutAttributes (pageLayout page)) (pageMain page)
        , siteFooter config
        ]
    ]

layoutAttributes :: Layout -> [A.Attribute E.Main]
layoutAttributes layout =
  case layout of
    Stage -> []
    Interior -> [ A.class_ "interior" ]

headContent :: Page -> [E.ChildHTML E.Head E.Html]
headContent page =
  [ Safe.meta Safe.Charset
  , E.meta [ A.name HTML.Viewport, A.content "width=device-width, initial-scale=1" ]
  , E.title [] [ E.text (pageTitle page) ]
  , E.meta [ A.name HTML.Description, A.content (pageDescription page) ]
  , Safe.meta . Safe.Name . Safe.ColorScheme . Safe.Palettes $ NEL.singleton Safe.Dark
  , E.link
      [ A.rel HTML.Rel_Icon
      , A.href (Asset.assetUrl Asset.favicon)
      , A.type_ (HTML.mkRawTypeOption "image/svg+xml")
      ]
  , E.link
      [ A.rel HTML.Rel_Stylesheet
      , A.href (Asset.assetUrl Asset.stylesheet)
      ]
  ]

--------------------------------------------------------------------------------
-- Header

-- | One primary-navigation destination. Every one is a generated route (or
-- an element on one), so navigation never depends on the current page.
data NavItem =
  NavItem
    { navLabel :: T.Text
    , navRoute :: Route
    , navFragment :: Maybe B.Id
    }

-- | The two link groups either side of the monogram medallion. Writing is
-- listed only when published writing exists, so the navigation never links
-- to an empty section.
navItems :: SiteConfig -> ([NavItem], [NavItem])
navItems config =
  ( [ NavItem "Home" Home Nothing
    , NavItem "Work" WorkIndex Nothing
    ]
      <> [ NavItem "Writing" WritingIndex Nothing | siteHasWriting config ]
  , [ NavItem "About" About Nothing
    , NavItem "Contact" About (Just contactId)
    ]
  )

siteHeader :: SiteConfig -> Route -> E.ChildHTML E.Body grandparent
siteHeader config current =
  E.header [ A.class_ "site-header" ]
    [ E.nav [ A.class_ "site-nav", A.aria_label "Primary" ]
        [ E.ul [ A.class_ "site-nav__list site-nav__list--start" ] (map (navLink current) start)
        , -- The monogram: the site's single personal signature.
          E.a [ A.class_ "site-nav__mark", A.href (routeUrl Home), A.aria_label "Tyler Baum — home" ]
            [ decorativeImage "site-nav__mark-img" Asset.monogramSimple 66 42 ]
        , E.ul [ A.class_ "site-nav__list site-nav__list--end" ] (map (navLink current) end)
        ]
    ]
  where
    (start, end) = navItems config

navLink :: Route -> NavItem -> E.ChildHTML E.UnorderedList grandparent
navLink current item =
  E.li [ A.class_ "site-nav__item" ]
    [ E.a ( [ A.class_ "site-nav__link", A.href target ]
            <> [ A.aria_current HTML.CurrentPage | isCurrent ]
          )
        [ E.text (navLabel item) ]
    ]
  where
    target = maybe (routeUrl (navRoute item)) (routeFragmentUrl (navRoute item)) (navFragment item)
    isCurrent = navRoute item == current && null (navFragment item)

--------------------------------------------------------------------------------
-- Footer

siteFooter :: SiteConfig -> E.ChildHTML E.Body grandparent
siteFooter config =
  E.footer [ A.class_ "site-footer" ]
    [ E.span [ A.class_ "site-footer__ornament", A.aria_hidden True ] []
    , E.p [] [ E.text (siteName config) ]
    ]
