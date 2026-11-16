-- | Discover, decode and validate everything under @content/@.
--
-- @
-- content/projects/{slug}/project.json   metadata (strict JSON, see README)
-- content/projects/{slug}/{body}.md      narrative (validated Markdown)
-- content/projects/{slug}/…              media referenced by either
-- content/writing/{slug}/article.json    the same, for articles
-- @
--
-- Discovery is deterministic (entries sorted; dot-files ignored). Every
-- entry must be a real directory (not a symlink) named by a valid slug,
-- and the metadata's @slug@ must equal the directory name. All files are
-- read through "Site.Source" (no traversal, no symlink escapes). Errors are
-- collected per source file, so one run reports every independent problem.
module Site.Content.Load
  ( ContentError (..)
  , loadContent
  , decodeProjectMeta
  , ProjectMeta (..)
  ) where

import Control.Monad (forM)
import Data.Aeson qualified as Json
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as BS
import Data.Char (isAsciiLower, isDigit)
import Data.Either (partitionEithers)
import Data.Foldable (toList)
import Data.List (isPrefixOf, nub, sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Scientific (floatingOrInteger)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory qualified as Dir
import System.FilePath (takeExtension, (</>))

import Site.Content.Markdown (Block (..), Document (..), Inline (..), LinkTarget (..), MarkdownError, Section (..), documentImages, inlineText, linkTarget, parseDocument)
import Site.Content.Types
import Site.Path (OutputPath, mkOutputPath, outputFilePath, outputText)
import Site.Routes (Slug, mkSlug, slugText)
import Site.Source (describeSourceProblem, sourceFileProblem)

-- | Problems with one source file (path relative to the source root).
data ContentError = ContentError FilePath [String]
  deriving (Eq)

instance Show ContentError where
  show (ContentError file messages) = file <> ":\n" <> unlines (map ("  " <>) messages)

--------------------------------------------------------------------------------
-- Discovery

loadContent :: FilePath -> IO (Either [ContentError] Content)
loadContent root = do
  (projectDirErrs, projectDirs) <- discover root "content/projects"
  (articleDirErrs, articleDirs) <- discover root "content/writing"
  projects <- forM projectDirs (uncurry (loadProject root))
  articles <- forM articleDirs (uncurry (loadArticle root))
  let (projectErrs, loadedProjects) = partitionEithers projects
      (articleErrs, loadedArticles) = partitionEithers articles
      errors =
        projectDirErrs <> articleDirErrs <> concat projectErrs <> concat articleErrs
          <> featuredConflicts loadedProjects
  pure $
    case errors of
      [] -> Right Content { contentProjects = loadedProjects, contentArticles = loadedArticles }
      _ -> Left errors

-- | The content directories of one kind, sorted by name.
discover :: FilePath -> FilePath -> IO ([ContentError], [(Slug, FilePath)])
discover root kind = do
  exists <- Dir.doesDirectoryExist (root </> kind)
  if not exists
    then pure ([], [])
    else do
      kindIsLink <- Dir.pathIsSymbolicLink (root </> kind)
      if kindIsLink
        then pure ([ContentError kind ["is a symlink; content directories must be real directories"]], [])
        else do
          names <- sort . filter (not . ("." `isPrefixOf`)) <$> Dir.listDirectory (root </> kind)
          results <- forM names $ \name -> do
            let rel = kind </> name
            isLink <- Dir.pathIsSymbolicLink (root </> rel)
            isDir <- Dir.doesDirectoryExist (root </> rel)
            pure $
              if isLink
                then Left (ContentError rel ["is a symlink; content directories must be real directories"])
                else
                  if not isDir
                    then Left (ContentError rel ["is not a directory; each entry in " <> kind <> " must be a content directory named by its slug"])
                    else case mkSlug (T.pack name) of
                      Left err -> Left (ContentError rel ["directory name: " <> show err])
                      Right slug -> Right (slug, rel)
          pure (partitionEithers results)

--------------------------------------------------------------------------------
-- Projects

-- | A project's decoded metadata, before its files are checked.
data ProjectMeta =
  ProjectMeta
    { metaSlug :: T.Text
    , metaTitle :: T.Text
    , metaSummary :: T.Text
    , metaCategory :: T.Text
    , metaDevelopment :: DevelopmentStatus
    , metaPublication :: PublicationStatus
    , metaTechnologies :: [T.Text]
    , metaFeatured :: Maybe Int
    , metaLinks :: [ExternalLink]
    , metaBody :: OutputPath
    , metaShowcase :: Maybe Showcase
    , metaHero :: Maybe HeroMeta
    , metaSections :: Map.Map T.Text SectionPlan
    }

-- | @hero@ as written, before its file is checked.
data HeroMeta = HeroMeta OutputPath HeroDescription HeroFocus

-- | One entry of @sections@: how a @##@ section of the body is presented.
data SectionPlan =
  SectionPlan
    { planLayout :: PlanLayout
    , planSidebar :: Bool
    }

data PlanLayout
  = PlanOverview [Fact]
  | PlanWideExhibit ArtifactMeta
  | PlanSplit ArtifactSide ArtifactMeta
  | PlanGrid
  | PlanResources

-- | An artifact as written, before its file is checked (and, for code, read).
data ArtifactMeta
  = ImageMeta Bool OutputPath T.Text
    -- ^ 'True' for a diagram.
  | CodeMeta T.Text (Maybe T.Text) OutputPath

projectFields :: [T.Text]
projectFields =
  [ "slug", "title", "summary", "category", "development_status", "publication_status"
  , "technologies", "featured_order", "links", "body", "showcase", "hero", "sections" ]

-- | Strictly decode @project.json@. Every field problem is reported.
decodeProjectMeta :: Json.Value -> Either [String] ProjectMeta
decodeProjectMeta value = do
  obj <- asObject value
  runV $
    noUnknownFields projectFields obj
      *> ( ProjectMeta
      <$> field obj "slug" text
      <*> field obj "title" text
      <*> field obj "summary" attributeText
      <*> field obj "category" text
      <*> field obj "development_status" (enum [("implemented", Implemented), ("in_development", InDevelopment), ("proposed", Proposed)])
      <*> field obj "publication_status" (enum [("draft", Draft), ("published", Published)])
      <*> field obj "technologies" (list text)
      <*> optionalField obj "featured_order" positiveInt
      <*> (maybe [] id <$> optionalField obj "links" (list externalLink))
      <*> field obj "body" markdownPath
      <*> optionalField obj "showcase" showcase
      <*> optionalField obj "hero" heroField
      <*> (maybe Map.empty id <$> optionalField obj "sections" sectionPlans)
         )

loadProject :: FilePath -> Slug -> FilePath -> IO (Either [ContentError] Project)
loadProject root slug dir = do
  let metaFile = dir </> "project.json"
  decoded <- readJson root dir "project.json" decodeProjectMeta
  case decoded of
    Left errs -> pure (Left errs)
    Right meta -> do
      let slugErrs =
            [ "field \"slug\": " <> show (metaSlug meta) <> " must equal the directory name " <> show (slugText slug)
            | metaSlug meta /= slugText slug ]
          owner = ProjectMedia slug
          published = metaPublication meta == Published
          showcaseErrs =
            case metaShowcase meta of
              Just sc | published, not (isImage sc) ->
                [ "field \"showcase\": kind " <> show (showcaseKind sc)
                    <> " is not supported for published projects (only \"image\", the card art; evidence belongs in a section artifact)" ]
              _ -> []
          showcaseMedia = [ p | Just (ImageShowcase p _) <- [metaShowcase meta] ]
          heroMedia = [ p | Just (HeroMeta p _ _) <- [metaHero meta] ]
      body <- loadBody root dir metaFile (metaBody meta) [ "main", slugText slug <> "-title" ]
      mediaErrs <- checkMedia root dir "field \"showcase\"" showcaseMedia
      heroErrs <- checkHero root dir heroMedia
      case body of
        Left bodyErrs ->
          pure (Left (fileErrors metaFile (slugErrs <> showcaseErrs <> mediaErrs <> heroErrs) <> bodyErrs))
        Right (document, imageErrs) -> do
          (sectionErrs, bodyStructureErrs, sections) <- dossierSections root dir (metaSections meta) document
          let bodyFile = dir </> outputFilePath (metaBody meta)
          case fileErrors metaFile (slugErrs <> showcaseErrs <> mediaErrs <> heroErrs <> sectionErrs)
                 <> imageErrs <> fileErrors bodyFile bodyStructureErrs of
            [] ->
              pure . Right $
                Project
                  { projectSlug = slug
                  , projectSource = dir
                  , projectTitle = metaTitle meta
                  , projectSummary = metaSummary meta
                  , projectCategory = metaCategory meta
                  , projectDevelopment = metaDevelopment meta
                  , projectPublication = metaPublication meta
                  , projectTechnologies = metaTechnologies meta
                  , projectFeatured = metaFeatured meta
                  , projectLinks = metaLinks meta
                  , projectShowcase = metaShowcase meta
                  , projectHero = fmap (\(HeroMeta p d f) -> Hero p d f) (metaHero meta)
                  , projectBody = document
                  , projectSections = sections
                  , projectMedia =
                      media owner dir
                        (showcaseMedia <> heroMedia <> concatMap sectionImages sections <> documentImages document)
                  }
            errs -> pure (Left errs)
  where
    isImage sc = case sc of ImageShowcase _ _ -> True; _ -> False

--------------------------------------------------------------------------------
-- Dossier sections and heroes

-- | The largest hero file accepted. The hero is the page's largest image
-- and is loaded eagerly, so an unoptimized export is an error, not a
-- silent slowdown (see README "Hero artwork").
heroByteLimit :: Integer
heroByteLimit = 1024 * 1024

-- | The hero must be an image inside the project directory, within the
-- size limit.
checkHero :: FilePath -> FilePath -> [OutputPath] -> IO [String]
checkHero root dir paths = do
  problems <- checkMedia root dir "field \"hero\": image" paths
  case problems of
    _ : _ -> pure problems
    [] ->
      fmap catMaybes . forM paths $ \path -> do
        size <- Dir.getFileSize (root </> dir </> outputFilePath path)
        pure $
          if size > heroByteLimit
            then Just ("field \"hero\": image " <> show (outputText path) <> " is " <> show size
                         <> " bytes; the limit is " <> show heroByteLimit <> " (re-export it with tools/art/promote_hero.py)")
            else Nothing

-- | Give every @##@ section of the body its layout. Returns errors about
-- @project.json@, errors about the body's structure, and the sections.
dossierSections :: FilePath -> FilePath -> Map.Map T.Text SectionPlan -> Document -> IO ([String], [String], [DossierSection])
dossierSections root dir plans document = do
  built <- forM (documentSections document) $ \section -> do
    let ident = sectionId section
        plan = Map.findWithDefault (SectionPlan (PlanOverview []) True) ident plans
        blocks = sectionBlocks section
        prefix = "field \"sections\": " <> show ident <> ": "
        ok body = ([], [], Just (DossierSection ident (sectionHeading section) (planSidebar plan) body))
        withArtifact meta k = do
          artifact <- loadArtifact root dir meta
          pure $ case artifact of
            Left why -> ([prefix <> why], [], Nothing)
            Right a -> ok (k a)
    case planLayout plan of
      PlanOverview facts -> pure (ok (Overview blocks facts))
      PlanWideExhibit meta -> withArtifact meta (\a -> WideExhibit a blocks)
      PlanSplit side meta -> withArtifact meta (\a -> Split side a blocks)
      PlanResources -> pure (ok (Resources blocks))
      PlanGrid ->
        pure $ case gridItems blocks of
          Left why -> ([], ["section " <> show ident <> " (layout \"grid\") " <> why], Nothing)
          Right (intro, items) -> ok (Grid intro items)
  let metaErrs = concat [ e | (e, _, _) <- built ] <> unknownErrs <> orderErrs
      structureErrs = concat [ e | (_, e, _) <- built ]
      sections = catMaybes [ s | (_, _, s) <- built ]
      known = map sectionId (documentSections document)
      unknownErrs =
        [ "field \"sections\": " <> show k <> " is not a ## section of the body"
            <> (if null known then " (the body has no ## sections)" else "; its sections are: " <> T.unpack (T.intercalate ", " known))
        | k <- Map.keys plans, k `notElem` known ]
      orderErrs = closingOrder sections
  pure (metaErrs, structureErrs, sections)

-- | Resources sections close the dossier: once one appears, every later
-- section must also be a resources section.
closingOrder :: [DossierSection] -> [String]
closingOrder sections =
  case break ((== ResourcesKind) . layoutKind . dossierBody) sections of
    (_, closing : rest) ->
      [ "field \"sections\": " <> show (dossierId s) <> " (layout " <> show (layoutKindName (layoutKind (dossierBody s)))
          <> ") follows the resources section " <> show (dossierId closing)
          <> "; resources sections close the dossier, so they must come last in the body"
      | s <- rest, layoutKind (dossierBody s) /= ResourcesKind ]
    _ -> []

-- | A grid section: optional introductory blocks, then one bullet list whose
-- every item is a single paragraph starting with @**Title.**@.
gridItems :: [Block] -> Either String ([Block], [GridItem])
gridItems blocks =
  case break isBullets blocks of
    (_, []) -> Left "needs a bullet list of items, each starting with **Title.**"
    (intro, [BulletList items])
      | length items < 2 || length items > gridItemLimit ->
          Left ("has " <> show (length items) <> " items; a grid holds 2 to " <> show gridItemLimit)
      | otherwise -> (,) intro <$> traverse item (zip [1 :: Int ..] items)
    (_, _) -> Left "must end with its bullet list (one list; put any other text before it)"
  where
    isBullets b = case b of BulletList _ -> True; _ -> False
    item (n, blocks') =
      case blocks' of
        [single] | Just (Strong title : rest) <- inlinesOf single ->
          let titleText = dropFullStop title
              text' = trimStart rest
           in if T.null (T.strip (inlineText titleText))
                then Left ("item " <> show n <> ": the **title** is empty")
                else if T.null (T.strip (inlineText text'))
                  then Left ("item " <> show n <> ": needs text after its **title**")
                  else Right (GridItem titleText text')
        _ -> Left ("item " <> show n <> ": must be one paragraph starting with **Title.**")
    inlinesOf b = case b of Plain xs -> Just xs; Para xs -> Just xs; _ -> Nothing
    trimStart xs =
      case xs of
        Str t : rest -> let t' = T.stripStart t in if T.null t' then trimStart rest else Str t' : rest
        SoftBreak : rest -> trimStart rest
        _ -> xs
    dropFullStop xs =
      case reverse xs of
        Str t : rest | Just t' <- T.stripSuffix "." t -> reverse (if T.null t' then rest else Str t' : rest)
        _ -> xs

gridItemLimit :: Int
gridItemLimit = 9

-- | Check an artifact's file, reading a code artifact's text.
loadArtifact :: FilePath -> FilePath -> ArtifactMeta -> IO (Either String Artifact)
loadArtifact root dir meta =
  case meta of
    ImageMeta diagram path alt -> do
      problems <- checkMedia root dir "artifact image" [path]
      pure $ case problems of
        [] -> Right ((if diagram then DiagramArtifact else ImageArtifact) path alt)
        why : _ -> Left why
    CodeMeta label language path -> do
      problem <- sourceFileProblem (root </> dir) path
      case problem of
        Just p -> pure (Left ("artifact code file " <> show (outputText path) <> " " <> describeSourceProblem p))
        Nothing -> do
          bytes <- BS.readFile (root </> dir </> outputFilePath path)
          pure $
            if BS.length bytes > codeByteLimit
              then Left ("artifact code file " <> show (outputText path) <> " is larger than " <> show codeByteLimit <> " bytes; show an excerpt")
              else case TE.decodeUtf8' bytes of
                Left _ -> Left ("artifact code file " <> show (outputText path) <> " is not valid UTF-8")
                Right source ->
                  let code = T.dropWhileEnd (== '\n') (T.replace "\r\n" "\n" source)
                   in if T.null (T.strip code)
                        then Left ("artifact code file " <> show (outputText path) <> " is empty")
                        else Right (CodeArtifact (CodeExcerpt label language path code))

codeByteLimit :: Int
codeByteLimit = 32 * 1024

-- | Images a section's artifact publishes.
sectionImages :: DossierSection -> [OutputPath]
sectionImages section =
  case dossierBody section of
    WideExhibit artifact _ -> artifactImage artifact
    Split _ artifact _ -> artifactImage artifact
    _ -> []
  where
    artifactImage artifact =
      case artifact of
        ImageArtifact p _ -> [p]
        DiagramArtifact p _ -> [p]
        CodeArtifact _ -> []

showcaseKind :: Showcase -> T.Text
showcaseKind sc =
  case sc of
    ImageShowcase _ _ -> "image"
    VideoShowcase {} -> "video"
    AudioShowcase _ _ -> "audio"
    CodeShowcase _ _ -> "code"
    InteractiveShowcase _ -> "interactive"

-- | Published projects may not share a featured position.
featuredConflicts :: [Project] -> [ContentError]
featuredConflicts projects =
  [ ContentError (projectSource p </> "project.json")
      [ "field \"featured_order\": " <> show n <> " is also used by "
          <> unwords [ show (T.unpack (slugText (projectSlug o))) | o <- others, projectSlug o /= projectSlug p ] ]
  | (n, others@(_ : _ : _)) <- Map.toList byOrder
  , p <- others
  ]
  where
    byOrder =
      Map.fromListWith (flip (<>))
        [ (n, [p]) | p <- projects, projectPublication p == Published, Just n <- [projectFeatured p] ]

--------------------------------------------------------------------------------
-- Articles

articleFields :: [T.Text]
articleFields = [ "slug", "title", "summary", "publication_status", "date", "body" ]

data ArticleMeta = ArticleMeta T.Text T.Text T.Text PublicationStatus (Maybe T.Text) OutputPath

decodeArticleMeta :: Json.Value -> Either [String] ArticleMeta
decodeArticleMeta value = do
  obj <- asObject value
  runV $
    noUnknownFields articleFields obj
      *> ( ArticleMeta
      <$> field obj "slug" text
      <*> field obj "title" text
      <*> field obj "summary" attributeText
      <*> field obj "publication_status" (enum [("draft", Draft), ("published", Published)])
      <*> optionalField obj "date" isoDate
      <*> field obj "body" markdownPath
         )

loadArticle :: FilePath -> Slug -> FilePath -> IO (Either [ContentError] Article)
loadArticle root slug dir = do
  let metaFile = dir </> "article.json"
  decoded <- readJson root dir "article.json" decodeArticleMeta
  case decoded of
    Left errs -> pure (Left errs)
    Right (ArticleMeta metaSlug title summary publication date bodyPath) -> do
      let slugErrs =
            [ "field \"slug\": " <> show metaSlug <> " must equal the directory name " <> show (slugText slug)
            | metaSlug /= slugText slug ]
      body <- loadBody root dir metaFile bodyPath [ "main", "article-title" ]
      case body of
        Left bodyErrs -> pure (Left (fileErrors metaFile slugErrs <> bodyErrs))
        Right (document, imageErrs) ->
          case fileErrors metaFile slugErrs <> imageErrs of
            [] ->
              pure . Right $
                Article
                  { articleSlug = slug
                  , articleSource = dir
                  , articleTitle = title
                  , articleSummary = summary
                  , articlePublication = publication
                  , articleDate = date
                  , articleBody = document
                  , articleMedia = media (ArticleMedia slug) dir (documentImages document)
                  }
            errs -> pure (Left errs)

--------------------------------------------------------------------------------
-- Files

fileErrors :: FilePath -> [String] -> [ContentError]
fileErrors _ [] = []
fileErrors file messages = [ContentError file messages]

-- | Read and strictly decode a metadata file inside a content directory.
readJson :: FilePath -> FilePath -> String -> (Json.Value -> Either [String] a) -> IO (Either [ContentError] a)
readJson root dir name decode = do
  let file = dir </> name
  case mkOutputPath name of
    Left err -> pure (Left [ContentError file [show err]])
    Right rel -> do
      problem <- sourceFileProblem (root </> dir) rel
      case problem of
        Just p -> pure (Left [ContentError file [describeSourceProblem p]])
        Nothing -> do
          bytes <- BS.readFile (root </> file)
          pure $
            case Json.eitherDecodeStrict' bytes of
              Left err -> Left [ContentError file ["invalid JSON: " <> err]]
              Right value -> either (Left . pure . ContentError file) Right (decode value)

-- | Read and parse a Markdown body; also check every image it references.
loadBody :: FilePath -> FilePath -> FilePath -> OutputPath -> [T.Text] -> IO (Either [ContentError] (Document, [ContentError]))
loadBody root dir metaFile bodyPath reserved = do
  let file = dir </> outputFilePath bodyPath
  problem <- sourceFileProblem (root </> dir) bodyPath
  case problem of
    Just p -> pure (Left [ContentError metaFile ["field \"body\": referenced file " <> show (outputText bodyPath) <> " " <> describeSourceProblem p]])
    Nothing -> do
      bytes <- BS.readFile (root </> file)
      case TE.decodeUtf8' bytes of
        Left _ -> pure (Left [ContentError file ["is not valid UTF-8"]])
        Right source ->
          case parseDocument file reserved source of
            Left errs -> pure (Left [ContentError file (map showMarkdownError errs)])
            Right document -> do
              imageErrs <- checkMedia root dir "image" (documentImages document)
              pure (Right (document, fileErrors file imageErrs))
  where
    showMarkdownError :: MarkdownError -> String
    showMarkdownError = show

-- | Media must be images (by extension) that exist inside the directory.
checkMedia :: FilePath -> FilePath -> String -> [OutputPath] -> IO [String]
checkMedia root dir what paths =
  fmap catMaybes . forM (nub paths) $ \path ->
    if takeExtension (outputText path) `notElem` imageExtensions
      then pure (Just (what <> " " <> show (outputText path) <> ": not an image file (allowed: " <> unwords imageExtensions <> ")"))
      else do
        problem <- sourceFileProblem (root </> dir) path
        pure (fmap (\p -> what <> " " <> show (outputText path) <> " " <> describeSourceProblem p) problem)

imageExtensions :: [String]
imageExtensions = [".svg", ".png", ".jpg", ".jpeg", ".webp", ".gif", ".avif"]

media :: MediaOwner -> FilePath -> [OutputPath] -> [MediaFile]
media owner dir paths = [ MediaFile owner dir p | p <- nub paths ]

--------------------------------------------------------------------------------
-- Strict JSON decoding with accumulated errors

-- | An applicative that collects every error instead of stopping at the first.
newtype V a = V (Either [String] a)

instance Functor V where
  fmap f (V x) = V (fmap f x)

instance Applicative V where
  pure = V . Right
  V (Left a) <*> V (Left b) = V (Left (a <> b))
  V (Left a) <*> _ = V (Left a)
  V (Right f) <*> V x = V (fmap f x)

runV :: V a -> Either [String] a
runV (V x) = x

asObject :: Json.Value -> Either [String] Json.Object
asObject value =
  case value of
    Json.Object obj -> Right obj
    _ -> Left ["must be a JSON object"]

-- | Reject keys outside the allowed set (misspellings are errors, not
-- silently ignored). Reported alongside every other field error.
noUnknownFields :: [T.Text] -> Json.Object -> V ()
noUnknownFields allowed obj =
  V $ case [ k | k <- map Key.toText (KeyMap.keys obj), k `notElem` allowed ] of
    [] -> Right ()
    unknown ->
      Left [ "unknown field " <> show k <> " (allowed: " <> T.unpack (T.intercalate ", " allowed) <> ")" | k <- sort unknown ]

-- | A JSON object with no keys outside the allowed set.
objectWith :: [T.Text] -> Json.Value -> Either [String] Json.Object
objectWith allowed value = do
  obj <- asObject value
  runV (noUnknownFields allowed obj *> pure obj)

field :: Json.Object -> T.Text -> (Json.Value -> Either String a) -> V a
field obj name decode =
  V $ case KeyMap.lookup (Key.fromText name) obj of
    Nothing -> Left ["missing required field " <> show name]
    Just v -> either (\e -> Left ["field " <> show name <> ": " <> e]) Right (decode v)

optionalField :: Json.Object -> T.Text -> (Json.Value -> Either String a) -> V (Maybe a)
optionalField obj name decode =
  V $ case KeyMap.lookup (Key.fromText name) obj of
    Nothing -> Right Nothing
    Just Json.Null -> Left ["field " <> show name <> ": null is not allowed; omit the field instead"]
    Just v -> either (\e -> Left ["field " <> show name <> ": " <> e]) (Right . Just) (decode v)

text :: Json.Value -> Either String T.Text
text value =
  case value of
    Json.String s | not (T.null (T.strip s)) -> Right (T.strip s)
    Json.String _ -> Left "must not be empty"
    other -> Left ("expected a string, got " <> jsonType other)

-- | Text that will be placed in an HTML attribute (summaries become the
-- page's meta description; alt text becomes @alt@). Brigid (at the pinned
-- commit) does not escape @"@ inside attribute values, so a straight double
-- quote could end the attribute and inject another. It is rejected here;
-- typographic quotes are fine.
attributeText :: Json.Value -> Either String T.Text
attributeText value = do
  t <- text value
  if T.any (== '"') t
    then Left "must not contain a straight double quote (\"); use typographic quotes (“ ”) instead"
    else Right t

list :: (Json.Value -> Either String a) -> Json.Value -> Either String [a]
list decode value =
  case value of
    Json.Array items ->
      case partitionEithers [ either (Left . (("[" <> show i <> "]: ") <>)) Right (decode v) | (i, v) <- zip [0 :: Int ..] (toList items) ] of
        ([], ok) -> Right ok
        (errs, _) -> Left (unwords errs)
    other -> Left ("expected an array, got " <> jsonType other)

enum :: [(T.Text, a)] -> Json.Value -> Either String a
enum options value =
  case value of
    Json.String s | Just a <- lookup s options -> Right a
    Json.String s -> Left ("invalid value " <> show s <> "; expected one of: " <> T.unpack (T.intercalate ", " (map fst options)))
    other -> Left ("expected a string, got " <> jsonType other)

positiveInt :: Json.Value -> Either String Int
positiveInt value =
  case value of
    Json.Number n ->
      case floatingOrInteger n :: Either Double Integer of
        Right i | i >= 1 && i <= 10000 -> Right (fromInteger i)
        _ -> Left ("expected a whole number from 1 to 10000, got " <> show n)
    other -> Left ("expected a number, got " <> jsonType other)

markdownPath :: Json.Value -> Either String OutputPath
markdownPath value = do
  raw <- text value
  path <- either (Left . show) Right (mkOutputPath (T.unpack raw))
  if takeExtension (T.unpack raw) == ".md"
    then Right path
    else Left (show raw <> " must be a .md file")

mediaPathField :: Json.Value -> Either String OutputPath
mediaPathField value = do
  raw <- text value
  either (Left . show) Right (mkOutputPath (T.unpack raw))

externalLink :: Json.Value -> Either String ExternalLink
externalLink value = do
  obj <- either (Left . unwords) Right (objectWith ["label", "url"] value)
  either (Left . unwords) Right . runV $
    ExternalLink
      <$> field obj "label" text
      <*> field obj "url" httpsUrl

httpsUrl :: Json.Value -> Either String T.Text
httpsUrl value = do
  raw <- text value
  case linkTarget raw of
    Right (External url) -> Right url
    Right _ -> Left (show raw <> " must be an https:// URL")
    Left why -> Left why

showcase :: Json.Value -> Either String Showcase
showcase value =
  case value of
    Json.Object obj ->
      case KeyMap.lookup "kind" obj of
        Just (Json.String kind) ->
          case kind of
            "image" -> decodeWith ["kind", "src", "alt"] $ \o ->
              ImageShowcase <$> field o "src" mediaPathField <*> field o "alt" attributeText
            "video" -> decodeWith ["kind", "src", "poster", "transcript"] $ \o ->
              VideoShowcase <$> field o "src" mediaPathField <*> optionalField o "poster" mediaPathField <*> field o "transcript" mediaPathField
            "audio" -> decodeWith ["kind", "src", "transcript"] $ \o ->
              AudioShowcase <$> field o "src" mediaPathField <*> field o "transcript" mediaPathField
            "code" -> decodeWith ["kind", "src", "caption"] $ \o ->
              CodeShowcase <$> field o "src" mediaPathField <*> field o "caption" text
            "interactive" -> decodeWith ["kind", "app"] $ \o ->
              InteractiveShowcase <$> field o "app" interactiveApp
            other -> Left ("unsupported showcase kind " <> show other <> "; expected one of: image, video, audio, code, interactive")
        Just other -> Left ("field \"kind\": expected a string, got " <> jsonType other)
        Nothing -> Left "missing required field \"kind\""
    other -> Left ("expected an object, got " <> jsonType other)
  where
    decodeWith allowed decode =
      either (Left . unwords) Right (objectWith allowed value >>= runV . decode)

-- | @hero@: @{ "src", "alt" | "decorative": true, "focus"? }@. The alt text
-- policy is explicit: exactly one of @alt@ and @decorative@.
heroField :: Json.Value -> Either String HeroMeta
heroField value = do
  obj <- either (Left . unwords) Right (objectWith ["src", "alt", "decorative", "focus"] value)
  let has k = KeyMap.member (Key.fromText k) obj
  either (Left . unwords) Right . runV $
    HeroMeta
      <$> field obj "src" mediaPathField
      <*> V (case (has "alt", has "decorative") of
               (True, True) -> Left ["give either \"alt\" or \"decorative\", not both"]
               (False, False) -> Left ["missing \"alt\" (a short description of the artwork) or \"decorative\": true (atmosphere only)"]
               (True, False) -> runV (HeroDescribed <$> field obj "alt" attributeText)
               (False, True) -> runV (field obj "decorative" decorativeFlag))
      <*> (maybe FocusCenter id <$> optionalField obj "focus" (enum [ (heroFocusName f, f) | f <- [minBound .. maxBound] ]))
  where
    decorativeFlag v =
      case v of
        Json.Bool True -> Right HeroDecorative
        Json.Bool False -> Left "false is not allowed; describe the artwork with \"alt\" instead"
        other -> Left ("expected true, got " <> jsonType other)

-- | @sections@: an object from a body section's id to its presentation.
sectionPlans :: Json.Value -> Either String (Map.Map T.Text SectionPlan)
sectionPlans value =
  case value of
    Json.Object obj ->
      case partitionEithers [ either (Left . ((show k <> ": ") <>)) (Right . (,) k) (sectionPlan v) | (key, v) <- KeyMap.toList obj, let k = Key.toText key ] of
        ([], plans) -> Right (Map.fromList plans)
        (errs, _) -> Left (unwords errs)
    other -> Left ("expected an object from section ids to layouts, got " <> jsonType other)

sectionPlan :: Json.Value -> Either String SectionPlan
sectionPlan value =
  case value of
    Json.Object obj ->
      case KeyMap.lookup "layout" obj of
        Just (Json.String layout) ->
          case layout of
            "overview" -> decodeWith ["facts"] $ \o -> PlanOverview . maybe [] id <$> optionalField o "facts" (list fact)
            "wide-exhibit" -> decodeWith ["artifact"] $ \o -> PlanWideExhibit <$> field o "artifact" artifactField
            "split" -> decodeWith ["artifact", "artifact_side"] $ \o ->
              (\side a -> PlanSplit (maybe ArtifactEnd id side) a)
                <$> optionalField o "artifact_side" (enum [("start", ArtifactStart), ("end", ArtifactEnd)])
                <*> field o "artifact" artifactField
            "grid" -> decodeWith [] (const (pure PlanGrid))
            "resources" -> decodeWith [] (const (pure PlanResources))
            other -> Left ("unknown layout " <> show other <> "; expected one of: " <> T.unpack (T.intercalate ", " (map layoutKindName [minBound .. maxBound])))
        Just other -> Left ("field \"layout\": expected a string, got " <> jsonType other)
        Nothing -> Left "missing required field \"layout\""
    other -> Left ("expected an object, got " <> jsonType other)
  where
    decodeWith extra decode =
      either (Left . unwords) Right $ do
        obj <- objectWith (["layout", "sidebar"] <> extra) value
        runV $ SectionPlan <$> decode obj <*> (maybe True id <$> optionalField obj "sidebar" bool)

fact :: Json.Value -> Either String Fact
fact value = do
  obj <- either (Left . unwords) Right (objectWith ["label", "value"] value)
  either (Left . unwords) Right . runV $ Fact <$> field obj "label" text <*> field obj "value" text

-- | @{ "kind": "image" | "diagram", "src", "alt" }@ or
-- @{ "kind": "code", "src", "label", "language"? }@.
artifactField :: Json.Value -> Either String ArtifactMeta
artifactField value =
  case value of
    Json.Object obj ->
      case KeyMap.lookup "kind" obj of
        Just (Json.String "image") -> decodeWith ["kind", "src", "alt"] $ \o ->
          ImageMeta False <$> field o "src" mediaPathField <*> field o "alt" attributeText
        Just (Json.String "diagram") -> decodeWith ["kind", "src", "alt"] $ \o ->
          ImageMeta True <$> field o "src" mediaPathField <*> field o "alt" attributeText
        Just (Json.String "code") -> decodeWith ["kind", "src", "label", "language"] $ \o ->
          (\src label lang -> CodeMeta label lang src)
            <$> field o "src" mediaPathField <*> field o "label" text <*> optionalField o "language" languageToken
        Just (Json.String other) -> Left ("unsupported artifact kind " <> show other <> "; expected one of: image, diagram, code")
        Just other -> Left ("field \"kind\": expected a string, got " <> jsonType other)
        Nothing -> Left "missing required field \"kind\""
    other -> Left ("expected an object, got " <> jsonType other)
  where
    decodeWith allowed decode =
      either (Left . unwords) Right (objectWith allowed value >>= runV . decode)

-- | A code language name, as used in a @language-…@ class.
languageToken :: Json.Value -> Either String T.Text
languageToken value = do
  raw <- text value
  if T.all (\c -> isAsciiLower c || isDigit c || c `elem` ("+-_" :: String)) raw
    then Right raw
    else Left (show raw <> " may contain only lowercase letters, digits, '+', '-' and '_'")

bool :: Json.Value -> Either String Bool
bool value =
  case value of
    Json.Bool b -> Right b
    other -> Left ("expected true or false, got " <> jsonType other)

-- | Interactive exhibits must name an application this site implements.
-- None exists yet, so every identifier is rejected.
interactiveApp :: Json.Value -> Either String T.Text
interactiveApp value = do
  app <- text value
  Left ("unknown interactive application " <> show app <> " (none are implemented yet)")

isoDate :: Json.Value -> Either String T.Text
isoDate value = do
  raw <- text value
  case T.splitOn "-" raw of
    [y, m, d]
      | T.length y == 4, T.length m == 2, T.length d == 2
      , T.all isDigit (y <> m <> d)
      , inRange 1 12 m, inRange 1 31 d ->
          Right raw
    _ -> Left ("invalid date " <> show raw <> "; expected YYYY-MM-DD")
  where
    inRange lo hi t = let n = read (T.unpack t) :: Int in n >= lo && n <= hi

jsonType :: Json.Value -> String
jsonType value =
  case value of
    Json.Object _ -> "an object"
    Json.Array _ -> "an array"
    Json.String _ -> "a string"
    Json.Number _ -> "a number"
    Json.Bool _ -> "a boolean"
    Json.Null -> "null"
