-- | An Error handling scheme that can be used with 'PrinterParser'
{-# LANGUAGE DeriveDataTypeable, TypeFamilies #-}
module Text.Zwaluw.Error where

import Control.Monad.Error (Error(..))
import Data.Data (Data, Typeable)
import Data.List (intercalate, sort, nub)
import Text.Zwaluw.Prim
import Text.Zwaluw.Pos

data ErrorMsg
    = SysUnExpect String
    | UnExpect String
    | Expect String
    | Message String
    | RouteEOF
    | RouteEOS
      deriving (Eq, Ord, Read, Show, Typeable, Data)

messageString :: ErrorMsg -> String
messageString (Expect s)         = s
messageString (UnExpect s)       = s
messageString (SysUnExpect s)    = s
messageString RouteEOF           = "end of input"
messageString RouteEOS           = "end of segment"
messageString (Message s)        = s

data ParserError pos = ParserError (Maybe pos) [ErrorMsg]
    deriving (Eq, Ord, Typeable, Data)

type instance Pos (ParserError p) = p

instance ErrorPosition (ParserError p) where
    getPosition (ParserError mPos _) = mPos


{-
instance ErrorList ParserError where
    listMsg s = [ParserError Nothing (Other s)]
-}

instance Error (ParserError p) where
    strMsg s = ParserError Nothing [Message s]

mkParserError :: pos -> [ErrorMsg] -> [Either (ParserError pos) a]
mkParserError pos e = [Left (ParserError (Just pos) e)]


infix  0 <?>

-- | annotate a parse error with an additional 'Expect' message
(<?>) :: PrinterParser (ParserError p) tok a b -> String -> PrinterParser (ParserError p) tok a b
router <?> msg = 
    router { prs = Parser $ \tok pos ->
        map (either (\(ParserError mPos errs) -> Left $ ParserError mPos ((Expect msg) : errs)) Right) (runParser (prs router) tok pos) }

-- | condense the 'ParserError's with the highest parse position into a single 'ParserError'
condenseErrors :: (Ord pos) => [ParserError pos] -> ParserError pos
condenseErrors errs = 
    case bestErrors errs of
      [] -> ParserError Nothing []
      errs'@(ParserError pos _ : _) ->
          ParserError pos (nub $ concatMap (\(ParserError _ e) -> e) errs')

-- | Helper function for turning '[ErrorMsg]' into a user-friendly 'String'
showErrorMessages :: String -> String -> String -> String -> String -> [ErrorMsg] -> String
showErrorMessages msgOr msgUnknown msgExpecting msgUnExpected msgEndOfInput msgs
    | null msgs = msgUnknown
    | otherwise = intercalate ("; ") $ clean $  [showSysUnExpect, showUnExpect, showExpect, showMessages]
    where
      isSysUnExpect (SysUnExpect {}) = True
      isSysUnExpect _                = False

      isUnExpect (UnExpect {})       = True
      isUnExpect _                   = False

      isExpect (Expect {})           = True
      isExpect _                     = False

      (sysUnExpect,msgs1) = span isSysUnExpect (sort msgs)
      (unExpect   ,msgs2) = span isUnExpect msgs1
      (expect     ,msgs3) = span isExpect msgs2

      showExpect      = showMany msgExpecting expect
      showUnExpect    = showMany msgUnExpected unExpect
      showSysUnExpect 
          | null sysUnExpect = ""
          | otherwise        = msgUnExpected ++ " " ++ (messageString $ head sysUnExpect)
      showMessages      = showMany "" msgs3

      showMany pre msgs = case clean (map messageString msgs) of
                            [] -> ""
                            ms | null pre  -> commasOr ms
                               | otherwise -> pre ++ " " ++ commasOr ms

      commasOr []         = ""
      commasOr [m]        = m
      commasOr ms         = commaSep (init ms) ++ " " ++ msgOr ++ " " ++ last ms

      commaSep            = seperate ", " . clean

      seperate   _ []     = ""
      seperate   _ [m]    = m
      seperate sep (m:ms) = m ++ sep ++ seperate sep ms

      clean               = nub . filter (not . null)

instance (Show pos) => Show (ParserError pos) where
    show e = showParserError show e

-- | turn a parse error into a user-friendly error message
showParserError :: (pos -> String) -- ^ function to turn the error position into a 'String'
               -> ParserError pos  -- ^ the 'ParserError'
               -> String
showParserError showPos (ParserError mPos msgs) =
        let posStr = case mPos of
                       Nothing -> "unknown position"
                       (Just pos) -> showPos pos
        in "parse error at " ++ posStr ++ ": " ++ (showErrorMessages "or" "unknown parse error" "expecting" "unexpected" "end of input" msgs)
