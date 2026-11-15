{-# LANGUAGE DataKinds #-}

-- | The Work index and the project detail pages.
--
-- Every project page uses one layout, after the approved project render
-- (@design/references/project-render-03.jpg@): the global navigation, then
-- a project sidebar (All projects, the current project, and links to the
-- page's sections) beside the project's content. The sidebar is generated
-- from the same section list as the content, so every entry has a target.
-- The full project dossier arrives in Phase 04.
module Site.Pages.Work
  ( indexPage
  , projectPage
  ) where

import Data.List.NonEmpty qualified as NEL
import Data.NonEmptyText qualified as NET
import Data.Text qualified as T

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Types qualified as HTML
import Brigid.Types qualified as B

import Site.Components (HeadingLevel (..), pageHeading, projectCard)
import Site.Page (Layout (..), Page (..), SiteConfig, sectionTitle)
import Site.Projects (Project (..), ProjectSection (..), SectionContent (..), projectTitleId)
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
            [ pageHeading [] titleId "Work"
            , E.p [ A.class_ "page-lede" ]
                [ E.text "Libraries, languages and tools I have built or am building." ]
            , E.ul [ A.class_ "work__list" ]
                (map (\project -> E.li [ A.class_ "work__item" ] [ projectCard Level2 project ]) projects)
            ]
        ]
    }
  where
    titleId = elementId "work-index-title"

projectPage :: SiteConfig -> Project -> Page
projectPage config project =
  Page
    { pageRoute = WorkDetail (projectSlug project)
    , pageTitle = sectionTitle config (projectName project)
    , pageDescription = projectSummary project
    , pageLayout = Interior
    , pageMain =
        [ E.div [ A.class_ "project-layout" ]
            [ projectNav project
            , E.article [ A.class_ "project", A.aria_labelledby (NEL.singleton titleId) ]
                ( E.div [ A.class_ "project__header" ]
                    [ E.p [ A.class_ "project__kicker" ] [ E.text (projectKicker project) ]
                    , E.h1 [ A.class_ "project__title", A.id titleId ] [ E.text (projectName project) ]
                    , E.p [ A.class_ "project__summary" ] [ E.text (projectSummary project) ]
                    , E.ul [ A.class_ "project__tags", A.aria_label "Topics" ]
                        (map (\tag -> E.li [] [ E.text tag ]) (projectTags project))
                    ]
                    : map projectSection (projectSections project)
                )
            ]
        ]
    }
  where
    titleId = projectTitleId project

-- | The project sidebar: a way back to all projects, the current project,
-- and one link per section actually on the page.
projectNav :: Project -> E.ChildHTML E.Division grandparent
projectNav project =
  E.nav [ A.class_ "project-nav", A.aria_label "Project" ]
    [ E.a [ A.class_ "project-nav__back", A.href (routeUrl WorkIndex) ]
        [ E.span [ A.class_ "project-nav__arrow", A.aria_hidden True ] [ E.text "←" ]
        , E.text "All projects"
        ]
    , E.a
        [ A.class_ "project-nav__current"
        , A.href (routeUrl (WorkDetail (projectSlug project)))
        , A.aria_current HTML.CurrentPage
        ]
        [ E.text (projectName project) ]
    , E.ul [ A.class_ "project-nav__sections", A.aria_label "Sections" ]
        [ E.li [] [ E.a [ A.href (sectionId section) ] [ E.text (sectionLabel section) ] ]
        | section <- projectSections project
        ]
    ]

projectSection :: ProjectSection -> E.ChildHTML E.Article grandparent
projectSection section =
  E.section
    [ A.class_ "project__section"
    , A.id (sectionId section)
    , A.aria_labelledby (NEL.singleton headingId)
    ]
    ( E.h2 [ A.class_ "project__section-title", A.id headingId ] [ E.text (sectionLabel section) ]
        : body (sectionContent section)
    )
  where
    headingId = sectionId section `suffixed` "-title"

    body content =
      case content of
        Paragraphs paras -> map (\para -> E.p [] [ E.text para ]) paras
        Facts facts ->
          [ E.dl [ A.class_ "project__facts" ]
              (concat [ [ E.dt [] [ E.text term ], E.dd [] [ E.text description ] ] | (term, description) <- facts ])
          ]
        Links links ->
          [ E.ul [ A.class_ "project__links" ]
              [ E.li [] [ E.a [ A.href (B.mkRawURL url) ] [ E.text label ] ] | (label, url) <- links ]
          ]

suffixed :: B.Id -> T.Text -> B.Id
suffixed (B.Id ident) suffix = elementId (NET.toText ident <> suffix)
