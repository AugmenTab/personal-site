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
  , ContactCopy (..)
  , contactCopy
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
import Site.Page (CopyStatus (..), Layout (..), Page (..), SiteConfig (..))
import Site.Routes (Route (..), contactId, elementId, mainId, routeUrl)
import Site.Settings (Settings (..), canonicalUrl, contactDisplay, contactHref, contactKind, contactLabel, contacts)

renderPage :: SiteConfig -> Page -> LBS.ByteString
renderPage config = renderLazyHTML . pageDocument config

pageDocument :: SiteConfig -> Page -> E.HTML
pageDocument config page =
  E.html [ A.lang (Just (siteLanguage config)) ]
    [ E.head [] (headContent config page)
    , E.body [ A.class_ (if extended then "page page--nav-extended" else "page") ]
        [ E.a [ A.class_ "skip-link", A.href mainId ] [ E.text "Skip to content" ]
        , siteHeader config (pageRoute page)
        , E.main (A.id mainId : layoutAttributes (pageLayout page)) (pageMain page)
        , siteFooter config (pageRoute page)
        ]
    ]
  where
    -- More than four links (since post-Phase 07 update 1 Writing is always
    -- present, so every page has five, or six with a Resume): phones then
    -- stack each side's links on its own row (CSS), because five do not
    -- fit one row at 390px.
    extended = let (start, end) = navItems config in length start + length end > 4

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
    -- No font preloads (measured in Phase 06): preloading the two shared
    -- faces cut the font-swap layout shift slightly (CLS 0.031 -> 0.022 on
    -- the desktop homepage, already far under 0.1) but delayed first paint
    -- and LCP on a throttled phone by ~150-200 ms, because the preloads
    -- compete with the render-blocking stylesheet.
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
  | ToFragment B.Id
    -- ^ An element present on every page, linked as a same-page fragment
    -- (@#contact@: the shared footer's Contact section).
  | ToDocument B.RawURL
    -- ^ A published file that is not a page (the résumé PDF). It opens in
    -- a new tab, so the site stays where the reader left it.

-- | One primary-navigation destination. Every one is a generated route, an
-- element on every page, or a published file, so navigation never leads
-- to a missing target.
data NavItem =
  NavItem
    { navLabel :: T.Text
    , navTarget :: NavTarget
    , navNote :: Maybe T.Text
      -- ^ Extra words for assistive technology, e.g. @"(PDF, opens in a
      -- new tab)"@.
    }

-- | The two link groups either side of the monogram medallion:
--
-- > Home  Work  Writing   (monogram)   About  [Resume]  Contact
--
-- Writing is always present: its index exists even before any article is
-- published (a "Coming soon." page). Resume appears only when a résumé PDF
-- is published, so the navigation never links to a missing file; its
-- visible label is "Resume" (no accent). Contact jumps to the current
-- page's footer.
navItems :: SiteConfig -> ([NavItem], [NavItem])
navItems config =
  ( [ NavItem "Home" (ToRoute Home) Nothing
    , NavItem "Work" (ToRoute WorkIndex) Nothing
    , NavItem "Writing" (ToRoute WritingIndex) Nothing
    ]
  , [ NavItem "About" (ToRoute About) Nothing ]
      <> resumeItem config
      <> [ NavItem "Contact" (ToFragment contactId) Nothing ]
  )

-- | The résumé link, when a résumé PDF is published.
resumeItem :: SiteConfig -> [NavItem]
resumeItem config =
  [ NavItem "Resume" (ToDocument url) (Just resumeNote) | Just url <- [siteResumeUrl config] ]

-- | What assistive technology hears after "Resume".
resumeNote :: T.Text
resumeNote = "(PDF, opens in a new tab)"

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
-- is a section of every page's footer, so it is never current.
--
-- A document link (the résumé) opens in a new tab: @target="_blank"@ with
-- @rel="noopener noreferrer"@, so the new tab gets no handle on this one
-- and no referrer. Page and fragment links keep the default behaviour.
-- (Brigid's typed 'A.rel' takes one relationship and repeating it emits a
-- second, ignored @rel@ attribute, so the two tokens are one attribute.)
navLink :: HTML.Class -> HTML.Class -> Route -> NavItem -> E.ChildHTML E.UnorderedList grandparent
navLink itemClass linkClass current item =
  E.li [ A.class_ itemClass ]
    [ E.a ( [ A.class_ linkClass ]
            <> targetAttributes
          )
        ( E.text (navLabel item)
            : [ E.span [ A.class_ "visually-hidden" ] [ E.text (" " <> note) ] | Just note <- [navNote item] ]
        )
    ]
  where
    targetAttributes =
      case navTarget item of
        ToRoute route -> A.href (routeUrl route) : [ A.aria_current HTML.CurrentPage | route == current ]
        ToFragment fragment -> [ A.href fragment ]
        ToDocument url -> [ A.href url, A.target HTML.Blank, A.customAttribute "rel" "noopener noreferrer" ]

--------------------------------------------------------------------------------
-- Footer

-- | The footer's site links: the content destinations, without Home (the
-- monogram and the name lead there) or Contact (the footer's own Contact
-- section follows them).
footerLinks :: SiteConfig -> [NavItem]
footerLinks config =
  [ NavItem "Work" (ToRoute WorkIndex) Nothing
  , NavItem "Writing" (ToRoute WritingIndex) Nothing
  , NavItem "About" (ToRoute About) Nothing
  ]
    <> resumeItem config

-- | The Contact section's own copy.
data ContactCopy =
  ContactCopy
    { contactStatus :: CopyStatus
    , contactInvitation :: T.Text
    }

-- | Owner-approved contact invitation.
contactCopy :: ContactCopy
contactCopy =
  ContactCopy
    { contactStatus = FinalCopy
    , contactInvitation = "Questions about a project, or an idea worth building? I’d be glad to hear from you."
    }

-- | The site footer, identical in structure on every page (prelaunch
-- correction; it used to drop its contact column on the homepage, which
-- had a Contact section of its own):
--
-- 1. identity: the name and the thesis;
-- 2. Site: a heading and a row of site links;
-- 3. Contact (@#contact@, the target of every Contact link): a heading,
--    the invitation and a row of the verified destinations, each one link;
-- 4. the copyright and colophon line.
--
-- Site and Contact stack beside the identity; their links run in rows.
-- One ornament (a ruled diamond); no monogram and no tree emblem.
siteFooter :: SiteConfig -> Route -> E.ChildHTML E.Body grandparent
siteFooter config current =
  E.footer [ A.class_ "site-footer" ]
    [ E.div [ A.class_ "site-footer__ornament", A.aria_hidden True ] []
    , E.div [ A.class_ "site-footer__inner" ]
        [ E.div [ A.class_ "site-footer__identity" ]
            [ E.p [ A.class_ "site-footer__name" ] [ E.text (settingsName settings) ]
            , E.p [ A.class_ "site-footer__thesis" ] [ E.text (settingsThesis settings) ]
            ]
        , E.div [ A.class_ "site-footer__sections" ]
            [ E.nav [ A.class_ "site-footer__nav", A.aria_label "Footer" ]
                [ E.h2 [ A.class_ "site-footer__heading" ] [ E.text "Site" ]
                , E.ul [ A.class_ "site-footer__links" ] (map (navLink "site-footer__item" "site-footer__link" current) (footerLinks config))
                ]
            , E.section [ A.class_ "site-footer__contact", A.id contactId, A.aria_labelledby (NEL.singleton contactTitleId) ]
                ( [ E.h2 [ A.class_ "site-footer__heading", A.id contactTitleId ] [ E.text "Contact" ]
                  , E.p [ A.class_ "site-footer__invitation" ] [ E.text (contactInvitation contactCopy) ]
                  ]
                    <> [ E.ul [ A.class_ "site-footer__links site-footer__links--contact" ]
                           [ E.li [ A.class_ "site-footer__item" ]
                               [ E.a [ A.class_ "site-footer__link site-footer__link--contact", A.href (B.mkRawURL (contactHref c)) ]
                                   [ E.span [ A.class_ (HTML.Class ("contact__icon contact__icon--" <> contactKind c)), A.aria_hidden True ] []
                                   , E.span [ A.class_ "site-footer__label" ] [ E.text (contactLabel c) ]
                                   , E.span [ A.class_ "visually-hidden" ] [ E.text (": " <> contactDisplay c) ]
                                   ]
                               ]
                           | c <- destinations
                           ]
                       | not (null destinations)
                       ]
                )
            ]
        ]
    , E.div [ A.class_ "site-footer__base" ]
        [ E.p [ A.class_ "site-footer__copyright" ]
            [ E.text ("© " <> settingsCopyrightYears settings <> " " <> settingsName settings) ]
        , E.p [ A.class_ "site-footer__colophon" ] [ E.text "Built with Haskell & Brigid." ]
        ]
    ]
  where
    settings = siteSettings config
    destinations = contacts settings

contactTitleId :: B.Id
contactTitleId = elementId "contact-title"
