{-# language DeriveGeneric #-}
{-# language OverloadedStrings #-}
{-# language CPP #-}
module Nuclear
  ( Msg(..)
  , Method
  , Body
  , fromBS
  , toBS
  , LazyByteString
  , Text
  , module Data.Aeson
  , module GHC.Generics
  ) where

import Data.Aeson
import GHC.Generics
import Data.Text
import Data.Monoid
import qualified Data.Text.Lazy as Lazy
import qualified Data.Text.Lazy.Encoding as Lazy
import qualified Data.ByteString.Lazy as LBS

type LazyByteString = LBS.ByteString

type Method = Text
type Body = Lazy.Text

data Msg
  = Msg
    { method :: Method
    , body :: Body
    } deriving (Show,Eq,Ord,Generic)

instance FromJSON Msg
instance ToJSON Msg
#if MIN_VERSION_aeson(0,10,0)
  where
    toEncoding = genericToEncoding defaultOptions
#endif

fromBS :: LazyByteString -> Either String Msg
fromBS = eitherDecode

toBS :: Msg -> LazyByteString
toBS = encode

encodeMsg :: ToJSON a => Text -> a -> Msg
encodeMsg method a =
  let body = Lazy.decodeUtf8 $ encode a
  in Msg {..}

decodeMsg :: FromJSON a => Msg -> Maybe a
decodeMsg Msg {..} = decode $ Lazy.encodeUtf8 body
