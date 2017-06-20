-- a port of Kristofer Joseph's Apache licensed Flexbox Grid css
-- from: https://github.com/kristoferjoseph/flexboxgrid
{-# language OverloadedStrings #-}
{-# language TemplateHaskell #-}
{-# language NoOverloadedLists #-}
{-# language ViewPatterns #-}
module Atomic.Grid where

import Atomic.CSS
import Atomic.ToTxt

import Data.Txt (Txt)

import Control.Monad
import Data.Foldable (foldr1)
import Data.Traversable (for)
import Data.Monoid

import Prelude hiding (or,and,rem,reverse)

onXS = id

onSM = atMedia (screenMinWidth (ems 48))

onMD = atMedia (screenMinWidth (ems 64))

onLG = atMedia (screenMinWidth (ems 75))

onXL = atMedia (screenMinWidth (ems 90))

data FlexSize = Xs | Sm | Md | Lg | Xl
instance ToTxt FlexSize where
  toTxt sz =
    case sz of
      Xs -> "xs"
      Sm -> "sm"
      Md -> "md"
      Lg -> "lg"
      Xl -> "xl"

uContainer :: Txt
uContainer = "u-container"

uContainerFluid :: Txt
uContainerFluid = "u-container-fluid"

uRow :: Txt
uRow = "u-row"

uReverse :: Txt
uReverse = "u-reverse"

uCol :: Txt
uCol = "u-col"

uHiddenUp :: FlexSize -> Txt
uHiddenUp (toTxt -> sz) = "u-hidden-" <> sz <> "-up"

uHiddenDown :: FlexSize -> Txt
uHiddenDown (toTxt -> sz) = "u-hidden-" <> sz <> "-down"

uCols :: FlexSize -> Int -> Txt
uCols (toTxt -> sz) (toTxt -> n) = "u-col-" <> sz <> "-" <> n

uColsGrow :: FlexSize -> Txt
uColsGrow (toTxt -> sz) = "u-cols-" <> sz

uColsOffset :: FlexSize -> Int -> Txt
uColsOffset (toTxt -> sz) (toTxt -> n) = "u-col-" <> sz <> "-offset-" <> n

uStart :: FlexSize -> Txt
uStart (toTxt -> sz)= "u-start-" <> sz

uCenter :: FlexSize -> Txt
uCenter (toTxt -> sz) = "u-center-" <> sz

uEnd :: FlexSize -> Txt
uEnd (toTxt -> sz) = "u-end-" <> sz

uTop :: FlexSize -> Txt
uTop (toTxt -> sz) = "u-top-" <> sz

uMiddle :: FlexSize -> Txt
uMiddle (toTxt -> sz) = "u-middle-" <> sz

uBottom :: FlexSize -> Txt
uBottom (toTxt -> sz) = "u-bottom-" <> sz

uAround :: FlexSize -> Txt
uAround (toTxt -> sz) = "u-around-" <> sz

uBetween :: FlexSize -> Txt
uBetween (toTxt -> sz) = "u-between-" <> sz

uFirst :: FlexSize -> Txt
uFirst (toTxt -> sz) = "u-first-" <> sz

uLast :: FlexSize -> Txt
uLast (toTxt -> sz) = "u-last-" <> sz

flexboxGrid = let c = classify in void $ do
  is (c uContainer) .
    or is (c uContainerFluid) .> do
      marginRight  =: auto
      marginLeft   =: auto
      maxWidth     =: calc(per 100 <<>> "-" <<>> rems 1)
      paddingLeft  =: rems 0.5
      paddingRight =: rems 0.5

  is (c uContainerFluid) .> do
    paddingRight =: rems 2
    paddingLeft  =: rems 2
    marginLeft   =: neg (rems 0.5)
    marginRight  =: neg (rems 0.5)

  is (c uRow) .> do
    boxSizing          =: borderBox
    display            =: webkitBox
    display            =: msFlexBox
    display            =: flex
    webkitBoxFlex      =: zero
    msFlex             =: zero <<>> one <<>> auto
    flex               =: zero <<>> one <<>> auto
    webkitBoxOrient    =: horizontal
    webkitBoxDirection =: normal
    msFlexDirection    =: rowS
    flexDirection      =: rowS
    msFlexWrap         =: wrapS
    flexWrap           =: wrapS
    marginRight        =: neg (rems 0.5)
    marginLeft         =: neg (rems 0.5)

  is (c uRow) .
    and is (c uReverse) .> do
      webkitBoxOrient    =: horizontal
      webkitBoxDirection =: reverse
      msFlexDirection    =: rowReverse
      flexDirection      =: rowReverse

  is (c uCol) .
    and is (c uReverse) .> do
      webkitBoxOrient    =: vertical
      webkitBoxDirection =: reverse
      msFlexDirection    =: columnReverse
      flexDirection      =: columnReverse

  is (c $ uHiddenUp Xs) .>
    display =: noneS

  is (c $ uHiddenDown Xl) .>
    display =: noneS

  for [(Xs,Nothing),(Sm,Just 48),(Md,Just 64),(Lg,Just 75),(Xl,Just 90)] $ \(sz,mn) -> do

    maybe id (atMedia . screenMaxWidth . ems) mn $
      is (c $ uHiddenDown sz) .>
        important (display =: noneS)

    maybe id (atMedia . screenMinWidth . ems) mn $ do

      is (c $ uHiddenUp sz) .>
        important (display =: noneS)

      for mn $ \n ->
        is (c uContainer) .>
          -- really, relative ems? Our breakpoint is em-based....
          -- I don't quite understand the interaction here.
          width =: rems (n + 1)

      columns <-
        is (c $ uColsGrow sz) .
          or is (c $ uColsOffset sz 0) .>
            extendable (important $ do
              boxSizing     =: borderBox
              webkitBoxFlex =: zero
              msFlex        =: zero <<>> zero <<>> auto
              flex          =: zero <<>> zero <<>> auto
              paddingRight  =: rems 0.5
              paddingLeft   =: rems 0.5
              )

      is (c $ uCols sz 12) .>
        extends columns

      for [1..11] $ \i ->
        is (c $ uCols sz i) .
          or is (c $ uColsOffset sz i) .>
            extends columns

      is (c $ uColsGrow sz) .> do
        webkitBoxFlex       =: one
        msFlexPositive      =: one
        flexGrow            =: one
        msFlexPreferredSize =: zero
        flexBasis           =: zero
        maxWidth            =: per 100

      is (c $ uColsOffset sz 0) .>
        marginLeft =: zero

      is (c $ uColsOffset sz 12) .> do
        msFlexPreferredSize =: per 100
        flexBasis           =: per 100
        maxWidth            =: per 100

      is (c $ uCols sz 0) .> do
        overflow =: hiddenS
        height =: per 0

      for [0..11] $ \i -> do
        -- close enough?
        let p = per (fromIntegral i * 8.33333333)

        is (c $ uCols sz i) .> do
          msFlexPreferredSize =: p
          flexBasis           =: p
          maxWidth            =: p

        is (c $ uColsOffset sz i) .>
          marginLeft =: p

      is (c $ uStart sz) .> do
        webkitBoxPack  =: startS
        msFlexPack     =: startS
        justifyContent =: flexStart
        textAlign      =: startS

      is (c $ uCenter sz) .> do
        webkitBoxPack  =: center
        msFlexPack     =: center
        justifyContent =: center
        textAlign      =: center

      is (c $ uEnd sz) .> do
        webkitBoxPack  =: endS
        msFlexPack     =: endS
        textAlign      =: endS
        justifyContent =: flexEnd

      is (c $ uTop sz) .> do
        webkitBoxAlign =: startS
        msFlexAlign    =: startS
        alignItems     =: flexStart

      is (c $ uMiddle sz) .> do
        webkitBoxAlign =: center
        msFlexAlign    =: center
        alignItems     =: center

      is (c $ uBottom sz) .> do
        webkitBoxAlign =: endS
        msFlexAlign    =: endS
        alignItems     =: flexEnd

      is (c $ uAround sz) .> do
        msFlexPack     =: distribute
        justifyContent =: spaceAround

      is (c $ uBetween sz) .> do
        webkitBoxPack  =: justify
        msFlexPack     =: justify
        justifyContent =: spaceBetween

      is (c $ uFirst sz) .> do
        webkitBoxOrdinalGroup =: zero
        msFlexOrder           =: neg (int 1)
        order                 =: neg (int 1)

      is (c $ uLast sz) .> do
        webkitBoxOrdinalGroup =: int 2
        msFlexOrder           =: one
        order                 =: one
