{-# LANGUAGE OverloadedStrings #-}

-- Copyright 2014 (c) Diego Souza <dsouza@c0d3.xxx>
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

module Leela.HZMQ.Router
       ( Worker (..)
       , RouterFH ()
       , stopRouter
       , startRouter
       ) where

import           Data.Maybe
import           System.ZMQ4
import           Leela.Logger
import           Control.Monad
import           Control.DeepSeq
import qualified Data.ByteString as B
import           Leela.Data.Time
import           Control.Exception
import           Leela.HZMQ.IOLoop
import           Control.Concurrent
import           Leela.Data.Endpoint
import           Leela.HZMQ.ZHelpers
import qualified Data.ByteString.Lazy as L

data Request = Request [B.ByteString] [B.ByteString]

data Worker = Worker { onJob :: [B.ByteString] -> IO [L.ByteString]
                     , onErr :: SomeException -> IO [L.ByteString]
                     }

newtype RouterFH = RouterFH (MVar Bool)

readMsg :: Request -> [B.ByteString]
readMsg (Request _ val) = val

readPeer :: Request -> [B.ByteString]
readPeer (Request val _) = val

reply :: Poller Router -> Request -> [L.ByteString] -> IO ()
reply poller job msg = do
  let ans = (map L.fromStrict $ readPeer job) ++ (L.empty : msg)
  ans `deepseq` (void $ sendMsg poller ans)

worker :: Poller Router -> Request -> Worker -> IO ()
worker poller job action = do
  mmsg <- try (onJob action (readMsg job))
  case mmsg of
    Left e    ->
      onErr action e >>= reply poller job
    Right msg ->
      reply poller job msg

forkWorker :: Poller Router -> Request -> Worker -> IO ()
forkWorker poller job action = void (forkIO $ void $ worker poller job action)

recvRequest :: [B.ByteString] -> (Maybe Request)
recvRequest []   = Nothing
recvRequest mmsg = do
  let (peer, msg0) = break B.null mmsg
  case msg0 of
    ("" : msg) -> Just (Request peer msg)
    _          -> Nothing

waitCTRL :: MVar Bool -> IO ()
waitCTRL ctrl = do
  sleep 1 >> readMVar ctrl >>= flip when (waitCTRL ctrl)

stopRouter :: RouterFH -> IO ()
stopRouter (RouterFH ctrl) = do
  _ <- swapMVar ctrl False
  putMVar ctrl False

startRouter :: Logger -> Endpoint -> Context -> Worker -> IO RouterFH
startRouter syslog endpoint ctx action = do
  notice syslog (printf "starting zmq.router: %s" (dumpEndpointStr endpoint))
  ctrl <- newMVar True
  void $ flip forkFinally (\_ -> void $ takeMVar ctrl) $ do
    withSocket ctx Router $ \fh -> do
      configAndBind fh (dumpEndpointStr endpoint)
      go ctrl fh
  return (RouterFH ctrl)
    where
      recvLoop poller = do
        msg <- recvMsg poller
        when (isJust msg) $ do
          let mreq = recvRequest (fromJust msg)
          when (isJust mreq) (forkWorker poller (fromJust mreq) action)
          recvLoop poller

      go ctrl fh = do
        warning syslog "router has started"
        poller <- newIOLoop_ fh
        wait   <- newQSem 0
        _      <- forkFinally (recvLoop poller) (const $ signalQSem wait)
        _      <- forkFinally (pollLoop poller) (const $ signalQSem wait)
        waitCTRL ctrl
        cancel poller
        replicateM_ 2 (waitQSem wait)
        warning syslog "router has quit"
