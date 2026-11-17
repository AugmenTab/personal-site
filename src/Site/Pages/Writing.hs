{-# LANGUAGE DataKinds #-}

-- | Writing: an index and one page per published article. The index always
-- exists and is always in the navigation; with no published article it
-- says "Coming soon." and lists nothing (no empty grid, no sample posts).
-- Draft articles are never rendered, listed or linked.
module Site.Pages.Writing
  ( indexPage
  , articlePage
  ) where

import Data.List.NonEmpty qualified as NEL

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E

import Site.Components (pageHeading)
import Site.Content.Markdown (Document (..), Section (..))
import Site.Content.Render (MediaUrl, renderBlocks, renderPhrasing)
import Site.Content.Types
import Site.Page (Layout (..), Page (..), SiteConfig, sectionTitle)
import Site.Routes (Route (WritingArticle, WritingIndex), elementId, routeUrl)

indexPage :: SiteConfig -> [Article] -> Page
indexPage config articles =
  Page
    { pageRoute = WritingIndex
    , pageTitle = sectionTitle config "Writing"
    , pageDescription = "Technical writing by Tyler Baum."
    , pageLayout = Interior
    , pageMain =
        [ E.section [ A.class_ "writing", A.aria_labelledby (NEL.singleton titleId) ]
            ( pageHeading [] titleId "Writing" : body )
        ]
    }
  where
    body
      | null articles =
          [ E.p [ A.class_ "page-lede writing__empty" ] [ E.text "Coming soon." ] ]
      | otherwise =
          [ E.p [ A.class_ "page-lede" ] [ E.text "Notes and essays, newest first." ]
          , E.ul [ A.class_ "writing__list" ] (map entry articles)
          ]
    titleId = elementId "writing-title"
    -- Date first (as on the homepage preview), then title, summary and a
    -- single link per article.
    entry article =
      E.li [ A.class_ "writing__item" ]
        ( [ E.p [ A.class_ "writing__date" ] [ E.text date ] | Just date <- [articleDate article] ]
            <> [ E.h2 [ A.class_ "writing__title" ] [ E.text (articleTitle article) ]
               , E.p [ A.class_ "writing__summary" ] [ E.text (articleSummary article) ]
               , E.p [ A.class_ "writing__more" ]
                   [ E.a [ A.href (routeUrl (WritingArticle (articleSlug article))) ]
                       [ E.text "Read"
                       , E.span [ A.class_ "visually-hidden" ] [ E.text (": " <> articleTitle article) ]
                       , E.span [ A.class_ "writing__arrow", A.aria_hidden True ] [ E.text " →" ]
                       ]
                   ]
               ]
        )

articlePage :: SiteConfig -> Article -> Page
articlePage config article =
  Page
    { pageRoute = WritingArticle (articleSlug article)
    , pageTitle = sectionTitle config (articleTitle article)
    , pageDescription = articleSummary article
    , pageLayout = Interior
    , pageMain =
        [ E.article [ A.class_ "article", A.aria_labelledby (NEL.singleton titleId) ]
            ( [ E.p [ A.class_ "article__back" ]
                  [ E.a [ A.href (routeUrl WritingIndex) ]
                      [ E.span [ A.aria_hidden True ] [ E.text "← " ], E.text "All writing" ]
                  ]
              , E.h1 [ A.class_ "article__title", A.id titleId ] [ E.text (articleTitle article) ]
              ]
                <> [ E.p [ A.class_ "article__date" ] [ E.text date ] | Just date <- [articleDate article] ]
                <> [ E.p [ A.class_ "article__summary" ] [ E.text (articleSummary article) ] ]
                <> [ E.div [ A.class_ "article__lead prose" ] (renderBlocks media lead) | not (null lead) ]
                <> map (articleSection media) (documentSections (articleBody article))
            )
        ]
    }
  where
    titleId = elementId "article-title"
    media = mediaUrl (ArticleMedia (articleSlug article))
    lead = documentLead (articleBody article)

articleSection :: MediaUrl -> Section -> E.ChildHTML E.Article grandparent
articleSection media section =
  E.section [ A.class_ "article__section prose", A.aria_labelledby (NEL.singleton headingId) ]
    ( E.h2 [ A.class_ "article__section-title", A.id headingId ] (renderPhrasing media (sectionHeading section))
        : renderBlocks media (sectionBlocks section)
    )
  where
    headingId = elementId (sectionId section)
