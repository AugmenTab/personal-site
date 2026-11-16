-- | The project taxonomy (README "Taxonomy"): a small, controlled
-- vocabulary, so that cards, search, filters and dossiers all describe a
-- project in the same canonical words.
--
-- * A __category__ is a project's one primary classification. It drives
--   the Work index's filter chips and the card and dossier kicker.
-- * __Topics__ are broader subjects that cut across categories (a project
--   may have several). They are searchable and shown on the dossier.
-- * __Technologies__ stay free text in @project.json@ (concrete languages,
--   frameworks and tools), validated for duplicates and for topics filed
--   in the wrong list (see "Site.Content.Load").
--
-- @project.json@ names categories and topics by their ids (e.g.
-- @"libraries-tooling"@, @"type-systems"@); the labels are defined here
-- and nowhere else. To add a category or topic, add a constructor and its
-- id and label below; nothing else needs to change. There are no
-- hierarchies or synonyms.
module Site.Taxonomy
  ( -- * Categories
    Category (..)
  , categoryId
  , categoryLabel
  , allCategories
  , parseCategory
    -- * Topics
  , Topic (..)
  , topicId
  , topicLabel
  , allTopics
  , parseTopic
  ) where

import Data.Text qualified as T

-- | Primary classifications, in display (filter chip) order.
data Category
  = ProgrammingLanguages
  | LibrariesTooling
  | AIAutomation
  | SimulationGames
  | CreativeTechnology
  deriving (Eq, Ord, Show, Bounded, Enum)

allCategories :: [Category]
allCategories = [minBound .. maxBound]

categoryId :: Category -> T.Text
categoryId category =
  case category of
    ProgrammingLanguages -> "programming-languages"
    LibrariesTooling -> "libraries-tooling"
    AIAutomation -> "ai-automation"
    SimulationGames -> "simulation-games"
    CreativeTechnology -> "creative-technology"

categoryLabel :: Category -> T.Text
categoryLabel category =
  case category of
    ProgrammingLanguages -> "Programming Languages"
    LibrariesTooling -> "Libraries & Tooling"
    AIAutomation -> "AI & Automation"
    SimulationGames -> "Simulation & Games"
    CreativeTechnology -> "Creative Technology"

parseCategory :: T.Text -> Either String Category
parseCategory raw =
  case [ c | c <- allCategories, categoryId c == raw ] of
    [c] -> Right c
    _ ->
      Left ( "invalid value " <> show raw <> "; expected one of: "
               <> T.unpack (T.intercalate ", " (map categoryId allCategories))
               <> " (categories are a controlled vocabulary; see README \"Taxonomy\")" )

-- | Cross-cutting subjects, in display order.
data Topic
  = TypeSystems
  | CompilerEngineering
  | FormalVerification
  | WebDevelopment
  | AIAgents
  | DeterministicSimulation
  | GameEngines
  | AudioEngineering
  deriving (Eq, Ord, Show, Bounded, Enum)

allTopics :: [Topic]
allTopics = [minBound .. maxBound]

topicId :: Topic -> T.Text
topicId topic =
  case topic of
    TypeSystems -> "type-systems"
    CompilerEngineering -> "compiler-engineering"
    FormalVerification -> "formal-verification"
    WebDevelopment -> "web-development"
    AIAgents -> "ai-agents"
    DeterministicSimulation -> "deterministic-simulation"
    GameEngines -> "game-engines"
    AudioEngineering -> "audio-engineering"

topicLabel :: Topic -> T.Text
topicLabel topic =
  case topic of
    TypeSystems -> "Type Systems"
    CompilerEngineering -> "Compiler Engineering"
    FormalVerification -> "Formal Verification"
    WebDevelopment -> "Web Development"
    AIAgents -> "AI Agents"
    DeterministicSimulation -> "Deterministic Simulation"
    GameEngines -> "Game Engines"
    AudioEngineering -> "Audio Engineering"

parseTopic :: T.Text -> Either String Topic
parseTopic raw =
  case [ t | t <- allTopics, topicId t == raw ] of
    [t] -> Right t
    _ ->
      Left ( "unknown topic " <> show raw <> "; expected one of: "
               <> T.unpack (T.intercalate ", " (map topicId allTopics)) )
