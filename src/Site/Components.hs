{-# LANGUAGE DataKinds #-}

-- | Small Brigid building blocks shared by more than one page.
module Site.Components
  ( decorativeImage
  , pageHeading
  , sectionHeading
  , HeadingLevel (..)
  , projectCard
  ) where

import Data.List.NonEmpty qualified as NEL
import Data.Text qualified as T
import Integer (Positive)

import Brigid.HTML.Attributes qualified as A
import Brigid.HTML.Elements qualified as E
import Brigid.HTML.Types qualified as HTML
import Brigid.Types qualified as B

import Site.Assets qualified as Asset
import Site.Content.Types (MediaOwner (..), Project (..), Showcase (..), developmentLabel, mediaUrl, projectTitleId)
import Site.Routes (Route (WorkDetail), routeUrl)
import Site.Taxonomy (categoryLabel)

-- | An image with empty alt text: artwork that carries no information.
decorativeImage :: E.ValidChild E.Image parent grandparent
                => HTML.Class -> Asset.Asset -> Positive -> Positive -> E.ChildHTML parent grandparent
decorativeImage cls asset w h =
  E.img
    [ A.class_ cls
    , A.src (Asset.assetUrl asset)
    , A.alt ""
    , A.width w
    , A.height h
    , A.decoding HTML.DecodeAsync
    ]

-- | The page's single @<h1>@, in the ruled Art Deco section-title style,
-- with optional modifier classes (e.g. @section-title--quiet@).
pageHeading :: E.ValidChild E.H1 parent grandparent
            => [T.Text] -> B.Id -> T.Text -> E.ChildHTML parent grandparent
pageHeading modifiers hid label =
  E.h1 [ A.class_ (sectionTitleClass modifiers), A.id hid ]
    [ E.span [ A.class_ "section-title__text" ] [ E.text label ] ]

-- | An @<h2>@ in the same ruled style.
sectionHeading :: E.ValidChild E.H2 parent grandparent
               => [T.Text] -> B.Id -> T.Text -> E.ChildHTML parent grandparent
sectionHeading modifiers hid label =
  E.h2 [ A.class_ (sectionTitleClass modifiers), A.id hid ]
    [ E.span [ A.class_ "section-title__text" ] [ E.text label ] ]

sectionTitleClass :: [T.Text] -> HTML.Class
sectionTitleClass modifiers = HTML.Class (T.unwords ("section-title" : modifiers))

-- | The level of a component's heading, so it can nest correctly under
-- whatever heading precedes it on the page.
data HeadingLevel = Level2 | Level3

-- | The framed project card. Its single link leads to the project's page;
-- CSS stretches the link's hit area over the whole card.
projectCard :: E.ValidChild E.Article parent grandparent
            => HeadingLevel -> Project -> E.ChildHTML parent grandparent
projectCard level project =
  E.article
    [ A.class_ (if hasVisual then "project-card" else "project-card project-card--text")
    , A.aria_labelledby (NEL.singleton (projectTitleId project))
    ]
    ( visual
        <> [ E.div [ A.class_ "project-card__body" ]
               [ -- Category and status as separate spans (same text as
                 -- 'projectKicker'), so narrow cards can stack them on two
                 -- lines and keep every card's title on the same line.
                 E.p [ A.class_ "project-card__kicker" ]
                   [ E.span [ A.class_ "project-card__category" ] [ E.text (categoryLabel (projectCategory project)) ]
                   , E.span [ A.class_ "project-card__kicker-sep" ] [ E.text " · " ]
                   , E.span [ A.class_ "project-card__status" ] [ E.text (developmentLabel (projectDevelopment project)) ]
                   ]
               , case level of
                   Level2 -> E.h2 [ A.class_ "project-card__title", A.id (projectTitleId project) ] [ E.text (projectTitle project) ]
                   Level3 -> E.h3 [ A.class_ "project-card__title", A.id (projectTitleId project) ] [ E.text (projectTitle project) ]
               , E.p [ A.class_ "project-card__summary" ] [ E.text (projectSummary project) ]
               , E.div [ A.class_ "project-card__footer" ]
                   [ E.ul [ A.class_ "project-card__tags", A.aria_label "Technologies" ]
                       (map (\tag -> E.li [] [ E.text tag ]) (projectTechnologies project))
                   , E.a
                       [ A.class_ "project-card__link"
                       , A.href (routeUrl (WorkDetail (projectSlug project)))
                       ]
                       [ E.text "View project"
                       , E.span [ A.class_ "visually-hidden" ] [ E.text (": " <> projectTitle project) ]
                       , E.span [ A.class_ "project-card__arrow", A.aria_hidden True ] [ E.text "→" ]
                       ]
                   ]
               ]
           ]
    )
  where
    -- The card shows an image showcase as decorative art (the project page
    -- shows it with its alt text); other showcase kinds give a text-only card.
    (hasVisual, visual) =
      case projectShowcase project of
        Just (ImageShowcase path _) ->
          ( True
          , [ E.div [ A.class_ "project-card__visual", A.aria_hidden True ]
                [ E.img
                    [ A.class_ "project-card__art"
                    , A.src (mediaUrl (ProjectMedia (projectSlug project)) path)
                    , A.alt ""
                    , A.width (360 :: Positive)
                    , A.height (360 :: Positive)
                    , A.decoding HTML.DecodeAsync
                    ]
                ]
            ]
          )
        _ -> (False, [])
