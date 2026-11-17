{-# LANGUAGE DataKinds #-}

-- | The Work index and the project detail pages.
--
-- Every project page uses one layout, after the approved project render
-- (@design/references/project-render-03.jpg@): the global navigation, then
-- a project sidebar (All projects, the current project, and links to the
-- page's sections) beside the project's opening (hero or header) and
-- content.
--
-- The page's content comes from the project's metadata (hero and header)
-- and its Markdown body (sections). Each section is presented in one of
-- five typed layouts (overview, wide exhibit, split, grid, resources; see
-- "Site.Content.Types"). The sidebar is generated from the same sections
-- that are rendered, so every entry has a target; a section leaves the
-- sidebar only when @project.json@ says so.
module Site.Pages.Work
  ( indexPage
  , projectPage
  ) where

import Data.List.NonEmpty qualified as NEL
import Data.NonEmptyText qualified as NET
import Data.Text qualified as T

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Elements.Safe qualified as Safe
import Brigid.HTML.Types qualified as HTML
import Brigid.Types qualified as B

import Site.Assets qualified as Asset
import Site.Components (HeadingLevel (..), pageHeading, projectCard)
import Site.Taxonomy (allCategories, categoryId, categoryLabel, topicLabel)
import Site.Content.Markdown (Document (..), inlineText)
import Site.Content.Render (MediaUrl, renderBlocks, renderInlines, renderPhrasing)
import Site.Content.Types
import Site.Page (Layout (..), Page (..), SiteConfig, sectionTitle)
import Site.Routes (Route (WorkDetail, WorkIndex), elementId, routeUrl)

-- | The Work index (Phase 05): every published project as a card, in a
-- two-column grid where there is room, with search and category filters.
--
-- The page is complete without JavaScript: every card is in the HTML and
-- visible, and the search controls are @hidden@. The page's one script
-- (@assets/scripts/work-filter.js@) reveals the controls and filters the
-- cards in place, using only what is rendered here:
--
-- * each item's @data-category@ (a category id from "Site.Taxonomy") and
--   @data-search@ (its title, summary, category, technologies and topics,
--   lowercased with whitespace collapsed; see 'searchText');
-- * one filter chip per category that a published project uses, in
--   vocabulary order, after All.
--
-- Search and the category filter combine: an item is shown when it is in
-- the selected category (All: any) and its text contains every word typed.
indexPage :: SiteConfig -> [Project] -> Page
indexPage config projects =
  Page
    { pageRoute = WorkIndex
    , pageTitle = sectionTitle config "Work"
    , pageDescription = "Libraries, languages and tools by Tyler Baum."
    , pageLayout = Interior
    , pageMain =
        [ E.section [ A.class_ "work work--index", A.aria_labelledby (NEL.singleton titleId) ]
            ( [ pageHeading [] titleId "Work"
              , E.p [ A.class_ "page-lede" ]
                  [ E.text "Libraries, languages and tools I have built or am building." ]
              ]
                <> ( if null projects
                       then []
                       else
                         [ discoveryControls projects
                         , E.ul [ A.class_ "work__list work__list--index", A.id workListId ]
                             (map indexItem projects)
                         , E.div [ A.class_ "work-filter__empty", A.id workEmptyId, A.hidden ]
                             [ E.p [ A.class_ "work-filter__empty-text" ] [ E.text "No projects match this search." ]
                             , E.button [ A.class_ "work-filter__reset" ] [ E.text "Show all projects" ]
                             ]
                         ]
                   )
            )
        ]
          <> [ E.script [ A.type_ HTML.Module, A.src (Asset.assetUrl Asset.workFilterScript) ] Nothing | not (null projects) ]
    }
  where
    titleId = elementId "work-index-title"

-- | One card, with the data the filter reads.
indexItem :: Project -> E.ChildHTML E.UnorderedList grandparent
indexItem project =
  E.li
    [ A.class_ "work__item"
    , A.customData "category" (categoryId (projectCategory project))
    , A.customData "search" (searchText project)
    ]
    [ projectCard Level2 project ]

-- | Everything a search matches, normalised as the script normalises the
-- query: lowercase, single spaces. One authoritative source: the same
-- project record the card and the dossier render.
searchText :: Project -> T.Text
searchText project =
  T.unwords . T.words . T.toLower . T.unwords $
    [ projectTitle project
    , projectSummary project
    , categoryLabel (projectCategory project)
    ]
      <> projectTechnologies project
      <> map topicLabel (projectTopics project)

-- | The search field, category chips and live result count. Hidden until
-- the script runs, so without JavaScript no inert control is shown.
discoveryControls :: [Project] -> E.ChildHTML E.Section grandparent
discoveryControls projects =
  E.search [ A.class_ "work-filter", A.id workFilterId, A.hidden, A.aria_label "Find a project" ]
    [ E.div [ A.class_ "work-filter__field" ]
        [ E.label [ A.class_ "work-filter__label", A.for workSearchId ] [ E.text "Search projects" ]
        , Safe.search
            [ A.class_ "work-filter__input"
            , A.id workSearchId
            , A.placeholder "Title, topic or technology"
            , A.customAttribute "autocomplete" "off"
            , A.customAttribute "spellcheck" "false"
            , A.customAttribute "aria-controls" (idText workListId)
            ]
        ]
    , E.div [ A.class_ "work-filter__chips", A.customAttribute "role" "group", A.aria_label "Filter by category" ]
        ( chip "" "All" True
            : [ chip (categoryId c) (categoryLabel c) False | c <- allCategories, c `elem` used ]
        )
    , E.p [ A.class_ "work-filter__status", A.id workStatusId, A.aria_live HTML.LivePolite ]
        [ E.text (countText (length projects)) ]
    ]
  where
    used = map projectCategory projects
    chip value label pressed =
      E.button
        [ A.class_ "work-filter__chip"
        , A.customData "category" value
        , A.customAttribute "aria-pressed" (if pressed then "true" else "false")
        ]
        [ E.text label ]

countText :: Int -> T.Text
countText n = T.pack (show n) <> (if n == 1 then " project" else " projects")

workFilterId, workSearchId, workListId, workStatusId, workEmptyId :: B.Id
workFilterId = elementId "work-filter"
workSearchId = elementId "work-search"
workListId = elementId "work-list"
workStatusId = elementId "work-status"
workEmptyId = elementId "work-empty"

idText :: B.Id -> T.Text
idText (B.Id i) = NET.toText i

-- | A project dossier, after the approved project render. One structure
-- serves every project; a hero only changes what opens the main column:
--
-- @
-- article.project.project-layout     (two columns on desktop, one below 900px)
--   header.project-hero | div.project__header   the opening   (main column)
--   nav.project-nav                             the sidebar   (left column)
--   div.project__body                           the dossier   (main column)
-- @
--
-- On desktop the sidebar spans both rows, beside the opening and the
-- dossier. Below 900px the three stack in source order: the opening, a
-- compact section index (see 'projectNav'), then the dossier. Source order
-- is reading and keyboard order at every width, which is why the sidebar
-- sits between the opening and the dossier rather than before the article.
--
-- Without a hero, the opening is the plain header (title, summary,
-- technologies, topics and links) and the dossier follows directly: no
-- decorative figure stands in for a hero (Phase 05 removed the card-art
-- fallback). The sections are the body's @##@ sections, each in the
-- layout @project.json@ gives it.
projectPage :: SiteConfig -> Project -> Page
projectPage config project =
  Page
    { pageRoute = WorkDetail (projectSlug project)
    , pageTitle = sectionTitle config (projectTitle project)
    , pageDescription = projectSummary project
    , pageLayout = maybe Interior (const Dossier) (projectHero project)
    , pageMain =
        [ E.article
            [ A.class_ (HTML.Class (T.unwords ("project" : "project-layout" : [ "project--hero" | hasHero ])))
            , A.aria_labelledby (NEL.singleton titleId)
            ]
            [ maybe (projectHeader project) (projectHero' media project) (projectHero project)
            , projectNav project
            , E.div [ A.class_ "project__body" ] body
            ]
        ]
    }
  where
    hasHero = maybe False (const True) (projectHero project)
    titleId = projectTitleId project
    media = mediaUrl (ProjectMedia (projectSlug project))
    lead = documentLead (projectBody project)
    body =
      [ E.div [ A.class_ "project__lead prose" ] (renderBlocks media lead) | not (null lead) ]
        <> map (dossierSection media) (projectSections project)

-- | The hero: atmospheric artwork behind the project's real header text.
-- The artwork is the page's largest image and is fetched first; its crop
-- follows the validated focus points (one class per axis and screen).
projectHero' :: MediaUrl -> Project -> Hero -> E.ChildHTML E.Article grandparent
projectHero' media project hero =
  E.header [ A.class_ (HTML.Class (T.unwords ("project-hero" : heroFocusClasses (heroFocus hero)))) ]
    [ E.div ( A.class_ "project-hero__art" : [ A.aria_hidden True | decorative ] )
        [ E.img
            [ A.class_ "project-hero__img"
            , A.src (media (heroImage hero))
            , A.alt altText
            , A.fetchpriority HTML.FetchHigh
            ]
        ]
    , E.div [ A.class_ "project-hero__inner" ] [ projectHeader project ]
    ]
  where
    (decorative, altText) =
      case heroDescription hero of
        HeroDecorative -> (True, "")
        HeroDescribed alt -> (False, alt)

-- | The project's real header text: the opening itself without a hero,
-- and the text over the artwork with one.
projectHeader :: E.ValidChild E.Division parent grandparent => Project -> E.ChildHTML parent grandparent
projectHeader project =
  E.div [ A.class_ "project__header" ]
    ( [ E.p [ A.class_ "project__kicker" ] [ E.text (projectKicker project) ]
      , E.h1 [ A.class_ "project__title", A.id (projectTitleId project) ] [ E.text (projectTitle project) ]
      , E.p [ A.class_ "project__summary" ] [ E.text (projectSummary project) ]
      , E.ul [ A.class_ "project__tags", A.aria_label "Technologies" ]
          (map (\tag -> E.li [] [ E.text tag ]) (projectTechnologies project))
      ]
        <> [ E.ul [ A.class_ "project__topics", A.aria_label "Topics" ]
               (map (\topic -> E.li [] [ E.text (topicLabel topic) ]) (projectTopics project))
           | not (null (projectTopics project))
           ]
        <> [ E.ul [ A.class_ "project__external", A.aria_label "Links" ]
               [ E.li [] [ E.a [ A.href (B.mkRawURL (linkUrl l)) ] [ E.text (linkLabel l) ] ]
               | l <- projectLinks project
               ]
           | not (null (projectLinks project))
           ]
    )

-- | The project sidebar: a way back to all projects, the current project,
-- and one link per section actually on the page.
--
-- It has two presentations of the same links, chosen by CSS at 900px:
--
-- * desktop: the accepted sidebar (All projects, the current project's
--   gilded tab, the section list);
-- * below 900px (Phase 05): All projects, then a collapsed "On this page"
--   disclosure (native @<details>@: no JavaScript) holding the section
--   list. The project's title is already in the opening just above, so
--   the tab is not repeated there.
--
-- Both section lists are rendered from the one 'sectionLinks' value, so
-- they cannot drift apart; the presentation not in use is @display: none@,
-- so assistive technology and the keyboard meet exactly one of them.
projectNav :: Project -> E.ChildHTML E.Article grandparent
projectNav project =
  E.nav [ A.class_ "project-nav", A.aria_label "Project" ]
    ( [ E.a [ A.class_ "project-nav__back", A.href (routeUrl WorkIndex) ]
          [ E.span [ A.class_ "project-nav__arrow", A.aria_hidden True ] [ E.text "←" ]
          , E.text "All projects"
          ]
      , E.a
          [ A.class_ "project-nav__current"
          , A.href (routeUrl (WorkDetail (projectSlug project)))
          , A.aria_current HTML.CurrentPage
          ]
          [ E.text (projectTitle project) ]
      ]
        <> ( if null sections
               then []
               else
                 [ E.ul [ A.class_ "project-nav__sections", A.aria_label "Sections" ] sectionLinks
                 , E.details [ A.class_ "project-nav__index" ]
                     [ E.summary [ A.class_ "project-nav__summary" ]
                         [ E.span [ A.class_ "project-nav__summary-label" ] [ E.text "On this page" ]
                         , E.span [ A.class_ "project-nav__summary-count" ]
                             [ E.text (T.pack (show (length sections)) <> (if length sections == 1 then " section" else " sections")) ]
                         ]
                     , E.ul [ A.class_ "project-nav__index-list", A.aria_label "Sections" ] sectionLinks
                     ]
                 ]
           )
    )
  where
    sections = sidebarSections project
    sectionLinks :: [E.ChildHTML E.UnorderedList gp]
    sectionLinks =
      [ E.li [] [ E.a [ A.href (elementId (dossierId section)) ] [ E.text (inlineText (dossierHeading section)) ] ]
      | section <- sections
      ]

--------------------------------------------------------------------------------
-- Dossier sections: one renderer per layout

-- | A dossier section in its layout. Every layout starts with the same
-- ruled @<h2>@ (the sidebar's target); overview and resources sections keep
-- their prose as direct children, the others arrange prose and artifact.
dossierSection :: E.ValidChild E.Section parent grandparent => MediaUrl -> DossierSection -> E.ChildHTML parent grandparent
dossierSection media section =
  E.section
    [ A.class_ (HTML.Class (T.unwords ("project__section" : "dossier-section" : ("dossier-section--" <> layoutKindName kind) : modifiers)))
    , A.aria_labelledby (NEL.singleton headingId)
    ]
    ( E.h2 [ A.class_ "project__section-title", A.id headingId ] (renderPhrasing media (dossierHeading section))
        : content
    )
  where
    headingId = elementId (dossierId section)
    kind = layoutKind (dossierBody section)
    modifiers =
      case dossierBody section of
        Overview _ _ -> [ "prose" ]
        Resources _ -> [ "prose" ]
        Split side _ _ -> [ "dossier-section--artifact-" <> sideName side ]
        _ -> []
    content =
      case dossierBody section of
        Overview blocks facts ->
          renderBlocks media blocks <> [ factList facts | not (null facts) ]
        Resources blocks ->
          renderBlocks media blocks
        WideExhibit artifact blocks ->
          [ E.figure [ A.class_ "dossier-exhibit" ]
              ( artifactView media artifact
                  : [ E.figcaption [ A.class_ "dossier-exhibit__caption prose" ] (renderBlocks media blocks) | not (null blocks) ]
              )
          ]
        Split side artifact blocks ->
          [ E.div [ A.class_ "dossier-split" ]
              ( case side of
                  ArtifactStart -> [ artifactFigure, text ]
                  ArtifactEnd -> [ text, artifactFigure ]
              )
          ]
          where
            text = E.div [ A.class_ "dossier-split__text prose" ] (renderBlocks media blocks)
            artifactFigure = E.figure [ A.class_ "dossier-split__artifact" ] [ artifactView media artifact ]
        Grid intro items ->
          [ E.div [ A.class_ "dossier-grid__intro prose" ] (renderBlocks media intro) | not (null intro) ]
            <> [ E.ul [ A.class_ (HTML.Class ("dossier-grid dossier-grid--count-" <> T.pack (show (length items)))) ]
                   [ E.li [ A.class_ "dossier-grid__item" ]
                       [ E.h3 [ A.class_ "dossier-grid__title" ] (renderPhrasing media (gridTitle item))
                       , E.p [ A.class_ "dossier-grid__text" ] (renderInlines media (gridText item))
                       ]
                   | item <- items
                   ]
               ]

sideName :: ArtifactSide -> T.Text
sideName side =
  case side of
    ArtifactStart -> "start"
    ArtifactEnd -> "end"

-- | The overview's small cluster of facts: label and value pairs. (Brigid
-- does not accept the @<div>@ grouping inside @<dl>@ that HTML allows, so
-- the pairs are siblings and CSS places each pair in its own column.)
factList :: E.ValidChild E.DescriptionList parent grandparent
         => [Fact] -> E.ChildHTML parent grandparent
factList facts =
  E.dl [ A.class_ "dossier-facts" ]
    (concat
       [ [ E.dt [] [ E.text (factLabel f) ]
         , E.dd [] [ E.text (factValue f) ]
         ]
       | f <- facts
       ])

-- | An artifact: a framed image or diagram, or a code panel with its label
-- on a tab. Code is escaped text; wide code and diagrams scroll inside
-- their frame, never the page, and a diagram links to its full-size file.
artifactView :: E.ValidChild E.Division parent grandparent => MediaUrl -> Artifact -> E.ChildHTML parent grandparent
artifactView media artifact =
  case artifact of
    ImageArtifact path alt ->
      E.div [ A.class_ "artifact artifact--image" ]
        [ E.img
            [ A.src (media path)
            , A.alt alt
            , A.loading HTML.Lazy
            , A.decoding HTML.DecodeAsync
            ]
        ]
    DiagramArtifact path alt ->
      E.div [ A.class_ "artifact artifact--diagram" ]
        -- On phones the diagram keeps a legible width and scrolls sideways
        -- inside this viewport, so keyboard users must be able to focus it
        -- to scroll it (WCAG 2.1.1; Phase 06). A named group, not a
        -- landmark, so it adds no region to the page outline.
        [ E.div
            [ A.class_ "artifact__viewport"
            , A.tabindex HTML.Reachable
            , A.customAttribute "role" "group"
            , A.aria_label "Diagram (scrolls sideways on narrow screens)"
            ]
            [ E.img
                [ A.src (media path)
                , A.alt alt
                , A.loading HTML.Lazy
                , A.decoding HTML.DecodeAsync
                ]
            ]
        , E.p [ A.class_ "artifact__open" ]
            [ E.a [ A.href (media path) ] [ E.text "Open the diagram at full size" ] ]
        ]
    CodeArtifact CodeExcerpt { codeLabel = label, codeLanguage = language, codeText = code } ->
      E.div [ A.class_ "artifact artifact--code" ]
        [ E.p [ A.class_ "artifact__tab" ]
            ( E.span [ A.class_ "artifact__label" ] [ E.text label ]
                : [ E.span [ A.class_ "artifact__language" ] [ E.text l ] | Just l <- [language] ]
            )
        , E.pre [ A.class_ "code-block artifact__code" ]
            [ E.code (maybe [] (\l -> [ A.class_ (HTML.Class ("language-" <> l)) ]) language)
                (concat
                   [ [ E.span [ A.class_ "artifact__line" ] [ E.text line ], E.text "\n" ]
                   | line <- T.splitOn "\n" code
                   ])
            ]
        ]
