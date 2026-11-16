{-# LANGUAGE DataKinds #-}

-- | The shared page shell: document, head, header navigation and footer.
--
-- Every page is rendered through 'renderPage'; pages supply only their
-- metadata and the contents of @<main>@ (see "Site.Page").
module Site.Layout
  ( renderPage
  , pageDocument
  , NavItem (..)
  , NavTarget (..)
  , navItems
  , footerLinks
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
import Site.Routes (Route (..), contactId, mainId, routeFragmentUrl, routeUrl)
import Site.Settings (Settings (..), canonicalUrl, contactDisplay, contactHref, contactLabel, contacts)

renderPage :: SiteConfig -> Page -> LBS.ByteString
renderPage config = renderLazyHTML . pageDocument config

pageDocument :: SiteConfig -> Page -> E.HTML
pageDocument config page =
  E.html [ A.lang (Just (siteLanguage config)) ]
    [ E.head [] (headContent config page)
    , E.body [ A.class_ "page" ]
        [ E.a [ A.class_ "skip-link", A.href mainId ] [ E.text "Skip to content" ]
        , siteHeader config (pageRoute page)
        , E.main (A.id mainId : layoutAttributes (pageLayout page)) (pageMain page)
        , siteFooter config (pageRoute page)
        ]
    ]

layoutAttributes :: Layout -> [A.Attribute E.Main]
layoutAttributes layout =
  case layout of
    Stage -> []
    Interior -> [ A.class_ "interior" ]
    Dossier -> [ A.class_ "interior interior--dossier" ]

--------------------------------------------------------------------------------
-- Head

-- | The document head: title, description, canonical URL and social
-- metadata (README "Metadata and discovery").
--
-- * The canonical URL and @og:url@ are the page's production URL, from
--   the configured origin ("Site.Settings").
-- * Open Graph and Twitter use the page's own title and description.
-- * No preview image is declared: no approved social artwork exists yet,
--   and a generic placeholder would misrepresent the work. The Twitter
--   card is therefore the plain @summary@ card.
-- * The 404 document has no canonical URL and asks not to be indexed: a
--   static host serves it at arbitrary paths.
headContent :: SiteConfig -> Page -> [E.ChildHTML E.Head E.Html]
headContent config page =
  [ Safe.meta Safe.Charset
  , E.meta [ A.name HTML.Viewport, A.content "width=device-width, initial-scale=1" ]
  , E.title [] [ E.text (pageTitle page) ]
  , E.meta [ A.name HTML.Description, A.content (pageDescription page) ]
  ]
    <> indexing
    <> [ Safe.meta . Safe.Name . Safe.ColorScheme . Safe.Palettes $ NEL.singleton Safe.Dark
       , property "og:site_name" (siteName config)
       , property "og:type" ogType
       , property "og:title" (pageTitle page)
       , property "og:description" (pageDescription page)
       , property "og:locale" "en_US"
       ]
    <> [ property "og:url" url | indexable ]
    <> [ E.meta [ A.customAttribute "name" "twitter:card", A.content "summary" ]
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
  where
    route = pageRoute page
    indexable = route /= NotFound
    url = canonicalUrl (siteSettings config) route
    indexing
      | indexable = [ E.link [ A.rel HTML.Rel_Canonical, A.href (B.mkRawURL url) ] ]
      | otherwise = [ E.meta [ A.name HTML.Robots, A.content "noindex" ] ]
    ogType =
      case route of
        WritingArticle _ -> "article"
        _ -> "website"
    property name value = E.meta [ A.customAttribute "property" name, A.content value ]

--------------------------------------------------------------------------------
-- Header

-- | Where a navigation link leads.
data NavTarget
  = ToRoute Route
    -- ^ A generated page.
  | ToSection Route B.Id
    -- ^ An element on a generated page (e.g. @/#contact@).
  | ToDocument B.RawURL
    -- ^ A published file that is not a page (the résumé PDF).

-- | One primary-navigation destination. Every one is a generated route, an
-- element on one, or a published file, so navigation never depends on the
-- current page.
data NavItem =
  NavItem
    { navLabel :: T.Text
    , navTarget :: NavTarget
    , navNote :: Maybe T.Text
      -- ^ Extra words for assistive technology, e.g. @"(PDF)"@.
    }

-- | The two link groups either side of the monogram medallion:
--
-- > Home  Work  [Writing]   (monogram)   About  [Résumé]  Contact
--
-- Writing appears only when published writing exists, and Résumé only
-- when a résumé PDF is published, so the navigation never links to an
-- empty section or a missing file.
navItems :: SiteConfig -> ([NavItem], [NavItem])
navItems config =
  ( [ NavItem "Home" (ToRoute Home) Nothing
    , NavItem "Work" (ToRoute WorkIndex) Nothing
    ]
      <> [ NavItem "Writing" (ToRoute WritingIndex) Nothing | siteHasWriting config ]
  , [ NavItem "About" (ToRoute About) Nothing ]
      <> [ NavItem "Résumé" (ToDocument url) (Just "(PDF)") | Just url <- [siteResumeUrl config] ]
      <> [ NavItem "Contact" (ToSection Home contactId) Nothing ]
  )

siteHeader :: SiteConfig -> Route -> E.ChildHTML E.Body grandparent
siteHeader config current =
  E.header [ A.class_ "site-header" ]
    [ E.nav [ A.class_ "site-nav", A.aria_label "Primary" ]
        [ E.ul [ A.class_ "site-nav__list site-nav__list--start" ] (map (navLink "site-nav__item" "site-nav__link" current) start)
        , -- The monogram: the site's single personal signature.
          E.a [ A.class_ "site-nav__mark", A.href (routeUrl Home), A.aria_label "Tyler Baum — home" ]
            [ decorativeImage "site-nav__mark-img" Asset.monogramSimple 66 42 ]
        , E.ul [ A.class_ "site-nav__list site-nav__list--end" ] (map (navLink "site-nav__item" "site-nav__link" current) end)
        ]
    ]
  where
    (start, end) = navItems config

-- | A navigation link. Only a page link can be the current page: Contact
-- is a section of the homepage, so on the homepage Home alone is current.
navLink :: HTML.Class -> HTML.Class -> Route -> NavItem -> E.ChildHTML E.UnorderedList grandparent
navLink itemClass linkClass current item =
  E.li [ A.class_ itemClass ]
    [ E.a ( [ A.class_ linkClass, A.href target ]
            <> [ A.aria_current HTML.CurrentPage | isCurrent ]
          )
        ( E.text (navLabel item)
            : [ E.span [ A.class_ "visually-hidden" ] [ E.text (" " <> note) ] | Just note <- [navNote item] ]
        )
    ]
  where
    (target, isCurrent) =
      case navTarget item of
        ToRoute route -> (routeUrl route, route == current)
        ToSection route fragment -> (routeFragmentUrl route fragment, False)
        ToDocument url -> (url, False)

--------------------------------------------------------------------------------
-- Footer

-- | The footer's site links: the content destinations, without Home (the
-- monogram and the name lead there) or Contact (the footer lists the
-- destinations themselves).
footerLinks :: SiteConfig -> [NavItem]
footerLinks config =
  [ NavItem "Work" (ToRoute WorkIndex) Nothing ]
    <> [ NavItem "Writing" (ToRoute WritingIndex) Nothing | siteHasWriting config ]
    <> [ NavItem "About" (ToRoute About) Nothing ]
    <> [ NavItem "Résumé" (ToDocument url) (Just "(PDF)") | Just url <- [siteResumeUrl config] ]

-- | The site footer: identity, site links, contact destinations, and the
-- copyright and colophon line. One ornament (a ruled diamond); no
-- monogram and no tree emblem.
--
-- The contact column is left out on the homepage, whose Contact section
-- sits directly above the footer with the same destinations: the same
-- links twice in a row would be redundant.
siteFooter :: SiteConfig -> Route -> E.ChildHTML E.Body grandparent
siteFooter config current =
  E.footer [ A.class_ "site-footer" ]
    [ E.div [ A.class_ "site-footer__ornament", A.aria_hidden True ] []
    , E.div [ A.class_ "site-footer__inner" ]
        ( [ E.div [ A.class_ "site-footer__identity" ]
              [ E.p [ A.class_ "site-footer__name" ] [ E.text (settingsName settings) ]
              , E.p [ A.class_ "site-footer__thesis" ] [ E.text (settingsThesis settings) ]
              ]
          , E.nav [ A.class_ "site-footer__nav", A.aria_label "Footer" ]
              [ E.p [ A.class_ "site-footer__heading" ] [ E.text "Site" ]
              , E.ul [ A.class_ "site-footer__links" ] (map (navLink "site-footer__item" "site-footer__link" current) (footerLinks config))
              ]
          ]
            <> [ E.div [ A.class_ "site-footer__contact" ]
                   [ E.p [ A.class_ "site-footer__heading" ] [ E.text "Contact" ]
                   , E.ul [ A.class_ "site-footer__links" ]
                       [ E.li [ A.class_ "site-footer__item" ]
                           [ E.a [ A.class_ "site-footer__link", A.href (B.mkRawURL (contactHref c)) ]
                               [ E.text (contactLabel c)
                               , E.span [ A.class_ "visually-hidden" ] [ E.text (": " <> contactDisplay c) ]
                               ]
                           ]
                       | c <- destinations
                       ]
                   ]
               | current /= Home, not (null destinations)
               ]
        )
    , E.div [ A.class_ "site-footer__base" ]
        [ E.p [ A.class_ "site-footer__copyright" ]
            [ E.text ("© " <> settingsCopyrightYears settings <> " " <> settingsName settings) ]
        , E.p [ A.class_ "site-footer__colophon" ] [ E.text "Built with Haskell & Brigid." ]
        ]
    ]
  where
    settings = siteSettings config
    destinations = contacts settings
