{-# LANGUAGE TypeSynonymInstances, DeriveDataTypeable, OverloadedStrings #-}
module Databrary.Action.Response
  ( Response
  , ResponseData(..)
  , emptyResponse
  , okResponse
  , result
  , unsafeResult
  , runResult
  , proxyResponse
  ) where

import Control.Exception (Exception, throwIO, throw, handle)
import Control.Monad (join)
import Control.Monad.IO.Class (MonadIO, liftIO)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BSB
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE
import Data.Typeable (Typeable)
import qualified Network.HTTP.Client as HC
import Network.HTTP.Types (ResponseHeaders, Status, ok200, hContentType)
import Network.Wai (Response, responseBuilder, responseLBS, StreamingBody, responseStream, FilePart(..), responseFile, responseStatus)
import System.Posix.Types (FileOffset)
import qualified Text.Blaze.Html as Html
import qualified Text.Blaze.Html.Renderer.Utf8 as Html

import Databrary.Files
import qualified Databrary.JSON as JSON

class ResponseData r where
  response :: Status -> ResponseHeaders -> r -> Response

instance ResponseData (Status -> ResponseHeaders -> Response) where
  response s h r = r s h

instance ResponseData BSB.Builder where
  response = responseBuilder

instance ResponseData BSL.ByteString where
  response = responseLBS

instance ResponseData BS.ByteString where
  response s h = responseBuilder s h . BSB.byteString

instance ResponseData StreamingBody where
  response = responseStream

instance ResponseData ((BSB.Builder -> IO ()) -> IO ()) where
  response s h f = responseStream s h (\w _ -> f w)

instance ResponseData ((BS.ByteString -> IO ()) -> IO ()) where
  response s h f = responseStream s h (\w l -> f (\b -> if BS.null b then l else w (BSB.byteString b)))

instance IsFilePath f => ResponseData (f, Maybe FilePart) where
  response s h (f, p) = responseFile s h (toFilePath f) p

instance IsFilePath f => ResponseData (f, FilePart) where
  response s h (f, p) = response s h (f, Just p)

instance IsFilePath f => ResponseData (f, Maybe FileOffset) where
  response s h (f, z) = response s h (f, join (FilePart 0) . toInteger <$> z)

instance ResponseData String where
  response s h =
    response s ((hContentType, "text/plain;charset=utf-8") : h) . BSB.stringUtf8

instance ResponseData T.Text where
  response s h =
    response s ((hContentType, "text/plain;charset=utf-8") : h) . TE.encodeUtf8Builder

instance ResponseData TL.Text where
  response s h =
    response s ((hContentType, "text/plain;charset=utf-8") : h) . TLE.encodeUtf8Builder

instance ResponseData JSON.Value where
  response s h =
    response s ((hContentType, "application/json") : h) . JSON.encode

instance ResponseData JSON.Encoding where
  response s h =
    response s ((hContentType, "application/json") : h) . JSON.fromEncoding

instance ResponseData JSON.Series where
  response s h =
    response s h . JSON.objectEncoding

instance (JSON.ToJSON k, JSON.ToObject o, ResponseData o) => ResponseData (JSON.Record k o) where
  response s h =
    response s h . JSON.recordObject

instance ResponseData Html.Html where
  response s h =
    response s ((hContentType, "text/html;charset=utf-8") : h) . Html.renderHtmlBuilder

emptyResponse :: Status -> ResponseHeaders -> Response
emptyResponse s h = response s h BS.empty

okResponse :: ResponseData r => ResponseHeaders -> r -> Response
okResponse = response ok200

newtype Result = Result { resultResponse :: Response } deriving (Typeable)
instance Show Result where
  showsPrec p (Result r) = showParen (p > 10)
    $ showString "Result " . showsPrec 11 (responseStatus r)
instance Exception Result

result :: MonadIO m => Response -> m a
result = liftIO . throwIO . Result

unsafeResult :: Response -> a
unsafeResult = throw . Result

runResult :: IO Response -> IO Response
runResult = handle (return . resultResponse)

proxyResponse :: HC.Response BSL.ByteString -> Response
proxyResponse r = responseLBS
  (HC.responseStatus r)
  (filter ((/= "transfer-encoding") . fst) $ HC.responseHeaders r)
  (HC.responseBody r)
