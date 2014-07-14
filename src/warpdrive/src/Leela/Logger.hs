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

module Leela.Logger
       ( Logger ()
       , Priority (..)
       , fmt
       , info
       , level
       , debug
       , fatal
       , printf
       , notice
       , warning
       , newLogger
       , nullLogger
       , closeLogger
       , flushLogger
       ) where

import Data.Time
import Data.Monoid
import Text.Printf
import System.Locale
import Data.ByteString (ByteString)
import System.Log.FastLogger
import Data.ByteString.Lazy.UTF8 (toString)
import Data.ByteString.Lazy.Builder

data Logger = Logger Priority LoggerSet
            | NullLogger

data Priority = DEBUG
              | INFO
              | NOTICE
              | WARNING
              | FATAL
              deriving (Eq, Ord, Show, Read)

class ToString a where
    fmt :: a -> String

newLogger :: Priority -> IO Logger
newLogger p = fmap (Logger p) (newStdoutLoggerSet defaultBufSize)

nullLogger :: Logger
nullLogger = NullLogger

level :: Logger -> Priority
level NullLogger   = DEBUG
level (Logger p _) = p

format :: Priority -> String -> IO LogStr
format prio s = do
  time <- fmap (formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S %Z") getCurrentTime
  return (toLogStr time <> toLogStr " - " <> toLogStr (show prio) <> toLogStr " " <> toLogStr s <> toLogStr "\n")

debug :: Logger -> String -> IO ()
debug NullLogger _ = return ()
debug (Logger p logger) s
  | DEBUG >= p     = pushLogStr logger =<< format DEBUG s
  | otherwise      = return ()

info :: Logger -> String -> IO ()
info NullLogger _ = return ()
info (Logger p logger) s
  | INFO >= p     = pushLogStr logger =<< format INFO s
  | otherwise     = return ()

notice :: Logger -> String -> IO ()
notice NullLogger _ = return ()
notice (Logger p logger) s
  | NOTICE >= p     = pushLogStr logger =<< format NOTICE s
  | otherwise       = return ()

warning :: Logger -> String -> IO ()
warning NullLogger _ = return ()
warning (Logger p logger) s
  | WARNING >= p = pushLogStr logger =<< format WARNING s
  | otherwise    = return ()

fatal :: Logger -> String -> IO ()
fatal NullLogger _ = return ()
fatal (Logger p logger) s
  | FATAL >= p     = pushLogStr logger =<< format FATAL s
  | otherwise      = return ()

closeLogger :: Logger -> IO ()
closeLogger NullLogger        = return ()
closeLogger (Logger _ logger) = rmLoggerSet logger

flushLogger :: Logger -> IO ()
flushLogger NullLogger       = return ()
flushLogger (Logger _ logger) = flushLogStr logger

instance ToString ByteString where

  fmt = toString . toLazyByteString . byteString

instance ToString Double where

  fmt = show

instance ToString Int where

  fmt = show

instance ToString Char where

  fmt '\n' = "[\\n]"
  fmt c    = [c]

instance (ToString a) => ToString (Maybe a) where

  fmt Nothing  = "<<nothing>>"
  fmt (Just s) = fmt s
