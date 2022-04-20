{-# LANGUAGE RoleAnnotations, PolyKinds #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Eclair.LLVM.LLVM
  ( module Eclair.LLVM.LLVM
  ) where

import Control.Monad.Morph
import qualified Data.Text as T
import LLVM.IRBuilder.Module
import LLVM.IRBuilder.Monad
import qualified LLVM.AST.Constant as Constant
import LLVM.AST.Operand ( Operand(..) )
import LLVM.AST.Type
import LLVM.AST.Name
import LLVM.Internal.EncodeAST
import LLVM.Internal.Coding hiding (alloca)
import LLVM.Internal.Type
import qualified LLVM.Context as Context
import qualified LLVM.Internal.DataLayout as DL
import qualified LLVM.Internal.FFI.DataLayout as DL
import qualified LLVM.CodeGenOpt as CG
import qualified LLVM.CodeModel as CM
import qualified LLVM.Relocation as Rel
import LLVM.Target
import Eclair.LLVM.Runtime


-- TODO: remove, import directly from llvm-hs
int16 :: Integer -> Operand
int16 = ConstantOperand . Constant.Int 16

nullPtr :: Type -> Operand
nullPtr = ConstantOperand . Constant.Null . ptr

def :: (MonadModuleBuilder m, MonadReader r m, HasSuffix r)
    => Text
    -> [(Type, ParameterName)]
    -> Type
    -> ([Operand] -> IRBuilderT m ())
    -> m Operand
def funcName args retTy body = do
  s <- asks (show . getSuffix)
  let funcNameWithHash = mkName $ toString $ funcName <> "_" <> s
  function funcNameWithHash args retTy body

mkType :: (MonadModuleBuilder m, MonadReader r m, HasSuffix r)
       => Text -> Type -> m Type
mkType typeName ty = do
  s <- asks (show . getSuffix)
  let typeNameWithHash = mkName $ toString $ typeName <> "_" <> s
  typedef typeNameWithHash (Just ty)

sizeOfType :: (Name, Type) -> ModuleBuilderT IO Word64
sizeOfType (n, ty) = do
  liftIO $ withHostTargetMachine Rel.PIC CM.Default CG.None $ \tm -> do
    dl <- getTargetMachineDataLayout tm
    Context.withContext $ flip runEncodeAST $ do
      createType
      ty' <- encodeM ty
      liftIO $ DL.withFFIDataLayout dl $ flip DL.getTypeAllocSize ty'
  where
    createType :: EncodeAST ()
    createType = do
      (t', n') <- createNamedType n
      defineType n n' t'
      setNamedType t' ty

-- NOTE: Orphan instance, but should give no conflicts.
instance MFunctor ModuleBuilderT where
  hoist nat = ModuleBuilderT . hoist nat . unModuleBuilderT

-- NOTE: Orphan instance, but should give no conflicts.
instance MFunctor IRBuilderT where
  hoist nat = IRBuilderT . hoist nat . unIRBuilderT

