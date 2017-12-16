{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleContexts #-}
module Pure.Service (module Pure.Service, module Export) where

import Ef.Base

import Pure.Data hiding ((!))

import qualified Pure.Data as Export

import Control.Concurrent
import GHC.Prim

import Data.IntMap.Strict as Map hiding (Key,(!))

import System.IO.Unsafe
import Unsafe.Coerce

instance (IsService' ts ms, MonadIO c) =>
          With
          (Service' ts ms)
          (Ef ms IO)
          c
  where
    using_ s = do
      -- faster lookup followed by modify if necessary which will check to
      -- make sure the service was not added between the lookup and the modify.
      mas <- lookupService (key s)
      case mas of
        Nothing -> do
          let Key _ i = key s
          liftIO $ modifyVault serviceVault__ $ \v ->
            case Map.lookup i v of
              Nothing -> do
                buf <- newEvQueue
                startService buf s
                asService :: As (Ef ms IO) <- unsafeConstructAs buf
                let new_v = Map.insert i (unsafeCoerce asService) v
                return (new_v,liftIO . runAs asService)
              Just as ->
                return (v,liftIO . runAs as)
        Just as ->
          return (liftIO . runAs as)
    with_ s m = do
      run <- using_ s
      run m
    shutdown_ s = do
      with_ s $ do
        buf <- get
        Shutdown sdn <- get
        publish sdn ()
        delay 0 $ do
          liftIO $ do
            killBuffer buf
            myThreadId >>= killThread
      deleteService (key s)


type IsService' ts ms = (ms <: Base, ts <. Base, Delta (Modules ts) (Messages ms))
type IsService ms = IsService' (Appended Base ms) (Appended Base ms)

type Base = '[Evented,State () Vault,State () Shutdown]

type ServiceKey ms = Key (As (Ef (Appended ms Base) IO))
type ServiceBuilder ts = Modules Base (Action (Appended ts Base) IO) -> IO (Modules (Appended ts Base) (Action (Appended ts Base) IO))
type ServicePrimer ms = Ef (Appended ms Base) IO ()

data Service' ts ms
  = Service
      { key      :: !(Key (As (Ef ms IO)))
      , build    :: !(Modules Base (Action ts IO) -> IO (Modules ts (Action ts IO)))
      , prime    :: !(Ef ms IO ())
      }
type Service ms = Service' (Appended ms Base) (Appended ms Base)

instance Eq (Service' ts ms) where
  (==) (Service i _ _) (Service i' _ _) =
    let Key _ k1 = i
        Key _ k2 = i'
    in k1 == k2

startService :: forall ms ts c.
                ( MonadIO c
                , IsService' ts ms
                )
              => EvQueue
              -> Service' ts ms
              -> c ()
startService rb Service {..} = do
  sdn :: Syndicate () <- syndicate
  lv <- liftIO createVault
  built <- liftIO $ build $  state rb
                         *:* state lv
                         *:* state (Shutdown sdn)
                         *:* Empty
  void $ liftIO $ forkIO $ do
    (obj,_) <- Object built ! do
      connect serviceShutdownSyndicate $ const (Ef.Base.lift shutdownSelf)
      prime
#ifdef __GHCJS__
    driverPrintExceptions ( "Service exception (" ++ show key ++ "): " )
#else
    driver
#endif
      rb obj

{-# NOINLINE serviceShutdownSyndicate #-}
serviceShutdownSyndicate :: Syndicate ()
serviceShutdownSyndicate = unsafePerformIO syndicate

{-# NOINLINE serviceVault__ #-}
serviceVault__ :: Vault
serviceVault__ = Vault (unsafePerformIO (newMVar Map.empty))

lookupService :: (Monad c, MonadIO c)
              => Key phantom -> c (Maybe phantom)
lookupService = liftIO . vaultLookup serviceVault__

deleteService :: (Monad c, MonadIO c)
              => Key phantom -> c ()
deleteService = liftIO . vaultDelete serviceVault__
