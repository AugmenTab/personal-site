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
    -- * Dossiers (Phase 04)
  , Hero (..)
  , HeroDescription (..)
  , HeroFocus (..)
  , FocusPoint (..)
  , FocusPercent
  , mkFocusPercent
  , focusPercent
  , focusCentre
  , defaultHeroFocus
  , legacyHeroFocus
  , heroFocusClasses
  , DossierSection (..)
  , DossierBody (..)
  , Fact (..)
  , GridItem (..)
  , Artifact (..)
  , CodeExcerpt (..)
  , ArtifactSide (..)
  , LayoutKind (..)
  , layoutKind
  , layoutKindName
  , sidebarSections
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

import Site.Content.Markdown (Block, Document, Inline)
import Site.Path (OutputPath, mkOutputPath, outputText)
import Site.Routes (Slug, elementId, slugText)
import Site.Taxonomy (Category, Topic, categoryLabel)

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
    , projectCategory :: Category
      -- ^ The primary classification ("Site.Taxonomy").
    , projectTopics :: [Topic]
      -- ^ Cross-cutting subjects, in vocabulary order, without duplicates.
    , projectDevelopment :: DevelopmentStatus
    , projectPublication :: PublicationStatus
    , projectTechnologies :: [T.Text]
      -- ^ Concrete languages, frameworks and tools, as written.
    , projectFeatured :: Maybe Int
      -- ^ Position among featured projects (homepage); 'Nothing' if not featured.
    , projectLinks :: [ExternalLink]
    , projectShowcase :: Maybe Showcase
      -- ^ Card art: shown (decoratively) on the project's cards only. The
      -- dossier never shows it; evidence belongs in a section artifact.
    , projectHero :: Maybe Hero
    , projectBody :: Document
      -- ^ The parsed Markdown body; its lead opens the dossier.
    , projectSections :: [DossierSection]
      -- ^ The body's @##@ sections, in body order, each with its layout.
    , projectMedia :: [MediaFile]
      -- ^ Every media file the project uses (showcase, hero, artifacts and
      -- Markdown images).
    }

--------------------------------------------------------------------------------
-- Dossiers

-- | The symbolic artwork at the top of a project page. It never carries
-- the page's text: the title, summary and tags are real HTML over it.
data Hero =
  Hero
    { heroImage :: OutputPath
    , heroDescription :: HeroDescription
    , heroFocus :: HeroFocus
    }
  deriving (Eq, Show)

-- | The hero's alt text policy, stated explicitly in @project.json@.
data HeroDescription
  = HeroDescribed T.Text
    -- ^ A short description of the artwork, as its @alt@ text.
  | HeroDecorative
    -- ^ Purely atmospheric: empty @alt@, hidden from assistive technology.
  deriving (Eq, Show)

-- | Which point of the artwork stays in view when the hero crops it, on
-- wide screens and on phones (where the hero is much taller than it is
-- wide, so a different point usually matters).
data HeroFocus =
  HeroFocus
    { focusDesktop :: FocusPoint
    , focusMobile :: FocusPoint
    }
  deriving (Eq, Show)

-- | A point of the artwork: @x@ from the left edge, @y@ from the top, each
-- in percent. It becomes the image's @object-position@, so the point x% of
-- the way across the artwork sits x% of the way across the hero.
data FocusPoint =
  FocusPoint
    { focusX :: FocusPercent
    , focusY :: FocusPercent
    }
  deriving (Eq, Show)

-- | 0 to 100 in steps of 5 (the stylesheet has one class per value, so no
-- CSS text ever comes from content). Built only by 'mkFocusPercent'.
newtype FocusPercent = FocusPercent Int
  deriving (Eq, Ord, Show)

focusStep :: Int
focusStep = 5

mkFocusPercent :: Int -> Either String FocusPercent
mkFocusPercent n
  | n < 0 || n > 100 = Left ("must be from 0 to 100, got " <> show n)
  | n `mod` focusStep /= 0 = Left ("must be a multiple of " <> show focusStep <> " (e.g. " <> show (focusStep * (n `div` focusStep)) <> " or " <> show (min 100 (focusStep * (n `div` focusStep + 1))) <> "), got " <> show n)
  | otherwise = Right (FocusPercent n)

focusPercent :: FocusPercent -> Int
focusPercent (FocusPercent n) = n

-- | The centre of the artwork: the default on both axes.
focusCentre :: FocusPoint
focusCentre = FocusPoint (FocusPercent 50) (FocusPercent 50)

-- | Centred everywhere (when @focus@ is omitted).
defaultHeroFocus :: HeroFocus
defaultHeroFocus = HeroFocus focusCentre focusCentre

-- | The Phase 04 keywords, kept for compatibility: each names one point
-- used on every screen.
legacyHeroFocus :: [(T.Text, FocusPoint)]
legacyHeroFocus =
  [ ("center", focusCentre)
  , ("top", FocusPoint (FocusPercent 50) (FocusPercent 10))
  , ("bottom", FocusPoint (FocusPercent 50) (FocusPercent 90))
  ]

-- | The hero's focus classes, e.g.
-- @project-hero--x-65 project-hero--y-35 project-hero--mx-80 project-hero--my-45@.
heroFocusClasses :: HeroFocus -> [T.Text]
heroFocusClasses (HeroFocus desktop mobile) =
  [ cls "x" (focusX desktop), cls "y" (focusY desktop), cls "mx" (focusX mobile), cls "my" (focusY mobile) ]
  where
    cls axis p = "project-hero--" <> axis <> "-" <> T.pack (show (focusPercent p))

-- | One @##@ section of a project body, with the layout it is presented in.
data DossierSection =
  DossierSection
    { dossierId :: T.Text
      -- ^ The id of the section's @<h2>@ (derived from the heading).
    , dossierHeading :: [Inline]
    , dossierInSidebar :: Bool
    , dossierBody :: DossierBody
    }
  deriving (Eq, Show)

-- | The five dossier layouts. Each carries exactly what it presents; the
-- Markdown blocks are the section's own content.
data DossierBody
  = Overview [Block] [Fact]
    -- ^ Prose, with an optional small cluster of facts. The default.
  | WideExhibit Artifact [Block]
    -- ^ A dominant artifact, then short supporting copy.
  | Split ArtifactSide Artifact [Block]
    -- ^ Prose beside an artifact (stacked on narrow screens).
  | Grid [Block] [GridItem]
    -- ^ An optional introduction, then a grid of short items.
  | Resources [Block]
    -- ^ A quiet closing section: status, limitations, links.
  deriving (Eq, Show)

-- | The layout names used in @project.json@.
data LayoutKind = OverviewKind | WideExhibitKind | SplitKind | GridKind | ResourcesKind
  deriving (Eq, Ord, Show, Bounded, Enum)

layoutKind :: DossierBody -> LayoutKind
layoutKind body =
  case body of
    Overview _ _ -> OverviewKind
    WideExhibit _ _ -> WideExhibitKind
    Split {} -> SplitKind
    Grid _ _ -> GridKind
    Resources _ -> ResourcesKind

layoutKindName :: LayoutKind -> T.Text
layoutKindName kind =
  case kind of
    OverviewKind -> "overview"
    WideExhibitKind -> "wide-exhibit"
    SplitKind -> "split"
    GridKind -> "grid"
    ResourcesKind -> "resources"

data Fact =
  Fact
    { factLabel :: T.Text
    , factValue :: T.Text
    }
  deriving (Eq, Show)

-- | A grid item, written in Markdown as a list item that starts with
-- @**Title.**@ followed by its text.
data GridItem =
  GridItem
    { gridTitle :: [Inline]
    , gridText :: [Inline]
    }
  deriving (Eq, Show)

data ArtifactSide = ArtifactStart | ArtifactEnd
  deriving (Eq, Show, Bounded, Enum)

-- | The evidence a section presents beside or above its prose.
data Artifact
  = ImageArtifact OutputPath T.Text
    -- ^ An image in the project directory and its alt text. Scales to fit.
  | DiagramArtifact OutputPath T.Text
    -- ^ An image whose detail must stay legible: on narrow screens it keeps
    -- a minimum width and scrolls, and it links to the full-size file.
  | CodeArtifact CodeExcerpt
  deriving (Eq, Show)

-- | Source text shown verbatim (escaped), read from a file at load time.
data CodeExcerpt =
  CodeExcerpt
    { codeLabel :: T.Text
      -- ^ Shown on the panel's tab, e.g. a file name.
    , codeLanguage :: Maybe T.Text
    , codeSource :: OutputPath
      -- ^ The text file it was read from (not published).
    , codeText :: T.Text
    }
  deriving (Eq, Show)

-- | The sections listed in the project sidebar, in order.
sidebarSections :: Project -> [DossierSection]
sidebarSections = filter dossierInSidebar . projectSections

-- | "Libraries & Tooling · In development".
projectKicker :: Project -> T.Text
projectKicker project =
  categoryLabel (projectCategory project) <> " · " <> developmentLabel (projectDevelopment project)

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

data MediaOwner
  = ProjectMedia Slug
  | ArticleMedia Slug
  | SiteMedia
    -- ^ A site-level document published at the root of the site under its
    -- own name (the résumé: @content/resume.pdf@ to @/resume.pdf@).
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

-- | Where a media file is published: @media/projects/{slug}/{path}@,
-- @media/writing/{slug}/{path}@, or (site documents) @{path}@ itself.
mediaOutput :: MediaOwner -> OutputPath -> Either String OutputPath
mediaOutput owner path =
  either (Left . show) Right . mkOutputPath $
    case owner of
      ProjectMedia slug -> "media/projects/" <> T.unpack (slugText slug) <> "/" <> outputText path
      ArticleMedia slug -> "media/writing/" <> T.unpack (slugText slug) <> "/" <> outputText path
      SiteMedia -> outputText path

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
    , contentResume :: Maybe MediaFile
      -- ^ The résumé PDF, when @content/resume.pdf@ exists (validated). It
      -- is published at @/resume.pdf@ and linked from the navigation and
      -- footer; without it, no résumé link exists anywhere.
    , contentWarnings :: [String]
      -- ^ Accepted, but worth an author's attention (e.g. a hero over its
      -- size budget). Printed by @site check@ and @site build@.
    }

emptyContent :: Content
emptyContent = Content [] [] Nothing []

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
