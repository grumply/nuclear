module Data.JSTime where

import Ef.Base

import Data.JSText
import GHC.Generics

import Data.Ratio

import Data.Time.Clock.POSIX

import Nuclear.ToBS
import Nuclear.FromBS
import Nuclear.ToText

-- milliseconds since beginning of 1970
newtype JSTime = JSTime { millis :: Integer }
  deriving (Show,Eq,Ord,Generic,ToJSON,FromJSON)
instance ToBS JSTime
instance FromBS JSTime
instance ToText JSTime
instance Num JSTime where
  (*) (JSTime t0) (JSTime t1) = JSTime (t0 * t1)
  (-) (JSTime t0) (JSTime t1) = JSTime (t0 - t1)
  (+) (JSTime t0) (JSTime t1) = JSTime (t0 + t1)
  abs = JSTime . abs . millis
  signum = JSTime . signum . millis
  fromInteger = JSTime

jstime :: (Monad super, MonadIO super) => super JSTime
jstime = timeInMillis

timeInMillis :: (Monad super, MonadIO super) => super JSTime
timeInMillis =
  (JSTime . posixToMillis) <$> (liftIO getPOSIXTime)

class FromJSTime a where
  fromJSTime :: JSTime -> a

instance FromJSTime POSIXTime where
  fromJSTime (JSTime jst) = posixFromMillis jst

posixToMillis :: POSIXTime -> Integer
posixToMillis =
  (`div` 1000)
  . numerator
  . toRational
  . (* 1000000)

posixFromMillis :: Integer -> POSIXTime
posixFromMillis =
  fromRational
  . (% 1000000)
  . (* 1000)
