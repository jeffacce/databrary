{-# LANGUAGE TemplateHaskell, PatternGuards #-}
module Databrary.Enum
  ( DBEnum
  , readDBEnum
  , makeDBEnum
  , pgEnumValues
  ) where

import Control.Monad (liftM2)
import qualified Data.Aeson.Types as JSON
import qualified Data.CaseInsensitive as CI (mk)
import Data.Char (toUpper)
import qualified Data.Text as T
import Database.PostgreSQL.Typed.Enum (PGEnum, pgEnumValues, makePGEnum)
import Text.Read (readMaybe)

import qualified Language.Haskell.TH as TH

import Databrary.Kind

class (PGEnum a, Kinded a) => DBEnum a

readDBEnum :: forall a . DBEnum a => String -> Maybe a
readDBEnum s
  | Just i <- readMaybe s, i >= fe minBound, i <= fe maxBound = Just (toEnum i)
  | [(x, _)] <- filter ((==) s . snd) pgEnumValues = Just x
  | [(x, _)] <- filter ((==) (CI.mk s) . CI.mk . snd) pgEnumValues = Just x
  | otherwise = Nothing
  where
  fe :: a -> Int
  fe = fromEnum

parseJSONEnum :: forall a . DBEnum a => JSON.Value -> JSON.Parser a
parseJSONEnum (JSON.String t) | Just e <- readDBEnum (T.unpack t) = return e
parseJSONEnum (JSON.Number x) = p (round x) where
  p i
    | i < fe minBound || i > fe maxBound = fail $ kindOf (undefined :: a) ++ " out of range"
    | otherwise = return $ toEnum i
  fe :: a -> Int
  fe = fromEnum
parseJSONEnum _ = fail $ "Invalid " ++ kindOf (undefined :: a)

makeDBEnum :: String -> String -> TH.DecsQ
makeDBEnum name typs =
  liftM2 (++)
    (makePGEnum name typs (\(h:r) -> typs ++ toUpper h : r))
    [d| instance Kinded $(return typt) where
          kindOf _ = $(TH.litE $ TH.stringL name)
        instance DBEnum $(return typt)
        instance JSON.ToJSON $(return typt) where
          toJSON = JSON.toJSON . fromEnum
        instance JSON.FromJSON $(return typt) where
          parseJSON = parseJSONEnum
    |]
  where
  typt = TH.ConT (TH.mkName typs)
