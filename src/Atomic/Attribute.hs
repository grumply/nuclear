{-# language DeriveDataTypeable #-}
{-# language OverloadedStrings #-}
{-# language TemplateHaskell #-}
{-# language StandaloneDeriving #-}
{-# language PatternSynonyms #-}
{-# language ViewPatterns #-}
{-# language CPP #-}
module Atomic.Attribute where

import Ef.Base hiding (Object,object)

import Data.Txt as T hiding (readIntMaybe)
import qualified Data.Txt as T
import Data.JSON hiding (Options)

import Atomic.Default
import Atomic.FromTxt
import Atomic.ToTxt
import Atomic.Cond
import Atomic.UnsafeEq

import Data.Data
import Data.Maybe
import Data.String
import Data.Typeable
import Data.Void

import GHC.Exts

import qualified Data.Function as F
import Data.List (sortBy)

-- import Control.Lens (makePrisms,makeLenses)

import Prelude

#ifdef __GHCJS__
import qualified Data.JSString as JSS
import qualified GHCJS.DOM.Types as T
import qualified GHCJS.DOM.Window as W
import qualified GHCJS.DOM.Document as D
import qualified GHCJS.DOM.Location as L
import qualified Data.JSString.Read as T
#else
import qualified Data.Text as JSS
import Data.Aeson (Value(..))
import Data.Text.Read as T
#endif

type Win =
#ifdef __GHCJS__
  W.Window
#else
  ()
#endif

type Doc =
#ifdef __GHCJS__
  D.Document
#else
  ()
#endif

type ENode =
#ifdef __GHCJS__
  T.Element
#else
  ()
#endif

type TNode =
#ifdef __GHCJS__
  T.Text
#else
  ()
#endif

type NNode =
#ifdef __GHCJS__
  T.Node
#else
  ()
#endif

type Loc =
#ifdef __GHCJS__
  L.Location
#else
  ()
#endif

data Options = Options
  { _preventDef :: Bool
  , _stopProp   :: Bool
  } deriving (Eq)

instance Default Options where
  def = Options False False

data Feature (ms :: [* -> *])
  = NullFeature
  | Attribute
    { _attr :: Txt
    , _value :: Txt
    }
  | DelayedAttribute
    { _attr :: Txt
    , _value :: Txt
    }
  | Property
    { _prop :: Txt
    , _value :: Txt
    }
  | DelayedProperty
    { _prop :: Txt
    , _value :: Txt
    }
  | StyleF
    { _stylePairs :: [(Txt,Txt)] }
  | OnE
    { _eventName :: Txt
    , _eventOptions :: Options
    , _eventCreate :: ((IO (),ENode,Obj) -> IO (Maybe (Ef ms IO ())))
    , _eventListener :: (Maybe (IO ()))
    }
  | OnWindow
    { _eventName :: Txt
    , _eventOptions :: Options
    , _eventWinCreate :: ((IO (),ENode,Win,Obj) -> IO (Maybe (Ef ms IO ())))
    , _eventListener :: Maybe (IO ())
    }
  | OnDocument
    { _eventName :: Txt
    , _eventOptions :: Options
    , _eventDocCreate :: ((IO (),ENode,Doc,Obj) -> IO (Maybe (Ef ms IO ())))
    , _eventListener :: (Maybe (IO ()))
    }
  | OnFeatureAdd
    { _featureAddEvent :: (ENode -> Ef ms IO ())
    }
  | OnFeatureRemove
    { _featureRemoveEvent :: (ENode -> Ef ms IO ())
    }
  | OnWillMount
    { _willMountEvent :: (ENode -> IO ())
    }
  | OnDidMount
    { _didMountEvent :: (ENode -> IO ())
    }
  | forall model. Typeable model => DiffFeature
    { _diffFeatureOn :: model
    , _diffedFeature :: Feature ms
    }
  | forall model. Typeable model => OnModelChangeIO
    { _updateModel :: model
    , _updateEvent :: (model -> model -> ENode -> IO ())
    }
  | forall model. Typeable model => OnModelChange
    { _watchModel :: model
    , _modelEvent :: (model -> model -> ENode -> Ef ms IO ())
    }
  | OnWillUnmount
    { _willUnmountEvent :: (ENode -> IO ())
    }
  | OnDidUnmount
    { _didUnmountEvent :: (ENode -> IO ())
    }
  | LinkTo
    { _link :: Txt
    , _eventListener :: (Maybe (IO ()))
    }
  | SVGLinkTo
    { _link :: Txt
    , _eventListener :: (Maybe (IO ()))
    }
  | XLink
    { _attr :: Txt
    , _value :: Txt
    }

instance ToJSON (Feature ms) where
  toJSON f =
#ifdef __GHCJS__
    objectValue $
#endif
      go f
    where
      go NullFeature = object [ "type" .= ("null" :: Txt)]
      go (Property k v) = object [ "type" .= ("prop" :: Txt), "prop" .= k, "val" .= v]
      go (DelayedProperty k v) = object [ "type" .= ("dprop" :: Txt), "prop" .= k, "val" .= v]
      go (Attribute k v) = object [ "type" .= ("attr" :: Txt), "attr" .= k, "val" .= v]
      go (DelayedAttribute k v) = object ["type" .= ("dattr" :: Txt), "attr" .= k, "val" .= v]
      go (StyleF ss) = object [ "type" .= ("style" :: Txt), "styles" .= ss ]
      go (LinkTo e _) = object [ "type" .= ("link" :: Txt), "link" .= e]
      go (SVGLinkTo e _) = object [ "type" .= ("svglink" :: Txt), "link" .= e ]
      go (XLink k v) = object [ "type" .= ("xlink" :: Txt), "key" .= k, "val" .= v]
      go (DiffFeature m f) = go f
      go _ = object []

instance FromJSON (Feature ms) where
  parseJSON o0 = do
#ifdef __GHCJS__
    flip (withObject "obj") o0 $ \o -> do
#else
      let (Object o) = o0
#endif
      t <- o .: "type"
      case t :: Txt of
        "null" ->
          pure NullFeature
        "attr" -> do
          k <- o .: "attr"
          v <- o .: "val"
          pure $ Attribute k v
        "dattr" -> do
          k <- o .: "attr"
          v <- o .: "val"
          pure $ DelayedAttribute k v
        "prop" -> do
          k <- o .: "prop"
          v <- o .: "val"
          pure $ Property k v
        "dprop" -> do
          k <- o .: "prop"
          v <- o .: "val"
          pure $ DelayedProperty k v
        "style" -> do
          ss <- o .: "styles"
          pure $ StyleF ss
        "link" -> do
          l <- o .: "link"
          pure $ LinkTo l Nothing
        "svglink" -> do
          l <- o .: "link"
          pure $ SVGLinkTo l Nothing
        "xlink" -> do
          k <- o .: "key"
          v <- o .: "val"
          pure $ XLink k v
        _ -> Ef.Base.empty

instance Eq (Feature ms) where
  (==) NullFeature NullFeature = True
  (==) (Property p v) (Property p' v') =
    prettyUnsafeEq p p' && prettyUnsafeEq v v'
  (==) (DelayedProperty p v) (DelayedProperty p' v') =
    prettyUnsafeEq p p' && prettyUnsafeEq v v'
  (==) (Attribute a v) (Attribute a' v') =
    prettyUnsafeEq a a' && prettyUnsafeEq v v'
  (==) (DelayedAttribute a v) (DelayedAttribute a' v') =
    prettyUnsafeEq a a' && prettyUnsafeEq v v'
  (==) (StyleF ss) (StyleF ss') =
    reallyUnsafeEq ss ss' || (==) (sortBy (compare `F.on` fst) ss) (sortBy (compare `F.on` fst) ss')
  (==) (DiffFeature m f) (DiffFeature m' f') =
    reallyVeryUnsafeEq m m'
  (==) (OnE e os ev _) (OnE e' os' ev' _) =
    prettyUnsafeEq e e' && prettyUnsafeEq os os'
  (==) (OnWindow e os ev _) (OnWindow e' os' ev' _) =
    prettyUnsafeEq e e' && prettyUnsafeEq os os'
  (==) (OnDocument e os ev _) (OnDocument e' os' ev' _) =
    prettyUnsafeEq e e' && prettyUnsafeEq os os'
  (==) (OnFeatureAdd e) (OnFeatureAdd e') =
    reallyUnsafeEq e e'
  (==) (OnFeatureRemove e) (OnFeatureRemove e') =
    reallyUnsafeEq e e'
  (==) (OnWillMount e) (OnWillMount e') =
    reallyUnsafeEq e e'
  (==) (OnDidMount e) (OnDidMount e') =
    reallyUnsafeEq e e'
  (==) (OnModelChangeIO m f) (OnModelChangeIO m' f') =
    typeOf m == typeOf m' && reallyVeryUnsafeEq m m' && reallyVeryUnsafeEq f f'
  (==) (OnModelChange m f) (OnModelChange m' f') =
    typeOf m == typeOf m' && reallyVeryUnsafeEq m m' && reallyVeryUnsafeEq f f'
  (==) (OnWillUnmount e) (OnWillUnmount e') =
    reallyUnsafeEq e e'
  (==) (OnDidUnmount e) (OnDidUnmount e') =
    reallyUnsafeEq e e'
  (==) (LinkTo t _) (LinkTo t' _) =
    prettyUnsafeEq t t'
  (==) (SVGLinkTo t _) (SVGLinkTo t' _) =
    prettyUnsafeEq t t'
  (==) (XLink t _) (XLink t' _) =
    prettyUnsafeEq t t'
  (==) _ _ = False

instance Cond (Feature ms) where
  nil = NullFeature

-- instance IsString (Feature ms) where
--   fromString = Attribute "class" . fromString

-- instance GHC.Exts.IsList (Feature ms) where
--   type Item (Feature ms) = Txt
--   fromList = fromTxt . T.intercalate " "
--   toList (Attribute "class" cs) = T.words cs
--   toList _ = []

-- -- is this a terrible idea?
-- instance GHC.Exts.IsList ([a] -> [a]) where
--   type Item ([a] -> [a]) = a
--   fromList = go
--     where
--       go [] xs' = xs'
--       go (x:xs) xs' = x:go xs xs'
--   toList f = f []

-- instance {-# OVERLAPS #-} IsString [Feature ms] where
--   fromString s = [fromString s]

-- instance FromTxt (Feature ms) where
--   fromTxt = Attribute "class" . fromTxt

-- instance FromTxt [Feature ms] where
--   fromTxt t = [fromTxt t]

pattern Attr k v <- (Attribute k v) where
  Attr k v = Attribute k v

pattern DelayedAttr k v <- (DelayedAttribute k v) where
  DelayedAttr k v = DelayedAttribute k v

pattern Prop k v <- (Property k v) where
  Prop k v = Property k v

pattern DelayedProp k v <- (DelayedProperty k v) where
  DelayedProp k v = DelayedProperty k v

delayedFeature (DelayedAttribute k v) = Attribute k v
delayedFeature (DelayedProperty k v) = Property k v
delayedFeature x = x

delayFeature (Attribute k v) = DelayedAttribute k v
delayFeature (Property k v) = DelayedProperty k v
delayFeature x = x

pattern Delay x <- (delayedFeature -> x) where
  Delay x = delayFeature x

checkNotNull p = if T.null p then (False,p) else (True,p)

pattern BoolProp k b <- (Property k (checkNotNull -> (b,_))) where
  BoolProp k b = Property k (if b then "true" else "")

-- on :: Txt -> Ef ms IO () -> Feature ms
-- on ev e = OnE ev def (\_ -> return (Just e)) Nothing

pattern On ev f <- (OnE ev _ f _) where
  On ev f = OnE ev def f Nothing

pattern OnDoc ev f <- (OnDocument ev _ f _) where
  OnDoc ev f = OnDocument ev def f Nothing

pattern OnWin ev f <- (OnWindow ev _ f _) where
  OnWin ev f = OnWindow ev def f Nothing

pattern OnAdd f <- (OnFeatureAdd f) where
  OnAdd f = OnFeatureAdd f

pattern OnRemove f <- (OnFeatureRemove f) where
  OnRemove f = OnFeatureRemove f

pattern OnMounting f <- (OnWillMount f) where
  OnMounting f = OnWillMount f

pattern OnMounted f <- (OnDidMount f) where
  OnMounted f = OnDidMount f

pattern DiffOn model f <- DiffFeature model f where
  DiffOn model f = DiffFeature model f

-- watches a model, as supplied, and calls the callback during feature diffing; top-down
-- make sure the body of the function will not change; must be totally static modulo the model/enode!
-- That is, the only way to witness a value before and after a change is to track it via the model!
-- If it is untracked, the function will only ever see the value after the change because of the
-- way diffing is performed on Features.
pattern Watch mdl f <- (OnModelChange mdl f) where
  Watch mdl f = OnModelChange mdl f

-- watches a model, as supplied, and calls the callback during feature diffing; top-down
-- make sure the body of the function will not change; must be totally static modulo the model/enode!
-- That is, the only way to witness a value before and after a change is to track it via the model!
-- If it is untracked, the function will only ever see the value after the change because of the
-- way diffing is performed on Features.
pattern WatchIO mdl f <- (OnModelChangeIO mdl f) where
  WatchIO mdl f = OnModelChangeIO mdl f

-- runs when the attribute is being cleaned up; top-down
pattern OnUnmounting f <- (OnWillUnmount f) where
  OnUnmounting f = OnWillUnmount f

-- runs when the element is remove()'d, not when it is removed from the DOM; bottom-up
pattern OnUnmounted f <- (OnDidUnmount f) where
  OnUnmounted f = OnDidUnmount f

preventedDefault :: Feature ms -> (Bool,Feature ms)
preventedDefault f@(OnE _ (Options True _) _ _) = (True,f)
preventedDefault f@(OnDocument _ (Options True _) _ _) = (True,f)
preventedDefault f@(OnWindow _ (Options True _) _ _) = (True,f)
preventedDefault f = (False,f)

preventDefault :: Feature ms -> Feature ms
preventDefault (OnE ev os f m) = OnE ev (os { _preventDef = True }) f m
preventDefault (OnDocument ev os f m) = OnDocument ev (os { _preventDef = True }) f m
preventDefault (OnWindow ev os f m) = OnWindow ev (os { _preventDef = True }) f m
preventDefault f = f

pattern PreventDefault f <- (preventedDefault -> (True,f)) where
  PreventDefault f = preventDefault f

stoppedPropagation :: Feature ms -> (Bool,Feature ms)
stoppedPropagation f@(OnE _ (Options _ True) _ _) = (True,f)
stoppedPropagation f@(OnDocument _ (Options _ True) _ _) = (True,f)
stoppedPropagation f@(OnWindow _ (Options _ True) _ _) = (True,f)
stoppedPropagation f = (False,f)

stopPropagation :: Feature ms -> Feature ms
stopPropagation (OnE ev os f m) = OnE ev (os { _stopProp = True }) f m
stopPropagation (OnDocument ev os f m) = OnDocument ev (os { _stopProp = True }) f m
stopPropagation (OnWindow ev os f m) = OnWindow ev (os { _stopProp = True }) f m
stopPropagation f = f

pattern StopPropagation f <- (stoppedPropagation -> (True,f)) where
  StopPropagation f = stopPropagation f

intercepted :: Feature ms -> (Bool,Feature ms)
intercepted f@(OnE _ (Options True True) _ _) = (True,f)
intercepted f@(OnDocument _ (Options True True) _ _) = (True,f)
intercepted f@(OnWindow _ (Options True True) _ _) = (True,f)
intercepted f = (False,f)

intercept :: Feature ms -> Feature ms
intercept (OnE ev os f m) = OnE ev (os { _preventDef = True, _stopProp = True }) f m
intercept (OnDocument ev os f m) = OnDocument ev (os { _preventDef = True, _stopProp = True }) f m
intercept (OnWindow ev os f m) = OnWindow ev (os { _preventDef = True, _stopProp = True }) f m
intercept f = f

pattern Intercept f <- (intercepted -> (True,f)) where
  Intercept f = intercept f

pattern Styles ss <- (StyleF ss) where
  Styles ss = StyleF ss

-- l for local
pattern Lref l <- (LinkTo l _) where
  Lref l = LinkTo l Nothing

pattern Href v <- (Property "href" v) where
  Href v = Property "href" v

pattern Value v <- (Property "value" v) where
  Value v = Property "value" v

xlink :: Txt -> Txt -> Feature ms
xlink xl v = XLink xl v

pattern SVGLink l <- (SVGLinkTo l _) where
  SVGLink l = SVGLinkTo l Nothing

-- makePrisms ''Feature
-- makeLenses ''Feature
-- makePrisms ''Options
-- makeLenses ''Options

pattern ClassList cs <- (Attribute "class" (T.splitOn " " -> !cs)) where
  ClassList cs = Attribute "class" $! T.intercalate " " cs

toBool :: Txt -> Bool
toBool t = if t == "" then False else True

fromBool :: Bool -> Txt
fromBool b = if b then "true" else ""

readIntMaybe :: Txt -> Maybe Int
readIntMaybe t =
#ifdef __GHCJS__
  T.readIntMaybe t
#else
  either (\_ -> Nothing) (Just . fst) (T.signed T.decimal t)
#endif

-- not a fan of the inefficiency
-- addClass :: Txt -> [Feature ms] -> [Feature ms]
-- addClass c = go False
--   where
--     go False [] = [Attribute "class" c]
--     go True [] = []
--     go _ ((Attribute "class" cs):fs) = (Attribute "class" (c <> " " <> cs)) : go True fs
--     go b (f:fs) = f:go b fs

pattern Id p <- (Property "id" p) where
  Id p = Property "id" p

pattern TitleP p <- (Property "title" p) where
  TitleP p = Property "title" p

pattern Hidden b <- (Property "hidden" (toBool -> b)) where
  Hidden b = Property "hidden" (fromBool b)

pattern Type p <- (Property "type" p) where
  Type p = Property "type" p

pattern Role v <- (Attribute "role" v) where
  Role v = Attribute "role" v

pattern DefaultValue v <- (Attribute "default-value" v) where
  DefaultValue v = Attribute "default-value" v

pattern Checked b <- (Property "checked" (toBool -> b)) where
  Checked b = Property "checked" (fromBool b)

pattern DefaultChecked <- (Attribute "checked" "checked") where
  DefaultChecked = Attribute "checked" "checked"

pattern Placeholder p <- (Property "placeholder" p) where
  Placeholder p = Property "placeholder" p

pattern Selected b <- (Property "selected" (toBool -> b)) where
  Selected b = Property "selected" (fromBool b)

pattern Accept p <- (Property "accept" p) where
  Accept p = Property "accept" p

pattern AcceptCharset p <- (Property "accept-charset" p) where
  AcceptCharset p = Property "accept-charset" p

pattern Autocomplete b <- (Property "autocomplete" (toBool -> b)) where
  Autocomplete b = Property "autocomplete" (fromBool b)

pattern Autofocus b <- (Property "autofocus" (toBool -> b)) where
  Autofocus b = Property "autofocus" (fromBool b)

pattern Disabled b <- (Property "disabled" (toBool -> b)) where
  Disabled b = Property "disabled" (fromBool b)

pattern Enctyp p <- (Property "enctyp" p) where
  Enctyp p = Property "enctyp" p

pattern For v <- (Attribute "for" v) where
  For v = Attribute "for" v

pattern Formaction v <- (Attribute "formaction" v) where
  Formaction v = Attribute "formaction" v

pattern ListA v <- (Attribute "list" v) where
  ListA v = Attribute "list" v

pattern Maxlength i <- (Attribute "maxlength" (readIntMaybe -> Just i)) where
  Maxlength i = Attribute "maxlength" (toTxt i)

pattern Minlength i <- (Attribute "minlength" (readIntMaybe -> Just i)) where
  Minlength i = Attribute "minlength" (toTxt i)

pattern Method p <- (Property "method" p) where
  Method p = Property "method" p

pattern Multiple b <- (Property "multiple" (checkNotNull -> (b,_))) where
  Multiple b = Property "multiple" (if b then "multiple" else "")

pattern Muted b <- (Property "muted" (checkNotNull -> (b,_))) where
  Muted b = Property "muted" (if b then "muted" else "")

pattern Name p <- (Property "name" p) where
  Name p = Property "name" p

pattern Novalidate b <- (Property "novalidate" (toBool -> b)) where
  Novalidate b = Property "novalidate" (fromBool b)

pattern Pattern p <- (Property "pattern" p) where
  Pattern p = Property "pattern" p

pattern Readonly b <- (Property "readonly" (toBool -> b)) where
  Readonly b = Property "readonly" (fromBool b)

pattern Required b <- (Property "required" (toBool -> b)) where
  Required b = Property "required" (fromBool b)

pattern Size i <- (Attribute "size" (readIntMaybe -> Just i)) where
  Size i = Attribute "size" (toTxt i)

pattern HtmlFor p <- (Property "htmlFor" p) where
  HtmlFor p = Property "htmlFor" p

pattern FormA v <- (Attribute "form" v) where
  FormA v = Attribute "form" v

pattern Max p <- (Property "max" p) where
  Max p = Property "max" p

pattern Min p <- (Property "min" p) where
  Min p = Property "min" p

pattern Step p <- (Property "step" p) where
  Step p = Property "step" p

pattern Cols i <- (Attribute "cols" (readIntMaybe -> Just i)) where
  Cols i = Attribute "cols" (toTxt i)

pattern Rows i <- (Attribute "rows" (readIntMaybe -> Just i)) where
  Rows i = Attribute "rows" (toTxt i)

pattern Wrap p <- (Property "wrap" p) where
  Wrap p = Property "wrap" p

pattern Target p <- (Property "target" p) where
  Target p = Property "target" p

pattern Download b <- (Property "download" (toBool -> b)) where
  Download b = Property "download" (fromBool b)

pattern DownloadAs p <- (Property "download" (checkNotNull -> (True,p))) where
  DownloadAs p = Property "download" p

pattern Hreflang p <- (Property "hreflang" p) where
  Hreflang p = Property "hreflang" p

pattern Media v <- (Attribute "media" v) where
  Media v = Attribute "media" v

pattern Rel v <- (Attribute "rel" v) where
  Rel v = Attribute "rel" v

pattern Ismap b <- (Property "ismap" (toBool -> b)) where
  Ismap b = Property "ismap" (fromBool b)

pattern Usemap p <- (Property "usemap" p) where
  Usemap p = Property "usemap" p

pattern Shape p <- (Property "shape" p) where
  Shape p = Property "shape" p

pattern Coords p <- (Property "coords" p) where
  Coords p = Property "coords" p

pattern Keytype p <- (Property "keytype" p) where
  Keytype p = Property "keytype" p

pattern Src p <- (Property "src" p) where
  Src p = Property "src" p

pattern Height i <- (Attribute "height" (readIntMaybe -> Just i)) where
  Height i = Attribute "height" (toTxt i)

pattern Width i <- (Attribute "width" (readIntMaybe -> Just i)) where
  Width i = Attribute "width" (toTxt i)

pattern Alt p <- (Property "alt" p) where
  Alt p = Property "alt" p

pattern Autoplay b <- (Property "autoplay" (toBool -> b)) where
  Autoplay b = Property "autoplay" (fromBool b)

pattern Controls b <- (Property "controls" (toBool -> b)) where
  Controls b = Property "controls" (fromBool b)

pattern Loop b <- (Property "loop" (toBool -> b)) where
  Loop b = Property "loop" (fromBool b)

pattern Preload p <- (Property "preload" p) where
  Preload p = Property "preload" p

pattern Poster p <- (Property "poster" p) where
  Poster p = Property "poster" p

pattern Default b <- (Property "default" (toBool -> b)) where
  Default b = Property "default" (fromBool b)

pattern Kind p <- (Property "kind" p) where
  Kind p = Property "kind" p

pattern Srclang p <- (Property "srclang" p) where
  Srclang p = Property "srclang" p

pattern Sandbox p <- (Property "sandbox" p) where
  Sandbox p = Property "sandbox" p

pattern Seamless b <- (Property "seamless" (toBool -> b)) where
  Seamless b = Property "seamless" (fromBool b)

pattern Srcdoc p <- (Property "srcdoc" p) where
  Srcdoc p = Property "srcdoc" p

pattern Reversed b <- (Property "reversed" (toBool -> b)) where
  Reversed b = Property "reversed" (fromBool b)

pattern Start p <- (Property "start" p) where
  Start p = Property "start" p

pattern Align p <- (Property "align" p) where
  Align p = Property "align" p

pattern Colspan i <- (Attribute "colspan" (readIntMaybe -> Just i)) where
  Colspan i = Attribute "colspan" (toTxt i)

pattern Rowspan i <- (Attribute "rowspan" (readIntMaybe -> Just i)) where
  Rowspan i = Attribute "rowspan" (toTxt i)

pattern Headers p <- (Property "headers" p) where
  Headers p = Property "headers" p

pattern Scope p <- (Property "scope" p) where
  Scope p = Property "scope" p

pattern Async b <- (Property "async" (toBool -> b)) where
  Async b = Property "async" (fromBool b)

pattern Charset v <- (Attribute "charset" v) where
  Charset v = Attribute "charset" v

pattern Content p <- (Property "content" p) where
  Content p = Property "content" p

pattern Defer b <- (Property "defer" (toBool -> b)) where
  Defer b = Property "defer" (fromBool b)

pattern HttpEquiv p <- (Property "http-equiv" p) where
  HttpEquiv p = Property "http-equiv" p

pattern Language p <- (Property "language" p) where
  Language p = Property "language" p

pattern Scoped b <- (Property "scoped" (toBool -> b)) where
  Scoped b = Property "scoped" (fromBool b)

pattern Accesskey p <- (Property "accesskey" p) where
  Accesskey p = Property "accesskey" p

pattern Contenteditable b <- (Property "contenteditable" (toBool -> b)) where
  Contenteditable b = Property "contenteditable" (fromBool b)

pattern Contextmenu v <- (Attribute "contextmenu" v) where
  Contextmenu v = Attribute "contextmenu" v

pattern Dir p <- (Property "dir" p) where
  Dir p = Property "dir" p

pattern Draggable b <- (Attribute "draggable" (checkNotNull -> (b,_))) where
  Draggable b = Attribute "draggable" (if b then "true" else "false")

pattern Dropzone p <- (Property "dropzone" p) where
  Dropzone p = Property "dropzone" p

pattern Itemprop v <- (Attribute "itemprop" v) where
  Itemprop v = Attribute "itemprop" v

pattern Lang p <- (Property "lang" p) where
  Lang p = Property "lang" p

pattern Spellcheck b <- (Property "spellcheck" (toBool -> b)) where
  Spellcheck b = Property "spellcheck" (fromBool b)

pattern Tabindex i <- (Attribute "tabindex" (readIntMaybe -> Just i)) where
  Tabindex i = Attribute "tabindex" (toTxt i)

pattern CiteA p <- (Property "cite" p) where
  CiteA p = Property "cite" p

pattern Datetime v <- (Attribute "datetime" v) where
  Datetime v = Attribute "datetime" v

pattern Manifest v <- (Attribute "manifest" v) where
  Manifest v = Attribute "manifest" v

--------------------------------------------------------------------------------
-- SVG Attributes

pattern AccentHeight v <- (Attribute "accent-height" v) where
  AccentHeight v = Attribute "accent-height" v

pattern Accumulate v <- (Attribute "accumulate" v) where
  Accumulate v = Attribute "accumulate" v

pattern Additive v <- (Attribute "additive" v) where
  Additive v = Attribute "additive" v

pattern AlignmentBaseline v <- (Attribute "alignment-baseline" v) where
  AlignmentBaseline v = Attribute "alignment-baseline" v

pattern AllowReorder v <- (Attribute "allowReorder" v) where
  AllowReorder v = Attribute "allowReorder" v

pattern Alphabetic v <- (Attribute "alphabetic" v) where
  Alphabetic v = Attribute "alphabetic" v

pattern ArabicForm v <- (Attribute "arabic-form" v) where
  ArabicForm v = Attribute "arabic-form" v

pattern Ascent v <- (Attribute "ascent" v) where
  Ascent v = Attribute "ascent" v

pattern AttributeName v <- (Attribute "attributeName" v) where
  AttributeName v = Attribute "attributeName" v

pattern AttributeType v <- (Attribute "attributeType" v) where
  AttributeType v = Attribute "attributeType" v

pattern AutoReverse v <- (Attribute "autoReverse" v) where
  AutoReverse v = Attribute "autoReverse" v

pattern Azimuth v <- (Attribute "azimuth" v) where
  Azimuth v = Attribute "azimuth" v

pattern BaseFrequency v <- (Attribute "baseFrequency" v) where
  BaseFrequency v = Attribute "baseFrequency" v

pattern BaslineShift v <- (Attribute "basline-shift" v) where
  BaslineShift v = Attribute "basline-shift" v

pattern BaseProfile v <- (Attribute "baseProfile" v) where
  BaseProfile v = Attribute "baseProfile" v

pattern Bbox v <- (Attribute "bbox" v) where
  Bbox v = Attribute "bbox" v

pattern Begin v <- (Attribute "begin" v) where
  Begin v = Attribute "begin" v

pattern Bias v <- (Attribute "bias" v) where
  Bias v = Attribute "bias" v

pattern By v <- (Attribute "by" v) where
  By v = Attribute "by" v

pattern CalcMode v <- (Attribute "calcMode" v) where
  CalcMode v = Attribute "calcMode" v

pattern CapHeight v <- (Attribute "cap-height" v) where
  CapHeight v = Attribute "cap-height" v

pattern ClassName c <- (Property "className" c) where
  ClassName c = Property "className" c
-- pattern Class v <- (Attribute "class" v) where
--   Class v = Attribute "class" v

pattern Clip v <- (Attribute "clip" v) where
  Clip v = Attribute "clip" v

pattern ClipPathUnits v <- (Attribute "clipPathUnits" v) where
  ClipPathUnits v = Attribute "clipPathUnits" v

pattern ClipPath v <- (Attribute "clip-path" v) where
  ClipPath v = Attribute "clip-path" v

pattern ClipRule v <- (Attribute "clip-rule" v) where
  ClipRule v = Attribute "clip-rule" v

pattern Color v <- (Attribute "color" v) where
  Color v = Attribute "color" v

pattern ColorInterpolation v <- (Attribute "color-interpolation" v) where
  ColorInterpolation v = Attribute "color-interpolation" v

pattern ColorInterpolationFilters v <- (Attribute "color-interpolation-filters" v) where
  ColorInterpolationFilters v = Attribute "color-interpolation-filters" v

pattern ColorProfile v <- (Attribute "color-profile" v) where
  ColorProfile v = Attribute "color-profile" v

pattern ColorRendering v <- (Attribute "color-rendering" v) where
  ColorRendering v = Attribute "color-rendering" v

pattern ContentScriptType v <- (Attribute "contentScriptType" v) where
  ContentScriptType v = Attribute "contentScriptType" v

pattern ContentStyleType v <- (Attribute "contentStyleType" v) where
  ContentStyleType v = Attribute "contentStyleType" v

pattern Cursor v <- (Attribute "cursor" v) where
  Cursor v = Attribute "cursor" v

pattern Cx v <- (Attribute "cx" v) where
  Cx v = Attribute "cx" v

pattern Cy v <- (Attribute "cy" v) where
  Cy v = Attribute "cy" v

pattern D v <- (Attribute "d" v) where
  D v = Attribute "d" v

pattern Decelerate v <- (Attribute "decelerate" v) where
  Decelerate v = Attribute "decelerate" v

pattern Descent v <- (Attribute "descent" v) where
  Descent v = Attribute "descent" v

pattern DiffuseConstant v <- (Attribute "diffuseConstant" v) where
  DiffuseConstant v = Attribute "diffuseConstant" v

pattern Direction v <- (Attribute "direction" v) where
  Direction v = Attribute "direction" v

pattern Display v <- (Attribute "display" v) where
  Display v = Attribute "display" v

pattern Divisor v <- (Attribute "divisor" v) where
  Divisor v = Attribute "divisor" v

pattern DominantBaseline v <- (Attribute "dominant-baseline" v) where
  DominantBaseline v = Attribute "dominant-baseline" v

pattern Dur v <- (Attribute "dur" v) where
  Dur v = Attribute "dur" v

pattern Dx v <- (Attribute "dx" v) where
  Dx v = Attribute "dx" v

pattern Dy v <- (Attribute "dy" v) where
  Dy v = Attribute "dy" v

pattern EdgeMode v <- (Attribute "edgeMode" v) where
  EdgeMode v = Attribute "edgeMode" v

pattern Elevation v <- (Attribute "elevation" v) where
  Elevation v = Attribute "elevation" v

pattern EnableBackground v <- (Attribute "enable-background" v) where
  EnableBackground v = Attribute "enable-background" v

pattern End v <- (Attribute "end" v) where
  End v = Attribute "end" v

pattern Exponent v <- (Attribute "exponent" v) where
  Exponent v = Attribute "exponent" v

pattern ExternalResourcesRequired v <- (Attribute "externalResourcesRequired" v) where
  ExternalResourcesRequired v = Attribute "externalResourcesRequired" v

pattern Fill v <- (Attribute "fill" v) where
  Fill v = Attribute "fill" v

pattern FillOpacity v <- (Attribute "fill-opacity" v) where
  FillOpacity v = Attribute "fill-opacity" v

pattern FillRule v <- (Attribute "fill-rule" v) where
  FillRule v = Attribute "fill-rule" v

pattern Filter v <- (Attribute "filter" v) where
  Filter v = Attribute "filter" v

pattern FilterRes v <- (Attribute "filterRes" v) where
  FilterRes v = Attribute "filterRes" v

pattern FilterUnits v <- (Attribute "filterUnits" v) where
  FilterUnits v = Attribute "filterUnits" v

pattern FloodColor v <- (Attribute "flood-color" v) where
  FloodColor v = Attribute "flood-color" v

pattern FontFamily v <- (Attribute "font-family" v) where
  FontFamily v = Attribute "font-family" v

pattern FontSize v <- (Attribute "font-size" v) where
  FontSize v = Attribute "font-size" v

pattern FontSizeAdjust v <- (Attribute "font-size-adjust" v) where
  FontSizeAdjust v = Attribute "font-size-adjust" v

pattern FontStretch v <- (Attribute "font-stretch" v) where
  FontStretch v = Attribute "font-stretch" v

pattern FontStyle v <- (Attribute "font-style" v) where
  FontStyle v = Attribute "font-style" v

pattern FontVariant v <- (Attribute "font-variant" v) where
  FontVariant v = Attribute "font-variant" v

pattern FontWeight v <- (Attribute "font-weight" v) where
  FontWeight v = Attribute "font-weight" v

pattern Format v <- (Attribute "format" v) where
  Format v = Attribute "format" v

pattern From v <- (Attribute "from" v) where
  From v = Attribute "from" v

pattern Fx v <- (Attribute "fx" v) where
  Fx v = Attribute "fx" v

pattern Fy v <- (Attribute "fy" v) where
  Fy v = Attribute "fy" v

pattern G1 v <- (Attribute "g1" v) where
  G1 v = Attribute "g1" v

pattern G2 v <- (Attribute "g2" v) where
  G2 v = Attribute "g2" v

pattern GlyphName v <- (Attribute "glyph-name" v) where
  GlyphName v = Attribute "glyph-name" v

pattern GlyphOrientationHorizontal v <- (Attribute "glyph-orientation-horizontal" v) where
  GlyphOrientationHorizontal v = Attribute "glyph-orientation-horizontal" v

pattern GlyphOrientationVertical v <- (Attribute "glyph-orientation-vertial" v) where
  GlyphOrientationVertical v = Attribute "glyph-orientation-vertical" v

pattern GlyphRef v <- (Attribute "glyphRef" v) where
  GlyphRef v = Attribute "glyphRef" v

pattern GradientTransform v <- (Attribute "gradientTransform" v) where
  GradientTransform v = Attribute "gradientTransform" v

pattern GradientUnits v <- (Attribute "gradientUnits" v) where
  GradientUnits v = Attribute "gradientUnits" v

pattern Hanging v <- (Attribute "hanging" v) where
  Hanging v = Attribute "hanging" v

pattern HorizAdvX v <- (Attribute "horiz-adv-x" v) where
  HorizAdvX v = Attribute "horiz-adv-x" v

pattern HorizOriginX v <- (Attribute "horiz-origin-x" v) where
  HorizOriginX v = Attribute "horiz-origin-x" v

pattern Ideographic v <- (Attribute "ideographic" v) where
  Ideographic v = Attribute "ideographic" v

pattern ImageRendering v <- (Attribute "image-rendering" v) where
  ImageRendering v = Attribute "image-rendering" v

pattern In v <- (Attribute "in" v) where
  In v = Attribute "in" v

pattern In2 v <- (Attribute "in2" v) where
  In2 v = Attribute "in2" v

-- pattern Intercept v <- (Attribute "intercept" v) where
--   Intercept v = Attribute "intercept" v

pattern K v <- (Attribute "k" v) where
  K v = Attribute "k" v

pattern K1 v <- (Attribute "k1" v) where
  K1 v = Attribute "k1" v

pattern K2 v <- (Attribute "k2" v) where
  K2 v = Attribute "k2" v

pattern K3 v <- (Attribute "k3" v) where
  K3 v = Attribute "k3" v

pattern K4 v <- (Attribute "k4" v) where
  K4 v = Attribute "k4" v

pattern KernelMatrix v <- (Attribute "kernelMatrix" v) where
  KernelMatrix v = Attribute "kernelMatrix" v

pattern KernelUnitLength v <- (Attribute "kernelUnitLength" v) where
  KernelUnitLength v = Attribute "kernelUnitLength" v

pattern Kerning v <- (Attribute "kerning" v) where
  Kerning v = Attribute "kerning" v

pattern KeyPoints v <- (Attribute "keyPoints" v) where
  KeyPoints v = Attribute "keyPoints" v

pattern KeySplines v <- (Attribute "keySplines" v) where
  KeySplines v = Attribute "keySplines" v

pattern KeyTimes v <- (Attribute "keyTimes" v) where
  KeyTimes v = Attribute "keyTimes" v

pattern LengthAdjust v <- (Attribute "lengthAdjust" v) where
  LengthAdjust v = Attribute "lengthAdjust" v

pattern LetterSpacing v <- (Attribute "letter-spacing" v) where
  LetterSpacing v = Attribute "letter-spacing" v

pattern LightingColor v <- (Attribute "lighting-color" v) where
  LightingColor v = Attribute "lighting-color" v

pattern LimitingConeAngle v <- (Attribute "limitingConeAngle" v) where
  LimitingConeAngle v = Attribute "limitingConeAngle" v

pattern Local v <- (Attribute "local" v) where
  Local v = Attribute "local" v

pattern MarkerEnd v <- (Attribute "marker-end" v) where
  MarkerEnd v = Attribute "marker-end" v

pattern MarkerMid v <- (Attribute "marker-mid" v) where
  MarkerMid v = Attribute "marker-mid" v

pattern MarkerStart v <- (Attribute "marker-start" v) where
  MarkerStart v = Attribute "marker-start" v

pattern MarkerHeight v <- (Attribute "markerHeight" v) where
  MarkerHeight v = Attribute "markerHeight" v

pattern MarkerUnits v <- (Attribute "markerUnits" v) where
  MarkerUnits v = Attribute "markerUnits" v

pattern MarkerWidth v <- (Attribute "markerWidth" v) where
  MarkerWidth v = Attribute "markerWidth" v

pattern MaskA v <- (Attribute "maskA" v) where
  MaskA v = Attribute "maskA" v

pattern MaskContentUnits v <- (Attribute "maskContentUnits" v) where
  MaskContentUnits v = Attribute "maskContentUnits" v

pattern MaskUnits v <- (Attribute "maskUnits" v) where
  MaskUnits v = Attribute "maskUnits" v

pattern Mathematical v <- (Attribute "mathematical" v) where
  Mathematical v = Attribute "mathematical" v

pattern Mode v <- (Attribute "mode" v) where
  Mode v = Attribute "mode" v

pattern NumOctaves v <- (Attribute "numOctaves" v) where
  NumOctaves v = Attribute "numOctaves" v

pattern Offset v <- (Attribute "offset" v) where
  Offset v = Attribute "offset" v

pattern Onabort v <- (Attribute "onabort" v) where
  Onabort v = Attribute "onabort" v

pattern Onactivate v <- (Attribute "onactivate" v) where
  Onactivate v = Attribute "onactivate" v

pattern Onbegin v <- (Attribute "onbegin" v) where
  Onbegin v = Attribute "onbegin" v

pattern Onclick v <- (Attribute "onclick" v) where
  Onclick v = Attribute "onclick" v

pattern Onend v <- (Attribute "onend" v) where
  Onend v = Attribute "onend" v

pattern Onerror v <- (Attribute "onerror" v) where
  Onerror v = Attribute "onerror" v

pattern Onfocusin v <- (Attribute "onfocusin" v) where
  Onfocusin v = Attribute "onfocusin" v

pattern Onfocusout v <- (Attribute "onfocusout" v) where
  Onfocusout v = Attribute "onfocusout" v

pattern Onload v <- (Attribute "onload" v) where
  Onload v = Attribute "onload" v

pattern Onmousedown v <- (Attribute "onmousedown" v) where
  Onmousedown v = Attribute "onmousedown" v

pattern Onmousemove v <- (Attribute "onmousemove" v) where
  Onmousemove v = Attribute "onmousemove" v

pattern Onmouseout v <- (Attribute "onmouseout" v) where
  Onmouseout v = Attribute "onmouseout" v

pattern Onmouseover v <- (Attribute "onmouseover" v) where
  Onmouseover v = Attribute "onmouseover" v

pattern Onmouseup v <- (Attribute "onmouseup" v) where
  Onmouseup v = Attribute "onmouseup" v

pattern Onrepeat v <- (Attribute "onrepeat" v) where
  Onrepeat v = Attribute "onrepeat" v

pattern Onresize v <- (Attribute "onresize" v) where
  Onresize v = Attribute "onresize" v

pattern Onscroll v <- (Attribute "onscroll" v) where
  Onscroll v = Attribute "onscroll" v

pattern Onunload v <- (Attribute "onunload" v) where
  Onunload v = Attribute "onunload" v

pattern Onzoom v <- (Attribute "onzoom" v) where
  Onzoom v = Attribute "onzoom" v

pattern Opacity v <- (Attribute "opacity" v) where
  Opacity v = Attribute "opacity" v

pattern Operator v <- (Attribute "operator" v) where
  Operator v = Attribute "operator" v

pattern Order v <- (Attribute "order" v) where
  Order v = Attribute "order" v

pattern Orient v <- (Attribute "orient" v) where
  Orient v = Attribute "orient" v

pattern Orientation v <- (Attribute "orientation" v) where
  Orientation v = Attribute "orientation" v

pattern Origin v <- (Attribute "origin" v) where
  Origin v = Attribute "origin" v

pattern Overflow v <- (Attribute "overflow" v) where
  Overflow v = Attribute "overflow" v

pattern OverlinePosition v <- (Attribute "overline-position" v) where
  OverlinePosition v = Attribute "overline-position" v

pattern OverlineThickness v <- (Attribute "overline-thickness" v) where
  OverlineThickness v = Attribute "overline-thickness" v

pattern Panose1 v <- (Attribute "panose-1" v) where
  Panose1 v = Attribute "panose-1" v

pattern PaintOrder v <- (Attribute "paint-order" v) where
  PaintOrder v = Attribute "paint-order" v

pattern PathLength v <- (Attribute "pathLength" v) where
  PathLength v = Attribute "pathLength" v

pattern PatternContentUnits v <- (Attribute "patternContentUnits" v) where
  PatternContentUnits v = Attribute "patternContentUnits" v

pattern PatternTransform v <- (Attribute "patternTransform" v) where
  PatternTransform v = Attribute "patternTransform" v

pattern PatternUnits v <- (Attribute "patternUnits" v) where
  PatternUnits v = Attribute "patternUnits" v

pattern PointerEvents v <- (Attribute "pointer-events" v) where
  PointerEvents v = Attribute "pointer-events" v

pattern Points v <- (Attribute "points" v) where
  Points v = Attribute "points" v

pattern PointsAtX v <- (Attribute "pointsAtX" v) where
  PointsAtX v = Attribute "pointsAtX" v

pattern PointsAtY v <- (Attribute "pointsAtY" v) where
  PointsAtY v = Attribute "pointsAtY" v

pattern PointsAtZ v <- (Attribute "pointsAtZ" v) where
  PointsAtZ v = Attribute "pointsAtZ" v

pattern PreserveAlpha v <- (Attribute "preserveAlpha" v) where
  PreserveAlpha v = Attribute "preserveAlpha" v

pattern PreserveAspectRatio v <- (Attribute "preserveAspectRatio" v) where
  PreserveAspectRatio v = Attribute "preserveAspectRatio" v

pattern PrimitiveUnits v <- (Attribute "primitiveUnits" v) where
  PrimitiveUnits v = Attribute "primitiveUnits" v

pattern R v <- (Attribute "r" v) where
  R v = Attribute "r" v

pattern Radius v <- (Attribute "radius" v) where
  Radius v = Attribute "radius" v

pattern RefX v <- (Attribute "refX" v) where
  RefX v = Attribute "refX" v

pattern RefY v <- (Attribute "refY" v) where
  RefY v = Attribute "refY" v

pattern RenderingIntent v <- (Attribute "rendering-intent" v) where
  RenderingIntent v = Attribute "rendering-intent" v

pattern RepeatCount v <- (Attribute "repeatCount" v) where
  RepeatCount v = Attribute "repeatCount" v

pattern RepeatDur v <- (Attribute "repeatDur" v) where
  RepeatDur v = Attribute "repeatDur" v

pattern RequiredExtensions v <- (Attribute "requiredExtensions" v) where
  RequiredExtensions v = Attribute "requiredExtensions" v

pattern RequiredFeatures v <- (Attribute "requiredFeatures" v) where
  RequiredFeatures v = Attribute "requiredFeatures" v

pattern Restart v <- (Attribute "restart" v) where
  Restart v = Attribute "restart" v

pattern Result v <- (Attribute "result" v) where
  Result v = Attribute "result" v

pattern Rotate v <- (Attribute "rotate" v) where
  Rotate v = Attribute "rotate" v

pattern Rx v <- (Attribute "rx" v) where
  Rx v = Attribute "rx" v

pattern Ry v <- (Attribute "ry" v) where
  Ry v = Attribute "ry" v

pattern Scale v <- (Attribute "scale" v) where
  Scale v = Attribute "scale" v

pattern Seed v <- (Attribute "seed" v) where
  Seed v = Attribute "seed" v

pattern ShapeRendering v <- (Attribute "shape-rendering" v) where
  ShapeRendering v = Attribute "shape-rendering" v

pattern Slope v <- (Attribute "slope" v) where
  Slope v = Attribute "slope" v

pattern Spacing v <- (Attribute "spacing" v) where
  Spacing v = Attribute "spacing" v

pattern SpecularConstant v <- (Attribute "specularConstant" v) where
  SpecularConstant v = Attribute "specularConstant" v

pattern SpecularExponent v <- (Attribute "specularExponent" v) where
  SpecularExponent v = Attribute "specularExponent" v

pattern Speed v <- (Attribute "speed" v) where
  Speed v = Attribute "speed" v

pattern SpreadMethod v <- (Attribute "spreadMethod" v) where
  SpreadMethod v = Attribute "spreadMethod" v

pattern StartOffset v <- (Attribute "startOffset" v) where
  StartOffset v = Attribute "startOffset" v

pattern StdDeviationA v <- (Attribute "stdDeviationA" v) where
  StdDeviationA v = Attribute "stdDeviationA" v

pattern Stemh v <- (Attribute "stemh" v) where
  Stemh v = Attribute "stemh" v

pattern Stemv v <- (Attribute "stemv" v) where
  Stemv v = Attribute "stemv" v

pattern StitchTiles v <- (Attribute "stitchTiles" v) where
  StitchTiles v = Attribute "stitchTiles" v

pattern StopColor v <- (Attribute "stop-color" v) where
  StopColor v = Attribute "stop-color" v

pattern StopOpacity v <- (Attribute "stop-opacity" v) where
  StopOpacity v = Attribute "stop-opacity" v

pattern StrikethroughPosition v <- (Attribute "strikethrough-position" v) where
  StrikethroughPosition v = Attribute "strikethrough-position" v

pattern StrikethroughThickness v <- (Attribute "strikethrough-thickness" v) where
  StrikethroughThickness v = Attribute "strikethrough-thickness" v

pattern StringA v <- (Attribute "string" v) where
  StringA v = Attribute "string" v

pattern Stroke v <- (Attribute "stroke" v) where
  Stroke v = Attribute "stroke" v

pattern StrokeDasharray v <- (Attribute "stroke-dasharray" v) where
  StrokeDasharray v = Attribute "stroke-dasharray" v

pattern StrokeDashoffset v <- (Attribute "stroke-dashoffset" v) where
  StrokeDashoffset v = Attribute "stroke-dashoffset" v

pattern StrokeLinecap v <- (Attribute "stroke-linecap" v) where
  StrokeLinecap v = Attribute "stroke-linecap" v

pattern StrokeLinejoin v <- (Attribute "stroke-linejoin" v) where
  StrokeLinejoin v = Attribute "stroke-linejoin" v

pattern StrokeMiterlimit v <- (Attribute "stroke-miterlimit" v) where
  StrokeMiterlimit v = Attribute "stroke-miterlimit" v

pattern StrokeOpacity v <- (Attribute "stroke-opacity" v) where
  StrokeOpacity v = Attribute "stroke-opacity" v

pattern StrokeWidth v <- (Attribute "stroke-width" v) where
  StrokeWidth v = Attribute "stroke-width" v

pattern SurfaceScale v <- (Attribute "surfaceScale" v) where
  SurfaceScale v = Attribute "surfaceScale" v

pattern SystemLanguage v <- (Attribute "systemLanguage" v) where
  SystemLanguage v = Attribute "systemLanguage" v

pattern TableValues v <- (Attribute "tableValues" v) where
  TableValues v = Attribute "tableValues" v

pattern TargetX v <- (Attribute "targetX" v) where
  TargetX v = Attribute "targetX" v

pattern TargetY v <- (Attribute "targetY" v) where
  TargetY v = Attribute "targetY" v

pattern TextAnchor v <- (Attribute "text-anchor" v) where
  TextAnchor v = Attribute "text-anchor" v

pattern TextDecoration v <- (Attribute "text-decoration" v) where
  TextDecoration v = Attribute "text-decoration" v

pattern TextRendering v <- (Attribute "text-rendering" v) where
  TextRendering v = Attribute "text-rendering" v

pattern TextLength v <- (Attribute "textLength" v) where
  TextLength v = Attribute "textLength" v

pattern To v <- (Attribute "to" v) where
  To v = Attribute "to" v

pattern Transform v <- (Attribute "transform" v) where
  Transform v = Attribute "transform" v

pattern U1 v <- (Attribute "u1" v) where
  U1 v = Attribute "u1" v

pattern U2 v <- (Attribute "u2" v) where
  U2 v = Attribute "u2" v

pattern UnerlinePosition v <- (Attribute "unerline-position" v) where
  UnerlinePosition v = Attribute "unerline-position" v

pattern UnderlineThickness v <- (Attribute "underline-thickness" v) where
  UnderlineThickness v = Attribute "underline-thickness" v

pattern Unicode v <- (Attribute "unicode" v) where
  Unicode v = Attribute "unicode" v

pattern UnicodeBidi v <- (Attribute "unicode-bidi" v) where
  UnicodeBidi v = Attribute "unicode-bidi" v

pattern UnicodeRange v <- (Attribute "unicode-range" v) where
  UnicodeRange v = Attribute "unicode-range" v

pattern UnitsPerEm v <- (Attribute "units-per-em" v) where
  UnitsPerEm v = Attribute "units-per-em" v

pattern VAlphabetic v <- (Attribute "v-alphabetic" v) where
  VAlphabetic v = Attribute "v-alphabetic" v

pattern VHanging v <- (Attribute "v-hanging" v) where
  VHanging v = Attribute "v-hanging" v

pattern VIdeographic v <- (Attribute "v-ideographic" v) where
  VIdeographic v = Attribute "v-ideographic" v

pattern VMathematical v <- (Attribute "v-mathematical" v) where
  VMathematical v = Attribute "v-mathematical" v

pattern Values v <- (Attribute "values" v) where
  Values v = Attribute "values" v

pattern Version v <- (Attribute "version" v) where
  Version v = Attribute "version" v

pattern VertAdvY v <- (Attribute "vert-adv-y" v) where
  VertAdvY v = Attribute "vert-adv-y" v

pattern VertOriginX v <- (Attribute "vert-origin-x" v) where
  VertOriginX v = Attribute "vert-origin-x" v

pattern VerOriginY v <- (Attribute "ver-origin-y" v) where
  VerOriginY v = Attribute "ver-origin-y" v

pattern ViewBox v <- (Attribute "viewBox" v) where
  ViewBox v = Attribute "viewBox" v

pattern ViewTarget v <- (Attribute "viewTarget" v) where
  ViewTarget v = Attribute "viewTarget" v

pattern Visibility v <- (Attribute "visibility" v) where
  Visibility v = Attribute "visibility" v

pattern Widths v <- (Attribute "widths" v) where
  Widths v = Attribute "widths" v

pattern WordSpacing v <- (Attribute "word-spacing" v) where
  WordSpacing v = Attribute "word-spacing" v

pattern WritingMode v <- (Attribute "writing-mode" v) where
  WritingMode v = Attribute "writing-mode" v

pattern X v <- (Attribute "x" v) where
  X v = Attribute "X" v

pattern XHeight v <- (Attribute "xHeight" v) where
  XHeight v = Attribute "xHeight" v

pattern X1 v <- (Attribute "x1" v) where
  X1 v = Attribute "x1" v

pattern X2 v <- (Attribute "x2" v) where
  X2 v = Attribute "x2" v

pattern XChannelSelector v <- (Attribute "xChannelSelector" v) where
  XChannelSelector v = Attribute "xChannelSelector" v

pattern XLinkActuate v <- (XLink "xlink:actuate" v) where
  XLinkActuate v = XLink "xlink:actuate" v

pattern XLinkArcrole v <- (XLink "xlink:arcrole" v) where
  XLinkArcrole v = XLink "xlink:arcrole" v

pattern XLinkHref v <- (XLink "xlink:href" v) where
  XLinkHref v = XLink "xlink:href" v

pattern XLinkRole v <- (XLink "xlink:role" v) where
  XLinkRole v = XLink "xlink:role" v

pattern XLinkShow v <- (XLink "xlink:show" v) where
  XLinkShow v = XLink "xlink:show" v

pattern XLinkTitle v <- (XLink "xlink:title" v) where
  XLinkTitle v = XLink "xlink:title" v

pattern XLinkType v <- (XLink "xlink:type" v) where
  XLinkType v = XLink "xlink:type" v

pattern XMLBase v <- (Attribute "xml:base" v) where
  XMLBase v = Attribute "xml:base" v

pattern XMLLang v <- (Attribute "xml:lang" v) where
  XMLLang v = Attribute "xml:lang" v

pattern XMLSpace v <- (Attribute "xml:space" v) where
  XMLSpace v = Attribute "xml:space" v

pattern Y v <- (Attribute "y" v) where
  Y v = Attribute "y" v

pattern Y1 v <- (Attribute "y1" v) where
  Y1 v = Attribute "y1" v

pattern Y2 v <- (Attribute "y2" v) where
  Y2 v = Attribute "y2" v

pattern YChannelSelector v <- (Attribute "yChannelSelector" v) where
  YChannelSelector v = Attribute "yChannelSelector" v

pattern Z v <- (Attribute "z" v) where
  Z v = Attribute "z" v

pattern ZoomAndPan v <- (Attribute "zoomAndPan" v) where
  ZoomAndPan v = Attribute "zoomAndPan" v

--------------------------------------------------------------------------------
-- Event listener 'Attribute's

----------------------------------------
-- Window events

pattern OnResize f <- (OnWindow "resize" _ f _) where
  OnResize f = OnWindow "resize" def f Nothing

pattern OnScroll f <- (OnWindow "scroll" _ f _) where
  OnScroll f = OnWindow "scroll" def f Nothing

pattern OnClose f <- (OnWindow "close" _ f _) where
  OnClose f = OnWindow "close" def f Nothing

pattern OnBeforeUnload f <- (OnWindow "beforeunload" _ f _) where
  OnBeforeUnload f = OnWindow "beforeunload" def f Nothing

----------------------------------------
-- Element events

pattern OnClick f <- (OnE "click" _ f _) where
  OnClick f = OnE "click" def f Nothing

pattern OnDoubleClick f <- (OnE "dblclick" _ f _) where
  OnDoubleClick f = OnE "dblclick" def f Nothing

pattern OnMouseDown f <- (OnE "mousedown" _ f _) where
  OnMouseDown f = OnE "mousedown" def f Nothing

pattern OnMouseUp f <- (OnE "mouseup" _ f _) where
  OnMouseUp f = OnE "mouseup" def f Nothing

pattern OnTouchStart f <- (OnE "touchstart" _ f _) where
  OnTouchStart f = OnE "touchstart" def f Nothing

pattern OnTouchEnd f <- (OnE "touchend" _ f _) where
  OnTouchEnd f = OnE "touchend" def f Nothing

pattern OnMouseEnter f <- (OnE "mouseenter" _ f _) where
  OnMouseEnter f = OnE "mouseenter" def f Nothing

pattern OnMouseLeave f <- (OnE "mouseleave" _ f _) where
  OnMouseLeave f = OnE "mouseleave" def f Nothing

pattern OnMouseOver f <- (OnE "mouseover" _ f _) where
  OnMouseOver f = OnE "mouseover" def f Nothing

pattern OnMouseOut f <- (OnE "mouseout" _ f _) where
  OnMouseOut f = OnE "mouseout" def f Nothing

pattern OnMouseMove f <- (OnE "mousemove" _ f _) where
  OnMouseMove f = OnE "mousemove" def f Nothing

pattern OnTouchMove f <- (OnE "touchmove" _ f _)  where
  OnTouchMove f = OnE "touchmove" def f Nothing

pattern OnTouchCancel f <- (OnE "touchcancel" _ f _) where
  OnTouchCancel f = OnE "touchcancel" def f Nothing

pattern OnInput f <- (OnE "input" _ f _) where
  OnInput f = OnE "input" def f Nothing

pattern OnChange f <- (OnE "change" _ f _) where
  OnChange f = OnE "change" def f Nothing

pattern OnSubmit f <- (OnE "submit" _ f _) where
  OnSubmit f = OnE "submit" def f Nothing

pattern OnBlur f <- (OnE "blur" _ f _) where
  OnBlur f = OnE "blur" def f Nothing

pattern OnFocus f <- (OnE "focus" _ f _) where
  OnFocus f = OnE "focus" def f Nothing

pattern OnKeyUp f <- (OnE "keyup" _ f _) where
  OnKeyUp f = OnE "keyup" def f Nothing

pattern OnKeyDown f <- (OnE "keydown" _ f _) where
  OnKeyDown f = OnE "keydown" def f Nothing

pattern OnKeyPress f <- (OnE "keypress" _ f _) where
  OnKeyPress f = OnE "keypress" def f Nothing

onInput :: (Txt -> Ef ms IO ()) -> Feature ms
onInput f = On "input" $ \(_,_,o) -> return $ parse o $ \o -> do
  target <- o .: "target"
  value <- target .: "value"
  pure $ f value

onInputChange :: (Txt -> Ef ms IO ()) -> Feature ms
onInputChange f = On "change" $ \(_,_,o) -> return $ parse o $ \o -> do
  target <- o .: "target"
  value <- target .: "value"
  pure $ f value

onCheck :: (Bool -> Ef ms IO ()) -> Feature ms
onCheck f = On "change" $ \(_,_,o) -> return $ parse o $ \o -> do
  target <- o .: "target"
  checked <- target .: "checked"
  pure $ f checked

onSubmit :: Ef ms IO () -> Feature ms
onSubmit e = Intercept $ On "submit" $ \_ -> return $ Just e

onBlur :: Ef ms IO () -> Feature ms
onBlur f = On "blur" $ \_ -> return $ Just f

onFocus :: Ef ms IO () -> Feature ms
onFocus f = On "focus" $ \_ -> return $ Just f

onKeyUp :: (Obj -> Maybe (Ef ms IO ())) -> Feature ms
onKeyUp f = On "keyup" $ \(_,_,o) -> return $ f o

onKeyDown :: (Obj -> Maybe (Ef ms IO ())) -> Feature ms
onKeyDown f = On "keydown" $ \(_,_,o) -> return $ f o

onKeyPress :: (Obj -> Maybe (Ef ms IO ())) -> Feature ms
onKeyPress f = On "keypress" $ \(_,_,o) -> return $ f o

onClick :: Ef ms IO () -> Feature ms
onClick f = On "click" $ \_ -> return $ Just f

onDoubleClick :: Ef ms IO () -> Feature ms
onDoubleClick f = On "dblclick" $ \_ -> return $ Just f

ignoreClick :: Feature ms
ignoreClick = Intercept $ On "click" $ \_ -> return Nothing

--------------------------------------------------------------------------------
-- Keys

keyCode :: Obj -> Maybe Int
keyCode = parseMaybe (.: "keyCode")

pattern Digit0 <- (keyCode -> Just 48)
pattern Digit1 <- (keyCode -> Just 49)
pattern Digit2 <- (keyCode -> Just 50)
pattern Digit3 <- (keyCode -> Just 51)
pattern Digit4 <- (keyCode -> Just 52)
pattern Digit5 <- (keyCode -> Just 53)
pattern Digit6 <- (keyCode -> Just 54)
pattern Digit7 <- (keyCode -> Just 55)
pattern Digit8 <- (keyCode -> Just 56)
pattern Digit9 <- (keyCode -> Just 57)

pattern Keya <- (keyCode -> Just 97)
pattern Keyb <- (keyCode -> Just 98)
pattern Keyc <- (keyCode -> Just 99)
pattern Keyd <- (keyCode -> Just 100)
pattern Keye <- (keyCode -> Just 101)
pattern Keyf <- (keyCode -> Just 102)
pattern Keyg <- (keyCode -> Just 103)
pattern Keyh <- (keyCode -> Just 104)
pattern Keyi <- (keyCode -> Just 105)
pattern Keyj <- (keyCode -> Just 106)
pattern Keyk <- (keyCode -> Just 107)
pattern Keyl <- (keyCode -> Just 108)
pattern Keym <- (keyCode -> Just 109)
pattern Keyn <- (keyCode -> Just 110)
pattern Keyo <- (keyCode -> Just 111)
pattern Keyp <- (keyCode -> Just 112)
pattern Keyq <- (keyCode -> Just 113)
pattern Keyr <- (keyCode -> Just 114)
pattern Keys <- (keyCode -> Just 115)
pattern Keyt <- (keyCode -> Just 116)
pattern Keyu <- (keyCode -> Just 117)
pattern Keyv <- (keyCode -> Just 118)
pattern Keyw <- (keyCode -> Just 119)
pattern Keyx <- (keyCode -> Just 120)
pattern Keyy <- (keyCode -> Just 121)
pattern Keyz <- (keyCode -> Just 122)

pattern KeyA <- (keyCode -> Just 65)
pattern KeyB <- (keyCode -> Just 66)
pattern KeyC <- (keyCode -> Just 67)
pattern KeyD <- (keyCode -> Just 68)
pattern KeyE <- (keyCode -> Just 69)
pattern KeyF <- (keyCode -> Just 70)
pattern KeyG <- (keyCode -> Just 71)
pattern KeyH <- (keyCode -> Just 72)
pattern KeyI <- (keyCode -> Just 73)
pattern KeyJ <- (keyCode -> Just 74)
pattern KeyK <- (keyCode -> Just 75)
pattern KeyL <- (keyCode -> Just 76)
pattern KeyM <- (keyCode -> Just 77)
pattern KeyN <- (keyCode -> Just 78)
pattern KeyO <- (keyCode -> Just 79)
pattern KeyP <- (keyCode -> Just 80)
pattern KeyQ <- (keyCode -> Just 81)
pattern KeyR <- (keyCode -> Just 82)
pattern KeyS <- (keyCode -> Just 83)
pattern KeyT <- (keyCode -> Just 84)
pattern KeyU <- (keyCode -> Just 85)
pattern KeyV <- (keyCode -> Just 86)
pattern KeyW <- (keyCode -> Just 87)
pattern KeyX <- (keyCode -> Just 88)
pattern KeyY <- (keyCode -> Just 89)
pattern KeyZ <- (keyCode -> Just 90)

pattern OpenParenthesis <- ShiftKey (keyCode -> Just 40)
pattern CloseParenthesis <- ShiftKey (keyCode -> Just 41)
pattern Exclamation <- ShiftKey (keyCode -> Just 33)
pattern At <- ShiftKey (keyCode -> Just 64)
pattern NumberSign <- ShiftKey (keyCode -> Just 35)
pattern Dollar <- ShiftKey (keyCode -> Just 36)
pattern Percent <- ShiftKey (keyCode -> Just 37)
pattern Caret <- ShiftKey (keyCode -> Just 94)
pattern Ampersand <- ShiftKey (keyCode -> Just 38)
pattern Asterisk <- ShiftKey (keyCode -> Just 42)
pattern Underscore <- ShiftKey (keyCode -> Just 95)
pattern Plus <- ShiftKey (keyCode -> Just 43)
pattern VerticalBar <- ShiftKey (keyCode -> Just 124)
pattern CurlyBracketLeft <- ShiftKey (keyCode -> Just 123)
pattern CurlyBracketRight <- ShiftKey (keyCode -> Just 125)
pattern QuestionMark <- ShiftKey (keyCode -> Just 63)
pattern FullStop <- (keyCode -> Just 46)
pattern ForwardSlash <- (keyCode -> Just 47)
pattern Tilde <- (keyCode -> Just 96)
pattern Grave <- ShiftKey (keyCode -> Just 126)
pattern Colon <- ShiftKey (keyCode -> Just 58)
pattern Semicolon <- (keyCode -> Just 59)
pattern Comma <- (keyCode -> Just 44)
pattern Period <- (keyCode -> Just 46)
pattern Quote <- (keyCode -> Just 39)
pattern DoubleQuote <- ShiftKey (keyCode -> Just 34)
pattern BracketLeft <- (keyCode -> Just 91)
pattern BracketRight <- (keyCode -> Just 93)
pattern Backslash <- (keyCode -> Just 47)
pattern Minus <- (keyCode -> Just 45)
pattern Equal <- (keyCode -> Just 61)

pattern KeyAlt <- (keyCode -> Just 18)
pattern KeyCapsLock <- (keyCode -> Just 20)
pattern KeyControl <- (keyCode -> Just 17)
pattern KeyOSLeft <- (keyCode -> Just 91)
pattern KeyOSRight <- (keyCode -> Just 92)
pattern KeyShift <- (keyCode -> Just 16)

pattern ContextMenu <- (keyCode -> Just 93)
pattern Enter <- (keyCode -> Just 13)
pattern Space <- (keyCode -> Just 32)
pattern Tab <- (keyCode -> Just 9)
pattern Delete <- (keyCode -> Just 46)
pattern EndKey <- (keyCode -> Just 35)
pattern Home <- (keyCode -> Just 36)
pattern Insert <- (keyCode -> Just 45)
pattern PageDown <- (keyCode -> Just 34)
pattern PageUp <- (keyCode -> Just 33)
pattern ArrowDown <- (keyCode -> Just 40)
pattern ArrowLeft <- (keyCode -> Just 37)
pattern ArrowRight <- (keyCode -> Just 39)
pattern ArrowUp <- (keyCode -> Just 38)
pattern Escape <- (keyCode -> Just 27)
pattern PrintScreen <- (keyCode -> Just 44)
pattern ScrollLock <- (keyCode -> Just 145)
pattern Pause <- (keyCode -> Just 19)

pattern F1 <- (keyCode -> Just 112)
pattern F2 <- (keyCode -> Just 113)
pattern F3 <- (keyCode -> Just 114)
pattern F4 <- (keyCode -> Just 115)
pattern F5 <- (keyCode -> Just 116)
pattern F6 <- (keyCode -> Just 117)
pattern F7 <- (keyCode -> Just 118)
pattern F8 <- (keyCode -> Just 119)
pattern F9 <- (keyCode -> Just 120)
pattern F10 <- (keyCode -> Just 121)
pattern F11 <- (keyCode -> Just 122)
pattern F12 <- (keyCode -> Just 123)
pattern F13 <- (keyCode -> Just 124)
pattern F14 <- (keyCode -> Just 125)
pattern F15 <- (keyCode -> Just 126)
pattern F16 <- (keyCode -> Just 127)
pattern F17 <- (keyCode -> Just 128)
pattern F18 <- (keyCode -> Just 129)
pattern F19 <- (keyCode -> Just 130)
pattern F20 <- (keyCode -> Just 131)
pattern F21 <- (keyCode -> Just 132)
pattern F22 <- (keyCode -> Just 133)
pattern F23 <- (keyCode -> Just 134)
pattern F24 <- (keyCode -> Just 135)

pattern NumLock <- (keyCode -> Just 144)
pattern Numpad0 <- (keyCode -> Just 96)
pattern Numpad1 <- (keyCode -> Just 97)
pattern Numpad2 <- (keyCode -> Just 98)
pattern Numpad3 <- (keyCode -> Just 99)
pattern Numpad4 <- (keyCode -> Just 100)
pattern Numpad5 <- (keyCode -> Just 101)
pattern Numpad6 <- (keyCode -> Just 102)
pattern Numpad7 <- (keyCode -> Just 103)
pattern Numpad8 <- (keyCode -> Just 104)
pattern Numpad9 <- (keyCode -> Just 105)
pattern NumpadAdd <- (keyCode -> Just 107)
pattern NumpadComma <- (keyCode -> Just 194)
pattern NumpadDecimal <- (keyCode -> Just 110)
pattern NumpadDivide <- (keyCode -> Just 111)
pattern NumpadEnter <- (keyCode -> Just 13)
pattern NumpadEqual <- (keyCode -> Just 12)
pattern NumpadMultiply <- (keyCode -> Just 106)
pattern NumpadSubtract <- (keyCode -> Just 109)

shiftModifier o = (parseMaybe (.: "shiftKey") o,o)
pattern ShiftKey o <- (shiftModifier -> (Just True,o))

altModifier o = (parseMaybe (.: "altKey") o,o)
pattern AltKey o <- (altModifier -> (Just True,o))

ctrlModifier o = (parseMaybe (.: "ctrlKey") o,o)
pattern CtrlKey o <- (ctrlModifier -> (Just True,o))

metaModifier o = (parseMaybe (.: "metaKey") o,o)
pattern MetaKey o <- (metaModifier -> (Just True,o))
