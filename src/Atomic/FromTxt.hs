{-# language CPP #-}
module Atomic.FromTxt where

#ifdef __GHCJS__
import Data.JSString
#endif

import Data.Txt

import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.Char8 as BSLC
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.Lazy as TL

class FromTxt a where
  fromTxt :: Txt -> a

instance FromTxt TL.Text where
#ifdef __GHCJS__
  fromTxt = lazyTextFromJSString
#else
  fromTxt = TL.fromStrict
#endif

instance FromTxt T.Text where
#ifdef __GHCJS__
  fromTxt = textFromJSString
#else
  fromTxt = id
#endif

#ifdef __GHCJS__
instance FromTxt JSString where
  fromTxt = id
#endif

instance FromTxt [Char] where
#ifdef __GHCJS__
  fromTxt = unpack
#else
  fromTxt = T.unpack
#endif

instance FromTxt B.ByteString where
#ifdef __GHCJS__
  fromTxt = BC.pack . unpack
#else
  fromTxt = T.encodeUtf8
#endif

instance FromTxt BSL.ByteString where
#ifdef __GHCJS__
  fromTxt = BSLC.pack . unpack
#else
  fromTxt = BSL.fromStrict . T.encodeUtf8
#endif

