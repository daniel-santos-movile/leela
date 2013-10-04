{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns      #-}
{-# LANGUAGE TupleSections     #-}
{-# LANGUAGE Rank2Types        #-}

-- This file is part of Leela.
--
-- Leela is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- Leela is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with Leela.  If not, see <http://www.gnu.org/licenses/>.

module Leela.Network.Core where

import qualified Data.Map as M
import           Data.Maybe
import           Leela.Logger
import           Leela.Helpers
import           Control.Monad
import           Leela.Data.LQL
import qualified Data.ByteString as B
import           Leela.Data.Graph (Matcher (..) , Result)
import qualified Leela.Data.Graph as G
import           Control.Exception
import           Control.Concurrent
import           Leela.Data.Journal
import           Leela.Data.QDevice
import           Leela.Data.Excepts
import           Leela.Data.LQL.Comp
import           Leela.Data.Namespace
import           Leela.Storage.Backend
import           Control.Concurrent.STM
import           Leela.Network.Protocol

data CoreServer = CoreServer { fdseq  :: TVar FH
                             , fdlist :: TVar (M.Map (B.ByteString, FH) (Int, Device Reply))
                             }

data Stream a = Chunk a
              | EOF

ttl :: Int
ttl = 300

whenChunk :: (Stream a -> IO ()) -> Stream a -> IO ()
whenChunk _ EOF   = return ()
whenChunk f chunk = f chunk

new :: IO CoreServer
new = do
  state <- makeState
  _     <- forkIO (forever (sleep 1 >> rungc (fdlist state)))
  return state
    where
      makeState = atomically $ do
        liftM2 CoreServer (newTVar 0) (newTVar M.empty)

rungc :: (Ord k, Show k) => TVar (M.Map k (Int, Device a)) -> IO ()
rungc tvar = do
  atomically kill >>= mapM_ burry
    where partition acc []       = acc
          partition (a, b) ((k, (tick, dev)):xs)
              | tick == 0 = partition ((k, dev) : a, b) xs
              | otherwise = partition (a, (k, (tick - 1, dev)) : b) xs

          kill = do
            (dead, alive) <- fmap (partition ([], []) . M.toList) (readTVar tvar)
            writeTVar tvar (M.fromList alive)
            return dead

          burry (k, dev) = do
            lwarn Network $ printf "closing/purging unused channel: %s" (show k)
            atomically $ close dev

nextfd :: CoreServer -> STM FH
nextfd srv = do
  curr <- readTVar $ fdseq srv
  writeTVar (fdseq srv) (curr + 1)
  return curr

makeFD :: CoreServer -> User -> IO (FH, Device Reply)
makeFD srv (User u) = atomically $ do
  ctrl <- control
  fd   <- nextfd srv
  dev  <- open ctrl pageSize
  modifyTVar (fdlist srv) (M.insert (u, fd) (ttl, dev))
  return (fd, dev)

selectFD :: CoreServer -> (User, FH) -> IO (Maybe (Device Reply))
selectFD srv ((User u), fh) = atomically $ do
  let resetTTL _ (_, dev) = Just (ttl, dev)
  (mdev, newv) <- fmap (M.updateLookupWithKey resetTTL (u, fh)) (readTVar (fdlist srv))
  writeTVar (fdlist srv) newv
  return (fmap snd mdev)

closeFD :: CoreServer -> (User, FH) -> IO ()
closeFD srv ((User u), fh) = do
  ldebug Network (printf "closing fd %s" (show k))
  atomically $ do
    db   <- readTVar (fdlist srv)
    case (M.lookup k db) of
      Nothing       -> return ()
      Just (_, dev) -> do writeTVar (fdlist srv) (M.delete k db)
                          close dev
    where k = (u, fh)

maybeCons :: Maybe a -> [a] -> [a]
maybeCons Nothing  = id
maybeCons (Just a) = (a:)

store :: (GraphBackend m) => m -> Journal -> IO ()
store m (PutNode n k g)  = putName n k g m
store m (PutLabel lbls)  = mapM_ (\(a, l) -> putLabel a [l] m) lbls
store m (PutLink lnks)   = mapM_ (\(a, b) -> putLink a [b] m) lnks

rechunk :: Int -> [a] -> [[a]]
rechunk n = go 0 []
    where go _ [] []      = []
          go _ acc []     = [acc]
          go k acc (x:xs)
            | k == n      = acc : go 0 [x] xs
            | otherwise   = go (k+1) (x:acc) xs

fetch :: (GraphBackend m, HasControl ctrl) => ctrl -> m -> Matcher r -> (Stream r -> IO ()) -> IO ()
fetch ctrl m selector callback0 =
  case selector of
    ByLabel k l f -> do dev <- openIO ctrl 2
                        getLabel dev k (glob l) m
                        load1 k f dev
    ByNode k f    -> do dev <- openIO ctrl 2
                        getLabel dev k (All Nothing) m
                        load1 k f dev
    where
      load1 k f dev = do
        mlabels <- devreadIO dev
        case mlabels of
          Left e       -> throwIO e
          Right []     -> callback0 EOF
          Right labels -> do
            let keys = M.fromList $ map (\l -> (G.labelRef k l, l)) labels
            subdev <- openIO ctrl 4
            getLink subdev (M.keys keys) m
            load2 subdev $ \guidNodes ->
              let labelNodes = map (\(lk, g) -> (g, fromJust $ M.lookup lk keys)) guidNodes
              in when (not $ null labelNodes) (callback0 $ Chunk (f labelNodes))
            load1 k f dev

      load2 subdev callback = do
        mnodes <- devreadIO subdev
        case mnodes of
          Left e      -> throwIO e
          Right []    -> callback []
          Right nodes -> callback nodes >> load2 subdev callback

eval :: (GraphBackend m, HasControl ctrl) => ctrl -> m -> Result r -> (Stream r -> IO ()) -> IO ()
eval _ _ (G.Fail 404 _) _         = throwIO NotFoundExcept
eval _ _ (G.Fail code msg) _      = do lwarn Network (printf "eval has failed: %d/%s" code msg)
                                       throwIO SystemExcept
eval ctrl m (G.Load f g) callback =
  catch (fetch ctrl m f $ \chunk ->
           case chunk of
             EOF     -> callback EOF
             Chunk r -> eval ctrl m r (whenChunk callback))
        (\e -> case e of
                 NotFoundExcept -> eval ctrl m g callback
                 _              -> throwIO e)
eval _ m (G.Done r j) callback    = do
  mapM_ (store m) j
  callback (Chunk r)
  callback EOF

deref :: (GraphBackend m) => m -> GUID -> IO (Namespace, Key)
deref m g = getName g m

evalLQL :: (GraphBackend m) => m -> Device Reply -> [LQL] -> IO ()
evalLQL _ dev []     = devwriteIO dev (Last Nothing)
evalLQL m dev (x:xs) = do
  case x of
    Create _ stmt  ->
      eval dev m stmt $ \chunk ->
        case chunk of
          EOF -> evalLQL m dev xs
          _   -> return ()
    Match _ cursor -> navigate cursor (evalLQL m dev xs)
    Deref u g      -> do
      (n, k) <- getName g m
      if (root u `isDerivedOf` n)
        then devwriteIO dev (Item $ Name n k) >> evalLQL m dev xs
        else devwriteIO dev (Fail 403 Nothing)
    where
      navigate G.Tail cont                  = cont
      navigate (G.Need r) cont              = eval dev m r $ \chunk -> do
        case chunk of
          EOF          -> cont
          Chunk cursor -> navigate cursor (return ())
      navigate (G.Item path links next) cont = do
        devwriteIO dev (Item $ makeList $ map (Path . (:path)) links)
        navigate next cont
      navigate (G.Head g) cont              = do
        eval dev m (G.loadNode1 g Nothing G.done) $ \chunk -> do
          case chunk of
            EOF          -> cont
            Chunk links  -> devwriteIO dev (Item $ makeList $ map (Path . (:[])) links)

evalFinalizer :: FH -> Device Reply -> Either SomeException () -> IO ()
evalFinalizer chan dev (Left e)  = do
  devwriteIO dev (encodeE e) `catch` ignore
  linfo Network $ printf "[fd: %s] session terminated with failure: %s" (show chan) (show e)
evalFinalizer chan _ (Right _)   = do
  linfo Network $ printf "[fd: %s] session terminated successfully" (show chan)

process :: (GraphBackend m) => m -> CoreServer -> Query -> IO Reply
process m srv (Begin sig msg) = do
  ldebug Network (printf "BEGIN %s" (show msg))
  case (chkloads (parseLQL (namespaceFrom sig)) msg) of
    Left _      -> return $ Fail 400 (Just "syntax error")
    Right stmts -> do
      (fh, dev) <- makeFD srv (sigUser sig)
      _         <- forkFinally (evalLQL m dev stmts) (evalFinalizer fh dev)
      return $ Done fh
process _ srv (Fetch sig fh limit) = do
  let channel = (sigUser sig, fh)
  ldebug Network (printf "FETCH %d %d" fh limit)
  mdev <- selectFD srv channel
  case mdev of
    Nothing  -> return $ Fail 404 $ Just "no such channel"
    Just dev -> do
      answer <- fmap (foldr1 reduce) (blkreadIO limit dev)
      when (isEOF answer) (closeFD srv channel)
      return answer
process _ srv (Close sig fh) = do
  ldebug Network (printf "CLOSE %d" fh)
  closeFD srv (sigUser sig, fh)
  return $ Last Nothing
