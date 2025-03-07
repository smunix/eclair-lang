
{-# LANGUAGE TypeFamilies, RankNTypes, QuasiQuotes #-}
module Test.Eclair.AST.LowerSpec
  ( module Test.Eclair.AST.LowerSpec
  ) where

import qualified Data.Text as T
import Eclair
import qualified Eclair.RA.IR as RA
import Eclair.Pretty
import System.FilePath
import Test.Hspec
import NeatInterpolation
import Eclair.Parser
import Eclair.TypeSystem
import Eclair.AST.Lower


cg :: FilePath -> IO T.Text
cg path = do
  let file = "tests/fixtures" </> path <.> "dl"
  ra <- compileRA file
  pure $ printDoc ra

resultsIn :: IO T.Text -> T.Text -> IO ()
resultsIn action output = do
  result <- action
  result `shouldBe` T.strip output

spec :: Spec
spec = describe "RA Code Generation" $ parallel $ do
  it "generates nothing for empty file" $ do
    cg "empty" `resultsIn` ""

  it "generates code for a single fact" $ do
    cg "single_fact" `resultsIn` [text|
      project (1, 2, 3) into another
      project (2, 3) into edge
      project (1, 2) into edge
      |]

  it "generates code for a single non-recursive rule" $ do
    cg "single_nonrecursive_rule" `resultsIn` [text|
      project (1, 2) into edge
      search edge as edge0 do
        project (edge0[0], edge0[1]) into path
      |]

  it "generates nested searches correctly" $ do
    cg "multiple_rule_clauses" `resultsIn` [text|
      project (2, 3) into second
      project (1) into first
      search first as first0 do
        search second as second1 where (second1[1] = first0[0]) do
          project (second1[0], first0[0]) into third
      |]

  it "generates code for a rule with 2 clauses of same name" $ do
    cg "multiple_clauses_same_name" `resultsIn` [text|
      project (1, 2) into link
      search link as link0 do
        search link as link1 where (link1[0] = link0[1]) do
          project (link0[0], link0[1], link1[1]) into chain
      |]

  it "generates code for a rule where columns need to equal each other" $
    cg "clause_with_same_vars" `resultsIn` [text|
      search c as c0 where (c0[2] = 42) do
        search other as other1 where (other1[0] = c0[0]) do
          if c0[0] = c0[4] do
            if c0[0] = c0[1] do
              project (c0[0]) into a
      search b as b0 do
        search other as other1 where (other1[0] = b0[0]) do
          if b0[0] = b0[1] do
            project (b0[0]) into a
      |]

  it "generates code for a rule containing an equality statement" $ do
    cg "assignment" `resultsIn` [text|
      search fact1 as fact10 do
        if 123 = fact10[1] do
          project (fact10[1], fact10[0]) into fact2
      search fact1 as fact10 do
        search fact1 as fact11 where (fact11[1] = fact10[0]) do
          if fact10[1] = fact10[0] do
            if fact11[0] = 123 do
              project (fact10[0], 1) into fact2
      |]

  it "generates code for a single recursive rule" $ do
    cg "single_recursive_rule" `resultsIn` [text|
      project (1, 2) into edge
      merge path delta_path
      loop do
        purge new_path
        search edge as edge0 do
          search delta_path as delta_path1 where (delta_path1[0] = edge0[1] and (edge0[0], delta_path1[1]) ∉ path) do
            project (edge0[0], delta_path1[1]) into new_path
        exit if counttuples(new_path) = 0
        merge new_path path
        swap new_path delta_path
      |]

  -- TODO variant where one is recursive
  it "generates code for mutually recursive rules" $ do
    cg "mutually_recursive_rules" `resultsIn` [text|
      project (3) into d
      project (2) into c
      project (1) into b
      merge c delta_c
      merge b delta_b
      loop do
        purge new_c
        purge new_b
        parallel do
          search b as b0 do
            search d as d1 where (d1[0] = b0[0] and (b0[0]) ∉ c) do
              project (b0[0]) into new_c
          search c as c0 do
            search d as d1 where (d1[0] = c0[0] and (c0[0]) ∉ b) do
              project (c0[0]) into new_b
        exit if counttuples(new_c) = 0 and counttuples(new_b) = 0
        merge new_c c
        swap new_c delta_c
        merge new_b b
        swap new_b delta_b
      search b as b0 do
        search c as c1 where (c1[0] = b0[0]) do
          project (b0[0]) into a
      |]

  -- TODO tests for rules with >2 clauses, ...

  it "generates code for program without top level facts" $
    cg "no_top_level_facts" `resultsIn` [text|
      search edge as edge0 do
        project (edge0[0], edge0[1]) into path
      merge path delta_path
      loop do
        purge new_path
        search edge as edge0 do
          search delta_path as delta_path1 where (delta_path1[0] = edge0[1] and (edge0[0], delta_path1[1]) ∉ path) do
            project (edge0[0], delta_path1[1]) into new_path
        exit if counttuples(new_path) = 0
        merge new_path path
        swap new_path delta_path
      |]
