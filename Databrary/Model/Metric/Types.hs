{-# LANGUAGE TemplateHaskell, TypeFamilies, DeriveDataTypeable, OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Databrary.Model.Metric.Types
  ( MeasureDatum
  , MeasureType(..)
  , Metric(..)
  ) where

import qualified Data.Aeson as JSON
import qualified Data.ByteString as BS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Language.Haskell.TH.Lift (deriveLiftMany)

import Control.Has (Has(..))
import Databrary.DB
import Databrary.Enum
import Databrary.Kind
import Databrary.Model.Permission.Types
import Databrary.Model.Id.Types

useTPG

makeDBEnum "data_type" "MeasureType"

type MeasureDatum = BS.ByteString

instance JSON.ToJSON MeasureDatum where
  toJSON = JSON.String . TE.decodeUtf8

type instance IdType Metric = Int32

data Metric = Metric
  { metricId :: Id Metric
  , metricName :: T.Text
  , metricClassification :: Classification
  , metricType :: MeasureType
  , metricOptions :: [MeasureDatum]
  , metricAssumed :: Maybe MeasureDatum
  }

instance Has (Id Metric) Metric where
  view f a = fmap (\i -> a{ metricId = i }) $ f $ metricId a
  see = metricId
instance Kinded Metric where
  kindOf _ = "metric"

deriveLiftMany [''MeasureType, ''Metric]
