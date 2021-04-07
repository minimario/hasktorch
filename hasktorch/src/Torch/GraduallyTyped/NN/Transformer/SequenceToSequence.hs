{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fplugin TypeLevel.Rewrite
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyRightAssociativeL
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL2
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL2C
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL3
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL3C
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL4
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL4C
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL5
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL5C
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL6
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL6C
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL7
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL7C
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL8
                -fplugin-opt=TypeLevel.Rewrite:Torch.GraduallyTyped.Unify.UnifyIdempotenceL8C #-}
{-# OPTIONS_GHC -v2 #-}

module Torch.GraduallyTyped.NN.Transformer.SequenceToSequence where

import Control.Monad.Indexed (ireturn, (>>>=))
import Control.Monad.Indexed.State (IxState (..))
import Control.Monad.Reader (MonadIO, MonadReader)
import Control.Monad.State.Strict (MonadState (state), runState)
import Data.Kind (Constraint, Type)
import Data.Singletons (SingI, sing)
import GHC.TypeLits (Nat, Symbol, type (<=?))
import Torch.DType (DType (..))
import Torch.GraduallyTyped.DType (DataType (..), KnownDataType, WithDataTypeC (..))
import Torch.GraduallyTyped.Device (Device (..), DeviceType (..), KnownDevice, WithDeviceC (..))
import Torch.GraduallyTyped.Layout (Layout (..), LayoutType (..))
import Torch.GraduallyTyped.NN.Class (HasForward (..), HasInitialize (..))
import Torch.GraduallyTyped.NN.Linear (HasInitializeLinearWithoutBiasC, Linear (..))
import Torch.GraduallyTyped.NN.Sparse (Embedding (..), HasInitializeEmbeddingC)
import Torch.GraduallyTyped.NN.Transformer.Decoder (HasInitializeTransformerDecoderC, TransformerDecoder, lookupDecoder)
import Torch.GraduallyTyped.NN.Transformer.DecoderStack (HasLookupDecoderStack)
import Torch.GraduallyTyped.NN.Transformer.Encoder (HasInitializeTransformerEncoderC, TransformerEncoder, lookupEncoder)
import Torch.GraduallyTyped.NN.Transformer.Stack (HasLookupStack)
import Torch.GraduallyTyped.NN.Transformer.Type (STransformerStyle (..), TensorDict, TransformerStyle (..), lookupTensor)
import Torch.GraduallyTyped.NN.Type (HasBias (..))
import Torch.GraduallyTyped.Random (Generator)
import Torch.GraduallyTyped.RequiresGradient (RequiresGradient (..))
import Torch.GraduallyTyped.Scalar (Scalar)
import Torch.GraduallyTyped.Shape.Class (BroadcastShapesF)
import Torch.GraduallyTyped.Shape.Type (Dim (..), KnownDim (..), Name (..), Shape (..), Size (..), WithDimC (..))
import Torch.GraduallyTyped.Tensor.Creation (WithCreateC (..), zeros)
import Torch.GraduallyTyped.Tensor.MathOperations.Pointwise (add, divScalar, mulScalar)
import Torch.GraduallyTyped.Tensor.Type (Tensor)
import Torch.GraduallyTyped.Unify (type (<+>))

-- | Sequence-to-sequence transformer model.
data
  SequenceToSequenceTransformer
    (numEncoderLayers :: Nat)
    (numDecoderLayers :: Nat)
    (style :: TransformerStyle)
    (device :: Device (DeviceType Nat))
    (dataType :: DataType DType)
    (headDim :: Dim (Name Symbol) (Size Nat))
    (headEmbedDim :: Dim (Name Symbol) (Size Nat))
    (embedDim :: Dim (Name Symbol) (Size Nat))
    (inputEmbedDim :: Dim (Name Symbol) (Size Nat))
    (ffnDim :: Dim (Name Symbol) (Size Nat))
    (posEncDim :: Dim (Name Symbol) (Size Nat))
    (vocabDim :: Dim (Name Symbol) (Size Nat))
    (dropoutP :: Type)
  where
  SequenceToSequenceTransformer ::
    forall numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP.
    { -- | encoder
      seqToSeqEncoder :: TransformerEncoder numEncoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim dropoutP,
      -- | decoder
      seqToSeqDecoder :: TransformerDecoder numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim inputEmbedDim ffnDim posEncDim dropoutP,
      -- | shared embedding
      --
      -- TODO: Generalize this so that models with embeddings that are sensitive to the padding idx can be supported, e.g. @'Just 0@.
      seqToSeqEmbedding :: Embedding ('Layout 'Dense) device dataType vocabDim inputEmbedDim 'Nothing,
      -- | input embedding dim for scaling
      seqToSeqInputEmbedDim :: Dim String Integer
    } ->
    SequenceToSequenceTransformer numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP

data
  GSequenceToSequenceTransformerWithLMHead
    (seqToSeqTransformer :: Type)
    (seqToSeqLMHead :: Type)
    (seqToSeqFinalLogitsBias :: Type)
  where
  GSequenceToSequenceTransformerWithLMHead ::
    forall seqToSeqTransformer seqToSeqLMHead seqToSeqFinalLogitsBias.
    { -- | sequence-to-sequence transformer
      seqToSeqTransformer :: seqToSeqTransformer,
      -- | language modelling head
      seqToSeqLMHead :: seqToSeqLMHead,
      -- | language modelling head
      seqToSeqFinalLogitsBias :: seqToSeqFinalLogitsBias
    } ->
    GSequenceToSequenceTransformerWithLMHead seqToSeqTransformer seqToSeqLMHead seqToSeqFinalLogitsBias

-- | Sequence-to-sequence transformer model with language modelling head.
data
  SequenceToSequenceTransformerWithLMHead
    (numEncoderLayers :: Nat)
    (numDecoderLayers :: Nat)
    (style :: TransformerStyle)
    (device :: Device (DeviceType Nat))
    (dataType :: DataType DType)
    (headDim :: Dim (Name Symbol) (Size Nat))
    (headEmbedDim :: Dim (Name Symbol) (Size Nat))
    (embedDim :: Dim (Name Symbol) (Size Nat))
    (inputEmbedDim :: Dim (Name Symbol) (Size Nat))
    (ffnDim :: Dim (Name Symbol) (Size Nat))
    (posEncDim :: Dim (Name Symbol) (Size Nat))
    (vocabDim :: Dim (Name Symbol) (Size Nat))
    (dropoutP :: Type)
  where
  SequenceToSequenceTransformerWithLMHead ::
    forall numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP.
    GSequenceToSequenceTransformerWithLMHeadF numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP ->
    SequenceToSequenceTransformerWithLMHead numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP

type GSequenceToSequenceTransformerWithLMHeadF
  (numEncoderLayers :: Nat)
  (numDecoderLayers :: Nat)
  (style :: TransformerStyle)
  (device :: Device (DeviceType Nat))
  (dataType :: DataType DType)
  (headDim :: Dim (Name Symbol) (Size Nat))
  (headEmbedDim :: Dim (Name Symbol) (Size Nat))
  (embedDim :: Dim (Name Symbol) (Size Nat))
  (inputEmbedDim :: Dim (Name Symbol) (Size Nat))
  (ffnDim :: Dim (Name Symbol) (Size Nat))
  (posEncDim :: Dim (Name Symbol) (Size Nat))
  (vocabDim :: Dim (Name Symbol) (Size Nat))
  (dropoutP :: Type) =
  GSequenceToSequenceTransformerWithLMHead
    (SeqToSeqTransformerF numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP)
    (SeqToSeqLMHeadF style device dataType inputEmbedDim vocabDim)
    (SeqToSeqFinalLogitsBiasF style device dataType vocabDim)

type family
  SeqToSeqTransformerF
    (numEncoderLayers :: Nat)
    (numDecoderLayers :: Nat)
    (style :: TransformerStyle)
    (device :: Device (DeviceType Nat))
    (dataType :: DataType DType)
    (headDim :: Dim (Name Symbol) (Size Nat))
    (headEmbedDim :: Dim (Name Symbol) (Size Nat))
    (embedDim :: Dim (Name Symbol) (Size Nat))
    (inputEmbedDim :: Dim (Name Symbol) (Size Nat))
    (ffnDim :: Dim (Name Symbol) (Size Nat))
    (posEncDim :: Dim (Name Symbol) (Size Nat))
    (vocabDim :: Dim (Name Symbol) (Size Nat))
    (dropoutP :: Type) ::
    Type
  where
  SeqToSeqTransformerF numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP = SequenceToSequenceTransformer numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP

type family
  SeqToSeqLMHeadF
    (style :: TransformerStyle)
    (device :: Device (DeviceType Nat))
    (dataType :: DataType DType)
    (inputEmbedDim :: Dim (Name Symbol) (Size Nat))
    (vocabDim :: Dim (Name Symbol) (Size Nat)) ::
    Type
  where
  SeqToSeqLMHeadF 'T5 device dataType inputEmbedDim vocabDim = Linear 'WithoutBias device dataType inputEmbedDim vocabDim
  SeqToSeqLMHeadF 'Pegasus device dataType inputEmbedDim vocabDim = Linear 'WithoutBias device dataType inputEmbedDim vocabDim

type family
  SeqToSeqFinalLogitsBiasF
    (style :: TransformerStyle)
    (device :: Device (DeviceType Nat))
    (dataType :: DataType DType)
    (vocabDim :: Dim (Name Symbol) (Size Nat)) ::
    Type
  where
  SeqToSeqFinalLogitsBiasF 'T5 device dataType vocabDim = ()
  SeqToSeqFinalLogitsBiasF 'Pegasus device dataType vocabDim = Tensor 'WithGradient ('Layout 'Dense) device dataType ('Shape '[ 'Dim ('Name "*") ('Size 1), vocabDim])

type HasInitializeSequenceToSequenceTransformerC
  (transformer :: Type)
  (device :: Device (DeviceType Nat))
  (dataType :: DataType DType)
  (headDim :: Dim (Name Symbol) (Size Nat))
  (headEmbedDim :: Dim (Name Symbol) (Size Nat))
  (embedDim :: Dim (Name Symbol) (Size Nat))
  (inputEmbedDim :: Dim (Name Symbol) (Size Nat))
  (ffnDim :: Dim (Name Symbol) (Size Nat))
  (posEncDim :: Dim (Name Symbol) (Size Nat))
  (vocabDim :: Dim (Name Symbol) (Size Nat))
  (dropoutP :: Type) =
  ( WithDeviceC device (WithDataTypeF dataType (WithDimF headDim (WithDimF headEmbedDim (WithDimF embedDim (WithDimF inputEmbedDim (WithDimF ffnDim (WithDimF posEncDim (WithDimF vocabDim (dropoutP -> Double -> Generator device -> (transformer, Generator device)))))))))),
    WithDataTypeC dataType (WithDimF headDim (WithDimF headEmbedDim (WithDimF embedDim (WithDimF inputEmbedDim (WithDimF ffnDim (WithDimF posEncDim (WithDimF vocabDim (dropoutP -> Double -> Generator device -> (transformer, Generator device))))))))),
    WithDimC headDim (WithDimF headEmbedDim (WithDimF embedDim (WithDimF inputEmbedDim (WithDimF ffnDim (WithDimF posEncDim (WithDimF vocabDim (dropoutP -> Double -> Generator device -> (transformer, Generator device)))))))),
    WithDimC headEmbedDim (WithDimF embedDim (WithDimF inputEmbedDim (WithDimF ffnDim (WithDimF posEncDim (WithDimF vocabDim (dropoutP -> Double -> Generator device -> (transformer, Generator device))))))),
    WithDimC embedDim (WithDimF inputEmbedDim (WithDimF ffnDim (WithDimF posEncDim (WithDimF vocabDim (dropoutP -> Double -> Generator device -> (transformer, Generator device)))))),
    WithDimC inputEmbedDim (WithDimF ffnDim (WithDimF posEncDim (WithDimF vocabDim (dropoutP -> Double -> Generator device -> (transformer, Generator device))))),
    WithDimC ffnDim (WithDimF posEncDim (WithDimF vocabDim (dropoutP -> Double -> Generator device -> (transformer, Generator device)))),
    WithDimC posEncDim (WithDimF vocabDim (dropoutP -> Double -> Generator device -> (transformer, Generator device))),
    WithDimC vocabDim (dropoutP -> Double -> Generator device -> (transformer, Generator device))
  )

instance
  ( HasInitializeSequenceToSequenceTransformerC (SequenceToSequenceTransformer numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP) device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP,
    HasInitialize (TransformerEncoder numEncoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim dropoutP),
    HasInitializeTransformerEncoderC numEncoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim dropoutP,
    HasInitialize (TransformerDecoder numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim inputEmbedDim ffnDim posEncDim dropoutP),
    HasInitializeTransformerDecoderC numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim inputEmbedDim ffnDim posEncDim dropoutP,
    HasInitializeEmbeddingC ('Layout 'Dense) device dataType vocabDim inputEmbedDim 'Nothing
  ) =>
  HasInitialize (SequenceToSequenceTransformer numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP)
  where
  type
    InitializeF (SequenceToSequenceTransformer numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP) =
      WithDeviceF
        device
        ( WithDataTypeF
            dataType
            ( WithDimF
                headDim
                ( WithDimF
                    headEmbedDim
                    ( WithDimF
                        embedDim
                        ( WithDimF
                            inputEmbedDim
                            ( WithDimF
                                ffnDim
                                ( WithDimF
                                    posEncDim
                                    ( WithDimF
                                        vocabDim
                                        (dropoutP -> Double -> Generator device -> (SequenceToSequenceTransformer numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP, Generator device))
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
  initialize =
    withDevice @device $
      \deviceType ->
        withDataType @dataType $
          \dType ->
            withDim @headDim $
              \headDim ->
                withDim @headEmbedDim $
                  \headEmbedDim ->
                    withDim @embedDim $
                      \embedDim ->
                        withDim @inputEmbedDim $
                          \inputEmbedDim ->
                            withDim @ffnDim $
                              \ffnDim ->
                                withDim @posEncDim $
                                  \posEncDim ->
                                    withDim @vocabDim @(dropoutP -> Double -> Generator device -> (SequenceToSequenceTransformer numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP, Generator device)) $
                                      \vocabDim -> go deviceType dType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim
    where
      go deviceType dType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP eps = runState $ do
        encoder <-
          state $
            withoutDim @posEncDim
              ( withoutDim @ffnDim
                  ( withoutDim @inputEmbedDim
                      ( withoutDim @embedDim
                          ( withoutDim @headEmbedDim
                              ( withoutDim @headDim
                                  ( withoutDataType @dataType
                                      ( withoutDevice @device
                                          ( initialize @(TransformerEncoder numEncoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim dropoutP)
                                          )
                                          deviceType
                                      )
                                      dType
                                  )
                                  headDim
                              )
                              headEmbedDim
                          )
                          embedDim
                      )
                      inputEmbedDim
                  )
                  ffnDim
              )
              posEncDim
              dropoutP
              eps
        decoder <-
          state $
            withoutDim @posEncDim
              ( withoutDim @ffnDim
                  ( withoutDim @inputEmbedDim
                      ( withoutDim @inputEmbedDim
                          ( withoutDim @embedDim
                              ( withoutDim @headEmbedDim
                                  ( withoutDim @headDim
                                      ( withoutDataType @dataType
                                          ( withoutDevice @device
                                              ( initialize @(TransformerDecoder numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim inputEmbedDim ffnDim posEncDim dropoutP)
                                              )
                                              deviceType
                                          )
                                          dType
                                      )
                                      headDim
                                  )
                                  headEmbedDim
                              )
                              embedDim
                          )
                          inputEmbedDim
                      )
                      inputEmbedDim
                  )
                  ffnDim
              )
              posEncDim
              dropoutP
              eps
        embedding <-
          state $
            withoutDim @inputEmbedDim
              ( withoutDim @vocabDim
                  ( withoutDataType @dataType
                      ( withoutDevice @device
                          ( initialize @(Embedding ('Layout 'Dense) device dataType vocabDim inputEmbedDim 'Nothing)
                          )
                          deviceType
                      )
                      dType
                  )
                  vocabDim
              )
              inputEmbedDim
        pure $ SequenceToSequenceTransformer encoder decoder embedding inputEmbedDim

type family
  HasInitializeSeqToSeqTransformerF
    (seqToSeqTransformer :: Type)
    (style :: TransformerStyle)
    (device :: Device (DeviceType Nat))
    (dataType :: DataType DType)
    (headDim :: Dim (Name Symbol) (Size Nat))
    (headEmbedDim :: Dim (Name Symbol) (Size Nat))
    (embedDim :: Dim (Name Symbol) (Size Nat))
    (inputEmbedDim :: Dim (Name Symbol) (Size Nat))
    (ffnDim :: Dim (Name Symbol) (Size Nat))
    (posEncDim :: Dim (Name Symbol) (Size Nat))
    (vocabDim :: Dim (Name Symbol) (Size Nat))
    (dropoutP :: Type) ::
    Constraint
  where
  HasInitializeSeqToSeqTransformerF seqToSeqTransformer _ device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP =
    ( HasInitialize seqToSeqTransformer,
      InitializeF seqToSeqTransformer ~ WithDeviceF device (WithDataTypeF dataType (WithDimF headDim (WithDimF headEmbedDim (WithDimF embedDim (WithDimF inputEmbedDim (WithDimF ffnDim (WithDimF posEncDim (WithDimF vocabDim (dropoutP -> Double -> Generator device -> (seqToSeqTransformer, Generator device)))))))))),
      HasInitializeSequenceToSequenceTransformerC seqToSeqTransformer device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP
    )

type family
  HasInitializeSeqToSeqLMHeadF
    (seqToSeqLMHead :: Type)
    (style :: TransformerStyle)
    (device :: Device (DeviceType Nat))
    (dataType :: DataType DType)
    (inputEmbedDim :: Dim (Name Symbol) (Size Nat))
    (vocabDim :: Dim (Name Symbol) (Size Nat)) ::
    Constraint
  where
  HasInitializeSeqToSeqLMHeadF seqToSeqLMHead _ device dataType inputEmbedDim vocabDim =
    ( HasInitialize seqToSeqLMHead,
      InitializeF seqToSeqLMHead ~ WithDeviceF device (WithDataTypeF dataType (WithDimF inputEmbedDim (WithDimF vocabDim (Generator device -> (seqToSeqLMHead, Generator device))))),
      WithDeviceC device (WithDataTypeF dataType (WithDimF inputEmbedDim (WithDimF vocabDim (Generator device -> (seqToSeqLMHead, Generator device))))),
      WithDataTypeC dataType (WithDimF inputEmbedDim (WithDimF vocabDim (Generator device -> (seqToSeqLMHead, Generator device)))),
      WithDimC inputEmbedDim (WithDimF vocabDim (Generator device -> (seqToSeqLMHead, Generator device))),
      WithDimC vocabDim (Generator device -> (seqToSeqLMHead, Generator device))
    )

type family
  HasInitializeSeqToSeqFinalLogitsBiasF
    (seqToSeqFinalLogitsBias :: Type)
    (style :: TransformerStyle)
    (device :: Device (DeviceType Nat))
    (dataType :: DataType DType)
    (vocabDim :: Dim (Name Symbol) (Size Nat)) ::
    Constraint
  where
  HasInitializeSeqToSeqFinalLogitsBiasF seqToSeqFinalLogitsBias 'T5 _ _ _ = ()
  HasInitializeSeqToSeqFinalLogitsBiasF seqToSeqFinalLogitsBias 'Pegasus device dataType vocabDim =
    ( WithCreateC seqToSeqFinalLogitsBias 'WithGradient ('Layout 'Dense) device dataType ('Shape '[ 'Dim ('Name "*") ('Size 1), vocabDim])
    )

instance
  ( SingI style,
    HasInitializeSequenceToSequenceTransformerC (SequenceToSequenceTransformerWithLMHead numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP) device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP,
    seqToSeqTransformer ~ SeqToSeqTransformerF numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP,
    HasInitializeSeqToSeqTransformerF seqToSeqTransformer style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP,
    seqToSeqLMHead ~ SeqToSeqLMHeadF style device dataType inputEmbedDim vocabDim,
    HasInitializeSeqToSeqLMHeadF seqToSeqLMHead style device dataType inputEmbedDim vocabDim,
    seqToSeqFinalLogitsBias ~ SeqToSeqFinalLogitsBiasF style device dataType vocabDim,
    HasInitializeSeqToSeqFinalLogitsBiasF seqToSeqFinalLogitsBias style device dataType vocabDim
  ) =>
  HasInitialize (SequenceToSequenceTransformerWithLMHead numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP)
  where
  type
    InitializeF (SequenceToSequenceTransformerWithLMHead numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP) =
      WithDeviceF
        device
        ( WithDataTypeF
            dataType
            ( WithDimF
                headDim
                ( WithDimF
                    headEmbedDim
                    ( WithDimF
                        embedDim
                        ( WithDimF
                            inputEmbedDim
                            ( WithDimF
                                ffnDim
                                ( WithDimF
                                    posEncDim
                                    ( WithDimF
                                        vocabDim
                                        (dropoutP -> Double -> Generator device -> (SequenceToSequenceTransformerWithLMHead numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP, Generator device))
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
  initialize =
    withDevice @device $
      \deviceType ->
        withDataType @dataType $
          \dType ->
            withDim @headDim $
              \headDim ->
                withDim @headEmbedDim $
                  \headEmbedDim ->
                    withDim @embedDim $
                      \embedDim ->
                        withDim @inputEmbedDim $
                          \inputEmbedDim ->
                            withDim @ffnDim $
                              \ffnDim ->
                                withDim @posEncDim $
                                  \posEncDim ->
                                    withDim @vocabDim @(dropoutP -> Double -> Generator device -> (SequenceToSequenceTransformerWithLMHead numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP, Generator device)) $
                                      \vocabDim -> go deviceType dType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim
    where
      go deviceType dType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP eps = runState $ do
        transformer <-
          state $
            withoutDim @vocabDim @(dropoutP -> Double -> Generator device -> (seqToSeqTransformer, Generator device))
              ( withoutDim @posEncDim
                  ( withoutDim @ffnDim
                      ( withoutDim @inputEmbedDim
                          ( withoutDim @embedDim
                              ( withoutDim @headEmbedDim
                                  ( withoutDim @headDim
                                      ( withoutDataType @dataType
                                          ( withoutDevice @device
                                              (initialize @seqToSeqTransformer)
                                              deviceType
                                          )
                                          dType
                                      )
                                      headDim
                                  )
                                  headEmbedDim
                              )
                              embedDim
                          )
                          inputEmbedDim
                      )
                      ffnDim
                  )
                  posEncDim
              )
              vocabDim
              dropoutP
              eps
        lmHead <-
          state $
            withoutDim @vocabDim
              ( withoutDim @inputEmbedDim
                  ( withoutDataType @dataType
                      ( withoutDevice @device
                          ( initialize @seqToSeqLMHead
                          )
                          deviceType
                      )
                      dType
                  )
                  inputEmbedDim
              )
              vocabDim
        let finalLogitsBias =
              case sing @style of
                ST5 -> ()
                SPegasus ->
                  withoutCreate @_ @'WithGradient @('Layout 'Dense) @device @dataType @('Shape '[ 'Dim ('Name "*") ('Size 1), vocabDim])
                    (zeros @'WithGradient @('Layout 'Dense) @device @dataType @('Shape '[ 'Dim ('Name "*") ('Size 1), vocabDim]))
                    WithGradient
                    Dense
                    deviceType
                    dType
                    [vocabDim]
        pure . SequenceToSequenceTransformerWithLMHead $ GSequenceToSequenceTransformerWithLMHead transformer lmHead finalLogitsBias

lookupInputEmbedDim ::
  forall inputEmbedDim m.
  (KnownDim inputEmbedDim, MonadFail m) =>
  m (Dim String Integer)
lookupInputEmbedDim = case dimVal @inputEmbedDim of
  Dim (Name name) (Size size) -> pure $ Dim name size
  Dim _ _ -> fail "input embedding dimension unspecified"

lookupSequenceToSequenceTransformer ::
  forall numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP m.
  ( SingI style,
    MonadReader TensorDict m,
    MonadIO m,
    MonadFail m,
    KnownDevice device,
    KnownDataType dataType,
    KnownDim headDim,
    KnownDim headEmbedDim,
    KnownDim embedDim,
    KnownDim ffnDim,
    KnownDim posEncDim,
    KnownDim inputEmbedDim,
    KnownDim vocabDim,
    Scalar dropoutP,
    HasLookupStack numEncoderLayers (1 <=? numEncoderLayers) numEncoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim dropoutP m,
    HasLookupDecoderStack numDecoderLayers (1 <=? numDecoderLayers) numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim inputEmbedDim ffnDim dropoutP m
  ) =>
  dropoutP ->
  Double ->
  String ->
  m (SequenceToSequenceTransformer numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP)
lookupSequenceToSequenceTransformer dropoutP eps prefix =
  let encoder ST5 = lookupEncoder dropoutP eps (prefix <> "encoder.")
      encoder SPegasus = lookupEncoder dropoutP eps (prefix <> "encoder.")
      decoder ST5 = lookupDecoder dropoutP eps (prefix <> "decoder.")
      decoder SPegasus = lookupDecoder dropoutP eps (prefix <> "decoder.")
      embedding ST5 = fmap @m Embedding $ lookupTensor "shared.weight"
      embedding SPegasus = fmap @m Embedding $ lookupTensor (prefix <> "shared.weight")
   in SequenceToSequenceTransformer
        <$> encoder (sing @style)
        <*> decoder (sing @style)
        <*> embedding (sing @style)
        <*> lookupInputEmbedDim @inputEmbedDim

lookupSequenceToSequenceTransformerWithLMHead ::
  forall numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP m.
  ( SingI style,
    MonadReader TensorDict m,
    MonadIO m,
    MonadFail m,
    KnownDevice device,
    KnownDataType dataType,
    KnownDim headDim,
    KnownDim headEmbedDim,
    KnownDim embedDim,
    KnownDim ffnDim,
    KnownDim posEncDim,
    KnownDim inputEmbedDim,
    KnownDim vocabDim,
    Scalar dropoutP,
    HasLookupStack numEncoderLayers (1 <=? numEncoderLayers) numEncoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim dropoutP m,
    HasLookupDecoderStack numDecoderLayers (1 <=? numDecoderLayers) numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim inputEmbedDim ffnDim dropoutP m
  ) =>
  dropoutP ->
  Double ->
  String ->
  m (SequenceToSequenceTransformerWithLMHead numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP)
lookupSequenceToSequenceTransformerWithLMHead dropoutP eps prefix =
  let transformer ST5 = lookupSequenceToSequenceTransformer dropoutP eps prefix
      transformer SPegasus = lookupSequenceToSequenceTransformer dropoutP eps (prefix <> "model.")
      lmHead ST5 = fmap @m LinearWithoutBias $ lookupTensor (prefix <> "lm_head.weight")
      lmHead SPegasus = fmap @m LinearWithoutBias $ lookupTensor (prefix <> "lm_head.weight")
      finalLogitsBias ST5 = pure @m ()
      finalLogitsBias SPegasus = lookupTensor (prefix <> "final_logits_bias")
   in SequenceToSequenceTransformerWithLMHead
        <$> ( GSequenceToSequenceTransformerWithLMHead
                <$> transformer (sing @style)
                <*> lmHead (sing @style)
                <*> finalLogitsBias (sing @style)
            )

-- | Input data type for use with a sequence-to-sequence transformer.
-- Use this for training.
data SequenceToSequenceTransformerInput input decoderInput pos decoderPos attentionMask decoderAttentionMask crossAttentionMask where
  SequenceToSequenceTransformerInput ::
    forall input decoderInput pos decoderPos attentionMask decoderAttentionMask crossAttentionMask.
    { input :: input,
      decoderInput :: decoderInput,
      pos :: pos,
      decoderPos :: decoderPos,
      attentionMask :: attentionMask,
      decoderAttentionMask :: decoderAttentionMask,
      crossAttentionMask :: crossAttentionMask
    } ->
    SequenceToSequenceTransformerInput input decoderInput pos decoderPos attentionMask decoderAttentionMask crossAttentionMask

deriving instance
  ( Show input,
    Show decoderInput,
    Show pos,
    Show decoderPos,
    Show attentionMask,
    Show decoderAttentionMask,
    Show crossAttentionMask
  ) =>
  Show (SequenceToSequenceTransformerInput input decoderInput pos decoderPos attentionMask decoderAttentionMask crossAttentionMask)

-- | Output data type for use with a sequence-to-sequence transformer.
data SequenceToSequenceTransformerOutput decoderOutput encoderOutput where
  SequenceToSequenceTransformerOutput ::
    forall decoderOutput encoderOutput.
    { decoderOutput :: decoderOutput,
      encoderOutput :: encoderOutput
    } ->
    SequenceToSequenceTransformerOutput decoderOutput encoderOutput

deriving instance
  ( Show decoderOutput,
    Show encoderOutput
  ) =>
  Show (SequenceToSequenceTransformerOutput decoderOutput encoderOutput)

-- | Input data type for use with a sequence-to-sequence transformer.
-- Use this for inference.
data SequenceToSequenceTransformerGenerationInput decoderInput encoderOutput decoderPos decoderAttentionMask crossAttentionMask where
  SequenceToSequenceTransformerGenerationInput ::
    forall decoderInput encoderOutput decoderPos decoderAttentionMask crossAttentionMask.
    { generationDecoderInput :: decoderInput,
      generationEncoderOutput :: encoderOutput,
      generationDecoderPos :: decoderPos,
      generationDecoderAttentionMask :: decoderAttentionMask,
      generationCrossAttentionMask :: crossAttentionMask
    } ->
    SequenceToSequenceTransformerGenerationInput decoderInput encoderOutput decoderPos decoderAttentionMask crossAttentionMask

deriving instance
  ( Show decoderInput,
    Show encoderOutput,
    Show decoderPos,
    Show decoderAttentionMask,
    Show crossAttentionMask
  ) =>
  Show (SequenceToSequenceTransformerGenerationInput decoderInput encoderOutput decoderPos decoderAttentionMask crossAttentionMask)

-- | 'HasForward' instance for sequence-to-sequence transformers without language modelling head.
--
-- @
--     ┌───────┐  ┌─────┐  ┌───────────────┐  ┌──────────────┐  ┌────────────┐  ┌──────────────────────┐  ┌────────────────────┐
--     │ input │  │ pos │  │ attentionMask │  │ decoderInput │  │ decoderPos │  │ decoderAttentionMask │  │ crossAttentionMask │
--     └───┬───┘  └──┬──┘  └──────┬────────┘  └──────┬───────┘  └─────┬──────┘  └──────────┬───────────┘  └─────────┬──────────┘
--         │         │            │                  │                │                    │                        │
--         ▼         │            │                  │                │                    │                        │
-- seqToSeqEmbedding │            │                  │                │                    │                        │
--         ▼         │            │                  │                │                    │                        │
--   (embedScaling)  │            │                  │                │                    │                        │
--         ▼         │            │                  │                │                    │                        │
--  seqToSeqEncoder◄─┘◄───────────┘                  ▼                │                    │                        │
--         │                                 seqToSeqEmbedding        │                    │                        │
--         │                                         ▼                │                    │                        │
--         │                                   (embedScaling)         │                    │                        │
--         │                                         ▼                │                    │                        │
--         ├─────────────────────────────────►seqToSeqDecoder◄────────┘◄───────────────────┘◄───────────────────────┘
--         │                                         │
--         ▼                                         ▼
-- ┌───────────────┐                         ┌───────────────┐
-- │ encoderOutput │                         │ decoderOutput │
-- └───────────────┘                         └───────────────┘
-- @
instance
  ( SingI style,
    HasForward
      (Embedding ('Layout 'Dense) device dataType vocabDim inputEmbedDim 'Nothing)
      input
      generator
      embeddingOutput
      embeddingGeneratorOutput,
    embeddingOutput ~ Tensor requiresGradient' layout' device' dataType' shape',
    HasForward
      (TransformerEncoder numEncoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim dropoutP)
      (embeddingOutput, pos, attentionMask)
      embeddingGeneratorOutput
      encoderOutput
      encoderGeneratorOutput,
    HasForward
      (Embedding ('Layout 'Dense) device dataType vocabDim inputEmbedDim 'Nothing)
      decoderInput
      encoderGeneratorOutput
      embeddingOutput'
      embeddingGeneratorOutput',
    embeddingOutput' ~ Tensor requiresGradient'' layout'' device'' dataType'' shape'',
    HasForward
      (TransformerDecoder numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim inputEmbedDim ffnDim posEncDim dropoutP)
      ( embeddingOutput',
        encoderOutput,
        decoderPos,
        decoderAttentionMask,
        crossAttentionMask
      )
      embeddingGeneratorOutput'
      decoderOutput
      generatorOutput
  ) =>
  HasForward
    (SequenceToSequenceTransformer numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP)
    (SequenceToSequenceTransformerInput input decoderInput pos decoderPos attentionMask decoderAttentionMask crossAttentionMask)
    generator
    (SequenceToSequenceTransformerOutput decoderOutput encoderOutput)
    generatorOutput
  where
  forward SequenceToSequenceTransformer {..} SequenceToSequenceTransformerInput {..} =
    let s :: Double = sqrt . fromIntegral . dimSize $ seqToSeqInputEmbedDim
        embedScaling ::
          forall requiresGradient layout device dataType shape.
          STransformerStyle style ->
          Tensor requiresGradient layout device dataType shape ->
          Tensor requiresGradient layout device dataType shape
        embedScaling ST5 = id
        embedScaling SPegasus = flip mulScalar s
     in runIxState $
          ireturn input
            >>>= IxState . forward seqToSeqEmbedding
            >>>= ireturn . embedScaling (sing @style)
            >>>= (\input' -> IxState $ forward seqToSeqEncoder (input', pos, attentionMask))
            >>>= ( \encoderOutput ->
                     ireturn decoderInput
                       >>>= IxState . forward seqToSeqEmbedding
                       >>>= ireturn . embedScaling (sing @style)
                       >>>= ( \decoderInput' ->
                                IxState $ forward seqToSeqDecoder (decoderInput', encoderOutput, decoderPos, decoderAttentionMask, crossAttentionMask)
                            )
                       >>>= \decoderOutput -> ireturn (SequenceToSequenceTransformerOutput decoderOutput encoderOutput)
                 )

-- | 'HasForward' instance for sequence-to-sequence transformers without language modelling head.
-- Use this instance for sequence generation once the encoder's output is available.
--
-- @
-- ┌───────────────┐  ┌──────────────┐  ┌────────────┐  ┌──────────────────────┐  ┌────────────────────┐
-- │ encoderOutput │  │ decoderInput │  │ decoderPos │  │ decoderAttentionMask │  │ crossAttentionMask │
-- └───────┬───────┘  └───────┬──────┘  └──────┬─────┘  └───────────┬──────────┘  └──────────┬─────────┘
--         │                  │                │                    │                        │
--         │                  ▼                │                    │                        │
--         │          seqToSeqEmbedding        │                    │                        │
--         │                  ▼                │                    │                        │
--         │            (embedScaling)         │                    │                        │
--         │                  ▼                │                    │                        │
--         ├──────────►seqToSeqDecoder◄────────┘◄───────────────────┘◄───────────────────────┘
--         │                  │
--         ▼                  ▼
-- ┌───────────────┐  ┌───────────────┐
-- │ encoderOutput │  │ decoderOutput │
-- └───────────────┘  └───────────────┘
-- @
instance
  ( SingI style,
    HasForward
      (Embedding ('Layout 'Dense) device dataType vocabDim inputEmbedDim 'Nothing)
      decoderInput
      generator
      embeddingOutput'
      embeddingGeneratorOutput',
    embeddingOutput' ~ Tensor requiresGradient'' layout'' device'' dataType'' shape'',
    HasForward
      (TransformerDecoder numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim inputEmbedDim ffnDim posEncDim dropoutP)
      ( embeddingOutput',
        encoderOutput,
        decoderPos,
        decoderAttentionMask,
        crossAttentionMask
      )
      embeddingGeneratorOutput'
      decoderOutput
      generatorOutput
  ) =>
  HasForward
    (SequenceToSequenceTransformer numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP)
    (SequenceToSequenceTransformerGenerationInput decoderInput encoderOutput decoderPos decoderAttentionMask crossAttentionMask)
    generator
    (SequenceToSequenceTransformerOutput decoderOutput encoderOutput)
    generatorOutput
  where
  forward SequenceToSequenceTransformer {..} SequenceToSequenceTransformerGenerationInput {..} =
    let s :: Double = sqrt . fromIntegral . dimSize $ seqToSeqInputEmbedDim
        embedScaling ::
          forall requiresGradient layout device dataType shape.
          STransformerStyle style ->
          Tensor requiresGradient layout device dataType shape ->
          Tensor requiresGradient layout device dataType shape
        embedScaling ST5 = id
        embedScaling SPegasus = flip mulScalar s
     in runIxState $
          ireturn generationDecoderInput
            >>>= IxState . forward seqToSeqEmbedding
            >>>= ireturn . embedScaling (sing @style)
            >>>= ( \decoderInput' ->
                     IxState $ forward seqToSeqDecoder (decoderInput', generationEncoderOutput, generationDecoderPos, generationDecoderAttentionMask, generationCrossAttentionMask)
                 )
            >>>= \decoderOutput -> ireturn (SequenceToSequenceTransformerOutput decoderOutput generationEncoderOutput)

type family
  SequenceToSequenceTransformerWithLMHeadDecoderOutputF
    (style :: TransformerStyle)
    (lmHeadOutput :: Type)
    (device :: Device (DeviceType Nat))
    (dataType :: DataType DType)
    (vocabDim :: Dim (Name Symbol) (Size Nat)) ::
    Type
  where
  SequenceToSequenceTransformerWithLMHeadDecoderOutputF 'T5 lmHeadOutput _ _ _ = lmHeadOutput
  SequenceToSequenceTransformerWithLMHeadDecoderOutputF 'Pegasus (Tensor requiresGradient' layout' device' dataType' shape') device dataType vocabDim =
    Tensor
      'WithGradient
      (layout' <+> 'Layout 'Dense)
      (device' <+> device)
      (dataType' <+> dataType)
      (BroadcastShapesF shape' ('Shape '[ 'Dim ('Name "*") ('Size 1), vocabDim]))

-- | 'HasForward' instance for sequence-to-sequence transformers with language modelling head.
--
-- @
--                        ┌───────┐
--                        │ input │
--                        └───┬───┘
--                            │
--                            ▼
--         ┌─────────seqToSeqTransformer
--         │                  ▼
--         │            seqToSeqLMHead
--         │                  ▼
--         │              (scaling)
--         │                  ▼
--         │      (seqToSeqFinalLogitsBias)
--         │                  │
--         ▼                  ▼
-- ┌───────────────┐  ┌───────────────┐
-- │ encoderOutput │  │ decoderOutput │
-- └───────────────┘  └───────────────┘
-- @
instance
  ( SingI style,
    HasForward
      (SequenceToSequenceTransformer numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP)
      input
      generator
      seqToSeqOutput
      seqToSeqGeneratorOutput,
    seqToSeqOutput ~ SequenceToSequenceTransformerOutput decoderOutput encoderOutput,
    HasForward
      (SeqToSeqLMHeadF style device dataType inputEmbedDim vocabDim)
      decoderOutput
      seqToSeqGeneratorOutput
      lmHeadOutput
      generatorOutput,
    lmHeadOutput ~ Tensor requiresGradient' layout' device' dataType' shape',
    decoderOutput'
      ~ SequenceToSequenceTransformerWithLMHeadDecoderOutputF style lmHeadOutput device dataType vocabDim
  ) =>
  HasForward
    (SequenceToSequenceTransformerWithLMHead numEncoderLayers numDecoderLayers style device dataType headDim headEmbedDim embedDim inputEmbedDim ffnDim posEncDim vocabDim dropoutP)
    input
    generator
    (SequenceToSequenceTransformerOutput decoderOutput' encoderOutput)
    generatorOutput
  where
  forward (SequenceToSequenceTransformerWithLMHead GSequenceToSequenceTransformerWithLMHead {..}) input =
    let s :: Double = sqrt . fromIntegral . dimSize $ seqToSeqInputEmbedDim seqToSeqTransformer
        scaling :: STransformerStyle style -> lmHeadOutput -> lmHeadOutput
        scaling ST5 = flip divScalar s
        scaling SPegasus = id
        finalLogitsBias :: STransformerStyle style -> lmHeadOutput -> decoderOutput'
        finalLogitsBias ST5 lmHeadOutput = lmHeadOutput
        finalLogitsBias SPegasus lmHeadOutput = lmHeadOutput `add` seqToSeqFinalLogitsBias
     in runIxState $
          ireturn input
            >>>= IxState . forward seqToSeqTransformer
            >>>= ( \SequenceToSequenceTransformerOutput {..} ->
                     ireturn decoderOutput
                       >>>= IxState . forward seqToSeqLMHead
                       >>>= ireturn . scaling (sing @style)
                       >>>= ireturn . finalLogitsBias (sing @style)
                       >>>= \decoderOutput' -> ireturn (SequenceToSequenceTransformerOutput decoderOutput' encoderOutput)
                 )

testForwardSeqToSeq :: _
testForwardSeqToSeq =
  let seqToSeq =
        undefined ::
          SequenceToSequenceTransformerWithLMHead
            128
            128
            'T5
            ('Device 'CPU)
            ('DataType 'Float)
            ('Dim ('Name "*") ('Size 8)) -- headDim
            ('Dim ('Name "*") ('Size 64)) -- headEmbedDim
            ('Dim ('Name "*") ('Size 512)) -- embedDim
            ('Dim ('Name "*") ('Size 512)) -- inputEmbedDim
            ('Dim ('Name "*") ('Size 2048)) -- ffnDim
            ('Dim ('Name "*") ('Size 32)) -- posEncDim
            ('Dim ('Name "*") ('Size 32128)) -- vocabDim
            Float
      input =
        undefined ::
          Tensor
            'WithoutGradient
            ('Layout 'Dense)
            ('Device 'CPU)
            ('DataType 'Int64)
            ('Shape '[ 'Dim ('Name "*") ('Size 1), 'Dim ('Name "*") ('Size 7)])
      decoderInput =
        undefined ::
          Tensor
            'WithoutGradient
            ('Layout 'Dense)
            ('Device 'CPU)
            ('DataType 'Int64)
            ('Shape '[ 'Dim ('Name "*") ('Size 1), 'Dim ('Name "*") ('Size 5)])
      pos =
        undefined ::
          Tensor
            'WithoutGradient
            ('Layout 'Dense)
            ('Device 'CPU)
            ('DataType 'Int64)
            ('Shape '[ 'Dim ('Name "*") ('Size 1), 'Dim ('Name "*") ('Size 7), 'Dim ('Name "*") ('Size 7)])
      decoderPos =
        undefined ::
          Tensor
            'WithoutGradient
            ('Layout 'Dense)
            ('Device 'CPU)
            ('DataType 'Int64)
            ('Shape '[ 'Dim ('Name "*") ('Size 1), 'Dim ('Name "*") ('Size 5), 'Dim ('Name "*") ('Size 5)])
      attentionMask =
        undefined ::
          Tensor
            'WithoutGradient
            ('Layout 'Dense)
            ('Device 'CPU)
            ('DataType 'Float)
            ('Shape '[ 'Dim ('Name "*") ('Size 1), 'Dim ('Name "*") ('Size 7), 'Dim ('Name "*") ('Size 7)])
      decoderAttentionMask =
        undefined ::
          Tensor
            'WithoutGradient
            ('Layout 'Dense)
            ('Device 'CPU)
            ('DataType 'Float)
            ('Shape '[ 'Dim ('Name "*") ('Size 1), 'Dim ('Name "*") ('Size 5), 'Dim ('Name "*") ('Size 5)])
      crossAttentionMask =
        undefined ::
          Tensor
            'WithoutGradient
            ('Layout 'Dense)
            ('Device 'CPU)
            ('DataType 'Float)
            ('Shape '[ 'Dim ('Name "*") ('Size 1), 'Dim ('Name "*") ('Size 5), 'Dim ('Name "*") ('Size 7)])
      g = undefined :: Generator ('Device 'CPU)
   in forward seqToSeq (SequenceToSequenceTransformerInput input decoderInput pos decoderPos attentionMask decoderAttentionMask crossAttentionMask) g