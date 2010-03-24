{-# LANGUAGE FlexibleInstances, MultiParamTypeClasses, TypeSynonymInstances, UndecidableInstances, PackageImports #-}
module URLT.Happstack where

import Control.Applicative.Error (Failing(Failure, Success))
import Control.Monad (MonadPlus(mzero))
import Data.List (intercalate)
import Happstack.Server (FilterMonad(..), ServerMonad(..), WebMonad(..), ServerPartT, Response, Request(rqPaths), ToMessage(..), dirs, runServerPartT, withRequest)
import URLT.Monad (URLT(URLT), liftURLT, mapURLT)
import URLT.MTL
import URLT.HandleT (Site, runSite)

instance (ServerMonad m) => ServerMonad (URLT url m) where
    askRq       = liftURLT askRq
    localRq f m = mapURLT (localRq f) m

instance (FilterMonad a m)=> FilterMonad a (URLT url m) where
    setFilter     = liftURLT . setFilter
    composeFilter = liftURLT . composeFilter
    getFilter     = mapURLT getFilter 

instance (WebMonad a m) => WebMonad a (URLT url m) where
    finishWith = liftURLT . finishWith

implSite :: (Monad m) => String -> FilePath -> Site url String (ServerPartT m a) -> ServerPartT m a
implSite domain approot siteSpec =
    dirs approot $ do rq <- askRq
                      let pathInfo = intercalate "/" (rqPaths rq)
                          f        = runSite (domain ++ approot) siteSpec pathInfo
                      case f of
                        (Failure _) -> 
                          mzero
                        (Success sp) -> localRq (const $ rq { rqPaths = [] }) sp
