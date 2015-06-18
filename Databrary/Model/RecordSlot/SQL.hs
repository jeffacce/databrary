{-# LANGUAGE TemplateHaskell, OverloadedStrings #-}
module Databrary.Model.RecordSlot.SQL
  ( selectContainerSlotRecord
  , selectRecordSlotRecord
  , selectVolumeSlotRecord
  , selectVolumeSlotRecordId
  , selectSlotRecord
  , insertSlotRecord
  , updateSlotRecord
  , deleteSlotRecord
  ) where

import qualified Language.Haskell.TH as TH

import Databrary.Has (view)
import Databrary.Model.Id.Types
import Databrary.Model.Segment
import Databrary.Model.Volume.Types
import Databrary.Model.Record.Types
import Databrary.Model.Record.SQL
import Databrary.Model.Container.Types
import Databrary.Model.Container.SQL
import Databrary.Model.Slot.Types
import Databrary.Model.SQL.Select
import Databrary.Model.Audit.SQL
import Databrary.Model.Volume.SQL
import Databrary.Model.RecordSlot.Types

slotRecordRow :: Selector -- ^ @'Segment'@
slotRecordRow = selector "slot_record" $ SelectColumn "slot_record" "segment"

makeSlotRecord :: Segment -> Record -> Container -> RecordSlot
makeSlotRecord seg r c = RecordSlot r (Slot c seg)

selectRecordContainerSlotRecord :: Selector -- ^ @'Record' -> 'Container' -> 'RecordSlot'@
selectRecordContainerSlotRecord = selectMap (TH.VarE 'makeSlotRecord `TH.AppE`) slotRecordRow

makeContainerSlotRecord :: (Record -> Container -> RecordSlot) -> (Volume -> Record) -> Container -> RecordSlot
makeContainerSlotRecord f rf c = f (rf (view c)) c

selectContainerSlotRecord :: Selector -- ^ @'Container' -> 'RecordSlot'@
selectContainerSlotRecord = selectJoin 'makeContainerSlotRecord
  [ selectRecordContainerSlotRecord
  , joinOn "slot_record.record = record.id"
    selectVolumeRecord -- XXX volumes match?
  ]

makeRecordSlotRecord :: (Record -> Container -> RecordSlot) -> (Volume -> Container) -> Record -> RecordSlot
makeRecordSlotRecord f cf r = f r (cf (view r))

selectRecordSlotRecord :: Selector -- ^ @'Record' -> 'RecordSlot'@
selectRecordSlotRecord = selectJoin 'makeRecordSlotRecord
  [ selectRecordContainerSlotRecord
  , joinOn "slot_record.container = container.id"
    selectVolumeContainer -- XXX volumes match?
  ]

makeVolumeSlotRecord :: (Record -> Container -> RecordSlot) -> (Volume -> Record) -> (Volume -> Container) -> Volume -> RecordSlot
makeVolumeSlotRecord f rf cf v = f (rf v) (cf v)

selectVolumeSlotRecord :: Selector -- ^ @'Volume' -> 'RecordSlot'@
selectVolumeSlotRecord = selectJoin 'makeVolumeSlotRecord
  [ selectRecordContainerSlotRecord
  , joinOn "slot_record.record = record.id"
    selectVolumeRecord
  , joinOn "slot_record.container = container.id AND record.volume = container.volume"
    selectVolumeContainer
  ]

segmentRecordIdTuple :: Segment -> Id Record -> (Segment, Id Record)
segmentRecordIdTuple = (,)

makeVolumeSlotRecordId :: (Volume -> Container) -> Maybe (Segment, Id Record) -> Volume -> (Slot, Maybe (Id Record))
makeVolumeSlotRecordId cf Nothing v = (containerSlot (cf v), Nothing)
makeVolumeSlotRecordId cf (Just (s, r)) v = (Slot (cf v) s, Just r)

selectVolumeSlotRecordId :: Selector -- ^ @'Volume' -> '(Slot, Maybe (Id Record))'@
selectVolumeSlotRecordId = selectJoin 'makeVolumeSlotRecordId
  [ selectVolumeContainer
  , maybeJoinOn "container.id = slot_record.container"
    $ selectColumns 'segmentRecordIdTuple "slot_record" ["segment", "record"]
  ]

selectSlotRecord :: TH.Name -- ^ @'Identity'@
  -> Selector -- ^ @'RecordSlot'@
selectSlotRecord ident = selectJoin '($)
  [ selectVolumeSlotRecord
  , joinOn "record.volume = volume.id"
    $ selectVolume ident
  ]

slotRecordVals :: String -- ^ @'RecordSlot'@
  -> [(String, String)]
slotRecordVals o =
  [ ("record", "${recordId $ slotRecord " ++ o ++ "}")
  , ("container", "${containerId $ slotContainer $ recordSlot " ++ o ++ "}")
  , ("segment", "${slotSegment $ recordSlot " ++ o ++ "}")
  ]

insertSlotRecord :: TH.Name -- ^ @'AuditIdentity'@
  -> TH.Name -- ^ @'RecordSlot'@
  -> TH.ExpQ
insertSlotRecord ident o = auditInsert ident "slot_record"
  (slotRecordVals os)
  Nothing
  where os = nameRef o

updateSlotRecord :: TH.Name -- ^ @'AuditIdentity'@
  -> TH.Name -- ^ @'RecordSlot'@
  -> TH.Name -- ^ @'Segment'@
  -> TH.ExpQ
updateSlotRecord ident o ds = auditUpdate ident "slot_record"
  [ ("segment", "${" ++ nameRef ds ++ "}") ]
  (whereEq $ slotRecordVals $ nameRef o)
  Nothing

deleteSlotRecord :: TH.Name -- ^ @'AuditIdentity'@
  -> TH.Name -- ^ @'RecordSlot'@
  -> TH.ExpQ
deleteSlotRecord ident o = auditDelete ident "slot_record"
  ("record = ${recordId $ slotRecord " ++ os ++ "} AND container = ${containerId $ slotContainer $ recordSlot " ++ os ++ "} AND segment <@ ${slotSegment $ recordSlot " ++ os ++ "}")
  Nothing
  where os = nameRef o
