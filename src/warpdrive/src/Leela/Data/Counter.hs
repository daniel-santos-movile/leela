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

module Leela.Data.Counter
       ( Counter ()
       , peek
       , next
       , newCounter
       ) where

import Data.IORef

data Counter a = Counter (IORef a)

newCounter :: (Integral a) => IO (Counter a)
newCounter = fmap Counter (newIORef 0)

next :: (Integral a) => Counter a -> IO a
next (Counter ioref) = atomicModifyIORef' ioref (\a -> let b = a + 1 in (b, b))

peek :: Counter a -> IO a
peek (Counter ioref) = readIORef ioref
