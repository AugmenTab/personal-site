{-# LANGUAGE DataKinds #-}

-- | The Work index and the project detail pages.
--
-- Every project page uses one layout, after the approved project render
-- (@design/references/project-render-03.jpg@): the global navigation, then
-- a project sidebar (All projects, the current project, and links to the
-- page's sections) beside the project's content.
--
-- The page's content comes from the project's metadata (header) and its
-- Markdown body (sections). The sidebar is generated from the same parsed
-- sections that are rendered, so every entry has a target and every
-- section has an entry. The full project dossier arrives in Phase 04.
module Site.Pages.Work
  ( indexPage
  , projectPage
  ) where

import Data.List.NonEmpty qualified as NEL

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Types qualified as HTML
import Brigid.Types qualified as B

import Site.Components (HeadingLevel (..), pageHeading, projectCard)
import Site.Content.Markdown (Document (..), Section (..), inlineText)
import Site.Content.Render (MediaUrl, renderBlocks, renderPhrasing)
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

projectPage :: SiteConfig -> Project -> Page
projectPage config project =
  Page
    { pageRoute = WorkDetail (projectSlug project)
    , pageTitle = sectionTitle config (projectTitle project)
    , pageDescription = projectSummary project
    , pageLayout = Interior
    , pageMain =
        [ E.div [ A.class_ "project-layout" ]
            [ projectNav project
            , E.article [ A.class_ "project", A.aria_labelledby (NEL.singleton titleId) ]
                ( [ projectHeader project ]
                    <> showcase
                    <> [ E.div [ A.class_ "project__lead prose" ] (renderBlocks media lead) | not (null lead) ]
                    <> map (projectSection media) (documentSections (projectBody project))
                )
            ]
        ]
    }
  where
    titleId = projectTitleId project
    media = mediaUrl (ProjectMedia (projectSlug project))
    lead = documentLead (projectBody project)
    showcase =
      case projectShowcase project of
        Just (ImageShowcase path alt) ->
          [ E.figure [ A.class_ "project__showcase" ]
              [ E.img [ A.src (media path), A.alt alt, A.decoding HTML.DecodeAsync ] ]
          ]
        _ -> []

projectHeader :: Project -> E.ChildHTML E.Article grandparent
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
               [ E.li [] [ E.a [ A.href (elementId (sectionId section)) ] [ E.text (inlineText (sectionHeading section)) ] ]
               | section <- sections
               ]
           | not (null sections)
           ]
    )
  where
    sections = documentSections (projectBody project)

projectSection :: MediaUrl -> Section -> E.ChildHTML E.Article grandparent
projectSection media section =
  E.section
    [ A.class_ "project__section prose"
    , A.aria_labelledby (NEL.singleton headingId)
    ]
    ( E.h2 [ A.class_ "project__section-title", A.id headingId ] (renderPhrasing media (sectionHeading section))
        : renderBlocks media (sectionBlocks section)
    )
  where
    headingId = elementId (sectionId section)
