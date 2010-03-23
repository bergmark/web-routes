{-# LANGUAGE CPP, TemplateHaskell #-}
{-# OPTIONS_GHC -optP-include -optPdist/build/autogen/cabal_macros.h #-}
module URLT.TH where

import Control.Applicative (Applicative((<*>)))
import Control.Applicative.Error (Failing(Failure, Success))
import Control.Monad (replicateM)
import Data.List (intercalate)
import Language.Haskell.TH
import Control.Monad.Consumer (Consumer, next, runConsumer)
import URLT.PathInfo


-- FIXME: handle unexpected end of input
-- FIXME: handle invalid input
-- FIXME: handle when called with a type (not data, newtype)
derivePathInfo :: Name -> Q [Dec]
derivePathInfo name
    = do c <- parseInfo name
         case c of
           Tagged cons cx keys ->
               do let context = [ mkCtx ''PathInfo [varT key] | key <- keys ] ++ map return cx
                  i <- instanceD (sequence context) (mkType ''PathInfo [mkType name (map varT keys)])
                       [ toURLFn cons 
                       , fromPathSegmentsFn cons
                       ]
                  return [i]
    where
#if MIN_VERSION_template_haskell(2,4,0)
      mkCtx = classP
#else
      mkCtx = mkType
#endif

      toURLFn :: [(Name, Int)] -> DecQ
      toURLFn cons 
          = do inp <- newName "inp"
               let body = caseE (varE inp) $
                            [ do args <- replicateM nArgs (newName "arg")
                                 let matchCon = conP conName (map varP args)
                                     conStr = (nameBase conName)
                                 match matchCon (normalB (toURLWork conStr args)) []
                                  |  (conName, nArgs) <- cons ]
                   toURLWork :: String -> [Name] -> ExpQ
                   toURLWork conStr args
                       = foldr1 (\a b -> appE (appE [| (++) |] a) b) ([| [conStr] |] : [ [| toPathSegments $(varE arg) |] | arg <- args ])
               funD 'toPathSegments [clause [varP inp] (normalB body)  []]
      fromPathSegmentsFn :: [(Name,Int)] -> DecQ
      fromPathSegmentsFn cons
          = do let body = 
                       do c <- newName "c"
                          doE [ bindS (varP c) (varE 'next)
                              , noBindS $ caseE (varE c)
                                        ([ do args <- replicateM nArgs (newName "arg")
                                              match (conP (mkName "Just") [litP $ stringL (nameBase conName) ])
                                                       (normalB (fromURLWork conName args)) []
                                          | (conName, nArgs) <- cons
                                        ] ++ 
                                        [ do str <- newName "str"
                                             let conNames = map (nameBase . fst) cons
                                             match (conP (mkName "Just") [varP str]) (normalB [| return (Failure ["Got '" ++ $(varE str) ++ "' expecting one of " ++ intercalate ", " conNames ]) |]) []
                                        , match (conP (mkName "Nothing") []) (normalB  [| return (Failure ["Unexpected end of input."]) |]) []
                                        ])
                                
                              ]
                   fromURLWork :: Name -> [Name] -> ExpQ
                   fromURLWork conName args
                       = doE $ [ bindS (varP arg) [| fromPathSegments |] | arg <- args ] ++
                               [ noBindS [| return $(foldl (\a b -> appE (appE [| (<*>) |] a) b)  (appE [| Success |] (conE conName)) (map varE args)) |] ]
               funD 'fromPathSegments [clause [] (normalB body) []]


mkType :: Name -> [TypeQ] -> TypeQ
mkType con = foldl appT (conT con)


data Class = Tagged [(Name, Int)] Cxt [Name]


parseInfo :: Name -> Q Class
parseInfo name
    = do info <- reify name
         case info of
           TyConI (DataD cx _ keys cs _)    -> return $ Tagged (map conInfo cs) cx $ map conv keys
           TyConI (NewtypeD cx _ keys con _)-> return $ Tagged [conInfo con] cx $ map conv keys
           _                            -> error "Invalid input"
    where conInfo (NormalC n args) = (n, length args)
          conInfo (RecC n args) = (n, length args)
          conInfo (InfixC _ n _) = (n, 2)
          conInfo (ForallC _ _ con) = conInfo con
#if MIN_VERSION_template_haskell(2,4,0)
          conv (PlainTV nm) = nm
          conv (KindedTV nm _) = nm
#else
          conv = id
#endif
