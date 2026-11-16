{-# LANGUAGE DataKinds #-}

-- | The Work index and the project detail pages.
--
-- Every project page uses one layout, after the approved project render
-- (@design/references/project-render-03.jpg@): the global navigation, then
-- a project sidebar (All projects, the current project, and links to the
-- page's sections) beside the project's content.
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
import Data.Text qualified as T

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Types qualified as HTML
import Brigid.Types qualified as B

import Site.Components (HeadingLevel (..), pageHeading, projectCard)
import Site.Content.Markdown (Document (..), inlineText)
import Site.Content.Render (MediaUrl, renderBlocks, renderInlines, renderPhrasing)
import Site.Content.Types
import Site.Page (Layout (..), Page (..), SiteConfig, sectionTitle)
import Site.Routes (Route (WorkDetail, WorkIndex), elementId, routeUrl)

indexPage :: SiteConfig -> [Project] -> Page
indexPage config projects =
  Page
    { pageRoute = WorkIndex
    , pageTitle = sectionTitle config "Work"
    , pageDescription = "Libraries, languages and tools by Tyler Baum."
    , pageLayout = Interior
    , pageMain =
        [ E.section [ A.class_ "work", A.aria_labelledby (NEL.singleton titleId) ]
            ( [ pageHeading [] titleId "Work"
              , E.p [ A.class_ "page-lede" ]
                  [ E.text "Libraries, languages and tools I have built or am building." ]
              ]
                <> [ E.ul [ A.class_ "work__list" ]
                       (map (\project -> E.li [ A.class_ "work__item" ] [ projectCard Level2 project ]) projects)
                   | not (null projects)
                   ]
            )
        ]
    }
  where
    titleId = elementId "work-index-title"

-- | A project dossier. With a hero, the page opens on the symbolic artwork
-- (title, summary and tags as real HTML over it), then the sidebar beside
-- the sections. Without one, the header sits beside the sidebar, above the
-- card art, as in Phase 02. Either way the sections are the body's @##@
-- sections, each in the layout @project.json@ gives it.
projectPage :: SiteConfig -> Project -> Page
projectPage config project =
  Page
    { pageRoute = WorkDetail (projectSlug project)
    , pageTitle = sectionTitle config (projectTitle project)
    , pageDescription = projectSummary project
    , pageLayout = maybe Interior (const Dossier) (projectHero project)
    , pageMain =
        case projectHero project of
          Just hero ->
            [ E.article [ A.class_ "project project--hero", A.aria_labelledby (NEL.singleton titleId) ]
                [ projectHero' media project hero
                , E.div [ A.class_ "project-layout" ]
                    [ projectNav project
                    , E.div [ A.class_ "project__body" ] body
                    ]
                ]
            ]
          Nothing ->
            [ E.div [ A.class_ "project-layout" ]
                [ projectNav project
                , E.article [ A.class_ "project", A.aria_labelledby (NEL.singleton titleId) ]
                    ( [ projectHeader project ]
                        <> showcase
                        <> body
                    )
                ]
            ]
    }
  where
    titleId = projectTitleId project
    media = mediaUrl (ProjectMedia (projectSlug project))
    lead = documentLead (projectBody project)
    body :: (E.ValidChild E.Section parent grandparent, E.ValidChild E.Division parent grandparent)
         => [E.ChildHTML parent grandparent]
    body =
      [ E.div [ A.class_ "project__lead prose" ] (renderBlocks media lead) | not (null lead) ]
        <> map (dossierSection media) (projectSections project)
    showcase =
      case projectShowcase project of
        Just (ImageShowcase path alt) ->
          [ E.figure [ A.class_ "project__showcase" ]
              [ E.img [ A.src (media path), A.alt alt, A.decoding HTML.DecodeAsync ] ]
          ]
        _ -> []

-- | The hero banner: the artwork, then the project's real header text over
-- it. The artwork is the page's largest image and is fetched first.
projectHero' :: MediaUrl -> Project -> Hero -> E.ChildHTML E.Article grandparent
projectHero' media project hero =
  E.header [ A.class_ (HTML.Class ("project-hero project-hero--focus-" <> heroFocusName (heroFocus hero))) ]
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

projectHeader :: E.ValidChild E.Division parent grandparent => Project -> E.ChildHTML parent grandparent
projectHeader project =
  E.div [ A.class_ "project__header" ]
    ( [ E.p [ A.class_ "project__kicker" ] [ E.text (projectKicker project) ]
      , E.h1 [ A.class_ "project__title", A.id (projectTitleId project) ] [ E.text (projectTitle project) ]
      , E.p [ A.class_ "project__summary" ] [ E.text (projectSummary project) ]
      , E.ul [ A.class_ "project__tags", A.aria_label "Technologies" ]
          (map (\tag -> E.li [] [ E.text tag ]) (projectTechnologies project))
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
projectNav :: Project -> E.ChildHTML E.Division grandparent
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
        <> [ E.ul [ A.class_ "project-nav__sections", A.aria_label "Sections" ]
               [ E.li [] [ E.a [ A.href (elementId (dossierId section)) ] [ E.text (inlineText (dossierHeading section)) ] ]
               | section <- sections
               ]
           | not (null sections)
           ]
    )
  where
    sections = sidebarSections project

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
        [ E.div [ A.class_ "artifact__viewport" ]
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
