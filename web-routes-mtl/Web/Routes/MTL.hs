{-# LANGUAGE GeneralizedNewtypeDeriving, FlexibleInstances, TypeFamilies, PackageImports #-}
module Web.Routes.MTL where

import "mtl" Control.Monad.Trans (MonadTrans(lift), MonadIO(liftIO))
import Web.Routes.Monad (RouteT, liftRouteT)

instance MonadTrans (RouteT url) where
  lift = liftRouteT
  
instance (MonadIO m) => MonadIO (RouteT url m) where  
  liftIO = lift . liftIO