{-# LANGUAGE OverloadedStrings, ViewPatterns #-}
module Databrary.Controller.Zip
  ( zipContainer
  , zipVolume
  ) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BSB
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Foldable as Fold
import Data.Function (on)
import Data.List (groupBy, partition)
import Data.Maybe (fromJust)
import Data.Monoid ((<>))
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types (hContentType, hCacheControl, hContentLength)
import System.Posix.FilePath ((<.>))

import Databrary.Ops
import Databrary.Has (view, peek)
import Databrary.Store.Asset
import Databrary.Store.Filename
import Databrary.Store.Zip
import Databrary.Model.Id
import Databrary.Model.Permission
import Databrary.Model.Volume
import Databrary.Model.Container
import Databrary.Model.Slot
import Databrary.Model.RecordSlot
import Databrary.Model.Asset
import Databrary.Model.AssetSlot
import Databrary.Model.Format
import Databrary.Model.Party
import Databrary.HTTP
import Databrary.HTTP.Path.Parser
import Databrary.Action
import Databrary.Controller.Paths
import Databrary.Controller.Asset
import Databrary.Controller.Container
import Databrary.Controller.Volume
import Databrary.Controller.Party
import Databrary.Controller.CSV

assetZipEntry :: AssetSlot -> AuthActionM ZipEntry
assetZipEntry AssetSlot{ slotAsset = a } = do
  Just f <- getAssetFile a
  req <- peek
  -- (t, _) <- assetCreation a
  -- Just (t, s) <- fileInfo f
  return blankZipEntry
    { zipEntryName = makeFilename (assetDownloadName a) `addFormatExtension` assetFormat a
    , zipEntryTime = Nothing
    , zipEntryComment = BSL.toStrict $ BSB.toLazyByteString $ actionURL (Just req) viewAsset (HTML, assetId a) []
    , zipEntryContent = ZipEntryFile (fromIntegral $ fromJust $ assetSize a) f
    }

containerZipEntry :: Maybe (Id Container) -> Container -> [AssetSlot] -> AuthActionM ZipEntry
containerZipEntry top c l = do
  req <- peek
  a <- mapM assetZipEntry l
  return blankZipEntry
    { zipEntryName = makeFilename (containerDownloadName top c)
    , zipEntryComment = BSL.toStrict $ BSB.toLazyByteString $ actionURL (Just req) viewContainer (HTML, (Nothing, containerId c)) []
    , zipEntryContent = ZipDirectory a
    }

volumeZipEntry :: Container -> Maybe BSB.Builder -> [AssetSlot] -> AuthActionM ZipEntry
volumeZipEntry top@Container{ containerVolume = v } csv al = do
  req <- peek
  zt <- mapM ent ct
  zb <- mapM ent cb
  return blankZipEntry
    { zipEntryName = makeFilename (volumeDownloadName v)
    , zipEntryComment = BSL.toStrict $ BSB.toLazyByteString $ actionURL (Just req) viewVolume (HTML, volumeId v) []
    , zipEntryContent = ZipDirectory
      $ maybe id (\c -> (blankZipEntry
        { zipEntryName = "spreadsheet.csv"
        , zipEntryContent = ZipEntryPure $ BSB.toLazyByteString c
        } :)) csv
      (if null zb then zt else (zt ++ [blankZipEntry
        { zipEntryName = "sessions"
        , zipEntryContent = ZipDirectory zb
        }]))
    }
  where
  (ct, cb) = partition (Fold.any (containerTop . slotContainer) . assetSlot . head) $ groupBy (me `on` fmap (containerId . slotContainer) . assetSlot) al
  me (Just x) (Just y) = x == y
  me _ _ = False
  ent [a@AssetSlot{ assetSlot = Nothing }] = assetZipEntry a
  ent l@(AssetSlot{ assetSlot = Just s } : _) = containerZipEntry (Just $ containerId top) (slotContainer s) l
  ent _ = fail "volumeZipEntry"

zipResponse :: BS.ByteString -> [ZipEntry] -> AuthAction
zipResponse n z = do
  req <- peek
  u <- peek
  let comment = BSL.toStrict $ BSB.toLazyByteString
        $ BSB.string7 "Downloaded by " <> TE.encodeUtf8Builder (partyName u) <> BSB.string7 " <" <> actionURL (Just req) viewParty (HTML, TargetParty $ partyId u) [] <> BSB.char7 '>'
  okResponse
    [ (hContentType, "application/zip")
    , ("content-disposition", "attachment; filename=" <> quoteHTTP (n <.> "zip"))
    , (hCacheControl, "max-age=31556926, private")
    , (hContentLength, BSC.pack $ show $ sizeZip z + fromIntegral (BS.length comment))
    ] (streamZip z comment)

zipEmpty :: ZipEntry -> Bool
zipEmpty ZipEntry{ zipEntryContent = ZipDirectory l } = all zipEmpty l
zipEmpty _ = False

checkAsset :: AssetSlot -> Bool
checkAsset a = dataPermission a > PermissionNONE && assetBacked (view a)

zipContainer :: AppRoute (Maybe (Id Volume), Id Slot)
zipContainer = action GET (pathMaybe pathId </> pathSlotId </< "zip") $ \(vi, ci) -> withAuth $ do
  c <- getContainer PermissionPUBLIC vi ci True
  z <- containerZipEntry Nothing c . filter checkAsset =<< lookupContainerAssets c
  auditSlotDownload (not $ zipEmpty z) (containerSlot c)
  zipResponse ("databrary-" <> BSC.pack (show (volumeId (containerVolume c))) <> "-" <> BSC.pack (show (containerId c))) [z]

zipVolume :: AppRoute (Id Volume)
zipVolume = action GET (pathId </< "zip") $ \vi -> withAuth $ do
  v <- getVolume PermissionPUBLIC vi
  cr@((top,tr):cr') <- lookupVolumeContainersRecords v
  csv <- null tr && null cr' ?!$> volumeCSV v cr
  a <- filter checkAsset <$> lookupVolumeAssetSlots v False
  z <- volumeZipEntry top csv a
  auditVolumeDownload (not $ zipEmpty z) v
  zipResponse ("databrary-" <> BSC.pack (show (volumeId v))) [z]
