{-# LANGUAGE UndecidableInstances #-}

module Eclair.AST.Analysis
  ( UngroundedVar(..)
  , Result(..)
  , runAnalysis
  ) where

import qualified Language.Souffle.Interpreted as S
import qualified Language.Souffle.Analysis as S
import qualified Eclair.AST.IR as IR
import Eclair.Id
import Data.Kind
import Data.Functor.Foldable


type NodeId = IR.NodeId

-- The facts submitted to Datalog closely follow the AST structure,
-- but are denormalized so that Datalog can easily process it.

data Lit
  = Lit NodeId IR.Number
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Lit "literal" 'S.Input

data Var
  = Var NodeId Id
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Var "variable" 'S.Input

data Atom
  = Atom NodeId Id
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Atom "atom" 'S.Input

data AtomArg
  = AtomArg { atomId :: NodeId, atomArgPos :: Word32, atomArgId :: NodeId }
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions AtomArg "atom_arg" 'S.Input

data Rule
  = Rule NodeId Id
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Rule "rule" 'S.Input

data RuleArg
  = RuleArg { raRuleId :: NodeId, raArgPos :: Word32, raArgId :: NodeId }
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Rule "rule_arg" 'S.Input

data RuleClause
  = RuleClause { rcRuleId :: NodeId, rcClausePos :: Word32, rcClauseId :: NodeId }
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Rule "rule_clause" 'S.Input

-- NOTE: not storing types right now, but might be useful later?
data DeclareType
  = DeclareType NodeId Id
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions DeclareType "declare_type" 'S.Input

newtype Module
  = Module NodeId
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Module "module" 'S.Input

data ModuleDecl
  = ModuleDecl { moduleId :: NodeId, declId :: NodeId }
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions ModuleDecl "module_declaration" 'S.Input

data UngroundedVar
  = UngroundedVar NodeId Id
  deriving stock (Generic, Eq, Show)
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions UngroundedVar "ungrounded_variable" 'S.Output

data SemanticAnalysis
  = SemanticAnalysis
  deriving S.Program
  via S.ProgramOptions SemanticAnalysis "semantic_analysis"
      '[ Lit
       , Var
       , Atom
       , AtomArg
       , Rule
       , RuleArg
       , RuleClause
       , DeclareType
       , Module
       , ModuleDecl
       , UngroundedVar
       ]

-- TODO: change to Vector when finished for performance?
type Container = []

newtype Result
  = Result (Container UngroundedVar)
  deriving (Eq, Show)
  -- TODO add other results


analysis :: S.Handle SemanticAnalysis -> S.Analysis S.SouffleM IR.AST Result
analysis prog = S.mkAnalysis addFacts run getFacts
  where
    addFacts :: IR.AST -> S.SouffleM ()
    addFacts = zygo getNodeId $ \case
      IR.LitF nodeId lit ->
        S.addFact prog $ Lit nodeId lit
      IR.VarF nodeId var ->
        S.addFact prog $ Var nodeId var
      IR.AtomF nodeId atom (unzip -> (argNodeIds, actions)) -> do
        S.addFact prog $ Atom nodeId atom
        S.addFacts prog $ mapWithPos (AtomArg nodeId) argNodeIds
        sequence_ actions
      IR.RuleF nodeId rule ruleArgs ruleClauses -> do
        let (argNodeIds, argActions) = unzip ruleArgs
            (clauseNodeIds, clauseActions) = unzip ruleClauses
        S.addFact prog $ Rule nodeId rule
        S.addFacts prog $ mapWithPos (RuleArg nodeId) argNodeIds
        S.addFacts prog $ mapWithPos (RuleClause nodeId) clauseNodeIds
        sequence_ argActions
        sequence_ clauseActions
      IR.DeclareTypeF nodeId ty _ ->
        S.addFact prog $ DeclareType nodeId ty
      IR.ModuleF nodeId (unzip -> (declNodeIds, actions)) -> do
        S.addFact prog $ Module nodeId
        S.addFacts prog $ map (ModuleDecl nodeId) declNodeIds
        sequence_ actions

    run :: S.SouffleM ()
    run = do
      -- TODO: optimal CPU core count? just use all cores?
      S.setNumThreads prog 8
      S.run prog

    getFacts :: S.SouffleM Result
    getFacts = Result <$> S.getFacts prog

    getNodeId :: IR.ASTF NodeId -> NodeId
    getNodeId = \case
      IR.LitF nodeId _ -> nodeId
      IR.VarF nodeId _ -> nodeId
      IR.AtomF nodeId _ _ -> nodeId
      IR.RuleF nodeId _ _ _ -> nodeId
      IR.DeclareTypeF nodeId _ _ -> nodeId
      IR.ModuleF nodeId _ -> nodeId

    mapWithPos :: (Word32 -> a -> b) -> [a] -> [b]
    mapWithPos g = zipWith g [0..]

runAnalysis :: IR.AST -> IO Result
runAnalysis ast = S.runSouffle SemanticAnalysis $ \case
  Nothing -> panic "Failed to load Souffle during semantic analysis!"
  Just prog -> S.execAnalysis (analysis prog) ast

