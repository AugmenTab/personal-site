-- | The typed content model: projects and articles as loaded from
-- @content/@ (see "Site.Content.Load" and README "Content").
module Site.Content.Types
  ( -- * Statuses
    DevelopmentStatus (..)
  , developmentLabel
  , PublicationStatus (..)
    -- * Projects
  , Project (..)
  , ExternalLink (..)
  , Showcase (..)
  , projectKicker
  , projectTitleId
    -- * Articles
  , Article (..)
    -- * Media
  , MediaFile (..)
  , MediaOwner (..)
  , mediaOutput
  , mediaUrl
    -- * Loaded content
  , Content (..)
  , emptyContent
  , publishedProjects
  , featuredProjects
  , publishedArticles
  ) where

import Data.List (sortOn)
import Data.Maybe (isJust)
import Data.Ord (Down (..))
import Data.Text qualified as T

import Brigid.Types qualified as B

import Site.Content.Markdown (Document)
import Site.Path (OutputPath, mkOutputPath, outputText)
import Site.Routes (Slug, elementId, slugText)

-- | The state of the actual work. It labels a project truthfully and never
-- decides whether it is published.
data DevelopmentStatus = Implemented | InDevelopment | Proposed
  deriving (Eq, Ord, Show, Bounded, Enum)

developmentLabel :: DevelopmentStatus -> T.Text
developmentLabel status =
  case status of
    Implemented -> "Implemented"
    InDevelopment -> "In development"
    Proposed -> "Proposed"

-- | Only 'Published' content produces routes, cards, links or media.
data PublicationStatus = Draft | Published
  deriving (Eq, Ord, Show, Bounded, Enum)

data ExternalLink =
  ExternalLink
    { linkLabel :: T.Text
    , linkUrl :: T.Text
      -- ^ Always @https://@ (validated).
    }
  deriving (Eq, Show)

-- | Project evidence. Each kind carries only the fields meaningful to it.
-- Phase 02 renders 'ImageShowcase' only; a published project asking for
-- another kind fails validation (full media presentation is Phase 04).
data Showcase
  = ImageShowcase OutputPath T.Text
    -- ^ Media path and alt text.
  | VideoShowcase OutputPath (Maybe OutputPath) OutputPath
    -- ^ Video, optional poster image, transcript.
  | AudioShowcase OutputPath OutputPath
    -- ^ Audio and transcript.
  | CodeShowcase OutputPath T.Text
    -- ^ Source file and caption.
  | InteractiveShowcase T.Text
    -- ^ An application identifier from a fixed allow-list (currently empty:
    -- no interactive exhibit exists yet). Never arbitrary script.
  deriving (Eq, Show)

data Project =
  Project
    { projectSlug :: Slug
    , projectSource :: FilePath
      -- ^ The project's directory, e.g. @content/projects/brigid@.
    , projectTitle :: T.Text
    , projectSummary :: T.Text
    , projectCategory :: T.Text
      -- ^ What kind of thing it is, e.g. "Haskell library".
    , projectDevelopment :: DevelopmentStatus
    , projectPublication :: PublicationStatus
    , projectTechnologies :: [T.Text]
    , projectFeatured :: Maybe Int
      -- ^ Position among featured projects (homepage); 'Nothing' if not featured.
    , projectLinks :: [ExternalLink]
    , projectShowcase :: Maybe Showcase
    , projectBody :: Document
    , projectMedia :: [MediaFile]
      -- ^ Every media file the project uses (showcase and Markdown images).
    }

-- | "Haskell library · In development".
projectKicker :: Project -> T.Text
projectKicker project =
  projectCategory project <> " · " <> developmentLabel (projectDevelopment project)

-- | The id of the project's title, @{slug}-title@.
projectTitleId :: Project -> B.Id
projectTitleId project = elementId (slugText (projectSlug project) <> "-title")

data Article =
  Article
    { articleSlug :: Slug
    , articleSource :: FilePath
    , articleTitle :: T.Text
    , articleSummary :: T.Text
    , articlePublication :: PublicationStatus
    , articleDate :: Maybe T.Text
      -- ^ @YYYY-MM-DD@ (validated).
    , articleBody :: Document
    , articleMedia :: [MediaFile]
    }

data MediaOwner = ProjectMedia Slug | ArticleMedia Slug
  deriving (Eq, Ord, Show)

-- | A media file belonging to one content item.
data MediaFile =
  MediaFile
    { mediaOwner :: MediaOwner
    , mediaRoot :: FilePath
      -- ^ The item's directory, relative to the source root, e.g.
      -- @content/projects/brigid@. The file must resolve inside it.
    , mediaPath :: OutputPath
      -- ^ Relative to 'mediaRoot', e.g. @card.svg@.
    }
  deriving (Eq, Show)

-- | Where a media file is published: @media/projects/{slug}/{path}@ or
-- @media/writing/{slug}/{path}@.
mediaOutput :: MediaOwner -> OutputPath -> Either String OutputPath
mediaOutput owner path =
  either (Left . show) Right . mkOutputPath $
    "media/" <> ownerDir owner <> "/" <> outputText path
  where
    ownerDir o =
      case o of
        ProjectMedia slug -> "projects/" <> T.unpack (slugText slug)
        ArticleMedia slug -> "writing/" <> T.unpack (slugText slug)

-- | The root-absolute URL of a media file.
mediaUrl :: MediaOwner -> OutputPath -> B.RawURL
mediaUrl owner path =
  B.mkRawURL . T.pack $
    either (const ("/media/invalid/" <> outputText path)) (("/" <>) . outputText) (mediaOutput owner path)

-- | Everything under @content/@, drafts included.
data Content =
  Content
    { contentProjects :: [Project]
    , contentArticles :: [Article]
    }

emptyContent :: Content
emptyContent = Content [] []

-- | Published projects for the Work index: featured ones first, by
-- featured order, then the rest by title, then slug. Never by directory
-- order.
publishedProjects :: Content -> [Project]
publishedProjects =
  sortOn (\p -> (maybe (1 :: Int, 0) (\n -> (0, n)) (projectFeatured p), T.toCaseFold (projectTitle p), projectSlug p))
    . filter ((== Published) . projectPublication)
    . contentProjects

-- | Published projects with a featured position, in that order (homepage).
featuredProjects :: Content -> [Project]
featuredProjects = filter (isJust . projectFeatured) . publishedProjects

-- | Published articles, newest first (undated last), then by slug.
publishedArticles :: Content -> [Article]
publishedArticles =
  sortOn (\a -> (Down (articleDate a), articleSlug a))
    . filter ((== Published) . articlePublication)
    . contentArticles
