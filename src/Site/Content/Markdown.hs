-- | Markdown parsing and validation: CommonMark text in, a small validated
-- document out. No HTML is produced here (see "Site.Content.Render").
--
-- The parser is @commonmark@ (commonmark-hs). Instead of its HTML renderer
-- we implement its 'IsInline' / 'IsBlock' classes for our own raw syntax
-- tree, so every construct is seen, and checked, before anything is
-- rendered. Validation then turns the raw tree into 'Document':
--
-- * __Raw HTML is rejected__ (inline and block), with its line number.
-- * __Links__ must be @https://…@, a root-absolute site path @/…@, or a
--   @#fragment@. Anything else (other schemes, @javascript:@ however it is
--   encoded, protocol-relative @//@, relative paths) is rejected, and so are
--   destinations containing whitespace, control characters, quotes, angle
--   brackets, backslashes or backticks. Destinations arrive entity- and
--   escape-decoded from the parser, so encoded schemes are checked in their
--   decoded form. Link titles are dropped.
-- * __Images__ must be relative paths to media files inside the content
--   item's own directory (checked later by the loader) and must have
--   non-empty alt text without straight double quotes (Brigid does not
--   escape @"@ inside attribute values).
-- * __Headings__: the page owns the @<h1>@, so Markdown may use @##@ to
--   @####@ only, at the top level of the document, starting at @##@ and
--   never skipping a level. Each @##@ starts a section (and a sidebar entry).
-- * __Heading ids__ are derived from the heading text by one function
--   ('headingSlug'), de-duplicated in document order against each other
--   and against ids the page already uses.
module Site.Content.Markdown
  ( Document (..)
  , Section (..)
  , Block (..)
  , Inline (..)
  , LinkTarget (..)
  , MarkdownError (..)
  , parseDocument
  , documentImages
  , inlineText
  , headingSlug
  , linkTarget
  ) where

import Commonmark (commonmark)
import Commonmark.Entity (lookupEntity)
import Commonmark.Types
  ( HasAttributes (..)
  , IsBlock (..)
  , IsInline (..)
  , ListType
  , Rangeable (..)
  , SourceRange (..)
  )
import Commonmark.Types qualified as CM
import Data.Char (isAlphaNum, isAscii, isAsciiLower, isControl, isDigit, isSpace, toLower)
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Text.Parsec.Error (errorPos)
import Text.Parsec.Pos (sourceLine)

import Site.Path (OutputPath, mkOutputPath)

--------------------------------------------------------------------------------
-- The validated document

data Document =
  Document
    { documentLead :: [Block]
      -- ^ Content before the first @##@ heading (no sidebar entry).
    , documentSections :: [Section]
    }
  deriving (Eq, Show)

data Section =
  Section
    { sectionId :: T.Text
      -- ^ The id of the section's @<h2>@, which the sidebar links to.
    , sectionHeading :: [Inline]
    , sectionBlocks :: [Block]
    }
  deriving (Eq, Show)

data Block
  = Para [Inline]
  | Plain [Inline]
    -- ^ A tight list item's text (no @<p>@).
  | Heading Int T.Text [Inline]
    -- ^ Level 3 or 4, with its id.
  | BulletList [[Block]]
  | OrderedList Int [[Block]]
  | Quote [Block]
  | CodeBlock (Maybe T.Text) T.Text
    -- ^ Language (validated token) and code, rendered as text.
  | Rule
  deriving (Eq, Show)

data Inline
  = Str T.Text
  | SoftBreak
  | LineBreak
  | Emph [Inline]
  | Strong [Inline]
  | Code T.Text
  | Link LinkTarget [Inline]
  | Image OutputPath T.Text
    -- ^ Media path relative to the content item's directory, and alt text.
  deriving (Eq, Show)

data LinkTarget
  = External T.Text
    -- ^ @https://…@
  | SitePath T.Text
    -- ^ @/…@ (optionally with @#fragment@); checked by the site link validator.
  | Fragment T.Text
    -- ^ @#…@ on the same page; checked by the site link validator.
  deriving (Eq, Show)

data MarkdownError = MarkdownError (Maybe Int) String
  deriving (Eq)

instance Show MarkdownError where
  show (MarkdownError line msg) = maybe "" (\l -> "line " <> show l <> ": ") line <> msg

--------------------------------------------------------------------------------
-- Raw syntax tree (the parser's view)

newtype RInlines = RInlines [RInline]
  deriving (Show)

data RInline
  = RStr T.Text
  | RSoft
  | RHard
  | REmph RInlines
  | RStrong RInlines
  | RLink T.Text RInlines
  | RImage T.Text RInlines
  | RCode T.Text
  | RRaw T.Text
  | RInlineAt SourceRange RInlines
  deriving (Show)

instance Semigroup RInlines where
  RInlines a <> RInlines b = RInlines (a <> b)

instance Monoid RInlines where
  mempty = RInlines []

instance Rangeable RInlines where
  ranged r x = RInlines [RInlineAt r x]

instance HasAttributes RInlines where
  addAttributes _ = id

instance IsInline RInlines where
  lineBreak = one RHard
  softBreak = one RSoft
  str = one . RStr
  entity = one . RStr . decodeEntity
  escapedChar = one . RStr . T.singleton
  emph = one . REmph
  strong = one . RStrong
  link destination _title = one . RLink destination
  image source _title = one . RImage source
  code = one . RCode
  rawInline _ = one . RRaw

newtype RBlocks = RBlocks [RBlock]
  deriving (Show)

data RBlock
  = RPara RInlines
  | RPlain RInlines
  | RRule
  | RQuote RBlocks
  | RCodeBlock T.Text T.Text
  | RHeading Int RInlines
  | RRawBlock T.Text
  | RReference
  | RList ListType [RBlocks]
  | RBlockAt SourceRange RBlocks
  deriving (Show)

instance Semigroup RBlocks where
  RBlocks a <> RBlocks b = RBlocks (a <> b)

instance Monoid RBlocks where
  mempty = RBlocks []

instance Rangeable RBlocks where
  ranged r x = RBlocks [RBlockAt r x]

instance HasAttributes RBlocks where
  addAttributes _ = id

instance IsBlock RInlines RBlocks where
  paragraph = oneB . RPara
  plain = oneB . RPlain
  thematicBreak = oneB RRule
  blockQuote = oneB . RQuote
  codeBlock info = oneB . RCodeBlock info
  heading level = oneB . RHeading level
  rawBlock _ = oneB . RRawBlock
  referenceLinkDefinition _ _ = oneB RReference
  list listType _spacing = oneB . RList listType

one :: RInline -> RInlines
one x = RInlines [x]

oneB :: RBlock -> RBlocks
oneB x = RBlocks [x]

-- | @&amp;@ → @&@, @&#106;@ → @j@; unknown entities stay literal text.
decodeEntity :: T.Text -> T.Text
decodeEntity raw =
  fromMaybe raw (lookupEntity (T.dropWhileEnd (== ';') (T.dropWhile (== '&') raw)))

--------------------------------------------------------------------------------
-- Validation

-- | Errors and a value; errors accumulate, so one run reports every problem.
type Checked a = ([MarkdownError], a)

-- | Parse and validate a Markdown document. @reservedIds@ are element ids
-- the surrounding page already uses; heading ids avoid them.
parseDocument :: FilePath -> [T.Text] -> T.Text -> Either [MarkdownError] Document
parseDocument source reservedIds input =
  case commonmark source input of
    Left parseError -> Left [MarkdownError (Just (sourceLine (errorPos parseError))) (show parseError)]
    Right (RBlocks raw) ->
      let (errs, blocks) = topLevel Nothing raw
          (headingErrs, document) = structure (assignIds reservedIds blocks)
       in case errs <> headingErrs of
            [] -> Right document
            problems -> Left (sortOn (\(MarkdownError line _) -> line) problems)

-- | A top-level block, before sectioning: headings keep their raw level.
data TopBlock = TopHeading (Maybe Int) Int [Inline] | TopBlock Block

topLevel :: Maybe Int -> [RBlock] -> Checked [TopBlock]
topLevel line = foldMap go
  where
    go b =
      case b of
        RBlockAt r (RBlocks inner) -> topLevel (lineOf r line) inner
        RHeading level ils ->
          let (errs, inlines) = checkInlines line ils
              linkErrs = [ err line "links inside headings are not supported" | any hasLink inlines ]
           in (errs <> linkErrs, [TopHeading line level inlines])
        other -> fmap (map TopBlock) (checkBlock line other)

checkBlocks :: Maybe Int -> [RBlock] -> Checked [Block]
checkBlocks line = foldMap (checkBlock line)

checkBlock :: Maybe Int -> RBlock -> Checked [Block]
checkBlock line b =
  case b of
    RBlockAt r (RBlocks inner) -> checkBlocks (lineOf r line) inner
    RPara ils -> single Para (checkInlines line ils)
    RPlain ils -> single Plain (checkInlines line ils)
    RRule -> ([], [Rule])
    RQuote (RBlocks inner) -> single Quote (checkBlocks line inner)
    RCodeBlock info body ->
      let language = T.takeWhile (not . isSpace) (T.strip info)
       in if T.null language || T.all languageChar language
            then ([], [CodeBlock (if T.null language then Nothing else Just (T.toLower language)) body])
            else ([err line ("code block language " <> show language <> " may contain only letters, digits, '+', '-' and '_'")], [])
    RHeading level _ ->
      ([err line ("a level-" <> show level <> " heading inside a list or block quote; headings must be at the top level")], [])
    RRawBlock html -> ([rawHtmlError line html], [])
    RReference -> ([], [])
    RList listType items ->
      let (errs, checked) = foldMap (\(RBlocks inner) -> fmap pure (checkBlocks line inner)) items
       in case listType of
            CM.BulletList _ -> (errs, [BulletList checked])
            CM.OrderedList start _ _ -> (errs, [OrderedList start checked])
  where
    single f (errs, x) = (errs, [f x])
    languageChar c = isAsciiLower c || isDigit c || c `elem` ("+-_" :: String) || (isAscii c && isAlphaNum c)

checkInlines :: Maybe Int -> RInlines -> Checked [Inline]
checkInlines line (RInlines xs) = fmap mergeStr (foldMap (checkInline line) xs)

checkInline :: Maybe Int -> RInline -> Checked [Inline]
checkInline line x =
  case x of
    RInlineAt r inner -> checkInlines (lineOf r line) inner
    RStr t -> ([], [Str t])
    RSoft -> ([], [SoftBreak])
    RHard -> ([], [LineBreak])
    REmph inner -> noLinksIn "emphasis" (fmap (pure . Emph) (checkInlines line inner))
    RStrong inner -> noLinksIn "strong emphasis" (fmap (pure . Strong) (checkInlines line inner))
    RCode t -> ([], [Code t])
    RRaw html -> ([rawHtmlError line html], [])
    RLink destination inner ->
      let (errs, label) = checkInlines line inner
          imageErrs = [ err line ("link " <> show destination <> " wraps an image; images inside links are not supported") | any isImage label ]
       in case linkTarget destination of
            Left why -> (err line why : errs <> imageErrs, [])
            Right target -> (errs <> imageErrs, [Link target label])
    RImage source inner ->
      let (errs, altInlines) = checkInlines line inner
          alt = T.strip (inlineText altInlines)
          altErrs =
            [ err line ("image " <> show source <> " has no alt text; describe the image in ![…]") | T.null alt ]
              -- Alt text becomes an attribute, and Brigid does not escape
              -- '"' in attribute values: refuse it (typographic quotes are fine).
              <> [ err line ("image " <> show source <> ": alt text must not contain a straight double quote (\"); use “ ” instead") | T.any (== '"') alt ]
       in case imagePath source of
            Left why -> (err line why : errs <> altErrs, [])
            Right path -> (errs <> altErrs, [Image path alt])
  where
    noLinksIn what (errs, result)
      | any (any hasLink . children) result =
          (errs <> [err line ("a link inside " <> what <> " is not supported; put the emphasis inside or around the link text instead")], result)
      | otherwise = (errs, result)
    children i = case i of Emph xs -> xs; Strong xs -> xs; _ -> []

-- | Does inline content contain a link (at any depth)?
hasLink :: Inline -> Bool
hasLink i =
  case i of
    Link _ _ -> True
    Emph xs -> any hasLink xs
    Strong xs -> any hasLink xs
    _ -> False

isImage :: Inline -> Bool
isImage i =
  case i of
    Image _ _ -> True
    Emph xs -> any isImage xs
    Strong xs -> any isImage xs
    _ -> False

rawHtmlError :: Maybe Int -> T.Text -> MarkdownError
rawHtmlError line html =
  err line ("raw HTML is not allowed in Markdown content: " <> show (T.take 60 (T.strip html)))

err :: Maybe Int -> String -> MarkdownError
err = MarkdownError

lineOf :: SourceRange -> Maybe Int -> Maybe Int
lineOf (SourceRange ranges) fallback =
  maybe fallback (Just . sourceLine . fst) (listToMaybe ranges)

mergeStr :: [Inline] -> [Inline]
mergeStr (Str a : Str b : rest) = mergeStr (Str (a <> b) : rest)
mergeStr (x : rest) = x : mergeStr rest
mergeStr [] = []

-- | The documented URL policy for Markdown links.
linkTarget :: T.Text -> Either String LinkTarget
linkTarget destination
  | T.null destination = Left "empty link destination"
  | T.any unsafeChar destination =
      Left ("link " <> show destination <> " contains whitespace, a control character, a quote, an angle bracket, a backslash or a backtick")
  | Just rest <- T.stripPrefix "https://" destination =
      if T.null (T.takeWhile (`notElem` ("/?#" :: String)) rest)
        then Left ("link " <> show destination <> " has no host")
        else Right (External destination)
  | "//" `T.isPrefixOf` destination = Left ("link " <> show destination <> " is protocol-relative; use https://")
  | "/" `T.isPrefixOf` destination = Right (SitePath destination)
  | Just fragment <- T.stripPrefix "#" destination =
      if T.null fragment then Left "empty #fragment link" else Right (Fragment fragment)
  | otherwise =
      Left ("link " <> show destination <> " is not allowed: use https://…, a site path starting with /, or a #fragment")

unsafeChar :: Char -> Bool
unsafeChar c = isSpace c || isControl c || c `elem` ("\"'<>\\`" :: String)

-- | Images: a relative media path inside the content item's directory.
imagePath :: T.Text -> Either String OutputPath
imagePath source =
  case mkOutputPath (T.unpack source) of
    Left why -> Left ("image " <> show source <> " must be a relative path to a media file in this content directory: " <> show why)
    Right path -> Right path

-- | Plain text of inline content (for ids, alt text and labels).
inlineText :: [Inline] -> T.Text
inlineText = foldMap go
  where
    go i =
      case i of
        Str t -> t
        SoftBreak -> " "
        LineBreak -> " "
        Emph xs -> inlineText xs
        Strong xs -> inlineText xs
        Code t -> t
        Link _ xs -> inlineText xs
        Image _ alt -> alt

-- | The id for a heading's text: lowercase letters and digits (any script),
-- other characters collapsed to single hyphens, trimmed; @section@ if
-- nothing is left.
headingSlug :: T.Text -> T.Text
headingSlug text =
  case T.intercalate "-" (filter (not . T.null) (T.split (== '-') (T.map keep (T.toLower text)))) of
    "" -> "section"
    slug -> slug
  where
    keep c = if isAlphaNum c then toLower c else '-'

-- | Give every heading a unique id, in document order: the slug, or the
-- slug with @-2@, @-3@, … if it is already taken (by an earlier heading or
-- by the page).
assignIds :: [T.Text] -> [TopBlock] -> [(Maybe Int, Either (Int, T.Text, [Inline]) Block)]
assignIds reserved = snd . foldl' step (Set.fromList reserved, [])
  where
    step (taken, acc) top =
      case top of
        TopBlock b -> (taken, acc <> [(Nothing, Right b)])
        TopHeading line level inlines ->
          let base = headingSlug (inlineText inlines)
              candidates = base : [ base <> "-" <> T.pack (show n) | n <- [2 :: Int ..] ]
              ident = case filter (`Set.notMember` taken) candidates of
                (free : _) -> free
                [] -> base -- unreachable: the candidate list is infinite
           in (Set.insert ident taken, acc <> [(line, Left (level, ident, inlines))])

-- | Check heading levels and split the document into sections.
structure :: [(Maybe Int, Either (Int, T.Text, [Inline]) Block)] -> Checked Document
structure items = (levelErrors, Document lead (reverse (map finish sections)))
  where
    levelErrors = snd (foldl' checkLevel (1, []) [ (line, level) | (line, Left (level, _, _)) <- items ])

    checkLevel (previous, errs) (line, level)
      | level == 1 =
          (previous, errs <> [err line "a level-1 heading (#): the page already has its title; start sections at ##"])
      | level > 4 =
          (previous, errs <> [err line ("a level-" <> show level <> " heading: use ## to #### only")])
      | level > previous + 1 =
          (level, errs <> [err line ("a level-" <> show level <> " heading follows a level-" <> show previous <> " heading; do not skip levels" <> (if previous == 1 then " (start at ##)" else ""))])
      | otherwise = (level, errs)

    (lead, sections) = foldl' place ([], []) items

    place (leadAcc, secs) (_, item) =
      case (item, secs) of
        (Left (2, ident, inlines), _) -> (leadAcc, (ident, inlines, []) : secs)
        (Left (level, ident, inlines), []) -> (leadAcc <> [Heading level ident inlines], [])
        (Left (level, ident, inlines), (sid, sh, body) : rest) -> (leadAcc, (sid, sh, body <> [Heading level ident inlines]) : rest)
        (Right b, []) -> (leadAcc <> [b], [])
        (Right b, (sid, sh, body) : rest) -> (leadAcc, (sid, sh, body <> [b]) : rest)

    finish (sid, sh, body) = Section sid sh body

-- | Every image the document references (to validate and publish).
documentImages :: Document -> [OutputPath]
documentImages (Document lead sections) =
  Map.keys (Map.fromList [ (p, ()) | p <- concatMap blockImages (lead <> concatMap sectionAll sections) ])
  where
    sectionAll s = Para (sectionHeading s) : sectionBlocks s
    blockImages b =
      case b of
        Para xs -> inlineImages xs
        Plain xs -> inlineImages xs
        Heading _ _ xs -> inlineImages xs
        BulletList items -> concatMap (concatMap blockImages) items
        OrderedList _ items -> concatMap (concatMap blockImages) items
        Quote bs -> concatMap blockImages bs
        CodeBlock _ _ -> []
        Rule -> []
    inlineImages = concatMap inlineImage
    inlineImage i =
      case i of
        Image p _ -> [p]
        Emph xs -> inlineImages xs
        Strong xs -> inlineImages xs
        Link _ xs -> inlineImages xs
        _ -> []
