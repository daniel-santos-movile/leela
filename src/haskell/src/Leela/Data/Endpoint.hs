{-# LANGUAGE OverloadedStrings #-}

-- -*- mode: haskell; -*-
-- All Rights Reserved.
--
--    Licensed under the Apache License, Version 2.0 (the "License");
--    you may not use this file except in compliance with the License.
--    You may obtain a copy of the License at
--
--        http://www.apache.org/licenses/LICENSE-2.0
--
--    Unless required by applicable law or agreed to in writing, software
--    distributed under the License is distributed on an "AS IS" BASIS,
--    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--    See the License for the specific language governing permissions and
--    limitations under the License.

module Leela.Data.Endpoint
       ( Endpoint (..)
       , endpoint
       , strEndpoint
       , parseEndpoint
       , isTCP
       , isUDP
       , isUNIX
       ) where

import           Data.Word
import           Data.Attoparsec
import           Control.Applicative
import           Data.Attoparsec.Char8 ((.*>))
import qualified Data.ByteString as B
import           Data.ByteString.Char8 (readInt, pack)

data Endpoint = TCP { eHost :: B.ByteString
                    , ePort :: Maybe Word16
                    , eUser :: Maybe B.ByteString
                    , ePass :: Maybe B.ByteString
                    , ePath :: B.ByteString
                    }
              | UDP { eHost :: B.ByteString
                    , ePort :: Maybe Word16
                    , eUser :: Maybe B.ByteString
                    , ePass :: Maybe B.ByteString
                    , ePath :: B.ByteString
                    }
              | UNIX { ePath :: B.ByteString
                     }
              deriving (Show)

isTCP :: Endpoint -> Bool
isTCP (TCP _ _ _ _ _) = True
isTCP _               = False

isUDP :: Endpoint -> Bool
isUDP (UDP _ _ _ _ _) = True
isUDP _               = False

isUNIX :: Endpoint -> Bool
isUNIX (UNIX _) = True
isUNIX _        = False

qstring :: (Word8 -> Bool) -> Parser (Maybe Word8, B.ByteString)
qstring p = cont []
    where
      cont acc = do
        eof <- atEnd
        if eof
          then return (Nothing, B.pack $ reverse acc)
          else go acc

      go acc = do
        c <- anyWord8
        case c of
          0x5c          -> anyWord8 >>= \c1 -> cont (c1:acc)
          _
            | p c       -> return (Just c, B.pack $ reverse acc)
            | otherwise -> cont (c:acc)

parseSepByColon :: (Word8 -> Bool) -> Parser (Maybe Word8, B.ByteString, Maybe B.ByteString)
parseSepByColon p = do
  (wl, l) <- qstring (\w -> w == 0x3a || p w)
  if (wl == Just 0x3a)
    then do
      (wr, r) <- qstring p
      return (wr, l, Just r)
    else return (wl, l, Nothing)

readWord :: B.ByteString -> Maybe Word16
readWord = fmap (fromIntegral . fst) . readInt

parseURL :: (B.ByteString -> Maybe Word16 -> Maybe B.ByteString -> Maybe B.ByteString -> B.ByteString -> a) -> Parser a
parseURL f = do
  (w, userOrHost, passOrPort) <- parseSepByColon (`elem` [0x40, 0x2f])
  case w of
    Just 0x40 -> do
      (_, host, port) <- parseSepByColon (== 0x2f)
      path            <- takeByteString
      return (f host (port >>= readWord) (Just userOrHost) passOrPort path)
    Just 0x2f -> do
      path <- takeByteString
      return (f userOrHost (passOrPort >>= readWord) Nothing Nothing path)
    Nothing   -> return (f userOrHost (passOrPort >>= readWord) Nothing Nothing B.empty)
    _         -> fail "unknonw endpoint"

parseEndpoint :: Parser Endpoint
parseEndpoint = do
  "tcp://" .*> parseURL TCP
  <|> "udp://" .*> parseURL UDP
  <|> "unix://" .*> fmap UNIX takeByteString

endpoint :: B.ByteString -> Maybe Endpoint
endpoint s =
  case (parseOnly parseEndpoint s) of
    Left _  -> Nothing
    Right e -> Just e

strEndpoint :: String -> Maybe Endpoint
strEndpoint = endpoint . pack