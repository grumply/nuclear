{-# language UndecidableInstances #-}
module Atomic.Cond where

import Control.Lens.Empty
import Control.Lens.Prism

import Data.Maybe
import Data.Txt

class Cond a where
  nil :: a

infix 9 ?
(?) :: (Cond x, Eq x) => x -> a -> a -> a
(?) x t e = if notNil x then t else e

infix 9 ?&
(?&) :: (Cond x, Eq x) => x -> a -> a -> a
(?&) x t e = x ? e $ t

cond :: Cond a => Bool -> a -> a
cond b t = b ? t $ nil

may :: Cond a => (b -> a) -> Maybe b -> a
may = maybe nil

ncond :: Cond a => Bool -> a -> a
ncond b = cond (not b)

isNil :: (Cond a, Eq a) => a -> Bool
isNil = (== nil)

notNil :: (Cond a, Eq a) => a -> Bool
notNil = (/= nil)

instance Cond [a] where
  nil = []

instance Cond (Maybe a) where
  nil = Nothing

instance Cond Bool where
  nil = False

instance {-# OVERLAPPABLE #-} (Monoid a, Eq a) => Cond a where
  nil = mempty
