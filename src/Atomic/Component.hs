{-# language UndecidableInstances #-}
{-# language FunctionalDependencies #-}
{-# language DeriveDataTypeable #-}
{-# language StandaloneDeriving #-}
{-# language OverloadedStrings #-}
{-# language PatternSynonyms #-}
{-# language TemplateHaskell #-}
{-# language DeriveFunctor #-}
{-# language ViewPatterns #-}
{-# language MagicHash #-}
{-# language CPP #-}

{-# language ImplicitParams #-}
module Atomic.Component (module Atomic.Component, ENode, TNode, NNode, Win, Doc, Loc) where

import Ef.Base hiding (Object,Client,After,Before,child,current,Lazy,Eager,construct,Index,observe,uncons,distribute,embed,initialize)
import qualified Ef.Base

import qualified Data.Foldable as F

import Data.Txt as Txt hiding (replace,map,head,filter)
import Data.JSON hiding (Result)

import Atomic.Attribute
import Atomic.Cond
import Atomic.CSS
import Atomic.Default
-- import Atomic.Dict
import Atomic.Key
import Atomic.Vault
import Atomic.ToTxt
import Atomic.FromTxt
import Atomic.Observable
import Atomic.UnsafeEq

import Control.Exception (assert)

#ifdef __GHCJS__
import qualified GHCJS.Types as T
import qualified GHCJS.Marshal as M
import qualified GHCJS.Marshal.Pure as M

import GHCJS.Foreign.Callback

import qualified JavaScript.Object.Internal as O

import qualified GHCJS.DOM as DOM
import qualified GHCJS.DOM.Element as E
import qualified GHCJS.DOM.EventM as Ev
import qualified GHCJS.DOM.EventTargetClosures as Ev
import qualified GHCJS.DOM.JSFFI.Generated.EventTarget as Ev
import qualified GHCJS.DOM.JSFFI.Generated.Event as Event
import qualified GHCJS.DOM.Document as D
import qualified GHCJS.DOM.History as H
import qualified GHCJS.DOM.Location as L
import qualified GHCJS.DOM.Node as N
import qualified GHCJS.DOM.NodeList as N
import qualified GHCJS.DOM.Types as T
import qualified GHCJS.DOM.Window as W

import GHCJS.DOM.RequestAnimationFrameCallback
import GHCJS.DOM.Window (requestAnimationFrame)
#else
import Data.Aeson (Value(..))
#endif

import Control.Concurrent
import Data.Bifunctor
import Data.Char
import Data.Data hiding (Constr)
import Data.Either
import Data.Foldable
import Data.Functor.Identity
import Data.Hashable
import Data.IORef
import Data.List as List hiding (delete,head)
import Data.Maybe
import Data.String
import Data.Traversable
import Data.Typeable
import Data.Void
import Data.Unique
import GHC.Generics hiding (Constructor)
import GHC.Prim

import qualified Data.Function as F

import qualified Data.IntMap.Strict as IM

import qualified Data.HashMap.Strict as Map

import Prelude
import Language.Haskell.TH hiding (Loc)
import Language.Haskell.TH.Syntax hiding (Loc)

import System.IO.Unsafe
import Unsafe.Coerce

-- import Control.Lens (Iso,iso,makePrisms,makeLenses,preview,review)
-- import Control.Lens.Plated (Plated(..))
-- import Control.Lens.At
-- import Control.Lens.Prism
-- import Control.Lens.Setter hiding ((.=))

import qualified GHC.Exts

#ifdef __GHCJS__
foreign import javascript unsafe
  "$r = $2.parentNode == $1;"
  is_already_embedded_js :: E.Element -> E.Element -> IO Bool

foreign import javascript unsafe
  "$r = $1.parentNode == $2;"
  is_already_embedded_text_js :: T.Text -> E.Element -> IO Bool

foreign import javascript unsafe
  "$1.parentNode.replaceChild($2,$1);"
  swap_js :: N.Node -> N.Node -> IO ()

foreign import javascript unsafe
  "$1.insertBefore($3,$1.childNodes[$2]);"
  insert_at_js :: E.Element -> Int -> N.Node -> IO ()

foreign import javascript unsafe
  "$1[\"parentNode\"][\"replaceChild\"]($2,$1);"
  swap_content_js :: T.Text -> E.Element -> IO ()

foreign import javascript unsafe
  "$1.nodeValue=$2;"
  changeText_js :: T.Text -> Txt -> IO ()

foreign import javascript unsafe
  "for (var property in $2) { $1.style[property] = $2[property]; }"
  setStyle_js :: E.Element -> O.Object -> IO ()

foreign import javascript unsafe
  "$1[$2] = null;"
  set_property_null_js :: O.Object -> Txt -> IO ()

foreign import javascript unsafe
  "$1[$2] = null;"
  set_element_property_null_js :: E.Element -> Txt -> IO ()

foreign import javascript unsafe
  "for (var property in $2) { $1.style[property] = null; }"
  clearStyle_js :: E.Element -> O.Object -> IO ()

foreign import javascript unsafe
  "$1.remove();"
  delete_js :: N.Node -> IO ()

foreign import javascript unsafe
  "var pse = new PopStateEvent('popstate',{state: 0});dispatchEvent(pse);"
  triggerPopstate_js :: IO ()

foreign import javascript unsafe
  "$1.value = $2;"
  set_value_js :: E.Element -> Txt -> IO ()

foreign import javascript unsafe
  "$1.appendChild($2);"
  append_child_js :: E.Element -> N.Node -> IO ()

foreign import javascript unsafe
  "$1.innerHTML = '';" clear_node_js :: N.Node -> IO ()

foreign import javascript unsafe
  "$1[$2] = $3" set_property_js :: E.Element -> Txt -> Txt -> IO ()
#endif

type StateUpdate ps st = ps -> st -> IO (st,IO ())
type StateUpdater ps st = StateUpdate ps st -> IO Bool

type Lifter e = Ef e IO () -> IO ()

type PropsUpdater props = props -> IO Bool

type Unmounter = MVar () -> IO Bool

data View e where
  -- NullView must have a presence on the page for proper diffing
  NullView
    :: { _node :: (Maybe ENode)
       } -> View e

  TextView
    ::  { _tnode      :: (Maybe TNode)
        , _content    :: Txt
        } -> View e

  RawView
    :: { _node        :: (Maybe ENode)
       , _tag         :: Txt
       , _attributes  :: [Feature e]
       , _content     :: Txt
       } -> View e

  HTML
    ::  { _node       :: (Maybe ENode)
        , _tag        :: Txt
        , _attributes :: [Feature e]
        , _atoms      :: [View e]
        } -> View e
  KHTML
    ::  { _node       :: (Maybe ENode)
        , _tag        :: Txt
        , _attributes :: [Feature e]
        , _keyed      :: [(Int,View e)]
        } -> View e

  STView
    :: (Typeable props) =>
       { _stprops  :: props
       , _strecord :: Maybe (MVar (ComponentRecord e props st config))
       , _stview   :: ( ?parent :: Proxy e
                      , ?state :: Proxy st
                      , ?props :: Proxy props
                      , ?config :: Proxy config
                      ) => Lifter e -> StateUpdater props st -> Component e props st config mountResult updateResult unmountResult
       , _stStateProxy :: Proxy st
       , _stPropsProxy :: Proxy props
       , _stConfigProxy :: Proxy config
       } -> View e

  SVG
    ::  { _node       :: (Maybe ENode)
        , _tag        :: Txt
        , _attributes :: [Feature e]
        , _atoms      :: [View e]
        } -> View e

  KSVG
    ::  { _node       :: (Maybe ENode)
        , _tag        :: Txt
        , _attributes :: [Feature e]
        , _keyed      :: [(Int,View e)]
        } -> View e

  Managed
    ::  { _node       :: (Maybe ENode)
        , _tag        :: Txt
        , _attributes :: [Feature e]
        , _constr     :: Constr
        } -> View e

  DiffView
    :: (Typeable model)
    => { _diff_model :: model
       , _diff_view :: View e
       } -> View e

  DiffEqView
    :: (Typeable model, Eq model)
    => { _diffEq_model :: model
       , _diffEq_view :: View e
       } -> View e

  View
    :: (Renderable a e, Typeable a, Typeable e) => { renderable :: a e } -> View e

pattern Rendered :: (Renderable a e, Typeable a, Typeable e) => a e -> View e
pattern Rendered ams <- (View (cast -> Just ams)) where
  Rendered ams = View ams

class Renderable (a :: [* -> *] -> *) (ms :: [* -> *]) where
  -- TODO:
  --   build :: a ms -> IO (View ms)
  --   diff :: (Ef ms IO () -> IO ()) -> ENode -> View ms -> a ms -> a ms -> IO (View ms)
  -- With build and diff the only primitive view elements would be HTML, SVG, Managed, and View.
  -- Great avenue for extensibility and modularity, but I don't see that the expressivity gained
  -- would currently justify the work; it's mostly just a refactoring, but it is a major refactoring.
  render :: a ms -> View ms
  default render :: (Generic (a ms), GRenderable (Rep (a ms)) ms) => a ms -> View ms
  render = grender . from

instance Renderable View ms where
  render (View a) = render a
  render a = a

class GRenderable a ms where
  grender :: a x -> View ms

instance GRenderable GHC.Generics.U1 ms where
  grender GHC.Generics.U1 = nil

instance (Renderable a ms) => GRenderable (GHC.Generics.K1 i (a ms)) ms where
  grender (GHC.Generics.K1 k) = render k

instance (GRenderable a ms, GRenderable b ms) => GRenderable (a :*: b) ms where
  grender (a :*: b) = mkHTML "div" [ ] [ grender a, grender b ]

instance (GRenderable a ms, GRenderable b ms) => GRenderable (a :+: b) ms where
  grender (L1 a) = grender a
  grender (R1 b) = grender b

mapRenderable :: (Typeable a, Typeable a', Typeable ms, Renderable a ms, Renderable a' ms) => (a ms -> a' ms) -> View ms -> View ms
mapRenderable f sa =
  case sa of
    Rendered a -> Rendered (f a)
    _ -> sa

forRenderable :: (Typeable a, Typeable a', Typeable ms, Renderable a ms, Renderable a' ms)
             => View ms -> (a ms -> a' ms) -> View ms
forRenderable = flip mapRenderable

infixl 9 %
(%) :: (Typeable a, Typeable a', Typeable ms, Renderable a ms, Renderable a' ms) => View ms -> (a ms -> a' ms) -> View ms
(%) = forRenderable

mapRenderables :: (Typeable a, Typeable a', Typeable ms, Renderable a ms, Renderable a' ms)
              => (a ms -> a' ms) -> [View ms] -> [View ms]
mapRenderables f as = map (mapRenderable f) as

forRenderables :: (Typeable a, Typeable a', Typeable ms, Renderable a ms, Renderable a' ms)
              => [View ms] -> (a ms -> a' ms) -> [View ms]
forRenderables = flip mapRenderables

data Mapping ms = forall a a'. (Typeable a, Typeable a', Typeable ms, Renderable a ms, Renderable a' ms)
                => Mapping (a ms -> a' ms)

maps :: View ms -> [Mapping ms] -> View ms
maps a mappings = Prelude.foldr tryMap a mappings
  where
    tryMap (Mapping m) res =
      case a of
        Rendered a -> Rendered (m a)
        _ -> res

forceToFromTxt :: (ToTxt t, FromTxt t) => Txt -> t
forceToFromTxt = fromTxt

witness :: View '[] -> View ms
witness = unsafeCoerce

witnesses :: [View '[]] -> [View ms]
witnesses = unsafeCoerce

styledRenderable :: View ms -> Maybe ([Feature ms] -> [View ms] -> View ms,Styles (),[Feature ms],[View ms])
styledRenderable (HTML _ tag fs vs) =
  case getStyles fs of
    Just (ss,rest) -> Just (HTML Nothing tag,ss,rest,vs)
    _ -> Nothing
styledRenderable (SVG _ tag fs vs) =
  case getStyles fs of
    Just (ss,rest) -> Just (SVG Nothing tag,ss,rest,vs)
    _ -> Nothing

getStyles :: [Feature ms] -> Maybe (Styles (),[Feature ms])
getStyles = go (return ()) []
  where
    go ss fs [] =
      case ss of
        Return _ -> Nothing
        _ -> Just (ss,Prelude.reverse fs)
    go ss fs ((StyleList styles):rest) =
      go (ss >> mapM_ (uncurry (=:)) styles) fs rest
    go ss fs (x:rest) = go ss (x:fs) rest

-- rudimentary; no CSS3
pattern Styled :: ([Feature ms] -> [View ms] -> View ms) -> Styles () -> [Feature ms] -> [View ms] -> View ms
pattern Styled f ss fs vs <- (styledRenderable -> Just (f,ss,fs,vs)) where
  Styled f ss fs vs = f (styled ss : fs) vs

pattern Null :: Typeable ms => View ms
pattern Null <- (NullView _) where
  Null = NullView Nothing

pattern Raw :: Txt -> [Feature ms] -> Txt -> View ms
pattern Raw t fs c <- (RawView _ t fs c) where
  Raw t fs c = RawView Nothing t fs c

pattern Translated :: (ToTxt t, FromTxt t, ToTxt f, FromTxt f) => f -> t
pattern Translated t <- (fromTxt . toTxt -> t) where
  Translated f = fromTxt $ toTxt f

-- Specialized to avoid type signatures.
pattern Text :: (ToTxt t, FromTxt t) => t -> Txt
pattern Text t = Translated t

pattern String :: (ToTxt t, FromTxt t) => t -> View ms
pattern String t <- (TextView _ (fromTxt -> t)) where
  String t = TextView Nothing (toTxt t)

pattern ST p v <- STView p _ v _ _ _ where
  ST p v = STView p Nothing v Proxy Proxy Proxy

weakRender (View a) = weakRender (render a)
weakRender a = a

addClass c = go False
  where
    go added [] = if added then [] else [ ClassList [ c ] ]
    go added ((ClassList cs) : fs) = ClassList (c : cs) : go True fs
    go added (f : fs) = f : go added fs

updateFeatures f v =
  case v of
    HTML     {..} -> HTML     { _attributes = f _attributes, .. }
    RawView  {..} -> RawView  { _attributes = f _attributes, .. }
    KHTML    {..} -> KHTML    { _attributes = f _attributes, .. }
    SVG  {..} -> SVG  { _attributes = f _attributes, .. }
    KSVG {..} -> KSVG { _attributes = f _attributes, .. }
    Managed  {..} -> Managed  { _attributes = f _attributes, .. }
    _             -> v

instance Default (View ms) where
  def = nil

-- toJSON for View will server-side render components, but not controllers.
instance (e <: '[]) => ToJSON (View e) where
  toJSON a =
#ifdef __GHCJS__
    objectValue $
#endif
      go a
    where
      go (STView props strec c sp pp cp) =
        let ?parent = Proxy :: Proxy e
            ?props = pp
            ?state = sp
            ?config = cp
        in unsafeCoerce go $
            case strec of
              Nothing -> unsafePerformIO $ do
                case c (\_ -> return ()) (\_ -> return False) of
                  Component {..} -> do
                    (config,state) <- runConstruct construct props
                    state' <- runInitializer initialize props state config
                    return $ renderer props state config (\_ -> return False)

              Just ref ->
                case unsafePerformIO (readMVar ref) of
                  ComponentRecord {..} -> crLive

      go (View v) = go (render v)
      go (TextView _ c) = object [ "type" .= ("text" :: Txt), "content" .= c]
      go (RawView _ t as c) = object [ "type" .= ("raw" :: Txt), "tag" .= t, "attrs" .= toJSON as, "content" .= c ]
      go (KHTML _ t as ks) = object [ "type" .= ("keyed" :: Txt), "tag" .= t, "attrs" .= toJSON as, "keyed" .= toJSON (map (fmap render) ks) ]
      go (HTML _ t as cs) = object [ "type" .= ("atom" :: Txt), "tag" .= t, "attrs" .= toJSON as, "children" .= toJSON (map render cs) ]
      go (KSVG _ t as ks) = object [ "type" .= ("keyedsvg" :: Txt), "tag" .= t, "attrs" .= toJSON as, "keyed" .= toJSON (map (fmap render) ks)]
      go (SVG _ t as cs) = object [ "type" .= ("svg" :: Txt), "tag" .= t, "attrs" .= toJSON as, "children" .= toJSON (map render cs) ]
      -- go (Component r) = go (render r)
      go (DiffView _ v) = go v
      go (DiffEqView _ v) = go v

      -- Need a better approach here.
      go (Managed mn t as (Controller' c)) =
        let !v = unsafePerformIO $ do
                  with c (return ())
                  Just (ControllerRecord {..}) <- lookupController (key c)
                  v <- readIORef crView
                  shutdown c
                  return $ cvCurrent v
        in go (HTML mn t as [unsafeCoerce v])

      go _ = object [ "type" .= ("null" :: Txt) ]

instance Typeable e => FromJSON (View e) where
  parseJSON o0 = do
#ifdef __GHCJS__
    flip (withObject "obj") o0 $ \o -> do
#else
      let (Object o) = o0
#endif
      t <- o .: "type"
      case t :: Txt of
        "text" -> do
          c <- o .: "content"
          pure $ TextView Nothing c
        "raw" -> do
          t <- o .: "tag"
          as <- o .: "attrs"
          c <- o .: "content"
          pure $ RawView Nothing t as c
        "keyed" -> do
          t <- o .: "tag"
          as <- o .: "attrs"
          ks <- o .: "keyed"
          pure $ KHTML Nothing t as ks
        "atom" -> do
          t <- o .: "tag"
          as <- o .: "attrs"
          cs <- o .: "children"
          pure $ HTML Nothing t as cs
        "keyedsvg" -> do
          t <- o .: "tag"
          as <- o .: "attrs"
          ks <- o .: "keyed"
          pure $ KSVG Nothing t as ks
        "svg" -> do
          t <- o .: "tag"
          as <- o .: "attrs"
          cs <- o .: "children"
          pure $ SVG Nothing t as cs
        "null" -> pure $ NullView Nothing
        _ -> Ef.Base.empty

instance Eq (View e) where
  (==) (NullView _) (NullView _) =
    True

  (==) (TextView _ t) (TextView _ t') =
    prettyUnsafeEq t t'

  (==) (RawView _ t fs c) (RawView _ t' fs' c') =
    prettyUnsafeEq t t' && prettyUnsafeEq fs fs' && prettyUnsafeEq c c'

  (==) (KHTML _ t fs ks) (KHTML _ t' fs' ks') =
    prettyUnsafeEq t t' && prettyUnsafeEq fs fs' && reallyUnsafeEq ks ks'

  (==) (HTML _ t fs cs) (HTML _ t' fs' cs') =
    prettyUnsafeEq t t' && prettyUnsafeEq fs fs' && reallyUnsafeEq cs cs'

  (==) (STView p _ v sp pp cp) (STView p' _ v' sp' pp' cp') =
    let ?parent = Proxy :: Proxy e
    in let v0 = let ?state = sp
                    ?props = pp
                    ?config = cp
                in v
           v1 = let ?state = sp'
                    ?props = pp'
                    ?config = cp'
                in v'
       in typeOf p == typeOf p' && reallyVeryUnsafeEq p p' && reallyVeryUnsafeEq v0 v1

  (==) (KSVG _ t fs ks) (KSVG _ t' fs' ks') =
    prettyUnsafeEq t t' && prettyUnsafeEq fs fs' && reallyUnsafeEq ks ks'

  (==) (SVG _ t fs cs) (SVG _ t' fs' cs') =
    prettyUnsafeEq t t' && prettyUnsafeEq fs fs' && reallyUnsafeEq cs cs'

  (==) (Managed _ t fs c) (Managed _ t' fs' c') =
    prettyUnsafeEq t t' && prettyUnsafeEq fs fs' && prettyUnsafeEq c c'

  (==) (DiffView m v) (DiffView m' v') =
    typeOf m == typeOf m' && reallyUnsafeEq m (unsafeCoerce m')

  (==) (DiffEqView m v) (DiffEqView m' v') =
    typeOf m == typeOf m' && prettyUnsafeEq m (unsafeCoerce m')

  (==) _ _ =
    False

instance Cond (View e) where
  nil = NullView Nothing

instance Typeable e => IsString (View e) where
  fromString = text . fromString

instance Typeable e => FromTxt (View e) where
  fromTxt = text

instance {-# OVERLAPS #-} Typeable e => IsString [View e] where
  fromString s = [fromString s]

instance Typeable e => FromTxt [View e] where
  fromTxt t = [fromTxt t]

mkHTML :: Txt -> [Feature e] -> [View e] -> View e
mkHTML _tag _attributes _atoms =
  let _node = Nothing
  in HTML {..}

mkSVG :: Txt -> [Feature e] -> [View e] -> View e
mkSVG _tag _attributes _atoms =
  let _node = Nothing
  in SVG {..}

text :: Txt -> View e
text _content =
  let _tnode = Nothing
  in TextView {..}

raw :: ([Feature e] -> [View e] -> View e) -> [Feature e] -> Txt -> View e
raw x _attributes _content =
  case x [] [] of
    HTML _ _tag _ _ ->
      let _node = Nothing
      in RawView {..}
    SVG _ _tag _ _ ->
      let _node = Nothing
      in RawView {..}
    _ -> error "HTMLic.Controller.raw: raw atoms may only be built from HTMLs and SVGs"

list :: ([Feature e] -> [View e] -> View e) -> [Feature e] -> [(Int,View e)] -> View e
list x _attributes _keyed =
  case x [] [] of
    HTML _ _tag _ _ ->
      let
        _node = Nothing
      in
        KHTML {..}
    SVG _ _tag _ _ ->
      let
        _node = Nothing
      in
        KSVG {..}
    _ -> error "HTMLic.Controller.list: lists may only be built from HTMLs and SVGs"
--
-- viewManager_ :: forall props st e. Int -> props -> st -> (props -> st -> (Ef e IO () -> IO ()) -> StateUpdate e props st -> View e) -> View e
-- viewManager_ k props initial_st view = STView props k initial_st Nothing view (\_ -> return ())
--
-- -- The hacks used to implement this atom type are somewhat finicky. The model tracks variables
-- -- for changes; if any of the variables within the model are updated, a diff will be performed.
-- -- This is how changes external to a `viewManager` are injected; if a `viewManager` uses state
-- -- from a `Controller`s model and that state is untracked in the `viewManager`, changes to the
-- -- `Controller`s model will not be injected. The same rules apply to nesting/inheriting
-- -- `viewManager` models.
-- --
-- -- Major caveat: If the list of elements holding a viewManager changes such that the diff algorithm
-- --               must recreate the element, it will be reset to its original state. This would
-- --               happen if the position of the st element within the list changes. If a variable
-- --               length list of children is required, either careful placement for the st element,
-- --               or the use of NullViews as placeholders, or some uses of keyed atoms can overcome
-- --               this problem. The solution is the good practice of keeping lists of views static
-- --               or at the very least keep extensibility at the end of a view list.
-- viewManager :: forall props st e. props -> st -> (props -> st -> (Ef e IO () -> IO ()) -> StateUpdate e props st -> View e) -> View e
-- viewManager props initial_st view = STView props 0 initial_st Nothing view (\_ -> return ())
--
-- constant :: View e -> View e
-- constant a = viewManager () () $ \_ _ _ _ -> a
--
mvc :: ([Feature e] -> [View e] -> View e)
    -> (forall ts' ms' m. (IsController' ts' ms' m) => [Feature e] -> Controller' ts' ms' m -> View e)
mvc f = \as c ->
  case f [] [] of
    HTML _ t _ _ -> Managed Nothing t as (Controller' c)
    _ -> error "Incorrect usage of construct; Controllers may only be embedded in plain html HTMLs."

diffView :: Typeable model => model -> View ms -> View ms
diffView = DiffView

diffEqView :: (Typeable model, Eq model) => model -> View ms -> View ms
diffEqView = DiffEqView

hashed :: Hashable a => ([Feature e] -> [View e] -> View e) -> [Feature e] -> [(a,View e)] -> View e
hashed x _attributes _keyed0 = list x _attributes (map (first hash) _keyed0)

css :: Ef '[CSS_] Identity a -> View e
css = css' False

css' :: forall a e. Bool -> Ef '[CSS_] Identity a -> View e
css' b = mkHTML "style" [ Property "type" "text/css", Property "scoped" (if b then "true" else "") ] . ((text "\n"):) . fst . go False []
  where
    go :: forall a. Bool -> [View e] -> Ef '[CSS_] Identity a -> ([View e],a)
    go b acc (Return a) = (acc,a)
    go b acc (Lift s) = go b acc (runIdentity s)
    go b acc c@(Do msg) =
      case prj msg of
        Just (CSS3_ atRule sel css k) ->
          case css of
            Return a ->
              go False (acc ++ [ text (atRule <> sel <> ";\n") ]) (k a)
            _ ->
              let (c,a) = go True [] css
              in go False (acc ++ ( text (atRule <> sel <> " {\n") : c) ++ [ text "\n}\n\n" ]) (k a)
        Just (CSS_ sel ss r) ->
          let (s,a) = renderStyles b ss
          in
            go b  ( acc ++ [ text ( (if b then "\t" else mempty)
                                      <> sel
                                      <> " {\n"
                                      <> (Txt.intercalate (if b then ";\n\t" else ";\n") s)
                                      <> (if b then "\n\t}\n\n" else "\n}\n\n")
                                  )
                           ]
                  ) (r a)

scss :: StaticCSS -> View e
scss = scss' False

scss' :: Bool -> StaticCSS -> View e
scss' b = raw (mkHTML "style") [ Property "type" "text/css", Property "scoped" (if b then "true" else "") ] . cssText

inlineCSS :: Ef '[CSS_] Identity a -> View e
inlineCSS = css' True . classify
  where
    classify :: forall a. Ef '[CSS_] Identity a -> Ef '[CSS_] Identity a
    classify (Return r) = Return r
    classify (Lift sup) = Lift (fmap classify sup)
    classify (Send e) =
      case e of
        CSS_ sel ss k ->
          Send (CSS_ (Txt.cons '.' sel) ss (classify . k))
        CSS3_ at sel css k ->
          Send (CSS3_ at sel (classify css) (classify . k))

-- rebuild finds managed nodes and re-embeds them in case they were
-- removed for other uses
rebuild :: forall e. View e -> IO ()
rebuild h =
#ifndef __GHCJS__
    return ()
#else
    go h
  where
    go :: View e -> IO ()
    go STView {..}  = do
      forM_ _strecord $ \ref -> do
        ComponentRecord {..} <- readMVar ref
        rebuild (unsafeCoerce crLive :: View e)
    go HTML {..}    = mapM_ go _atoms
    go SVG {..} = mapM_ go _atoms
    go KHTML {..}   = mapM_ (go . snd) _keyed
    go KSVG {..}  = mapM_ (go . snd) _keyed
    go (DiffView _ v) = go v
    go (DiffEqView _ v) = go v
    go m@Managed {..} = do
      case _constr of
        Controller' c -> do
          mi_ <- lookupController (key c)
          forM_ mi_ $ \ControllerRecord {..} -> do
            ControllerView {..} <- readIORef crView
            rebuild cvCurrentLive
            forM_ _node $ \node ->
              embed_ node cvCurrentLive
    go _ =
      return ()
#endif

triggerBackground :: forall m e. (MonadIO m) => View e -> m ()
triggerBackground = go
  where
    bg Controller {..} = do
      mc <- lookupController key
      case mc of
        Nothing -> return ()
        Just ControllerRecord {..} -> do
          let ControllerHooks _ bg _= crHooks
          publish bg ()
          ControllerView {..} <- liftIO $ readIORef crView
          go $ unsafeCoerce cvCurrentLive

    go :: View e -> m ()
    go STView {..}  =
      forM_ _strecord $ \ref -> do
        ComponentRecord {..} <- liftIO $ readMVar ref
        go (unsafeCoerce crLive)
    go HTML {..}    = mapM_ go _atoms
    go SVG {..} = mapM_ go _atoms
    go KHTML {..}   = mapM_ (go . snd) _keyed
    go KSVG {..} = mapM_ (go . snd) _keyed
    go (DiffView _ v) = go v
    go (DiffEqView _ v) = go v
    go m@Managed {..} = case _constr of Controller' c -> bg (unsafeCoerce c)
    go _ = return ()

triggerForeground :: forall m e. (MonadIO m) => View e -> m ()
triggerForeground = go
  where
    fg Controller {..} = do
      mc <- lookupController key
      case mc of
        Nothing -> return ()
        Just ControllerRecord {..} -> do
          let ControllerHooks _ _ fg = crHooks
          publish fg ()
          ControllerView {..} <- liftIO $ readIORef crView
          go (unsafeCoerce cvCurrentLive)

    go :: View e -> m ()
    go STView {..}  =
      forM_ _strecord $ \ref -> do
        ComponentRecord {..} <- liftIO $ readMVar ref
        go (unsafeCoerce crLive)
    go HTML {..}    = mapM_ go _atoms
    go SVG {..} = mapM_ go _atoms
    go KHTML {..}   = mapM_ (go . snd) _keyed
    go KSVG {..} = mapM_ (go . snd) _keyed
    go (DiffView _ v) = go v
    go (DiffEqView _ v) = go v
    go m@Managed {..} = case _constr of Controller' c -> fg (unsafeCoerce c)
    go _ = return ()

onForeground :: ( MonadIO c, MonadIO c'
                , ms <: '[Evented]
                , ms' <: '[State () ControllerHooks]
                , With w (Narrative (Messages ms') c') IO
                )
             => w -> Ef '[Ef.Base.Event ()] (Ef ms c) () -> Ef ms c (Promise (IO ()))
onForeground c f = do
  connectWith c (get >>= \(ControllerHooks _ _ fg) -> return fg) $ \_ -> f

onBackground :: ( MonadIO c, MonadIO c'
                , ms <: '[Evented]
                , ms' <: '[State () ControllerHooks]
                , With w (Narrative (Messages ms') c') IO
                )
             => w -> Ef '[Event ()] (Ef ms c) () -> Ef ms c (Promise (IO ()))
onBackground c f = do
  connectWith c (get >>= \(ControllerHooks _ bg _) -> return bg) $ \_ -> f

reflect :: forall ts ms m c.
           ( IsController' ts ms m
           , MonadIO c
           )
        => Controller' ts ms m
        -> c (Promise (View ms))
reflect c =
  with c $ do
    ControllerState {..} :: ControllerState m <- get
    ControllerView {..} <- liftIO $ readIORef asLive
    return (unsafeCoerce cvCurrentLive)

data DiffStrategy = Eager | Manual deriving (Eq)

data AState m =
  AState
    { as_live :: forall ms. IORef (ControllerView ms m)
    , as_model :: forall ms. m ms
    }

data ControllerPatch m =
  forall ms a. (Renderable a ms, ms <: '[]) =>
  APatch
      -- only modify ap_AState with atomicModifyIORef
    { ap_send         :: Ef ms IO () -> IO ()
    , ap_AState       :: IORef (Maybe (AState m),Bool) -- an AState record for manipulation; nullable by context to stop a patch.
    , ap_patchRenderable    :: (m ms -> a ms)
    , ap_viewTrigger  :: IO ()
    , ap_hooks        :: ControllerHooks
    }

type IsController' ts ms m = (ms <: Base m, ts <. Base m, Delta (Modules ts) (Messages ms))
type IsController ms m = IsController' ms ms m

data ControllerHooks = ControllerHooks
  { chRendered   :: Syndicate ()
  , chForeground :: Syndicate ()
  , chBackground :: Syndicate ()
  }

data ControllerView ms m = ControllerView
  { cvCurrent     :: View ms
  , cvCurrentLive :: View ms
  , cvModel       :: m ms
  , cvForeground  :: Bool
  }

data ControllerRecord ms m = ControllerRecord
  { crAsController :: As (Ef ms IO)
  , crView        :: IORef (ControllerView ms m)
  , crHooks       :: ControllerHooks
  }

data ControllerState (m :: [* -> *] -> *) where
  ControllerState ::
    { asPatch        :: Maybe (ControllerPatch m)
    , asDiffer       :: ControllerState m -> Ef ms IO ()
    , asDiffStrategy :: DiffStrategy
    , asUpdates      :: Syndicate (m ms)
    , asModel        :: m ms
    , asLive         :: IORef (ControllerView ms m)
    } -> ControllerState m

type MVC m ms = (ms <: Base m)
type VC ms = ms <: '[State () ControllerHooks, State () Shutdown, Evented]

type Base (m :: [* -> *] -> *)
  = '[ State () (ControllerState m)
     , State () ControllerHooks
     , State () Shutdown
     , Evented
     ]

data Constr where
  Controller' :: (IsController' ts ms m) => Controller' ts ms m -> Constr
instance Eq Constr where
 (==) (Controller' c) (Controller' c') =
  let Key k1 :: Key GHC.Prim.Any = unsafeCoerce (key c)
      Key k2 :: Key GHC.Prim.Any = unsafeCoerce (key c')
  in prettyUnsafeEq k1 k2

instance ToTxt (Feature e) where
  toTxt NullFeature          = mempty

  toTxt (DiffFeature _ f) = toTxt f

  toTxt (DiffEqFeature _ f) = toTxt f

  toTxt (Attribute attr val) =
    if Txt.null val then
      attr
    else
      attr <> "=\"" <> val <> "\""

  toTxt (Property prop val) =
    prop <> "=\"" <> val <> "\""

  toTxt (StyleF pairs) =
    "style=\""
      <> Txt.intercalate
           (Txt.singleton ';')
           (fst $ renderStyles False (mapM_ (uncurry (=:)) pairs))
      <> "\""

  toTxt (LinkTo href _)    = "href=\"" <> href <> "\""

  toTxt (SVGLinkTo href _) = "xlink:href=\"" <> href <> "\""

  toTxt (XLink xl v)     = xl <> "=\"" <> v <> "\""

  toTxt _ = mempty

instance ToTxt [Feature e] where
  toTxt fs =
    Txt.intercalate
     (Txt.singleton ' ')
     (Prelude.filter (not . Txt.null) $ Prelude.map toTxt fs)

type ControllerKey ms m = Key (ControllerRecord (Appended ms (Base m)) m)
type ControllerBuilder ts m = Modules (Base m) (Action (Appended ts (Base m)) IO) -> IO (Modules (Appended ts (Base m)) (Action (Appended ts (Base m)) IO))
type ControllerPrimer ms m = Ef (Appended ms (Base m)) IO ()

data Controller' ts ms m = forall a. Renderable a ms => Controller
  { key       :: !(Key (ControllerRecord ms m))
  , build     :: !(Modules (Base m) (Action ts IO) -> IO (Modules ts (Action ts IO)))
  , prime     :: !(Ef ms IO ())
  , model     :: !(m ms)
  , view      :: !(m ms -> a ms)
  }
type Controller ms m = Controller' (Appended ms (Base m)) (Appended ms (Base m)) m

instance ToTxt (Controller' ts ms m) where
  toTxt = toTxt . key

instance Eq (Controller' ts ms m) where
  (==) (Controller k _ _ _ _) (Controller k' _ _ _ _) =
    let Key k1 = k
        Key k2 = k'
    in prettyUnsafeEq k1 k2

instance Ord (Controller' ts ms m) where
  compare (Controller (Key k) _ _ _ _) (Controller (Key k') _ _ _ _) = compare k k'

instance IsController' ts ms m
  => With (Controller' ts ms m)
          (Ef ms IO)
          IO
  where
    using_ c = do
      -- FIXME: likely a bug here with double initialization in multithreaded contexts!
      mi_ <- lookupController (key c)
      case mi_ of
        Just (ControllerRecord {..}) -> return (runAs crAsController)
        Nothing -> do
          mkController BuildOnly c
          using_ c
    with_ c m = do
      run <- using_ c
      run m
    shutdown_ c = do
      -- this method should 1. destroy the view 2. syndicate a shutdown event 3. poison the context
      -- so that unmount events that call with on the context do not fail
      miohhm <- lookupController (key c)
      case miohhm of
        Just ControllerRecord {..} -> do
          ControllerView {..} <- liftIO $ readIORef crView
          cleanup (void . with c) [cvCurrentLive]
          delete cvCurrentLive
          void $ runAs crAsController $ do
            buf <- get
            Shutdown sdn <- get
            publish sdn ()
            -- this is where things get iffy... what should this look like?
            delay 0 $ do
              deleteController (key c)
              liftIO $ do
                killBuffer buf
                myThreadId >>= killThread
        _ -> return ()

{-# NOINLINE constructShutdownSyndicate #-}
constructShutdownSyndicate :: Syndicate ()
constructShutdownSyndicate = unsafePerformIO syndicate

{-# NOINLINE constructVault__ #-}
constructVault__ :: Vault
constructVault__ = Vault (unsafePerformIO (newMVar Map.empty))

lookupController :: (MonadIO c) => Key phantom -> c (Maybe phantom)
lookupController = vaultLookup constructVault__

getControllerName :: IsController' ts ms m => Controller' ts ms m -> Txt
getControllerName = toTxt . key

addController :: (MonadIO c) => Key phantom -> phantom -> c ()
addController = vaultAdd constructVault__

deleteController :: (MonadIO c) => Key phantom -> c ()
deleteController = vaultDelete constructVault__

data MkControllerAction
  = ClearAndAppend ENode
  | forall e. Replace (View e)
  | Append ENode
  | BuildOnly

mkController :: forall ms ts m.
          ( IsController' ts ms m
          , ms <: Base m
          )
       => MkControllerAction
       -> Controller' ts ms m
       -> IO (ControllerRecord ms m)
mkController mkControllerAction c@Controller {..} = do
  let !raw = render $ view model
  doc <- getDocument
  buf <- newEvQueue
  ch  <- ControllerHooks <$> syndicate <*> syndicate <*> syndicate
  us  <- syndicate
  sdn <- Shutdown <$> syndicate
  as  <- unsafeConstructAs buf
  let sendEv = void . runAs as
  (i,l) <- case mkControllerAction of
            ClearAndAppend n -> do
              i <- buildAndEmbedMaybe sendEv doc ch True Nothing raw
              clearNode . Just =<< toNode n
              mn <- getNode i
              forM_ mn (appendChild n)
              return (i,True)
            Replace as -> do
              i <- buildAndEmbedMaybe sendEv doc ch True Nothing raw
              replace as i
              return (i,True)
            Append en -> do
              i <- buildAndEmbedMaybe sendEv doc ch True (Just en) raw
              return (i,True)
            BuildOnly -> do
              i <- buildAndEmbedMaybe sendEv doc ch False Nothing raw
              return (i,False)
  cr <- ControllerRecord <$> pure as <*> newIORef (ControllerView raw i model l) <*> pure ch
  -- keep out of forkIO to prevent double-initialization
  addController key cr
  forkIO $ do
    built <- build $ Ef.Base.state
                            (ControllerState
                                Nothing
                                (differ view (publish (chRendered ch) ()) sendEv)
                                Eager
                                us
                                model
                                (crView cr)
                            )
                    *:* Ef.Base.state ch
                    *:* Ef.Base.state sdn
                    *:* Ef.Base.state buf
                    *:* Empty
    (obj',_) <- Ef.Base.Object built Ef.Base.! do
      connect constructShutdownSyndicate $ const (Ef.Base.lift shutdownSelf)
      prime
#if (defined __GHCJS__) || (defined DEVEL)
    driverPrintExceptions (" Controller exception (" ++ show key ++ "): ")
#else
    driver
#endif
        buf obj'
  return cr

diff :: forall m ms. ms <: Base m => Proxy m -> Ef ms IO ()
diff _ = do
  as@ControllerState {..} :: ControllerState m <- get
  unsafeCoerce (asDiffer as)

setEagerDiff :: forall m ms. ms <: '[State () (ControllerState m)] => Proxy m -> Ef ms IO ()
setEagerDiff _ = do
  ControllerState {..} :: ControllerState m <- get
  put ControllerState { asDiffStrategy = Eager, .. }

setManualDiff :: forall m ms. ms <: '[State () (ControllerState m)] => Proxy m -> Ef ms IO ()
setManualDiff _ = do
  ControllerState {..} :: ControllerState m <- get
  put ControllerState { asDiffStrategy = Manual, .. }

currentHTML :: (IsController' ts ms m, MonadIO c) => Controller' ts ms m -> c (Promise (View ms))
currentHTML c = with c $ ownHTML c

ownHTML :: forall ts ms c m.
           ( IsController' ts ms m
           , MonadIO c
           , ms <: Base m
           )
        => Controller' ts ms m
        -> Ef ms c (View ms)
ownHTML _ = do
  ControllerState {..} :: ControllerState m <- get
  ControllerView {..} <- liftIO $ readIORef asLive
  return (unsafeCoerce cvCurrent)

onModelChange :: forall ts ms ms' m c e.
                ( IsController' ts ms m
                , MonadIO c
                , ms <: Base m
                , ms' <: '[Evented]
                , e ~ Ef ms' c
                )
              => Controller' ts ms m
              -> (m ms -> Ef '[Event (m ms)] e ())
              -> e (Promise (IO ()))
onModelChange c f = do
  buf <- get
  with c $ do
    ControllerState {..} :: ControllerState m <- get
    sub <- subscribe (unsafeCoerce asUpdates) (return buf)
    bhv <- listen sub f
    return (stop bhv >> leaveSyndicate (unsafeCoerce asUpdates) sub)

onOwnModelChange :: forall ts ms ms' m c e.
                    ( IsController' ts ms m
                    , MonadIO c
                    , ms <: Base m
                    , e ~ Ef ms c
                    )
                  => Controller' ts ms m
                  -> (m ms -> Ef '[Event (m ms)] e ())
                  -> e (IO ())
onOwnModelChange _ f = do
  buf <- get
  pr  <- promise
  ControllerState {..} :: ControllerState m <- get
  sub <- subscribe (unsafeCoerce asUpdates) (return buf)
  bhv <- listen sub f
  return (stop bhv >> leaveSyndicate (unsafeCoerce asUpdates) sub)

onOwnModelChangeByProxy :: forall ms m c e. (MonadIO c, ms <: Base m, e ~ Ef ms c)
                        => Proxy m -> (m ms -> Ef '[Event (m ms)] e ()) -> e (IO ())
onOwnModelChangeByProxy _ f = do
  buf <- get
  pr  <- promise
  ControllerState {..} :: ControllerState m <- get
  sub <- subscribe (unsafeCoerce asUpdates) (return buf)
  bhv <- listen sub f
  return (stop bhv >> leaveSyndicate (unsafeCoerce asUpdates) sub)

getModel :: forall m ms. ms <: '[State () (ControllerState m)] => Ef ms IO (m ms)
getModel = do
  ControllerState {..} :: ControllerState m <- get
  return $ unsafeCoerce asModel

putModel :: forall ms m. ms <: Base m => m ms -> Ef ms IO ()
putModel !new = do
  (ControllerState {..},(old,cmp')) <- modify $ \(ControllerState {..} :: ControllerState m) ->
    let !old = unsafeCoerce asModel
        cmp' = ControllerState { asModel = unsafeCoerce new, .. }
    in (cmp',(old,cmp'))
  publish (unsafeCoerce asUpdates) new
  let d :: ControllerState m -> Ef ms IO ()
      d = unsafeCoerce asDiffer
#ifdef __GHCJS__
  case reallyUnsafePtrEquality# old new of
    1# -> return ()
    _  ->
      case asDiffStrategy of
        Eager  -> d cmp'
        Manual -> return ()
#else
  d cmp'
#endif

modifyModel :: forall e ms m. ms <: Base m => (m ms -> m ms) -> Ef ms IO ()
modifyModel f = do
  (ControllerState {..},(old,!new,cmp')) <- modify $ \ControllerState {..} ->
    let !old = unsafeCoerce asModel
        !new = f old
        cmp' = ControllerState { asModel = unsafeCoerce new, ..  }
    in (cmp',(old,new,cmp'))
  publish (unsafeCoerce asUpdates) new
  let d :: ControllerState m -> Ef ms IO ()
      d = unsafeCoerce asDiffer
#ifdef __GHCJS__
  case reallyUnsafePtrEquality# old new of
    1# -> return ()
    _  ->
      case asDiffStrategy of
        Eager  -> d cmp'
        Manual -> return ()
#else
  d cmp'
#endif

differ :: (ms <: Base m, Renderable a ms)
       => (m ms -> a ms)
       -> IO ()
       -> (Ef ms IO () -> IO ())
       -> ControllerState m
       -> Ef ms IO ()
differ r trig sendEv ControllerState {..} = do
#ifdef __GHCJS__
  ch <- get
  let setupDiff = do
        let !new_as = AState (unsafeCoerce asLive) (unsafeCoerce asModel)
        new_ap_AState <- liftIO $ newIORef (Just new_as,False)
        let !aPatch = APatch sendEv new_ap_AState r trig ch
        put ControllerState { asPatch = Just aPatch, .. }
        liftIO $ diff_ aPatch
        return ()
  case asPatch of
    -- no current patch awaiting diff
    -- if this strategy doesn't work, use the return value
    -- from diff_ to cancel the animation frame event instead
    Nothing ->
      setupDiff
    Just APatch {..} -> do
        shouldSetupDiff <- liftIO $ atomicModifyIORef' ap_AState $ \mpatch ->
          case mpatch of
            (Just cs,False) ->
              ((Just cs { as_model = unsafeCoerce asModel },False),False)
            _ -> (mpatch,True)
        when shouldSetupDiff $ do
          setupDiff
  return ()
#else
  let v = render $ r (unsafeCoerce asModel)
  liftIO $ do
    ControllerView _ _ _ isFG <- liftIO $ readIORef asLive
    writeIORef asLive $ unsafeCoerce $ ControllerView v v (unsafeCoerce asModel) isFG
#endif

#ifdef __GHCJS__
toNode :: T.IsNode n => n -> IO NNode
toNode = T.castToNode
#else
toNode :: n -> IO NNode
toNode _ = return ()
#endif

createElement :: Doc -> Txt -> IO (Maybe ENode)
createElement doc tag =
#ifdef __GHCJS__
  D.createElement doc (Just tag)
#else
  return (Just ())
#endif

createTextNode :: Doc -> Txt -> IO (Maybe TNode)
createTextNode doc c =
#ifdef __GHCJS__
  D.createTextNode doc c
#else
  return (Just ())
#endif

createElementNS :: Doc -> Txt -> Txt -> IO (Maybe ENode)
createElementNS doc ns tag =
#ifdef __GHCJS__
  D.createElementNS doc (Just ns) (Just tag)
#else
  return (Just ())
#endif

clearNode :: Maybe NNode -> IO ()
clearNode mnode =
#ifdef __GHCJS__
  forM_ mnode clear_node_js
#else
  return ()
#endif

#ifdef __GHCJS__
appendChild :: T.IsNode n => ENode -> n -> IO ()
appendChild parent child =
  append_child_js parent =<< toNode child
#else
appendChild :: ENode -> n -> IO ()
appendChild _ _ =
  return ()
#endif

setInnerHTML :: ENode -> Txt -> IO ()
setInnerHTML el r =
#ifdef __GHCJS__
  E.setInnerHTML el (Just r)
#else
  return ()
#endif

isAlreadyEmbedded :: ENode -> ENode -> IO Bool
isAlreadyEmbedded target elem =
#ifdef __GHCJS__
  is_already_embedded_js target elem
#else
  return True
#endif

isAlreadyEmbeddedText :: TNode -> ENode -> IO Bool
isAlreadyEmbeddedText target txt =
#ifdef __GHCJS__
  is_already_embedded_text_js target txt
#else
  return True
#endif

changeText :: TNode -> Txt -> IO ()
changeText t cnt' =
#ifdef __GHCJS__
  changeText_js t cnt'
#else
  return ()
#endif

swapContent :: TNode -> ENode -> IO ()
swapContent t e =
#ifdef __GHCJS__
  swap_content_js t e
#else
  return ()
#endif

embed_ :: forall e. ENode -> View e -> IO ()
embed_ parent STView {..} = do
  forM_ _strecord $ \ref -> do
    ComponentRecord {..} <- readMVar ref
    embed_ parent (unsafeCoerce crLive :: View e)
embed_ parent TextView {..} =
  forM_ _tnode $ \node -> do
    ae <- isAlreadyEmbeddedText node parent
    unless ae (void $ appendChild parent node)
embed_ parent n =
  forM_ (_node n) $ \node -> do
    ae <- isAlreadyEmbedded node parent
    unless ae (void $ appendChild parent node)

embedMany_ parent children = do
  forM_ children $ \child -> do
    embed_ parent child

setAttributes :: [Feature e] -> (Ef e IO () -> IO ()) -> Bool -> ENode -> IO ([Feature e],IO ())
setAttributes as f diffing el = do
#ifdef __GHCJS__
  didMount_ <- newIORef (return ())
  attrs <- go didMount_ as
  dm <- readIORef didMount_
  return (attrs,dm)
  where
    go _ [] = return []
    go didMount_ (a:as) = do
      dm <- readIORef didMount_
      (a',dm') <- setAttribute_ f diffing el a dm
      writeIORef didMount_ dm'
      res <- go didMount_ as
      return (a':res)
#else
  return (as,return ())
#endif

newtype ComponentProperties ps = ComponentProperties { unwrapProperties :: ps }
getProps ::
  ( ms <: '[Reader () (ComponentProperties ps)]
  , ?props :: Proxy ps
  ) => Ef ms IO ps
getProps = asks unwrapProperties

newtype ComponentState st = ComponentState { unwrapComponentState :: st }
getState ::
  ( ms <: '[Reader () (ComponentState st)]
  , ?state :: Proxy st
  ) => Ef ms IO st
getState = asks unwrapComponentState

newtype ComponentConfig c = ComponentConfig { unwrapComponentConfig :: c }
getConfig ::
  ( ms <: '[Reader () (ComponentConfig c)]
  , ?config :: Proxy c
  ) => Ef ms IO c
getConfig = asks unwrapComponentConfig

-- Access to ComponentView can be cumbersome; generally requires type signature
-- See if this implicit param can help.
newtype ComponentView parent = ComponentView { unwrapComponentView :: View parent }
getView ::
  ( ?parent :: Proxy parent
  , ms <: '[Reader () (ComponentView parent)]
  ) => Ef ms IO (View parent)
getView = asks unwrapComponentView

type Construct props state config =
  forall ps.
  ( ps ~ ComponentProperties props
  , ?props :: Proxy props
  , ?state :: Proxy state
  , ?config :: Proxy config
  , Method "Construct"
    '[ About
       '[ "This method is run once during Component initialization and"
        , "produces the initial state and a read-only configuration value"
        , "seen by all other lifecycle methods."
        ]
     , Environment
       '[ Variable props
          '[ About
              '[ "Properties as seen during construction. Made available to"
               , "mount via `getProps`."
               ]
           ]
        ]
     , Results
       '[ Result state
          '[ About '[ "The initial state of the Component." ] ]
        , Result config
          '[ About
             '[ "The static configuration used throughout the life of the"
              , "Component."
              ]
           ]
        ]
     ]
  ) => Ef '[ Reader () ps ]
           IO
           (config,state)

runConstruct ::
  forall props state config.
  ( ?props :: Proxy props
  , ?state :: Proxy state
  , ?config :: Proxy config
  ) => Construct props state config -> props -> IO (config,state)
runConstruct constructMethod props = do
  let obj = Ef.Base.Object $
              reader (ComponentProperties props)
              *:* Ef.Base.Empty
  (_,(config,state)) <- obj Ef.Base.! constructMethod
  return (config,state)

type Initializer props state config =
  forall ps st cfg.
  ( ps ~ ComponentProperties props
  , st ~ ComponentState state
  , cfg ~ ComponentConfig config
  , ?props :: Proxy props
  , ?state :: Proxy state
  , ?config :: Proxy config
  , Method "Initializer"
    '[ About
       '[ "This method is run during server-side rendering only and allows"
        , "the Component to dynamically initialize state that is not"
        , "necessary on the client."
          ]
     , Environment
       '[ Variable props
          '[ About
             '[ "Properties as seen during construction. Made available to"
              , "mount via `getProps`."
              ]
           ]
        , Variable state
          '[ About
             '[ "State produced during construction. Made available to"
              , "mount via `getState`."
              ]
           ]
        , Variable config
          '[ About
             '[ "The read-only environment produced by the constructor."
              , "Made available via `getConfig`"
              ]
           ]
        ]
     , Results
       '[ Result state
          '[ About
             '["Produces a state value that is used during server-side"
              , "rendering to text."
              ]
           ]
        ]
     ]
  ) => Ef '[ Reader () ps
           , Reader () st
           , Reader () cfg
           ]
           IO
           state

runInitializer ::
  forall props state config.
  ( ?props :: Proxy props
  , ?state :: Proxy state
  , ?config :: Proxy config
  ) => Initializer props state config -> props -> state -> config -> IO state
runInitializer initializerMethod props state config = do
  let obj = Ef.Base.Object $
              reader (ComponentProperties props)
              *:* reader (ComponentState state)
              *:* reader (ComponentConfig config)
              *:* Ef.Base.Empty
  (_,state) <- obj Ef.Base.! initializerMethod
  return state

type Mount props state config mountResult =
  forall ps st cfg.
  ( ps ~ ComponentProperties props
  , st ~ ComponentState state
  , cfg ~ ComponentConfig config
  , ?props :: Proxy props
  , ?state :: Proxy state
  , ?config :: Proxy config
  , Method "Mount"
    '[ About
       '[ "This method is run only once after initialization, before calling"
        , "render for the first time. Unlike Update, Mount does not"
        , "run in an animation frame."
        ]
     , Environment
       '[ Variable props
          '[ About
             '[ "Properties as seen during construction. Made available to"
              , "mount via `getProps`."
              ]
           ]
        , Variable state
          '[ About
             '[ "State produced during construction. Made available to"
              , "mount via `getState`."
              ]
           ]
        , Variable config
          '[ About
             '[ "The read-only environment produced by the constructor."
              , "Made available via `getConfig`"
              ]
           ]
        ]
     ]
  ) => Ef '[ Reader () ps
           , Reader () st
           , Reader () cfg
           ]
           IO
           mountResult

runMount
  :: ( ?props :: Proxy props
     , ?state :: Proxy state
     , ?config :: Proxy config
     , Function "runMount"
       '[ About '[ "Run a mount method." ]
        , Params
          '[ Param mountMethod
             '[ About '[ "A method to be invoked before the first render." ] ]
           , Param props
             '[ About '[ "Current properties as seen in the constructor." ] ]
           , Param state
             '[ About '[ "Current state as returned from the constructor." ] ]
           , Param config
             '[ About
                '[ "The read-only environment produced by the constructor." ]
              ]
           ]
        , Results
          '[ Result mountResult
             '[ About
                '[ "An arbitrary result typed tied to the Mounted method."
                 , "This may be a useful place to inject profiling"
                 , "information."
                 ]
              ]
           ]
        ]

      ) => Mount props state config mountResult -> props -> state -> config -> IO mountResult
runMount mountMethod props state config = do
  let obj = Ef.Base.Object $
              reader (ComponentProperties props)
              *:* reader (ComponentState state)
              *:* reader (ComponentConfig config)
              *:* Ef.Base.Empty
  (_,mountResult) <- obj Ef.Base.! mountMethod
  return mountResult

type Mounted mountResult parent props state config =
  forall ps st cfg dom.
  ( ps ~ ComponentProperties props
  , st ~ ComponentState state
  , cfg ~ ComponentConfig config
  , dom ~ ComponentView parent
  , ?parent :: Proxy parent
  , ?props :: Proxy props
  , ?state :: Proxy state
  , ?config :: Proxy config
  , Method "Mounted"
    '[ About
       '[ "This method is run only once after rendering for the first time"
        , "before the end of the animation frame. The result of the render"
        , "is available for reflowing analysis or setting component state."
        , "Mounted can inspect the result of the call to Mount that"
        , "preceded it which may be useful for debugging purposes."
        ]
     , Environment
       '[ Variable props
          '[ About
             '[ "Properties as seen during construction. Made available to"
              , "mounted via `getProps`."
              ]
           ]
        , Variable state
          '[ About
             '[ "State produced during construction. Made available to"
              , "mounted via `getState`."
              ]
           ]
        , Variable dom
          '[ About
             '[ "A transient view of the managed DOM for the newly rendered"
              , "Component. Made available to mounted via `getView`. It is"
              , "likely for this view to be invalidated later during a"
              , "reconciliation cycle in which this view will be diffed"
              , "against a newly rendered view."
              ]
           ]
        , Variable config
          '[ About
             '[ "The read-only environment produced during"
              , "initialization. Made available via `getConfig`"
              ]
           ]
        ]
     ]
  ) => mountResult
    -> Ef '[ Reader () ps
           , Reader () st
           , Reader () dom
           , Reader () cfg
           ]
           IO
           ()

runMounted
  :: ( dom ~ View parent
     , ?parent :: Proxy parent
     , ?props :: Proxy props
     , ?state :: Proxy state
     , ?config :: Proxy config
     , Function "runUpdated"
       '[ About
          '[ "Run a Mounted method. A transient view of the DOM is"
           , "available to the method via `getView`. The result of"
           , "mount is avaialble via function parameterization. This"
           , "method runs in an animation frame before painting and permits"
           , "non-reflowing use of normally reflowing invocations."
           ]
        , Implicits
          '[ Implicit (Proxy parent)
             '[ About
                '[ "The parent implicit assists in retrieving a View"
                 , "quantified by the parent context."
                 ]
              ]
           ]
        , Params
          '[ Param mountedMethod
             '[ About
                '[ "The method to be invoked after a re-render and diff." ]
              ]
           , Param mountResult
             '[ About
                '[ "The result of the call to Mount that preceded this"
                 , "call."
                 ]
              ]
           , Param props
             '[ About '[ "Properties unmodified from initial construction." ] ]
           , Param state
             '[ About '[ "Initial state as produced by constructor." ] ]
           , Param dom
             '[ About
                '[ "A transient view of the managed DOM for the rendered"
                 , "Component. It is likely for this view to be"
                 , "invalidated during the next update when the view is"
                 , "re-rendered and this view is diffed against it. During"
                 , "the evaluation of mounted, this view should be valid."
                 ]
              ]
           , Param config
             '[ About
                '[ "The read-only environment produced during"
                 , "initialization."
                 ]
              ]
           ]
        ]
     ) => Mounted mountResult parent props state config -> mountResult -> props -> state -> dom -> config -> IO ()
runMounted mountedMethod mountResult props state dom config = do
  let obj = Ef.Base.Object $
              reader (ComponentProperties props)
              *:* reader (ComponentState state)
              *:* reader (ComponentView dom)
              *:* reader (ComponentConfig config)
              *:* Ef.Base.Empty
  _ <- obj Ef.Base.! (mountedMethod mountResult)
  return ()

type ReceiveProps parent props state config =
  forall newprops oldprops oldstate newstate dom cfg.
  ( newprops ~ props
  , oldprops ~ ComponentProperties props
  , oldstate ~ ComponentState state
  , newstate ~ state
  , dom ~ ComponentView parent
  , cfg ~ ComponentConfig config
  , ?parent :: Proxy parent
  , ?props :: Proxy props
  , ?state :: Proxy state
  , ?config :: Proxy config
  , Method "ReceiveProps"
    '[ About
       '[ "This method is run at the beginning of a reconciliation cycle"
        , "when the properties passed to a Component have implicitly"
        , "changed."
        ]
     , Implicits
       '[ Implicit (Proxy parent)
          '[ About
             '[ "The parent implicit assists in retrieving a View"
              , "quantified by the parent context."
              ]
           ]
        ]
     , Environment
       '[ Variable oldprops
          '[ About
             '[ "Properties before this reconciliation cycle."
              , "Made available to via `getProps`."
              ]
           ]
        , Variable oldstate
          '[ About
             '[ "State before this reconciliation cycle."
              , "Made available to via `getState`."
              ]
           ]
        , Variable dom
          '[ About
             '[ "A transient view of the managed DOM for the Component"
              , "being reconciled. Made available to forceUpdate via"
              , "`ask`. It is likely for this view to be invalidated"
              , "later during the active reconciliation cycle in which"
              , "this method is run when the view is re-rendered and this"
              , "view is diffed against it."
              ]
           ]
        , Variable config
          '[ About
             '[ "The read-only environment produced during"
              , "initialization. Made available via `getConfig`"
              ]
           ]
        ]
     , Params
       '[ Param newprops
          '[ About '[ "New properties during this reconciliation cycle." ] ]
        ]
     , Results
       '[ Result newstate
          '[ About
             '[ "New state produced for further reconciliation. To return"
              , "the old state, send `ask` as the last message."
              ]
           ]
        ]
     ]
  ) => newprops
    -> Ef '[ Reader () oldprops
           , Reader () oldstate
           , Reader () dom
           , Reader () cfg
           ]
           IO
           newstate

runReceiveProps
  :: ( newprops ~ props
     , oldprops ~ props
     , oldstate ~ state
     , newstate ~ state
     , dom ~ View parent
     , ?parent :: Proxy parent
     , ?props :: Proxy props
     , ?state :: Proxy state
     , ?config :: Proxy config
     , Function "runReceivePropsMethod"
       '[ About
          '[ "A method with implicit access to old properties and old state"
           , "and a transient view via ask and functional access to new"
           , "properties. Produces a new state value to be further used"
           , "during reconciliation."
           ]
        , Implicits
          '[ Implicit (Proxy parent)
             '[ About
                '[ "The parent implicit assists in retrieving a View"
                 , "quantified by the parent context."
                 ]
              ]
           ]
        , Params
          '[ Param oldprops
             '[ About
                '[ "Properties as they were before this reconciliation cycle." ]
              ]
           , Param newprops
             '[ About '[ "New properties; may be the same as old properties." ]
              ]
           , Param oldstate
             '[ About '[ "State as it was before this reconciliation cycle." ] ]
           , Param newstate
             '[ About
                '[ "New state; may be the same as old state. Produced either"
                 , "as a result of a state update call or during"
                 , "receiveProps if this reconciliation cycle is due to"
                 , "the reception of new properties."
                 ]
              ]
           , Param dom
             '[ About
                '[ "A transient view of the managed DOM for the Component"
                 , "being reconciled. It is likely for this view to be"
                 , "invalidated later during this active reconciliation"
                 , "cycle when the view is re-rendered and this view is"
                 , "diffed against it."
                 ]
              ]
           , Param config
             '[ About
                '[ "The read-only environment produced during"
                 , "initialization."
                 ]
              ]
           , Param receivePropsMethod
             '[ About
                '[ "The receiveProps method to be invoked to produce a new"
                 , "state from an old properties and old state when given a"
                 , "new properties."
                 ]
              ]
           ]
        , Results
          '[ Result newstate
             '[ About
                '[ "Produced state from the receivePropsMethod that will"
                 , "be used during the next phase of the reconciliation cycle,"
                 , "forceUpdate."
                 ]
              ]
           ]
        ]
     ) => ReceiveProps parent props state config -> oldprops -> newprops -> oldstate -> dom -> config -> IO newstate
runReceiveProps receivePropsMethod oldprops newprops oldstate dom config = do
  let obj = Ef.Base.Object $
              reader (ComponentProperties oldprops)
              *:* reader (ComponentState oldstate)
              *:* reader (ComponentView dom)
              *:* reader (ComponentConfig config)
              *:* Ef.Base.Empty
  (_,newstate) <- obj Ef.Base.! (receivePropsMethod newprops)
  return newstate

type ForceUpdate parent props state config =
    forall newprops oldprops newstate oldstate dom cfg.
    ( newprops ~ props
    , oldprops ~ ComponentProperties props
    , newstate ~ state
    , oldstate ~ ComponentState state
    , dom ~ ComponentView parent
    , cfg ~ ComponentConfig config
    , ?parent :: Proxy parent
    , ?props :: Proxy props
    , ?state :: Proxy state
    , ?config :: Proxy config
    , Method "ForceUpdate"
      '[ About
         '[ "This method is run at the beginning of a reconciliation cycle"
          , "after ReceiveProps during property changes or after state"
          , "changes but before Update. This allows the Component under"
          , "reconciliation to choose to not re-render."
          ]
       , Implicits
         '[ Implicit (Proxy parent)
            '[ About
               '[ "The parent implicit assists in retrieving a View"
                , "quantified by the parent context."
                ]
             ]
          ]
       , Environment
         '[ Variable oldprops
            '[ About
               '[ "Properties before this reconciliation cycle."
                , "Made available via `ask`."
                ]
             ]
          , Variable oldstate
            '[ About
               '[ "State before this reconciliation cycle."
                , "Made available via `ask`."
                ]
             ]
          , Variable dom
            '[ About
               '[ "A transient view of the managed DOM for the Component"
                , "being reconciled. Made available to ShouldUpdate via"
                , "`ask`. It is likely for this view to be invalidated"
                , "later during the active reconciliation cycle in which"
                , "this method is run when the view is re-rendered and this"
                , "view is diffed against it."
                ]
             ]
          , Variable config
            '[ About
               '[ "The read-only environment produced during"
                , "initialization. Made available via `ask`"
                ]
             ]
          ]
       , Params
         '[ Param newprops
            '[ About '[ "New properties during this reconciliation cycle." ] ]
          , Param newstate
            '[ About '[ "New state during this reconciliation cycle." ] ]
          ]
       ]
    ) => newprops
      -> newstate
      -> Ef '[ Reader () oldprops
             , Reader () oldstate
             , Reader () dom
             , Reader () cfg
             ] IO Bool

runForceUpdate
  :: ( newprops ~ props
     , oldprops ~ props
     , oldstate ~ state
     , newstate ~ state
     , dom ~ View parent
     , ?parent :: Proxy parent
     , ?props :: Proxy props
     , ?state :: Proxy state
     , ?config :: Proxy config
     , Function "runForceUpdate"
       '[ About
          '[ "Run a forceUpdate method with old and new properties and old"
           , "and new state as well as a transient view. Old props, old"
           , " state, and the transient view of the DOM are available to"
           , "the method via `ask`. New props and state are avaialble via"
           , "function parameterization."
           ]
        , Implicits
          '[ Implicit (Proxy parent)
             '[ About
                '[ "The parent implicit assists in retrieving a View"
                 , "quantified by the parent context."
                 ]
              ]
           ]
        , Params
          '[ Param forceUpdateMethod
             '[ About
                '[ "A method to be invoked to determine if a re-rendering and"
                 , "diffing is to be considered necessary during the active"
                 , "reconciliation cycle. The result of this method will be"
                 , "ignored if the current batch of reconciliations is"
                 , "already forcing a re-render."
                 ]
              ]
           , Param oldprops
             '[ About
                '[ "Properties as they were before this reconciliation cycle." ]
              ]
           , Param newprops
             '[ About
                '[ "New properties; may be the same as old properties." ]
              ]
           , Param oldstate
             '[ About
                '[ "State as it was before this reconciliation cycle." ]
              ]
           , Param newstate
             '[ About
                '[ "New state; may be the same as old state. Produced either"
                 , "as a result of a state update call or during"
                 , "receiveProps if this reconciliation cycle is due to"
                 , "the reception of new properties."
                 ]
              ]
           , Param dom
             '[ About
                '[ "A transient view of the managed DOM for the Component"
                 , "being reconciled. It is likely for this view to be"
                 , "invalidated later during this active reconciliation cycle"
                 , "when the view is re-rendered and this view is diffed"
                 , "against it."
                 ]
              ]
           , Param config
             '[ About
                '[ "The read-only environment produced during"
                 , "initialization."
                 ]
              ]
           ]
        ]

     ) => ForceUpdate parent props state config -> oldprops -> newprops -> oldstate -> newstate -> dom -> config -> IO Bool
runForceUpdate forceUpdateMethod oldprops newprops oldstate newstate dom config = do
  let obj = Ef.Base.Object $
              reader (ComponentProperties oldprops)
              *:* reader (ComponentState oldstate)
              *:* reader (ComponentView dom)
              *:* reader (ComponentConfig config)
              *:* Ef.Base.Empty
  (_,shouldForceUpdate) <- obj Ef.Base.! (forceUpdateMethod newprops newstate)
  return shouldForceUpdate

type Update parent props state config updateResult =
    forall newprops oldprops newstate oldstate dom cfg.
    ( newprops ~ ComponentProperties props
    , oldprops ~ props
    , newstate ~ ComponentState state
    , oldstate ~ state
    , dom ~ ComponentView parent
    , cfg ~ ComponentConfig config
    , ?parent :: Proxy parent
    , ?props :: Proxy props
    , ?state :: Proxy state
    , ?config :: Proxy config
    , Method "Update"
      '[ About
         '[ "This method is run before a re-render and diff inside of an"
          , "animation frame. Update is useful, in situations where the"
          , "transient view is reliable, for performing reflowing analysis"
          , "before a view is updated, e.g., the F step in FLIP animations."
          ]
       , Implicits
         '[ Implicit (Proxy parent)
            '[ About
               '[ "The parent implicit assists in retrieving a View"
                , "quantified by the parent context."
                ]
             ]
         ]
       , Environment
         '[ Variable newprops
            '[ About
               '[ "New properties during this reconciliation cycle."
                , "Made available via `ask`."
                ]
             ]
          , Variable newstate
            '[ About
               '[ "New state during this reconciliation cycle."
                , "Made available via `ask`."
                ]
             ]
          , Variable dom
            '[ About
               '[ "A transient view of the managed DOM for the Component"
                , "being reconciled. Made available to Update via"
                , "`ask`. It is likely for this view to be invalidated"
                , "during the re-rendering and diffing performed"
                , "immediately after Update."
                ]
             ]
          , Variable config
            '[ About
               '[ "The read-only environment produced during"
                , "initialization. Made available via `ask`"
                ]
             ]
          ]
       , Params
         '[ Param oldprops
            '[ About '[ "Old properties from the previous render." ] ]
          , Param oldstate
            '[ About '[ "Old state from the previous render." ] ]
          ]
       , Results
         '[ Result updateResult
            '[ About
               '[ "An arbitrary result type that will be passed to"
                , "Updated."
                ]
             ]
          ]
       ]
    ) => oldprops
      -> oldstate
      -> Ef '[ Reader () newprops
             , Reader () newstate
             , Reader () dom
             , Reader () cfg
             ]
             IO
             updateResult

runUpdate
  :: ( newprops ~ props
     , oldprops ~ props
     , oldstate ~ state
     , newstate ~ state
     , dom ~ View parent
     , ?parent :: Proxy parent
     , ?props :: Proxy props
     , ?state :: Proxy state
     , ?config :: Proxy config
     , Function "runUpdate"
       '[ About
          '[ "Run an update method with old and new properties and old"
           , "and new state as well as a transient view. New props, new"
           , "state, and the transient view of the DOM are available to the"
           , "method via `ask`. New props and state are avaialble via"
           , "function parameterization."
           ]
        , Implicits
          '[ Implicit (Proxy parent)
             '[ About
                '[ "The parent implicit assists in retrieving a"
                 , "quantified by the parent context."
                 ]
              ]
           ]
        , Params
          '[ Param updateMethod
             '[ About
                '[ "A method to be invoked to before a re-render and diff." ]
              ]
           , Param oldprops
             '[ About
                '[ "Properties as they were before this reconciliation cycle." ]
              ]
           , Param newprops
             '[ About
                '[ "New properties; may be the same as old properties." ]
              ]
           , Param oldstate
             '[ About
                '[ "State as it was before this reconciliation cycle." ]
              ]
           , Param newstate
             '[ About
                '[ "New state; may be the same as old state. Produced either"
                 , "as a result of a state update call or during"
                 , "receiveProps if this reconciliation cycle is due to"
                 , "the reception of new properties."
                 ]
              ]
           , Param dom
             '[ About
                '[ "A transient view of the managed DOM for the Component"
                 , "being reconciled. It is likely for this view to be"
                 , "invalidated later during this active reconciliation cycle"
                 , "when the view is re-rendered and this view is diffed"
                 , "against it."
                 ]
              ]
           , Param config
             '[ About
                '[ "The read-only environment produced during"
                 , "initialization."
                 ]
              ]
          ]
        , Results
          '[ Result updateResult
             '[ About
                '[ "An arbitrary result typed tied to the Updated method."
                 , "This is optionally where the result of DOM analysis is"
                 , "returned for animations that will be initiated in"
                 , "Updated."
                 ]
              ]
           ]
        ]
     ) => Update parent props state config updateResult -> oldprops -> newprops -> oldstate -> newstate -> dom -> config -> IO updateResult
runUpdate updateMethod oldprops newprops oldstate newstate dom config = do
  let obj = Ef.Base.Object $
              reader (ComponentProperties newprops)
              *:* reader (ComponentState newstate)
              *:* reader (ComponentView dom)
              *:* reader (ComponentConfig config)
              *:* Ef.Base.Empty
  (_,result) <- obj Ef.Base.! (updateMethod oldprops oldstate)
  return result

type Updated updateResult parent props state config =
    forall newprops oldprops newstate oldstate dom cfg.
    ( newprops ~ ComponentProperties props
    , oldprops ~ props
    , newstate ~ ComponentState state
    , oldstate ~ state
    , dom ~ ComponentView parent
    , cfg ~ ComponentConfig config
    , ?parent :: Proxy parent
    , ?props :: Proxy props
    , ?state :: Proxy state
    , ?config :: Proxy config
    , Method "Updated"
      '[ About
         '[ "This method is run after a re-render and diff inside of an"
          , "animation frame. Updated is useful for performing reflowing"
          , "analysis after a view is updated, e.g to begin a CSS animation"
          , "using the FLIP approach."
          ]
        , Implicits
          '[ Implicit (Proxy parent)
             '[ About
                '[ "The parent implicit assists in retrieving a View"
                 , "quantified by the parent context."
                 ]
              ]
           ]
        , Environment
          '[ Variable newprops
             '[ About
                '[ "New properties during this reconciliation cycle."
                 , "Made available via `ask`."
                 ]
              ]
           , Variable newstate
             '[ About
                '[ "New state during this reconciliation cycle."
                 , "Made available via `ask`."
                 ]
              ]
           , Variable dom
             '[ About
                '[ "A transient view of the managed DOM for the Component"
                 , "being reconciled. Made available to Update via"
                 , "`ask`. It is likely for this view to be invalidated"
                 , "during the re-rendering and diffing performed"
                 , "immediately after Update."
                 ]
              ]
           ]
        , Params
          '[ Param updateResult
             '[ About '[ "Result of the Update method." ] ]
           , Param oldprops
             '[ About '[ "Old properties from the previous render." ] ]
           , Param oldstate
             '[ About '[ "Old state from the previous render." ] ]
           ]
        ]
    ) => updateResult
      -> oldprops
      -> oldstate
      -> Ef '[ Reader () newprops
             , Reader () newstate
             , Reader () dom
             , Reader () cfg
             ]
             IO
             ()

runUpdated
  :: ( newprops ~ props
     , oldprops ~ props
     , oldstate ~ state
     , newstate ~ state
     , dom ~ View parent
     , cfg ~ ComponentConfig config
     , ?parent :: Proxy parent
     , ?props :: Proxy props
     , ?state :: Proxy state
     , ?config :: Proxy config
     , Function "runUpdated"
       '[ About
          '[ "Run an updated method with old and new properties and old"
           , "and new state as well as a transient view and the result of"
           , "update. New props, new state, and the transient view of"
           , "the DOM are available to the method via `ask`. Old props, old"
           , "state and the result of update are avaialble via"
           , "function parameterization. This method runs in an animation"
           , "frame before painting and permits non-reflowing use of"
           , "normally reflowing invocations, like getBoundingClientRect(),"
           , "and is thus useful for, e.g., the L and I steps in FLIP"
           , "animations where the P step is implicit."
           ]
        , Implicits
          '[ Implicit (Proxy parent)
             '[ About
                '[ "The parent implicit assists in retrieving a View"
                 , "quantified by the parent context."
                 ]
              ]
           ]
        , Params
          '[ Param updatedMethod
             '[ About
                '[ "The method to be invoked after a re-render and diff." ]
              ]
           , Param oldprops
             '[ About
                '[ "Properties as they were before this reconciliation cycle." ]
              ]
           , Param newprops
             '[ About '[ "New properties; may be the same as old properties." ]
              ]
           , Param oldstate
             '[ About '[ "State as it was before this reconciliation cycle." ] ]
           , Param newstate
             '[ About
                '[ "New state; may be the same as old state. Produced either"
                 , "as a result of a state update call or during"
                 , "receiveProps if this reconciliation cycle is due to"
                 , "the reception of new properties."
                 ]
              ]
           , Param dom
             '[ About
                '[ "A transient view of the managed DOM for the Component"
                 , "being reconciled. It is likely for this view to be"
                 , "invalidated later during the next reconciliation cycle"
                 , "when the view is re-rendered and this view is diffed"
                 , "against it. During the evaluation of updated, this"
                 , "view should be valid and active unless it was manipulated"
                 , "by another Updated method."
                 ]
              ]
           , Param config
             '[ About
                '[ "The read-only environment produced during"
                 , "initialization."
                 ]
              ]
           , Param updateResult
             '[ About
                '[ "An arbitrary result typed tied to the previous Update"
                 , "method. This is optionally where the result of DOM"
                 , "analysis was passed for animations that are to be"
                 , "initiated in the active animation frame. While the"
                 , "recently rendered view has not been painted, normally"
                 , "reflowing methods like getBoundingClientRect are"
                 , "invokable without forcing reflow. This is useful for,"
                 , "e.g., the L step in FLIP animations."
                 ]
              ]
           ]
        ]

     ) => Updated updateResult parent props state config -> updateResult -> oldprops -> newprops -> oldstate -> newstate -> dom -> config -> IO ()
runUpdated updatedMethod updateResult oldprops newprops oldstate newstate dom config = do
  let obj = Ef.Base.Object $
              reader (ComponentProperties newprops)
              *:* reader (ComponentState newstate)
              *:* reader (ComponentView dom)
              *:* reader (ComponentConfig config)
              *:* Ef.Base.Empty
  _ <- obj Ef.Base.! (updatedMethod updateResult oldprops oldstate)
  return ()

type Unmount parent props state config unmountResult =
  forall ps st dom cfg.
  ( ps ~ ComponentProperties props
  , st ~ ComponentState state
  , dom ~ ComponentView parent
  , cfg ~ ComponentConfig config
  , ?parent :: Proxy parent
  , ?props :: Proxy props
  , ?state :: Proxy state
  , ?config :: Proxy config
  , Method "Unmount"
    '[ About
       '[ "This method is run before a Component's view is unmounted and"
        , "destroyed. Any manually added listeners should be removed here."
        ]
     , Implicits
       '[ Implicit (Proxy parent)
          '[ About
             '[ "The parent implicit assists in retrieving a View quantified"
              , "by the parent context."
              ]
           ]
        ]
     , Environment
       '[ Variable props
          '[ About '[ "Current properties. Made available via `getProps`." ] ]
        , Variable state
          '[ About '[ "Current state. Made available via `getState`." ] ]
        , Variable config
          '[ About
             '[ "The read-only environment produced during initialization." ]
           ]
        ]
     ]
  ) => Ef '[ Reader () ps
           , Reader () st
           , Reader () dom
           , Reader () cfg
           ]
           IO
           unmountResult

runUnmount
  :: ( dom ~ View parent
     , ?parent :: Proxy parent
     , ?props :: Proxy props
     , ?state :: Proxy state
     , ?config :: Proxy config
     , Function "runUnmount"
       '[ About
          '[ "Run an unmount method with current properties and state as"
           , "well as the final view of the DOM. This is where manually"
           , "attached event listeners should be detached before the"
           , "Component is destructed."
           ]
        , Implicits
          '[ Implicit (Proxy parent)
             '[ About
                '[ "The parent implicit assists in retrieving a View"
                 , "quantified by the parent context."
                 ]
              ]
           ]
        , Params
          '[ Param unmountMethod
             '[ About
                '[ "The method to be invoked before the Component is"
                 , "destructed."
                 ]
              ]
           , Param props
             '[ About '[ "The final properties of the Component." ] ]
           , Param state
             '[ About '[ "The final state of the Component." ] ]
           , Param dom
             '[ About
                '[ "The view of the DOM before it is destroyed. Use it to"
                 , "remove manually attched event listeners if necessary."
                 ]
              ]
           , Param config
             '[ About
                '[ "The read-only environment produced during initialization." ]
              ]
           ]
        , Results
          '[ Result unmountResult
             '[ About
                '[ "Result of the call to the unmountMethod. This result"
                 , "will be tied into the Destructor method. May be useful"
                 , "for debugging and profiling."
                 ]
              ]
           ]
        ]
     ) => Unmount parent props state config unmountResult -> props -> state -> dom -> config -> IO unmountResult
runUnmount unmountMethod props state dom config = do
  let obj = Ef.Base.Object $
              reader (ComponentProperties props)
              *:* reader (ComponentState state)
              *:* reader (ComponentView dom)
              *:* reader (ComponentConfig config)
              *:* Ef.Base.Empty
  (_,unmountResult) <- obj Ef.Base.! unmountMethod
  return unmountResult


type Destruct unmountResult props state config =
  forall ps st cfg.
  ( ps ~ ComponentProperties props
  , st ~ ComponentState state
  , cfg ~ ComponentConfig config
  , ?props :: Proxy props
  , ?state :: Proxy state
  , ?config :: Proxy config
  , Method "Destruct"
    '[ About
       '[ "This method is run at the end of the Component's lifecycle with"
        , "final access to the Component's properties, state, configuration"
        , "and the result of the Unmount method."
        ]
     , Params
       '[ Param unmountResult
          '[ About
             '[ "Result of the predecessor call to Unmount." ]
           ]
        ]
     , Environment
       '[ Variable props
          '[ About '[ "The final properties of the Component." ] ]
        , Variable state
          '[ About '[ "The final state of the Component." ] ]
        , Variable config
          '[ About
             '[ "The read-only environment produced during initialization." ]
           ]
        ]
     ]
  ) => unmountResult
    -> Ef '[ Reader () ps
           , Reader () st
           , Reader () cfg
           ]
           IO
           ()

runDestruct
  :: ( ?parent :: Proxy parent
     , ?props :: Proxy props
     , ?state :: Proxy state
     , ?config :: Proxy config
     , Function "runDestruct"
       '[ About
          '[ "This function runs the final cleanup method for a Component."
           , "This is the last time this Component's props, state and config"
           , "will be accessible. This method is passed the result of"
           , "Unmount."
           ]
        , Params
          '[ Param unmountResult
             '[ About
                '[ "Result of the predecessor call to Unmount." ]
              ]
           , Param props
             '[ About '[ "The final properties of the Component." ] ]
           , Param state
             '[ About '[ "The fianl state of the component." ] ]
           , Param config
             '[ About
                '[ "The read-only environment produced during initialization." ]
              ]
           ]
        ]
     ) => Destruct unmountResult props state config -> unmountResult -> props -> state -> config -> IO ()
runDestruct destructMethod unmountResult props state config = do
  let obj = Ef.Base.Object $
              reader (ComponentProperties props)
              *:* reader (ComponentState state)
              *:* reader (ComponentConfig config)
              *:* Ef.Base.Empty
  _ <- obj Ef.Base.! (destructMethod unmountResult)
  return ()

type Renderer parent props state config =
  props -> state -> config -> StateUpdater props state -> View parent

data Component (parent :: [* -> *]) (props :: *) (state :: *) (config :: *) (mountResult :: *) (updateResult :: *) (unmountResult :: *) =
    Component
      { construct    :: Construct                         props state config
      , initialize   :: Initializer                       props state config
      , mount        :: Mount                             props state config mountResult
      , mounted      :: Mounted      mountResult   parent props state config
      , receiveProps :: ReceiveProps               parent props state config
      , forceUpdate  :: ForceUpdate                parent props state config
      , update       :: Update                     parent props state config updateResult
      , renderer     :: Renderer                   parent props state config
      , updated      :: Updated      updateResult  parent props state config
      , unmount      :: Unmount                    parent props state config unmountResult
      , destruct     :: Destruct     unmountResult        props state config
      }

instance (Typeable parent, Typeable props, Typeable state, Typeable config) => Default (Component parent props state config mountResult updateResult unmountResult) where
  def =
    Component
      { renderer     = \_ _ _ _ -> def
      , destruct     = \_ -> def
      , unmount      = return (error "unmount: no result")
      , updated      = \_ _ _ -> def
      , update       = \_ _ -> return (error "willUpate: no result")
      , forceUpdate  = \_ _ -> return True
      , receiveProps = \_ -> asks unwrapComponentState
      , mounted      = \_ -> def
      , mount        = return (error "mount: no result")
      , initialize   = asks unwrapComponentState
      , construct    = error "Component.construct: state not initialized."
      }

_rAF f = void $ do
#ifdef __GHCJS__
  rafCallback <- newRequestAnimationFrameCallback $ \_ -> f
  win <- getWindow
  requestAnimationFrame win (Just rafCallback)
#else
  f
#endif

buildComponent
  :: ( parent <: '[]
     , ?config ::Proxy config
     , ?parent ::Proxy parent
     , ?props  ::Proxy props
     , ?state  ::Proxy state
     ) => (Ef parent IO () -> IO ())
       -> Maybe ENode
       -> Bool
       -> ControllerHooks
       -> MVar (ComponentRecord parent props state config)
       -> MVar (ComponentPatchQueue props state)
       -> IORef (Maybe (PropsUpdater props))
       -> IORef (Maybe (StateUpdater props state))
       -> IORef (Maybe Unmounter)
       -> props
       -> Component parent props state config x y z
       -> IO ()
buildComponent f mparent isFG hooks strec stq pupd supd unm props c@Component {..} = do
  fg <- newIORef isFG
  (config,state) <- runConstruct construct props
  result <- runMount mount props state config
  d <- getDocument
  mupd <- readIORef supd
  forM_ mupd $ \upd ->
    _rAF $ do
      let mid = renderer props state config upd
      new <- buildAndEmbedMaybe f d hooks isFG mparent mid
      runMounted mounted result props state new config
      putMVar strec $
        ComponentRecord
          props
          state
          config
          pupd
          supd
          unm
          f
          fg
          hooks
          new
          mid
          c
          stq

newtype ComponentPatch props state =
  ComponentPatch
    { cpUpdate :: Either (MVar ()) (Either props (StateUpdate props state)) }

newtype ComponentPatchQueue props state
  = ComponentPatchQueue ([ComponentPatch props state],Maybe ThreadId)

data ComponentRecord parent props state config where
  ComponentRecord ::
    { crProps :: props
    , crState :: state
    , crConfig :: config
    , crInject :: IORef (Maybe (PropsUpdater props))
    , crUpdate :: IORef (Maybe (StateUpdater props state))
    , crUnmount :: IORef (Maybe Unmounter)
    , crLifter :: Lifter parent
    , crForeground :: IORef Bool
    , crControllerHooks :: ControllerHooks
    , crLive :: View parent
    , crMid :: View parent
    , crComponent :: Component parent props state config mountResult updateResult unmountResult
    , crPatchQueue :: MVar (ComponentPatchQueue props state)
    } -> ComponentRecord parent props state config

newPatchQueue ::
  forall parent state props config.
  ( ?state :: Proxy state
  , ?props :: Proxy props
  ) => IO (MVar (ComponentPatchQueue props state))
newPatchQueue = newMVar $ ComponentPatchQueue ([],Nothing)

queueComponentUpdate
  :: forall parent props state config x y z.
     ( parent <: '[]
     , ?config ::Proxy config
     , ?parent ::Proxy parent
     , ?props  ::Proxy props
     , ?state  ::Proxy state
     ) => MVar (ComponentPatchQueue props state)
       -> MVar (ComponentRecord parent props state config)
       -> Either (MVar ()) (Either props (StateUpdate props state))
       -> IO Bool ::: "Always returns True."
queueComponentUpdate q crec mepu = do
  modifyMVar q $ \(ComponentPatchQueue (ps,patchThread)) -> do
    assert (List.null ps || isJust patchThread) $ do
      let p = ComponentPatch mepu
      if isJust patchThread then
        return (ComponentPatchQueue (p:ps,patchThread),True)
      else do
        tid <- forkIO $ componentPatcher q crec (List.reverse $ p:ps)
        return (ComponentPatchQueue ([],Just tid),True)

data RenderUpdate where
  RenderUpdate
    :: { ru_willUpd :: IO updateResult
       , ru_didUpd :: updateResult -> IO ()
       , ru_updated :: IO ()
       } -> RenderUpdate

componentPatcher
  :: forall parent props state config.
     ( parent <: '[]
     , ?config ::Proxy config
     , ?parent ::Proxy parent
     , ?props  ::Proxy props
     , ?state  ::Proxy state
     ) => MVar (ComponentPatchQueue props state)
       -> MVar (ComponentRecord parent props state config)
       -> [ComponentPatch props state]
       -> IO ()
componentPatcher q crec ps = do
    cr@ComponentRecord { .. } <- readMVar crec
    go cr crComponent crProps crState crConfig crLive [] ps
  where

    invalidateComponent cr = do
      writeIORef (crInject cr) Nothing
      writeIORef (crUpdate cr) Nothing
      writeIORef (crUnmount cr) Nothing

    continue :: IO ()
    continue =
      join $ modifyMVar q $ \(ComponentPatchQueue (ps,patchThread)) -> do
        assert (isJust patchThread) $
          return $
            case ps of
              [] -> (ComponentPatchQueue ([],Nothing),def)
              _  -> (ComponentPatchQueue ([],patchThread),componentPatcher q crec (List.reverse ps))

    go :: forall x y z.
          ComponentRecord parent props state config
       -> Component parent props state config x y z
       -> props
       -> state
       -> config
       -> View parent
       -> [RenderUpdate]
       -> [ComponentPatch props state]
       -> IO ()
    go cr _ _ _ _ _ [] [] =
      continue

    go cr c newProps newState _ _ acc [] = do
      renderUpdates <- newEmptyMVar
      runUpdates renderUpdates newProps newState (List.reverse acc)
      rus <- takeMVar renderUpdates
      sequence_ rus
      continue
      where
        runUpdates renderUpdates props state as =
          _rAF $ do
            dus <- forM as $ \RenderUpdate {..} -> do
              res <- ru_willUpd
              return (ru_didUpd res,ru_updated)
            mupd <- readIORef (crUpdate cr)
            forM_ mupd $ \upd -> do
              let new = (renderer c) props state (crConfig cr) upd
              doc <- getDocument
              isFG <- readIORef (crForeground cr)
              new_live <- diffHelper (crLifter cr) doc (crControllerHooks cr) isFG (crLive cr) (crMid cr) new
              cbs <- forM dus $ \(du,c) -> do
                du
                return c
              swapMVar crec cr
                { crLive = new_live
                , crMid = new
                , crState = state
                , crProps = props
                }
              putMVar renderUpdates cbs

    go cr c props state config live acc (ComponentPatch p : ps ) =
      either remove (either propUpdate stateUpdate) p
      where
        propUpdate newProps = do
          newState <- runReceiveProps (receiveProps c) props newProps state live config
          shouldUpdate <- runForceUpdate (forceUpdate c) props newProps state newState live config
          if shouldUpdate || not (List.null acc) then
            let
              will = runUpdate (update c) props newProps state newState live config
              did = \wur -> runUpdated (updated c) wur props newProps state newState live config
            in
              go cr c newProps newState config live (RenderUpdate will did def : acc) ps
          else
            go cr c newProps newState config live acc ps

        stateUpdate f = do
          (newState,updatedCallback) <- f props state
          shouldUpdate <- runForceUpdate (forceUpdate c) props props state newState live config
          if shouldUpdate || not (List.null acc) then
            let
              will = runUpdate (update c) props props state newState live config
              did = \wur -> runUpdated (updated c) wur props props state newState live config
            in
              go cr c props newState config live (RenderUpdate will did updatedCallback : acc) ps
          else
            go cr c props newState config live acc ps

        remove barrier = do
          invalidateComponent cr
          wur <- runUnmount (unmount c) props state live config
          putMVar barrier ()
          runDestruct (destruct c) wur props state config

-- consider this: https://github.com/spicyj/innerhtml-vs-createelement-vs-clonenode
-- and this: https://stackoverflow.com/questions/8913419/is-chromes-appendchild-really-that-slow
-- Would a bottom-up, display='none' -> display='' solution work globally?
-- Does the fact that this runs in a rAF resolve any of this a priori?
buildAndEmbedMaybe :: forall e. (e <: '[]) => (Ef e IO () -> IO ()) -> Doc -> ControllerHooks -> Bool -> Maybe ENode -> View e -> IO (View e)
buildAndEmbedMaybe f doc ch isFG mn v = do
  go mn $ render v
  where
    go :: Maybe ENode -> View e -> IO (View e)
    go mparent (View c) = go mparent (render c)

    go mparent nn@NullView {..} = do
      _cond@(Just el) <- createElement doc "template"
      forM_ mparent (flip appendChild el)
      return $ NullView _cond

    go mparent RawView {..} = do
      _node@(Just el) <- createElement doc _tag
      (_attributes,didMount) <- setAttributes _attributes f False el
      setInnerHTML el _content
      forM_ mparent $ \parent -> appendChild parent el
      didMount
      return $ RawView _node _tag _attributes _content

    go mparent HTML {..} = do
      _node@(Just el) <- createElement doc _tag
      (_attributes,didMount) <- setAttributes _attributes f False el
      _atoms <- mapM (go (Just el)) _atoms
      forM_ mparent $ \parent -> appendChild parent el
      didMount
      return $ HTML _node _tag _attributes _atoms


    go mparent STView {..} =
      let ?parent = Proxy :: Proxy e
          ?state = _stStateProxy
          ?props = _stPropsProxy
          ?config = _stConfigProxy
      in do
        strec <- newEmptyMVar
        stq <- newPatchQueue
        stUpd <- newIORef $ Just $ queueComponentUpdate stq strec . Right . Right
        psUpd <- newIORef $ Just $ queueComponentUpdate stq strec . Right . Left
        unm   <- newIORef $ Just $ queueComponentUpdate stq strec . Left
        let
          stateUpdater f = do
            upd <- readIORef stUpd
            case upd of
              Nothing  -> return False
              Just upd -> do
                upd f
                return True

          propsUpdater ps = do
            upd <- readIORef psUpd
            case upd of
              Nothing  -> return False
              Just upd -> do
                upd ps
                return True

          unmounter = do
            upd <- readIORef unm
            case upd of
              Nothing  -> return False
              Just upd -> do
                barrier <- newEmptyMVar
                upd barrier
                takeMVar barrier
                return True

          c = _stview f stateUpdater

        buildComponent f mparent isFG ch strec stq psUpd stUpd unm _stprops c

        return $ STView _stprops (Just strec) _stview _stStateProxy _stPropsProxy _stConfigProxy

    go mparent SVG {..} = do
      _node@(Just el) <- createElementNS doc "http://www.w3.org/2000/svg" _tag
      (_attributes,didMount) <- setAttributes _attributes f False el
      _atoms <- mapM (go (Just el)) _atoms
      forM_ mparent $ \parent -> appendChild parent el
      didMount
      return $ SVG _node _tag _attributes _atoms

    go mparent KHTML {..} = do
      _node@(Just el) <- createElement doc _tag
      (_attributes,didMount) <- setAttributes _attributes f False el
      _keyed <- mapM (\(k,x) -> go (Just el) (render x) >>= \y -> return (k,y)) _keyed
      forM_ mparent $ \parent -> appendChild parent el
      didMount
      return $ KHTML _node _tag _attributes _keyed

    go mparent KSVG {..} = do
      _node@(Just el) <- createElementNS doc "http://www.w3.org/2000/svg" _tag
      (_attributes,didMount) <- setAttributes _attributes f False el
      _keyed <- mapM (\(k,x) -> go (Just el) (render x) >>= \y -> return (k,y)) _keyed
      forM_ mparent $ \parent -> appendChild parent el
      didMount
      return $ KSVG _node _tag _attributes _keyed

    go mparent TextView {..} = do
      _tnode@(Just el) <- createTextNode doc _content
      forM_ mparent (flip appendChild el)
      return $ TextView _tnode _content

    go mparent (DiffView m v) = do
      n <- go mparent v
      return (DiffView m n)

    go mparent (DiffEqView m v) = do
      n <- go mparent v
      return (DiffEqView m n)

    go mparent m@Managed {..} =
      case _constr of
        Controller' a -> do
          case _node of
            Nothing -> do
              _node@(Just el) <- createElement doc _tag
              (_attributes,didMount) <- setAttributes _attributes f False el
              mi_ <- lookupController (key a)
              case mi_ of
                Nothing -> do
                  -- never built before; make and embed
                  ControllerRecord {..} <- mkController BuildOnly a
                  ControllerView {..} <- liftIO $ readIORef crView
                  forM_ mparent $ \parent -> do
                    when isFG (triggerForeground m)
                    embed_ parent Managed {..}
                  embed_ el cvCurrentLive
                  didMount
                  return Managed {..}
                Just ControllerRecord {..} -> do
                  ControllerView {..} <- liftIO $ readIORef crView
                  rebuild Managed {..}
                  when isFG (triggerForeground m)
                  embed_ el cvCurrentLive
                  forM_ mparent $ \parent -> embed_ parent Managed {..}
                  didMount
                  return Managed {..}

            Just e -> do
              mi_ <- lookupController (key a)
              case mi_ of
                Nothing -> do
                  -- shut down?
                  ControllerRecord {..} <- mkController BuildOnly a
                  ControllerView {..} <- liftIO $ readIORef crView
                  forM_ mparent $ \parent -> do
                    when isFG (triggerForeground m)
                    embed_ parent Managed {..}
                  embed_ e cvCurrentLive
                  return Managed {..}
                Just ControllerRecord {..} -> do
                  ControllerView {..} <- liftIO $ readIORef crView
                  rebuild m
                  when isFG (triggerForeground m)
                  embed_ e cvCurrentLive
                  return m

buildHTML :: e <: '[] => Doc -> ControllerHooks -> Bool -> (Ef e IO () -> IO ()) -> View e -> IO (View e)
buildHTML doc ch isFG f = buildAndEmbedMaybe f doc ch isFG Nothing

getElement :: forall e. View e -> IO (Maybe ENode)
getElement View {} = return Nothing
getElement TextView {} = return Nothing
getElement (DiffView _ v) = getElement v
getElement (DiffEqView _ v) = getElement v
getElement STView {..} =
  case _strecord of
    Nothing -> return Nothing
    Just ref -> do
      ComponentRecord {..} <- readMVar ref
      getElement (unsafeCoerce crLive :: View e)
getElement n = return $ _node n

getNode :: forall e. View e -> IO (Maybe NNode)
getNode View {} = return Nothing
getNode (DiffView _ v) = getNode v
getNode (DiffEqView _ v) = getNode v
getNode TextView {..} = forM _tnode toNode
getNode STView {..} =
  case _strecord of
    Nothing -> return Nothing
    Just ref -> do
      ComponentRecord {..} <- readMVar ref
      getNode (unsafeCoerce crLive :: View e)
getNode n = forM (_node n) toNode

getAttributes :: View e -> [Feature e]
getAttributes TextView {} = []
getAttributes STView {} = []
getAttributes View {} = []
getAttributes NullView {} = []
getAttributes (DiffView _ v) = getAttributes v
getAttributes (DiffEqView _ v) = getAttributes v
getAttributes n = _attributes n

getChildren :: forall e. View e -> IO [View e]
getChildren (DiffView _ v) = getChildren v
getChildren (DiffEqView _ v) = getChildren v
getChildren STView {..} = do
  case _strecord of
    Nothing -> return []
    Just ref -> do
      ComponentRecord {..} <- readMVar ref
      return [unsafeCoerce crLive :: View e]
getChildren HTML {..} = return _atoms
getChildren SVG {..} = return _atoms
getChildren KHTML {..} = return $ map snd _keyed
getChildren KSVG {..} = return $ map snd _keyed
getChildren _ = return []

diff_ :: ControllerPatch m -> IO ()
diff_ APatch {..} = do
#ifdef __GHCJS__
  -- made a choice here to do all the diffing in the animation frame; this way we
  -- can avoid recalculating changes multiple times during a frame. No matter how
  -- many changes occur in any context, the diff is only calculated once per frame.
  rafCallback <- newRequestAnimationFrameCallback $ \_ -> do
    (mcs,b) <- atomicModifyIORef' ap_AState $ \(mcs,b) -> ((Nothing,True),(mcs,b))
    case mcs of
      Nothing -> return ()
      Just (AState as_live !as_model) -> do
        doc <- getDocument
        ControllerView !raw_html !live_html live_m isFG <- readIORef as_live
        let !new_html = render $ ap_patchRenderable as_model
        new_live_html <- diffHelper ap_send doc ap_hooks isFG live_html raw_html new_html
        writeIORef as_live $ ControllerView new_html new_live_html as_model isFG
        ap_viewTrigger
  win <- getWindow
  requestAnimationFrame win (Just rafCallback)
  return ()
  -- void $ forkIO $ takeMVar mv >> releaseCallback (unsafeCoerce rafCallback :: Callback (T.JSVal -> IO ()))
#else
  (mcs,b) <- atomicModifyIORef' ap_AState $ \(mcs,b) -> ((Nothing,True),(mcs,b))
  case mcs of
    Nothing -> return ()
    Just (AState as_live !as_model) -> do
      doc <- getDocument
      ControllerView !raw_html !live_html live_m isFG <- readIORef as_live
      let !new_html = render $ ap_patchRenderable as_model
      new_live_html <- diffHelper ap_send doc ap_hooks isFG live_html raw_html new_html
      writeIORef as_live $ ControllerView new_html new_live_html as_model isFG
      ap_viewTrigger
#endif

replace :: View e -> View e' -> IO ()
#ifndef __GHCJS__
replace _ _ = return ()
#else
replace old new = do
  mon <- getNode old
  mnn <- getNode new
  forM_ mon $ \on ->
    forM_ mnn $ \nn ->
      swap_js on nn
#endif

delete :: View e -> IO ()
#ifndef __GHCJS__
delete _ = return ()
#else
delete o = do
  mn <- getNode o
  forM_ mn delete_js
#endif

cleanup :: (Ef e IO () -> IO ()) -> [View e] -> IO (IO ())
#ifndef __GHCJS__
cleanup _ _ = return (return ())
#else
cleanup f = go (return ())
  where
    go didUnmount [] = return didUnmount
    go didUnmount (STView {..} : rest) =
      error "cleanup.STView"
    go didUnmount (r:rest) = do
      me <- getElement r
      du <- case me of
              Nothing -> return (return ())
              Just e  -> foldM (flip (cleanupAttr f e)) (return ()) (getAttributes r)
      unmounts' <- cleanup f =<< getChildren r
      go (unmounts' >> du >> didUnmount) rest
#endif

insertAt :: ENode -> Int -> View e -> IO ()
#ifndef __GHCJS__
insertAt _ _ _ = return ()
#else
insertAt parent ind n = getNode n >>= \mn -> forM_ mn $ insert_at_js parent ind
#endif

insertBefore_ :: forall e. ENode -> View e -> View e -> IO ()
#ifndef __GHCJS__
insertBefore_ _ _ _ = return ()
#else
insertBefore_ parent child new = do
  mcn <- getNode child
  mnn <- getNode new
  void $ N.insertBefore parent mnn mcn
#endif

diffHelper :: forall e v. (v ~ View e, e <: '[])
           => (Ef e IO () -> IO ()) -> Doc -> ControllerHooks -> Bool -> v -> v -> v -> IO v
diffHelper f doc ch isFG =
#ifdef __GHCJS__
    go
#else
    \_ _ n -> return n
#endif
  where

    go :: v -> v -> v -> IO v
    go old mid@(View m) new@(View n) =
      if reallyVeryUnsafeEq m n then do
        return old
      else
        go old (render m) (render n)

    go old mid new = do
      if reallyUnsafeEq mid new then do
        return old
      else
        go' old (render mid) (render new)

    go' :: View e -> View e -> View e -> IO (View e)
    go' old mid new@(View n) = do
      go old (render mid) (render new)

    go' old mid@(View _) new =
      go old (render mid) (render new)

    go' old@(DiffView _ v_old) mid@(DiffView m v) new@(DiffView m' v') =
      if typeOf m == typeOf m' && reallyVeryUnsafeEq m m' then
        return old
      else do
        new <- go' v_old v v'
        return (DiffView m' new)

    go' old@(DiffEqView _ v_old) mid@(DiffEqView m v) new@(DiffEqView m' v') =
      if typeOf m == typeOf m' && prettyUnsafeEq m (unsafeCoerce m') then do
        return old
      else do
        new <- go' v_old v v'
        return (DiffEqView m' new)

    go' old@NullView{} _ new = do
      case new of
        NullView _ -> return old
        _          -> do
          new' <- buildHTML doc ch isFG f new
          replace old new'
          didUnmount <- cleanup f [old]
          delete old
          didUnmount
          return new'

    go' old _ new@NullView{} = do
      new' <- buildHTML doc ch isFG f new
      replace old new'
      didUnmount <- cleanup f [old]
      delete old
      didUnmount
      return new'

    go' old@HTML {} mid@HTML {} new@HTML {} = do
      if prettyUnsafeEq (_tag old) (_tag new)
      then do
        let Just n = _node old
        (a',didMount) <-
              if reallyUnsafeEq (_attributes mid) (_attributes new) then do
                return (_attributes old,return ())
              else
                runElementDiff f n (_attributes old) (_attributes mid) (_attributes new)
        c' <- if reallyUnsafeEq (_atoms mid) (_atoms new) then do
                return (_atoms old)
              else
                diffChildren n (_atoms old) (_atoms mid) (_atoms new)
        didMount
        return $ HTML (_node old) (_tag old) a' c'
      else do new' <- buildHTML doc ch isFG f new
              replace old new'
              didUnmount <- cleanup f [old]
              delete old
              didUnmount
              return new'

    go' old@STView {} _ new@STView {} = do
      case (old,new) of
        (STView p ~(Just r) c _ _ _,STView p' _ _ _ _ _) -> do
          if typeOf p == typeOf p' then
            if reallyVeryUnsafeEq p p' then do
              return old
            else do
              withMVar r $ \ComponentRecord {..} -> do
                inj <- readIORef crInject
                forM_ inj ($ (unsafeCoerce p'))
              return old
          else do
            -- FIXME: This is still wonky.
            new' <- buildHTML doc ch isFG f new
            ComponentRecord {..} <- readMVar r
            barrier <- newEmptyMVar
            munm <- readIORef crUnmount
            case munm of
              Nothing ->
                -- ?
                replace crLive new'
              Just unm -> do
                b <- unm barrier
                if b then do
                  replace crLive new'
                  didUnmount <- cleanup f [crLive]
                  delete crLive
                  didUnmount
                else do
                  -- hmm?
                  replace crLive new'
            return new'


    go' old@SVG {} mid@SVG {} new@SVG {} =
      if prettyUnsafeEq (_tag old) (_tag new)
      then do
        let Just n = _node old
        (a',didMount) <-
              if reallyUnsafeEq (_attributes mid) (_attributes new) then do
                return (_attributes old,return ())
              else do
                runElementDiff f n (_attributes old) (_attributes mid) (_attributes new)
        c' <- if reallyUnsafeEq (_atoms mid) (_atoms new) then do
                return (_atoms old)
              else do
                diffChildren n (_atoms old) (_atoms mid) (_atoms new)
        didMount
        return $ SVG (_node old) (_tag old) a' c'
      else do new' <- buildHTML doc ch isFG f new
              replace old new'
              didUnmount <- cleanup f [old]
              delete old
              didUnmount
              return new'

    go' old@(KHTML old_node old_tag old_attributes old_keyed)
      mid@(KHTML midAnode _ midAattributes midAkeyed)
      new@(KHTML _ new_tag new_attributes new_keyed) =
      if prettyUnsafeEq old_tag new_tag
      then do
        let Just n = _node old
        (a',didMount) <-
              if reallyUnsafeEq midAattributes new_attributes then
                return (old_attributes,return ())
              else
                runElementDiff f n old_attributes midAattributes new_attributes
        c' <- if reallyUnsafeEq midAkeyed new_keyed then return old_keyed else
                diffKeyedChildren n old_keyed midAkeyed new_keyed
        didMount
        return $ KHTML old_node old_tag a' c'
      else do new' <- buildHTML doc ch isFG f new
              replace old new'
              didUnmount <- cleanup f [old]
              delete old
              didUnmount
              return new'

    go' old@(KSVG old_node old_tag old_attributes old_keyed)
      mid@(KSVG midAnode _ midAattributes midAkeyed)
      new@(KSVG _ new_tag new_attributes new_keyed) =
      if prettyUnsafeEq old_tag new_tag
      then do
        let Just n = _node old
        (a',didMount) <-
              if reallyUnsafeEq midAattributes new_attributes then
                return (old_attributes,return ())
              else
                runElementDiff f n old_attributes midAattributes new_attributes
        c' <- if reallyUnsafeEq midAkeyed new_keyed then return old_keyed else
                diffKeyedChildren n old_keyed midAkeyed new_keyed
        didMount
        return $ KSVG old_node old_tag a' c'
      else do new' <- buildHTML doc ch isFG f new
              replace old new'
              didUnmount <- cleanup f [old]
              delete old
              didUnmount
              return new'

    go' txt@(TextView (Just t) cnt) mid@(TextView _ mcnt) new@(TextView _ cnt') =
      if prettyUnsafeEq mcnt cnt' then do
        return txt
      else do
        changeText t cnt'
        return $ TextView (Just t) cnt'

    go' old@(RawView {}) mid@(RawView {}) new@(RawView {}) =
      if prettyUnsafeEq (_tag old) (_tag new) then do
        let Just n = _node old
        (a',didMount) <-
                if reallyUnsafeEq (_attributes mid) (_attributes new) then
                  return (_attributes old,return ())
                else
                  runElementDiff f n (_attributes old) (_attributes mid) (_attributes new)
        if prettyUnsafeEq (_content mid) (_content new) then do
          didMount
          return $ RawView (_node old) (_tag old) a' (_content old)
        else do
          setInnerHTML n (_content new)
          didMount
          return $ RawView (_node old) (_tag old) a' (_content new)
      else do new' <- buildHTML doc ch isFG f new
              replace old new'
              didUnmount <- cleanup f [old]
              delete old
              didUnmount
              return new'

    go' old@(Managed {}) mid new@(newc@(Managed {})) =
      if    (_constr old) == (_constr newc)
        && prettyUnsafeEq (_tag old) (_tag newc)
      then do
        let Just n = _node old
        (a',didMount) <-
                if reallyUnsafeEq (_attributes mid) (_attributes newc) then
                  return (_attributes old,return ())
                else
                  runElementDiff f n (_attributes old) (_attributes mid) (_attributes newc)
        didMount
        return $ Managed (_node old) (_tag old) a' (_constr old)
      else do
        when isFG (triggerBackground old)
        new' <- buildAndEmbedMaybe f doc ch isFG Nothing new
        replace old new'
        when isFG (triggerForeground new')
        didUnmount <- cleanup f [old]
        delete old
        didUnmount
        return new'

    go' old _ n = do
      n' <- buildAndEmbedMaybe f doc ch isFG Nothing n
      case old of
        t@(TextView (Just o) _) ->
          forM_ (_node n') (swapContent o)
        STView {..} ->
          forM_ _strecord $ \strec_ -> do
            strec <- readMVar strec_
            barrier <- newEmptyMVar
            munm <- readIORef (crUnmount strec)
            case munm of
              Nothing  -> replace old n'
              Just unm -> do
                b <- unm barrier
                if b then do
                  replace old n'
                  didUnmount <- cleanup f [old]
                  delete old
                  didUnmount
                else do
                  -- hmm?
                  replace old n'
        _ -> do
          replace old n'
          didUnmount <- cleanup f [old]
          delete old
          didUnmount
      return n'

    diffChildren :: ENode -> [v] -> [v] -> [v] -> IO [v]
    diffChildren n olds mids news = do
      withLatest olds mids news
      where

        withLatest :: [v] -> [v] -> [v] -> IO [v]
        withLatest = go_
          where

            go_ :: [v] -> [v] -> [v] -> IO [v]
            go_ [] _ news =
              mapM (buildAndEmbedMaybe f doc ch isFG (Just n)) news

            go_ olds _ [] = do
              didUnmount <- cleanup f olds
              mapM_ delete olds
              didUnmount
              return []

            go_ (old:olds) (mid:mids) (new:news) =
              let
                remove = do
                  didUnmount <- cleanup f [old]
                  delete old
                  didUnmount

                continue :: v -> IO [v]
                continue up = do
                  upds <-
                    if reallyUnsafeEq mids news then return olds else
                      withLatest olds mids news
                  return (up:upds)

              in do
                new <- go old mid new
                continue new

    diffKeyedChildren :: ENode -> [(Int,v)] -> [(Int,v)] -> [(Int,v)] -> IO [(Int,v)]
    diffKeyedChildren n = go_ 0 IM.empty
      where

        go_ :: Int -> IM.IntMap v -> [(Int,v)] -> [(Int,v)] -> [(Int,v)] -> IO [(Int,v)]
        go_ i store a m b = do
          if reallyUnsafeEq m b then do
            mapM_ cleanupElement store
            return a
          else
            go__ i store a m b
          where

            getFromStore :: IM.IntMap v -> Int -> (Maybe v,IM.IntMap v)
            getFromStore store i = IM.updateLookupWithKey (\_ _ -> Nothing) i store

            cleanupElement :: v -> IO ()
            cleanupElement v = do
              didUnmount <- cleanup f [v]
              delete v
              didUnmount

            go__ :: Int -> IM.IntMap v -> [(Int,v)] -> [(Int,v)] -> [(Int,v)] -> IO [(Int,v)]
            go__ _ store [] _ [] = do
              mapM_ cleanupElement store
              return []

            go__ i store [] _ ((bkey,b):bs) = do

              (child,store') <-
                case getFromStore store bkey of

                  (Nothing,_) -> do
                    new <- buildAndEmbedMaybe f doc ch isFG (Just n) b
                    return (new,store)

                  (Just prebuilt_b,store') -> do
                    mn <- getNode prebuilt_b
                    forM_ mn (appendChild n)
                    return (prebuilt_b,store')

              rest <- go__ 0 store' [] [] bs
              return $ (bkey,child) : rest

            go__ _ store olds _ [] = do
              mapM_ (cleanupElement . snd) olds
              mapM_ cleanupElement store
              return []

            go__ i store old@((akey,a):as) mid@((mkey,m):ms) new@((bkey,b):bs)
              | akey == bkey = do
                  new <- go' a (render m) (render b)
                  let !i' = i + 1
                  rest <- go_ i' store as ms bs
                  return $ (akey,new):rest

              | otherwise =
                  case (as,ms,bs) of
                    ((akey',a'):as',(mkey',m'):ms',(bkey',b'):bs')

                      -- swap
                      | bkey == akey' && akey == bkey' -> do

                          -- Diff both nodes
                          new1 <- go' a (render m) (render b)
                          new2 <- go' a' (render m') (render b')

                          -- move the second before the first
                          insertAt n i new1

                          -- continue with the rest of the list
                          let !i' = i + 2
                          rest <- go_ i' store as' ms' bs'
                          return $ (akey',new1):(akey,new2):rest

                      -- insert
                      | akey == bkey' ->

                          -- check if bkey was deleted earlier for re-embedding
                          case getFromStore store bkey of

                            (Nothing,_) ->
                              -- bkey wasn't deleted, check if it exists later in the list
                              case List.lookup bkey as of

                                Nothing -> do

                                  -- bkey is not later in the list, create it
                                  new <- buildAndEmbedMaybe f doc ch isFG Nothing b
                                  insertAt n i new
                                  let !i' = i + 1
                                  rest <- go_ i' store old mid bs
                                  return $ (bkey,new):rest

                                Just prebuilt_b -> do

                                  -- bkey found later in the list, move it
                                  -- this path defeats reallyUnsafeEq
                                  insertAt n i prebuilt_b
                                  let !i' = i + 1
                                      old' = List.deleteFirstsBy ((==) `F.on` fst) old [(bkey,prebuilt_b)]
                                      mid' = List.deleteFirstsBy ((==) `F.on` fst) mid [(bkey,prebuilt_b)]
                                  rest <- go__ i' store old' mid' bs
                                  return $ (bkey,prebuilt_b):rest

                            (Just prebuilt_b,store') -> do

                              -- bkey was seen earlier, move it
                              insertAt n i prebuilt_b
                              let !i' = i + 1
                              rest <- go_ i' store' old mid bs
                              return $ (bkey,prebuilt_b):rest

                      -- delete
                      | otherwise -> do

                          -- simply add akey to the store and continue
                          let !store' = IM.insert akey a store
                              !i' = i + 1
                          go_ i' store' as ms new

                    _ | akey == bkey -> do

                          new <- go' a (render m) (render b)
                          let !i' = i + 1
                          rest <- go_ i' store as ms bs
                          return $ (akey,new):rest

                      | otherwise -> do

                          let !store' = IM.insert akey a store
                              !i' = i + 1
                          go_ i' store' as ms new

applyStyleDiffs :: ENode -> [(Txt,Txt)] -> [(Txt,Txt)] -> IO [(Txt,Txt)]
applyStyleDiffs el olds0 news0 = do
#ifndef __GHCJS__
  return news0
#else
  obj <- O.create
  res <- go obj olds0 news0
  setStyle_js el obj
  return res
  where
    go obj = go'
      where
        go' [] news =
          mapM (\new@(nm,val) -> O.setProp nm (M.pToJSVal val) obj >> return new) news

        go' olds [] =
          mapM (\old@(nm,_) -> set_property_null_js obj nm >> return old) olds

        go' (old@(oname,oval):olds) (new@(nname,nval):news) =
          let
            remove =
              set_property_null_js obj oname

            set =
              O.setProp nname (M.pToJSVal nval) obj

            goRest =
              go' olds news

            continue up = do
              upds <- if reallyUnsafeEq olds news then return olds else goRest
              return (up:upds)

            update = do
              set
              continue new

            replace = do
              remove
              update

          in
            if reallyUnsafeEq old new then
                continue old
            else
              if prettyUnsafeEq oname nname then
                update
              else do
                replace
#endif

runElementDiff :: f ~ Feature e => (Ef e IO () -> IO ()) -> ENode -> [f] -> [f] -> [f] -> IO ([f],IO ())
runElementDiff f el os0 ms0 ns0 = do
#ifndef __GHCJS__
    return (ns0,return ())
#else
    dm_ <- newIORef (return ())
    fs <- go dm_ os0 ms0 ns0
    dm <- readIORef dm_
    return (fs,dm)
  where

    go dm_ [] [] news = do
      dm <- readIORef dm_
      go' news
      where
        go' [] = return []
        go' (n:ns) = do
          dm <- readIORef dm_
          (f,dm') <- setAttribute_ f True el n dm
          writeIORef dm_ dm'
          fs <- go' ns
          return (f:fs)

    go dm_ olds _ [] =
      mapM (\old -> removeAttribute_ f el old >> return NullFeature) olds

    go dm_ (old:olds) (mid:mids) (new:news) =
      let
        remove =
          removeAttribute_ f el old

        set = do
          dm <- readIORef dm_
          (f,dm') <- setAttribute_ f True el new dm
          writeIORef dm_ dm'
          return f

        goRest =
          go dm_ olds mids news

        continue up = do
          upds <- if reallyUnsafeEq mids news then do
                    return olds
                  else do
                    goRest
          return (up:upds)

        update = do
          new' <- set
          continue new'

        replace = do
          remove
          update

      in
        if reallyUnsafeEq mid new then do
          continue old
        else
          case (mid,new) of
            (_,NullFeature) -> do
              remove
              continue new

            (NullFeature,_) ->
              update

            (DiffFeature m ft,DiffFeature m' ft') ->
              if typeOf m == typeOf m' && reallyVeryUnsafeEq m m' then
                continue old
              else
                replace

            (DiffEqFeature m ft,DiffEqFeature m' ft') ->
              if typeOf m == typeOf m' && prettyUnsafeEq m (unsafeCoerce m') then
                continue old
              else
                replace

            (Property nm oldV,Property nm' newV) ->
              if prettyUnsafeEq nm nm' then
                if prettyUnsafeEq oldV newV then
                  continue old
                else
                  update
              else
                replace

            (DelayedProperty nm oldV,DelayedProperty nm' newV) ->
              if prettyUnsafeEq nm nm' then
                if prettyUnsafeEq oldV newV then
                  continue old
                else
                  update
              else
                replace

            (StyleF oldS,StyleF newS) -> do
              -- we know /something/ changed
              applyStyleDiffs el oldS newS
              continue new

            (Attribute nm val,Attribute nm' val') ->
              if prettyUnsafeEq nm nm' then
                if prettyUnsafeEq val val' then do
                  continue old
                else do
                  update
              else
                replace

            (DelayedAttribute nm val,DelayedAttribute nm' val') ->
              if prettyUnsafeEq nm nm' then
                if prettyUnsafeEq val val' then do
                  continue old
                else do
                  update
              else
                replace

            (OnE e os g _,OnE e' os' g' _) ->
              if prettyUnsafeEq e e' && prettyUnsafeEq os os' && reallyUnsafeEq g g' then
                continue old
              else
                replace

            (OnDocument e os g _,OnDocument e' os' g' _) ->
              if prettyUnsafeEq e e' && prettyUnsafeEq os os' && reallyUnsafeEq g g' then
                continue old
              else
                replace

            (OnWindow e os g _,OnWindow e' os' g' _) ->
              if prettyUnsafeEq e e' && prettyUnsafeEq os os' && reallyUnsafeEq g g' then
                continue old
              else do
                replace

            (OnFeatureAdd e,OnFeatureAdd e') ->
              -- Unlike On(Will/Did)Mount, OnFeatureAdd runs any time the handler changes, like OnModelChange.
              if reallyUnsafeEq e e' then
                continue old
              else do
                f (e' el)
                replace

            (OnFeatureRemove e,OnFeatureRemove e') ->
              if reallyUnsafeEq e e' then
                continue old
              else do
                f (e el)
                replace

            (OnWillMount g,OnWillMount g') ->
              -- OnWillMount has already run, it can't run again.
              continue old

            (OnDidMount g,OnDidMount g') ->
              -- OnDidMount has already run, it can't run again.
              continue old

            (OnModelChangeIO m g,OnModelChangeIO m' g') ->
              if typeOf m == typeOf m' then
                if reallyVeryUnsafeEq m m' then
                  if reallyVeryUnsafeEq g g' then
                    continue old
                  else
                    replace
                else do
                  g' (unsafeCoerce m) m' el
                  replace
              else
                replace

            (OnModelChange m g,OnModelChange m' g') ->
              if typeOf m == typeOf m' then
                if reallyVeryUnsafeEq m m' then
                  if reallyVeryUnsafeEq g g' then
                    continue old
                  else
                    replace
                else do
                  f (g' (unsafeCoerce m) m' el)
                  replace
              else
                replace

            (OnWillUnmount g,OnWillUnmount g') ->
              if reallyUnsafeEq g g' then
                continue old
              else
                replace

            (OnDidUnmount g,OnDidUnmount g') ->
              if reallyUnsafeEq g g' then
                continue old
              else
                replace

            (LinkTo olda oldv, LinkTo newa newv) ->
              if prettyUnsafeEq olda newa && reallyUnsafeEq oldv newv then
                continue old
              else
                replace

            (SVGLinkTo olda oldv, SVGLinkTo newa newv) ->
              if prettyUnsafeEq olda newa && reallyUnsafeEq oldv newv then
                continue old
              else
                replace

            (XLink olda oldv,XLink newa newv) ->
              if prettyUnsafeEq olda newa then
                if prettyUnsafeEq oldv newv then
                  continue old
                else
                  update
              else
                replace

            _ ->
              replace
#endif

removeAttribute_ :: (Ef e IO () -> IO ()) -> ENode -> Feature e -> IO ()
removeAttribute_ f element attr =
#ifndef __GHCJS__
  return ()
#else
  case attr of
    DiffFeature _ ft ->
      removeAttribute_ f element ft

    DiffEqFeature _ ft ->
      removeAttribute_ f element ft

    Property nm _ ->
      set_element_property_null_js element nm

    DelayedProperty nm _ ->
      set_element_property_null_js element nm

    Attribute nm _ ->
      E.removeAttribute element nm

    DelayedAttribute nm _ ->
      E.removeAttribute element nm

    LinkTo _ unreg -> do
      forM_ unreg id
      E.removeAttribute element ("href" :: Txt)

    OnE _ _ _ unreg ->
      forM_ unreg id

    OnDocument _ _ _ unreg ->
      forM_ unreg id

    OnWindow _ _ _ unreg ->
      forM_ unreg id

    OnFeatureRemove e ->
      f (e element)

    StyleF styles -> do
      obj <- O.create
      forM_ styles $ \(nm,val) -> O.unsafeSetProp nm (M.pToJSVal val) obj
      clearStyle_js element obj

    SVGLinkTo _ unreg -> do
      forM_ unreg id
      E.removeAttributeNS element (Just ("http://www.w3.org/1999/xlink" :: Txt)) ("xlink:href" :: Txt)

    XLink nm _ ->
      E.removeAttributeNS element (Just ("http://www.w3.org/1999/xlink" :: Txt)) nm

    _ -> return ()
#endif

onRaw :: ENode -> Txt -> Atomic.Attribute.Options -> (IO () -> Obj -> IO ()) -> IO (IO ())
onRaw el nm os f = do
#ifdef __GHCJS__
  stopper <- newIORef undefined
  stopListener <- Ev.on el (Ev.unsafeEventName nm :: Ev.EventName E.Element T.CustomEvent) $ do
    ce <- Ev.event
    when (_preventDef os) Ev.preventDefault
    when (_stopProp os) Ev.stopPropagation
    stop <- liftIO $ readIORef stopper
    liftIO $ f stop (unsafeCoerce ce)
  writeIORef stopper stopListener
  return stopListener
#else
  return (return ())
#endif

property :: ENode -> Feature e -> IO ()
#ifdef __GHCJS__
property node (Property k v) = set_property_js node k v
property node (DelayedProperty k v) = set_property_js node k v
#endif
property _ _ = return ()

attribute :: ENode -> Feature e -> IO ()
#ifdef __GHCJS__
attribute node (Attribute k v) = E.setAttribute node k v
attribute node (DelayedAttribute k v) = E.setAttribute node k v
#endif
attribute _ _ = return ()

#ifdef __GHCJS__
addEventListenerOptions :: (MonadIO c, Ev.IsEventTarget et, T.ToJSString t)
                        => et -> t -> T.EventListener -> Obj -> c ()
addEventListenerOptions self type' callback options =
  liftIO $
    js_addEventListenerOptions
      (T.toEventTarget self)
      (T.toJSString type')
      callback
      options

removeEventListenerOptions :: (MonadIO c, Ev.IsEventTarget et, T.ToJSString t)
                           => et -> t -> T.EventListener -> Obj -> c ()
removeEventListenerOptions self type' callback options =
  liftIO $
    js_removeEventListenerOptions
      (T.toEventTarget self)
      (T.toJSString type')
      callback
      options

foreign import javascript unsafe
        "$1[\"addEventListener\"]($2, $3,\n$4)" js_addEventListenerOptions
        :: T.EventTarget -> JSString -> T.EventListener -> Obj -> IO ()

foreign import javascript unsafe
        "$1[\"removeEventListener\"]($2,\n$3, $4)" js_removeEventListenerOptions
        :: T.EventTarget -> JSString -> T.EventListener -> Obj -> IO ()

onWith :: forall et e. (T.IsEventTarget et, T.IsEvent e)
       => Obj
       -> et
       -> Ev.EventName et e
       -> Ev.EventM et e ()
       -> IO (IO ())
onWith options target (Ev.EventName eventName) callback = do
  sl@(Ev.SaferEventListener l) :: Ev.SaferEventListener et e <- Ev.newListener callback
  addEventListenerOptions target eventName l options
  return (removeEventListenerOptions target eventName l options >> Ev.releaseListener sl)
#endif

setAttribute_ :: f ~ Feature e => (Ef e IO () -> IO ()) -> Bool -> ENode -> f -> IO () -> IO (f,IO ())
setAttribute_ c diffing element attr didMount =
#ifndef __GHCJS__
  return (attr,return ())
#else
  case attr of
    NullFeature ->
      return (NullFeature,didMount)

    DiffFeature m f -> do
      (f,dm) <- setAttribute_ c diffing element f didMount
      return (DiffFeature m f,dm)

    DiffEqFeature m f -> do
      (f,dm) <- setAttribute_ c diffing element f didMount
      return (DiffEqFeature m f,dm)

    Property nm v -> do
      set_property_js element nm v
      return (attr,didMount)

    DelayedProperty nm v -> do
      rafCallback <- newRequestAnimationFrameCallback $ \_ ->
        set_property_js element nm v
      win <- getWindow
      requestAnimationFrame win (Just rafCallback)
      return (attr,didMount)

    -- optimize this; we're doing a little more work than necessary!
    Attribute nm val -> do
      E.setAttribute element nm val
      return (attr,didMount)

    DelayedAttribute nm val -> do
      rafCallback <- newRequestAnimationFrameCallback $ \_ ->
        E.setAttribute element nm val
      win <- getWindow
      requestAnimationFrame win (Just rafCallback)
      return (attr,didMount)

    LinkTo href _ -> do
      E.setAttribute element ("href" :: Txt) href
      stopListener <-
#ifdef PASSIVE_LISTENERS
        -- enable by default when I have a polyfill or Edge/IE supports
        onWith
          (object (if _passive os then [ "passive" .= True ] else []))
#else
        Ev.on
#endif
          element
          (Ev.unsafeEventName "click" :: Ev.EventName E.Element T.MouseEvent)
            $ do Ev.preventDefault
                 liftIO $ do
                   win <- getWindow
                   Just hist <- W.getHistory win
                   H.pushState hist (M.pToJSVal (0 :: Int)) ("" :: Txt) href
                   triggerPopstate_js
                   scrollToTop
      return (LinkTo href (Just stopListener),didMount)

    OnE ev os f _ -> do
      stopper <- newIORef undefined
      stopListener <-
#ifdef PASSIVE_LISTENERS
        -- enable by default when I have a polyfill or Edge/IE supports
        onWith
          (object (if _passive os then [ "passive" .= True ] else []))
#else
        Ev.on
#endif
          element
          (Ev.unsafeEventName ev :: Ev.EventName E.Element T.CustomEvent) -- for the type checking; actually just an object
            $ do ce <- Ev.event
                 when (_preventDef os) Ev.preventDefault
                 when (_stopProp os) Ev.stopPropagation
                 stop <- liftIO $ readIORef stopper
                 liftIO $ mapM_ c =<< f (Evt
                   (unsafeCoerce ce)
                   (Event.preventDefault ce)
                   (Event.stopPropagation ce)
                   (join $ readIORef stopper)
                   element
                   )
                 return ()
      writeIORef stopper stopListener
      return (OnE ev os f (Just stopListener),didMount)

    OnDocument ev os f _ -> do
      stopper <- newIORef undefined
      doc <- getDocument
      stopListener <-
#ifdef PASSIVE_LISTENERS
        -- enable by default when I have a polyfill or Edge/IE supports
        onWith
          (object (if _passive os then [ "passive" .= True ] else []))
#else
        Ev.on
#endif
          doc
          (Ev.unsafeEventName ev :: Ev.EventName Doc T.CustomEvent) -- for the type checking; actually just an object
            $ do ce <- Ev.event
                 when (_preventDef os) Ev.preventDefault
                 when (_stopProp os) Ev.stopPropagation
                 stop <- liftIO $ readIORef stopper
                 liftIO $ mapM_ c =<< f (Evt
                   (unsafeCoerce ce)
                   (Event.preventDefault ce)
                   (Event.stopPropagation ce)
                   (join $ readIORef stopper)
                   element
                   )
                 return ()
      writeIORef stopper stopListener
      return (OnDocument ev os f (Just stopListener),didMount)

    OnWindow ev os f _ -> do
      stopper <- newIORef undefined
      win <- getWindow
      stopListener <-
#ifdef PASSIVE_LISTENERS
        -- enable by default when I have a polyfill or Edge/IE supports
        onWith
          (object (if _passive os then [ "passive" .= True ] else []))
#else
        Ev.on
#endif
          win
          (Ev.unsafeEventName ev :: Ev.EventName Win T.CustomEvent) -- for the type checking; actually just an object
            $ do ce <- Ev.event
                 when (_preventDef os) Ev.preventDefault
                 when (_stopProp os) Ev.stopPropagation
                 stop <- liftIO $ readIORef stopper
                 liftIO $ mapM_ c =<< f (Evt
                   (unsafeCoerce ce)
                   (Event.preventDefault ce)
                   (Event.stopPropagation ce)
                   (join $ readIORef stopper)
                   element
                   )
                 return ()
      writeIORef stopper stopListener
      return (OnWindow ev os f (Just stopListener),didMount)

    OnFeatureAdd e -> do
      c (e element)
      return (attr,didMount)

    OnWillMount f -> do
      f element
      return (attr,didMount)

    OnDidMount f -> do
      return (attr,if diffing then didMount else f element >> didMount)

    StyleF styles -> do
      obj <- O.create
      forM_ styles $ \(nm,val) -> O.unsafeSetProp nm (M.pToJSVal val) obj
      setStyle_js element obj
      return (attr,didMount)

    SVGLinkTo href _ -> do
      E.setAttributeNS element (Just ("http://www.w3.org/1999/xlink" :: Txt)) ("xlink:href" :: Txt) href
      stopListener <-
        Ev.on
          element
          (Ev.unsafeEventName "click" :: Ev.EventName E.Element T.MouseEvent)
            $ do Ev.preventDefault
                 liftIO $ do
                   win <- getWindow
                   Just hist <- W.getHistory win
                   H.pushState hist (M.pToJSVal (0 :: Int)) ("" :: Txt) href
                   triggerPopstate_js
                   scrollToTop
      return (SVGLinkTo href (Just stopListener),didMount)

    XLink nm val -> do
      E.setAttributeNS element (Just ("http://www.w3.org/1999/xlink" :: Txt)) nm val
      return (attr,didMount)

    _ -> return (attr,didMount)
#endif

cleanupAttr :: (Ef e IO () -> IO ()) -> ENode -> Feature e -> IO () -> IO (IO ())
cleanupAttr f element attr didUnmount =
#ifndef __GHCJS__
  return didUnmount
#else
  case attr of
    SVGLinkTo _ unreg -> do
      forM_ unreg id
      return didUnmount
    LinkTo _ unreg -> do
      forM_ unreg id
      return didUnmount
    DiffFeature _ ft ->
      cleanupAttr f element ft didUnmount
    DiffEqFeature _ ft ->
      cleanupAttr f element ft didUnmount
    OnE _ _ _ unreg -> do
      forM_ unreg id
      return didUnmount
    OnDocument _ _ _ unreg -> do
      forM_ unreg id
      return didUnmount
    OnWindow _ _ _ unreg -> do
      forM_ unreg id
      return didUnmount
    OnFeatureRemove e -> do
      f (e element)
      return didUnmount
    OnWillUnmount g -> do
      g element
      return didUnmount
    OnDidUnmount g -> return (didUnmount >> g element)
    _ -> return didUnmount
#endif

getWindow :: MonadIO c => c Win
getWindow =
#ifdef __GHCJS__
  fromJust <$> liftIO DOM.currentWindow
#else
  return ()
#endif

scrollToTop :: MonadIO c => c ()
scrollToTop = do
  win <- getWindow
#ifdef __GHCJS__
  W.scrollTo win 0 0
#else
  return win
#endif

getDocument :: (MonadIO c) => c Doc
getDocument = do
#ifdef __GHCJS__
    win <- getWindow
    Just doc <- liftIO $ W.getDocument win
#else
    let doc = ()
#endif
    return doc

getFirstElementByTagName :: MonadIO c => Txt -> c ENode
getFirstElementByTagName nm = do
  doc     <- getDocument
#ifdef __GHCJS__
  Just nl <- D.getElementsByTagName doc nm
  Just b  <- N.item nl 0
  liftIO $ T.castToElement b
#else
  return doc
#endif

getLocation :: (MonadIO c) => c Loc
getLocation = do
  win <- getWindow
#ifdef __GHCJS__
  Just loc <- W.getLocation win
#else
  let loc = ()
#endif
  return loc

redirect :: MonadIO c => Txt -> c ()
redirect redir = do
  loc <- getLocation
#ifdef __GHCJS__
  L.assign loc redir
#else
  return loc
#endif

-- makePrisms ''View
-- makeLenses ''View
