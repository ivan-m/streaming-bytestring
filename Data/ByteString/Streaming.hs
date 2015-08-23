{-# LANGUAGE CPP, BangPatterns #-}
{-#LANGUAGE RankNTypes, GADTs #-}
-- This library emulates Data.ByteString.Lazy but includes a monadic element
-- and thus at certain points uses a `Stream`/`FreeT` type in place of lists.

-- |
-- Module      : Data.ByteString.Streaming
-- Copyright   : (c) Don Stewart 2006
--               (c) Duncan Coutts 2006-2011
--               (c) Michael Thompson 2015
-- License     : BSD-style
--
-- Maintainer  : what_is_it_to_do_anything@yahoo.com
-- Stability   : experimental
-- Portability : portable
--
-- A time and space-efficient implementation of effectful byte streams
-- using a stream of packed 'Word8' arrays, suitable for high performance
-- use, both in terms of large data quantities, or high speed
-- requirements. Streaming ByteStrings are encoded as streams of strict chunks
-- of bytes.
--
-- A key feature of streaming ByteStrings is the means to manipulate large or
-- unbounded streams of data without requiring the entire sequence to be
-- resident in memory. To take advantage of this you have to write your
-- functions in a streaming style, e.g. classic pipeline composition. The
-- default I\/O chunk size is 32k, which should be good in most circumstances.
--
-- Some operations, such as 'concat', 'append', 'reverse' and 'cons', have
-- better complexity than their "Data.ByteString" equivalents, due to
-- optimisations resulting from the list spine structure. For other
-- operations streaming, like lazy, ByteStrings are usually within a few percent of
-- strict ones.
--
-- This module is intended to be imported @qualified@, to avoid name
-- clashes with "Prelude" functions.  eg.
--
-- > import qualified Data.ByteString.Streaming as B
--
-- Original GHC implementation by Bryan O\'Sullivan.
-- Rewritten to use 'Data.Array.Unboxed.UArray' by Simon Marlow.
-- Rewritten to support slices and use 'Foreign.ForeignPtr.ForeignPtr'
-- by David Roundy.
-- Rewritten again and extended by Don Stewart and Duncan Coutts.
-- Lazy variant by Duncan Coutts and Don Stewart.
-- Streaming variant by Michael Thompson, following the ideas of Gabriel Gonzales'
-- pipes-bytestring
--
module Data.ByteString.Streaming (
    -- * The @ByteString@ type
    ByteString

    -- * Introducing and eliminating 'ByteString's 
    , empty            -- empty :: ByteString m () 
    , pack             -- pack :: Monad m => [Word8] -> ByteString m () 
    , singleton        -- singleton :: Monad m => Word8 -> ByteString m () 
  
    , fromChunks       -- fromChunks :: Monad m => Stream (Of ByteString) m r -> ByteString m r 
    , fromLazy         -- fromLazy :: Monad m => ByteString -> ByteString m () 
    , fromStrict       -- fromStrict :: ByteString -> ByteString m () 
    , toChunks         -- toChunks :: Monad m => ByteString m r -> Stream (Of ByteString) m r 
    , toLazy           -- toLazy :: Monad m => ByteString m () -> m ByteString
    , toLazy'           -- toLazy :: Monad m => ByteString m () -> m ByteString  
    , toStrict         -- toStrict :: Monad m => ByteString m () -> m ByteString 

    -- * Transforming ByteStrings
    , map              -- map :: Monad m => (Word8 -> Word8) -> ByteString m r -> ByteString m r 
    , intercalate      -- intercalate :: Monad m => ByteString m () -> Stream (ByteString m) m r -> ByteString m r 
    , intersperse      -- intersperse :: Monad m => Word8 -> ByteString m r -> ByteString m r 
    
    -- * Basic interface
    , cons             -- cons :: Monad m => Word8 -> ByteString m r -> ByteString m r 
    , cons'            -- cons' :: Word8 -> ByteString m r -> ByteString m r 
    , append           -- append :: Monad m => ByteString m r -> ByteString m s -> ByteString m s   
    , filter           -- filter :: (Word8 -> Bool) -> ByteString m r -> ByteString m r 
    , head             -- head :: Monad m => ByteString m r -> m Word8 
    , null             -- null :: Monad m => ByteString m r -> m Bool 
    , uncons           -- uncons :: Monad m => ByteString m r -> m (Either r (Word8, ByteString m r)) 
    , nextChunk        -- nextChunk :: Monad m => ByteString m r -> m (Either r (ByteString, ByteString m r)) 
    , chunk
    , yield
    
    -- * Substrings

    -- ** Breaking strings
    , break            -- break :: Monad m => (Word8 -> Bool) -> ByteString m r -> ByteString m (ByteString m r) 
    , drop             -- drop :: Monad m => GHC.Int.Int64 -> ByteString m r -> ByteString m r 
    , group            -- group :: Monad m => ByteString m r -> Stream (ByteString m) m r 
    , span             -- span :: Monad m => (Word8 -> Bool) -> ByteString m r -> ByteString m (ByteString m r) 
    , splitAt          -- splitAt :: Monad m => GHC.Int.Int64 -> ByteString m r -> ByteString m (ByteString m r) 
    , splitWith        -- splitWith :: Monad m => (Word8 -> Bool) -> ByteString m r -> Stream (ByteString m) m r 
    , take             -- take :: Monad m => GHC.Int.Int64 -> ByteString m r -> ByteString m () 
    , takeWhile        -- takeWhile :: (Word8 -> Bool) -> ByteString m r -> ByteString m () 

    -- ** Breaking into many substrings
    , split            -- split :: Monad m => Word8 -> ByteString m r -> Stream (ByteString m) m r 
    
    -- ** Special folds

    , concat          -- concat :: Monad m => Stream (ByteString m) m r -> ByteString m r 

    -- * Building ByteStrings
    
    -- ** Infinite ByteStrings
    , repeat           -- repeat :: Word8 -> ByteString m () 
    , iterate          -- iterate :: (Word8 -> Word8) -> Word8 -> ByteString m () 
    , cycle            -- cycle :: Monad m => ByteString m r -> ByteString m s 
    
    -- ** Unfolding ByteStrings
    , unfoldr          -- unfoldr :: (a -> Maybe (Word8, a)) -> a -> ByteString m () 
    , unfold           -- unfold  :: (a -> Either r (Word8, a)) -> a -> ByteString m r

    -- *  Folds, including support for `Control.Foldl`
    , foldr            -- foldr :: Monad m => (Word8 -> a -> a) -> a -> ByteString m () -> m a 
    , fold             -- fold :: Monad m => (x -> Word8 -> x) -> x -> (x -> b) -> ByteString m () -> m b 
    , fold'            -- fold' :: Monad m => (x -> Word8 -> x) -> x -> (x -> b) -> ByteString m r -> m (b, r) 
    , length
    , length'
    , last
    , last'
    , head
    , head'
    , null
    , null'
    -- * I\/O with 'ByteString's

    -- ** Standard input and output
    , getContents      -- getContents :: ByteString IO () 
    , stdin            -- stdin :: ByteString IO () 
    , stdout           -- stdout :: ByteString IO r -> IO r 
    , interact         -- interact :: (ByteString IO () -> ByteString IO r) -> IO r 

    -- ** Files
    , readFile         -- readFile :: FilePath -> ByteString IO () 
    , writeFile        -- writeFile :: FilePath -> ByteString IO r -> IO r 
    , appendFile       -- appendFile :: FilePath -> ByteString IO r -> IO r 

    -- ** I\/O with Handles
    , fromHandle       -- fromHandle :: Handle -> ByteString IO () 
    , toHandle         -- toHandle :: Handle -> ByteString IO r -> IO r 
    , hGet             -- hGet :: Handle -> Int -> ByteString IO () 
    , hGetContents     -- hGetContents :: Handle -> ByteString IO () 
    , hGetContentsN    -- hGetContentsN :: Int -> Handle -> ByteString IO () 
    , hGetN            -- hGetN :: Int -> Handle -> Int -> ByteString IO () 
    , hGetNonBlocking  -- hGetNonBlocking :: Handle -> Int -> ByteString IO () 
    , hGetNonBlockingN -- hGetNonBlockingN :: Int -> Handle -> Int -> ByteString IO () 
    , hPut             -- hPut :: Handle -> ByteString IO r -> IO r 
    , hPutNonBlocking  -- hPutNonBlocking :: Handle -> ByteString IO r -> ByteString IO r 
    -- * Etc.
--    , zipWithStream    -- zipWithStream :: Monad m => (forall x. a -> ByteString m x -> ByteString m x) -> [a] -> Stream (ByteString m) m r -> Stream (ByteString m) m r 
    , distribute       -- distribute :: ByteString (t m) a -> t (ByteString m) a 
  ) where

import Prelude hiding
    (reverse,head,tail,last,init,null,length,map,lines,foldl,foldr,unlines
    ,concat,any,take,drop,splitAt,takeWhile,dropWhile,span,break,elem,filter,maximum
    ,minimum,all,concatMap,foldl1,foldr1,scanl, scanl1, scanr, scanr1
    ,repeat, cycle, interact, iterate,readFile,writeFile,appendFile,replicate
    ,getContents,getLine,putStr,putStrLn ,zip,zipWith,unzip,notElem)
import qualified Prelude
import qualified Data.List              as L  -- L for list/lazy
import qualified Data.ByteString.Lazy.Internal as BI  -- just for fromChunks etc

import qualified Data.ByteString        as P  (ByteString) -- type name only
import qualified Data.ByteString        as S  -- S for strict (hmm...)
import qualified Data.ByteString.Lazy   as BL
import qualified Data.ByteString.Internal as S
import qualified Data.ByteString.Unsafe as S

import Data.ByteString.Streaming.Internal 
import Streaming hiding (concats, split, unfold, distribute)
import Streaming.Internal (Stream (..))
import qualified Streaming.Prelude as SP

import Data.Monoid

import Control.Monad            (mplus,liftM, join, ap, liftM2)
import Control.Monad.Trans
import Control.Monad.Morph

import Data.Word                (Word8)
import Data.Int                 (Int64)
import System.IO                (Handle,openBinaryFile,IOMode(..)
                                ,hClose)
import qualified System.IO as IO (stdin, stdout)
import System.IO.Error          (mkIOError, illegalOperationErrorType)
import System.IO.Unsafe
import Control.Exception        (bracket)
import Foreign.ForeignPtr       (withForeignPtr)
import Foreign.Storable
import Foreign.Ptr

-- | /O(n)/ Concatenate a stream of byte streams.
concat :: Monad m => Stream (ByteString m) m r -> ByteString m r
concat x = destroy x join Go Empty 

-- |  Given a byte stream on a transformed monad, make it possible to \'run\' 
--    transformer.
distribute
  :: (Monad m, MonadTrans t, MFunctor t, Monad (t m), Monad (t (ByteString m)))
  => ByteString (t m) a -> t (ByteString m) a
distribute ls = dematerialize ls
             return
             (\bs x -> join $ lift $ Chunk bs (Empty x) )
             (join . hoist (Go . fmap Empty))
{-# INLINE distribute #-}
-- unpackBytes (Empty r)   = Return r
-- unpackBytes (Chunk c cs) = unpackAppendBytesLazy c (unpackBytes cs)
-- unpackBytes (Go m)       = Delay (liftM unpackBytes m)


-- -----------------------------------------------------------------------------
-- Introducing and eliminating 'ByteString's

-- | /O(1)/ The empty 'ByteString' -- i.e. return ()
empty :: ByteString m ()
empty = Empty ()
{-# INLINE empty #-}

-- | /O(1)/ Convert a 'Word8' into a minimal 'ByteString'
singleton :: Monad m => Word8 -> ByteString m ()
singleton w = Chunk (S.singleton w)  (Empty ())
{-# INLINE singleton #-}

-- | /O(n)/ Convert a monadic stream separate bytes into a packed byte stream.
pack :: Monad m => Stream (Of Word8) m r -> ByteString m r
pack = packBytes'
{-#INLINE pack #-}

-- | /O(n)/ Converts a packed byte stream into a stream of individual bytes.
unpack ::  Monad m => ByteString m r -> Stream (Of Word8) m r 
unpack = unpackBytes

-- | /O(c)/ Convert a monadic stream of individual strict 'ByteString' 
-- chunks into a byte stream.
fromChunks :: Monad m => Stream (Of P.ByteString) m r -> ByteString m r
fromChunks cs = destroy cs 
  (\(bs :> rest) -> Chunk bs rest)
  Go
  return
{-#INLINE fromChunks#-}

-- | /O(c)/ Convert a byte stream into a stream of individual strict bytestrings.
toChunks :: Monad m => ByteString m r -> Stream (Of P.ByteString) m r
toChunks bs =
  dematerialize bs
      return
      (\b mx -> Step (b:> mx))
      Delay
{-#INLINE toChunks#-}

-- |/O(1)/ yield a strict 'ByteString' chunk.
fromStrict :: P.ByteString -> ByteString m ()
fromStrict bs | S.null bs = Empty ()
              | otherwise = Chunk bs  (Empty ())


-- |/O(n)/ Convert a monadic byte stream into a single strict 'ByteString'.
--
-- Note that this is an /expensive/ operation that forces the whole monadic
-- ByteString into memory and then copies all the data. If possible, try to
-- avoid converting back and forth between streaming and lazy bytestrings,
-- and still more between streaming and strict bytestrings.

toStrict :: Monad m => ByteString m () -> m (S.ByteString)
toStrict = liftM S.concat . SP.toListM . toChunks


-- |/O(n)/ Convert a monadic byte stream into a single strict 'ByteString',
-- retaining the return value of the original pair, for use with 'mapsM'

toStrict' :: Monad m => ByteString m r -> m (Of S.ByteString r)
toStrict' bs = do 
  (bss :> r) <- SP.toListM' (toChunks bs)
  return $ (S.concat bss :> r)

-- |/O(c)/ Transmute a lazy bytestring to its representation
-- as a monadic stream of chunks.
fromLazy :: Monad m => BI.ByteString -> ByteString m ()
fromLazy = BI.foldrChunks Chunk (Empty ())

-- |/O(n)/ Convert a monadic byte stream into a single lazy 'ByteString'
-- with the same internal chunk structure.
toLazy :: Monad m => ByteString m () -> m BI.ByteString
toLazy bs = dematerialize bs
                (\() -> return (BI.Empty))
                (\b mx -> liftM (BI.Chunk b) mx)
                join
{-#INLINE toLazy #-}   
             
-- |/O(n)/ Convert a monadic byte stream into a single lazy 'ByteString'
-- with the same invisible chunk structure; retaining the original
-- return value. 
toLazy' :: Monad m => ByteString m r -> m (Of BI.ByteString r)
toLazy' bs = dematerialize bs
                (\r -> return (BI.Empty :> r))
                (\b mx -> do 
                      (bs :> x) <- mx 
                      return $ BI.Chunk b bs :> x
                      )
                join
{-#INLINE toLazy' #-}                
    


-- -- -- ---------------------------------------------------------------------
-- -- -- Basic interface
-- --
-- | /O(1)/ Test whether a ByteString is empty.
null :: Monad m => ByteString m r -> m Bool
null (Empty _)      = return True
null (Go m)         = m >>= null
null (Chunk bs rest) = if S.null bs 
  then null rest 
  else return False
{-# INLINE null #-}


-- | /O(1)/ Test whether a ByteString is empty, collecting its return value;
-- this operation must check the whole length of the string.
null' :: Monad m => ByteString m r -> m (Of Bool r)
null' (Empty r)  = return $! True :> r
null' (Go m)     = m >>= null'
null' (Chunk bs rest) = if S.null bs 
   then null' rest 
   else do 
     r <- SP.drain $ toChunks rest
     return $! False :> r
{-# INLINE null' #-}


length :: Monad m => ByteString m r -> m Int
length  = liftM (\(n:>r) -> n) . foldlChunks (\n c -> n + fromIntegral (S.length c)) 0 
{-# INLINE length #-}

-- | /O(n\/c)/ 'length' returns the length of a byte stream as an 'Int64'
length' :: Monad m => ByteString m r -> m (Of Int r)
length' cs = foldlChunks (\n c -> n + fromIntegral (S.length c)) 0 cs
{-# INLINE length' #-}

-- infixr 5 `cons` -- , `cons'` --same as list (:)
-- -- nfixl 5 `snoc`
--
-- | /O(1)/ 'cons' is analogous to '(:)' for lists.
--
cons :: Monad m => Word8 -> ByteString m r -> ByteString m r
cons c cs = Chunk (S.singleton c) cs
{-# INLINE cons #-}

-- | /O(1)/ Unlike 'cons', 'cons\'' is
-- strict in the ByteString that we are consing onto. More precisely, it forces
-- the head and the first chunk. It does this because, for space efficiency, it
-- may coalesce the new byte onto the first \'chunk\' rather than starting a
-- new \'chunk\'.
--
-- So that means you can't use a lazy recursive contruction like this:
--
-- > let xs = cons\' c xs in xs
--
-- You can however use 'cons', as well as 'repeat' and 'cycle', to build
-- infinite byte streams.
--
cons' :: Word8 -> ByteString m r -> ByteString m r
cons' w (Chunk c cs) | S.length c < 16 = Chunk (S.cons w c) cs
cons' w cs                             = Chunk (S.singleton w) cs
{-# INLINE cons' #-}
-- --
-- | /O(n\/c)/ Append a byte to the end of a 'ByteString'
snoc :: Monad m => ByteString m r -> Word8 -> ByteString m r
snoc cs w = do 
  r <- cs
  singleton w
  return r
{-# INLINE snoc #-}

-- | /O(1)/ Extract the first element of a ByteString, which must be non-empty.
head :: Monad m => ByteString m r -> m Word8
head (Empty _)   = error "head"
head (Chunk c _) = return $ S.unsafeHead c
head (Go m)      = m >>= head
{-# INLINE head #-}

-- | /O(c)/ Extract the first element of a ByteString, which must be non-empty.
head' :: Monad m => ByteString m r -> m (Of (Maybe Word8) r)
head' (Empty r)  = return (Nothing :> r)
head' (Chunk c rest) = case S.uncons c of 
  Nothing -> head' rest
  Just (w,_) -> do
    r <- SP.drain $ toChunks rest
    return $! (Just w) :> r
head' (Go m)      = m >>= head'
{-# INLINE head' #-}

-- | /O(1)/ Extract the head and tail of a ByteString, or Nothing
-- if it is empty
uncons :: Monad m => ByteString m r -> m (Maybe (Word8, ByteString m r))
uncons (Empty _) = return Nothing
uncons (Chunk c cs)
    = return $ Just (S.unsafeHead c
                     , if S.length c == 1
                         then cs
                         else Chunk (S.unsafeTail c) cs )
uncons (Go m) = m >>= uncons
{-# INLINABLE uncons #-}
--
-- | /O(1)/ Extract the head and tail of a ByteString, or its return value
-- if it is empty
nextByte :: Monad m => ByteString m r -> m (Either r (Word8, ByteString m r))
nextByte (Empty r) = return (Left r)
nextByte (Chunk c cs)
    = if S.null c 
        then nextByte cs
        else return $ Right (S.unsafeHead c
                     , if S.length c == 1
                         then cs
                         else Chunk (S.unsafeTail c) cs )
nextByte (Go m) = m >>= nextByte
{-# INLINABLE nextByte #-}

unconsChunk :: Monad m => ByteString m r -> m (Maybe (S.ByteString, ByteString m r))
unconsChunk (Empty _) = return Nothing
unconsChunk (Chunk c cs) = if S.null c then unconsChunk cs else return $ Just (c,cs)
unconsChunk (Go m) = m >>= unconsChunk
{-# INLINABLE unconsChunk #-}

nextChunk :: Monad m => ByteString m r -> m (Either r (S.ByteString, ByteString m r))
nextChunk (Empty r) = return (Left r)
nextChunk (Chunk c cs) = if S.null c then nextChunk cs else return $ Right (c,cs)
nextChunk (Go m) = m >>= nextChunk
{-# INLINABLE nextChunk #-}


-- | /O(n\/c)/ Extract the last element of a ByteString, which must be finite
-- and non-empty.
last :: Monad m => ByteString m r -> m Word8
last (Empty r)      = error "Data.ByteString.Streaming.last: empty string"
last (Go m)         = m >>= last
last (Chunk c0 cs0) = go c0 cs0
 where 
   go c (Empty _)    = if S.null c 
       then error "Data.ByteString.Streaming.last: empty string"
       else return $ S.unsafeLast c
   go _ (Chunk c cs) = go c cs
   go x (Go m)       = m >>= go x
{-# INLINABLE last #-}
 
last' :: Monad m => ByteString m r -> m (Of (Maybe Word8) r)
last' (Empty r)      = return (Nothing :> r)
last' (Go m)         = m >>= last'
last' (Chunk c0 cs0) = go c0 cs0
  where 
    go c (Empty r)    = return $ (Just (S.unsafeLast c) :> r)
    go _ (Chunk c cs) = go c cs
    go x (Go m)       = m >>= go x  
{-# INLINABLE last' #-}

-- -- | /O(n\/c)/ Return all the elements of a 'ByteString' except the last one.
-- init :: ByteString -> ByteString
-- init Empty          = errorEmptyStream "init"
-- init (Chunk c0 cs0) = go c0 cs0
--   where go c Empty | S.length c == 1 = Empty
--                    | otherwise       = Chunk (S.unsafeInit c) Empty
--         go c (Chunk c' cs)           = Chunk c (go c' cs)
--
-- -- | /O(n\/c)/ Extract the 'init' and 'last' of a ByteString, returning Nothing
-- -- if it is empty.
-- --
-- -- * It is no faster than using 'init' and 'last'
-- unsnoc :: ByteString -> Maybe (ByteString, Word8)
-- unsnoc Empty        = Nothing
-- unsnoc (Chunk c cs) = Just (init (Chunk c cs), last (Chunk c cs))

-- | /O(n\/c)/ Append two
append :: Monad m => ByteString m r -> ByteString m s -> ByteString m s
append xs ys = dematerialize xs (const ys) Chunk Go
{-# INLINE append #-}
--
-- ---------------------------------------------------------------------
-- Transformations

-- | /O(n)/ 'map' @f xs@ is the ByteString obtained by applying @f@ to each
-- element of @xs@.
map :: Monad m => (Word8 -> Word8) -> ByteString m r -> ByteString m r
map f z = dematerialize z
   Empty
   (\bs x -> Chunk (S.map f bs) x)
   Go
-- map f s = go s
--     where
--         go (Empty r)    = Empty r
--         go (Chunk x xs) = Chunk y ys
--             where
--                 y  = S.map f x
--                 ys = go xs
--         go (Go mbs) = Go (liftM go mbs)
{-# INLINE map #-}
--
-- -- | /O(n)/ 'reverse' @xs@ returns the elements of @xs@ in reverse order.
-- reverse :: ByteString -> ByteString
-- reverse cs0 = rev Empty cs0
--   where rev a Empty        = a
--         rev a (Chunk c cs) = rev (Chunk (S.reverse c) a) cs
-- {-# INLINE reverse #-}
--
-- -- | The 'intersperse' function takes a 'Word8' and a 'ByteString' and
-- -- \`intersperses\' that byte between the elements of the 'ByteString'.
-- -- It is analogous to the intersperse function on Streams.
intersperse :: Monad m => Word8 -> ByteString m r -> ByteString m r
intersperse _ (Empty r)    = Empty r
intersperse w (Go m)       = Go (liftM (intersperse w) m)
intersperse w (Chunk c cs) = Chunk (S.intersperse w c)
                                   (dematerialize cs Empty (Chunk . intersperse') Go)
  where intersperse' :: P.ByteString -> P.ByteString
        intersperse' (S.PS fp o l) =
          S.unsafeCreate (2*l) $ \p' -> withForeignPtr fp $ \p -> do
            poke p' w
            S.c_intersperse (p' `plusPtr` 1) (p `plusPtr` o) (fromIntegral l) w
          
{-# INLINABLE intersperse #-}

{- | 'foldr', applied to a binary operator, a starting value
-- (typically the right-identity of the operator), and a ByteString,
-- reduces the ByteString using the binary operator, from right to left.

> foldr cons = id
-}
foldr :: Monad m => (Word8 -> a -> a) -> a -> ByteString m () -> m a
foldr k  = foldrChunks (flip (S.foldr k))
{-# INLINE foldr #-}

-- -- ---------------------------------------------------------------------
-- | 'fold', applied to a binary operator, a starting value (typically
-- the left-identity of the operator), and a ByteString, reduces the
-- ByteString using the binary operator, from left to right.
-- We use the style of the foldl libarary for left folds
fold :: Monad m => (x -> Word8 -> x) -> x -> (x -> b) -> ByteString m () -> m b
fold step begin done p0 = loop p0 begin
  where
    loop p !x = case p of
        Chunk bs bss -> loop bss $! S.foldl' step x bs
        Go    m      -> m >>= \p' -> loop p' x
        Empty _      -> return (done x)
{-# INLINABLE fold #-}


-- | 'fold\'' keeps the return value of the left-folded bytestring. Useful for
--   simultaneous folds over a segmented bytestream

fold' :: Monad m => (x -> Word8 -> x) -> x -> (x -> b) -> ByteString m r -> m (Of b r)
fold' step begin done p0 = loop p0 begin
  where
    loop p !x = case p of
        Chunk bs bss -> loop bss $! S.foldl' step x bs
        Go    m    -> m >>= \p' -> loop p' x
        Empty r      -> return (done x :> r)
{-# INLINABLE fold' #-}

--

-- --
-- -- | 'foldl1' is a variant of 'foldl' that has no starting value
-- -- argument, and thus must be applied to non-empty 'ByteStrings'.
-- foldl1 :: (Word8 -> Word8 -> Word8) -> ByteString -> Word8
-- foldl1 _ Empty        = errorEmptyStream "foldl1"
-- foldl1 f (Chunk c cs) = foldl f (S.unsafeHead c) (Chunk (S.unsafeTail c) cs)
--
-- -- | 'foldl1\'' is like 'foldl1', but strict in the accumulator.
-- foldl1' :: (Word8 -> Word8 -> Word8) -> ByteString -> Word8
-- foldl1' _ Empty        = errorEmptyStream "foldl1'"
-- foldl1' f (Chunk c cs) = foldl' f (S.unsafeHead c) (Chunk (S.unsafeTail c) cs)
--
-- -- | 'foldr1' is a variant of 'foldr' that has no starting value argument,
-- -- and thus must be applied to non-empty 'ByteString's
-- foldr1 :: (Word8 -> Word8 -> Word8) -> ByteString -> Word8
-- foldr1 _ Empty          = errorEmptyStream "foldr1"
-- foldr1 f (Chunk c0 cs0) = go c0 cs0
--   where go c Empty         = S.foldr1 f c
--         go c (Chunk c' cs) = S.foldr  f (go c' cs) c
--
-- ---------------------------------------------------------------------
-- Special folds

-- | /O(n)/ Concatenate a list of ByteStrings.
-- concat :: (Monad m) => [ByteString m ()] -> ByteString m ()
-- concat css0 = to css0
--   where
--     go css (Empty m')   = to css
--     go css (Chunk c cs) = Chunk c (go css cs)
--     go css (Go m)       = Go (liftM (go css) m)
--     to []               = Empty ()
--     to (cs:css)         = go css cs


-- -- | Map a function over a 'ByteString' and concatenate the results
-- concatMap :: (Word8 -> ByteString) -> ByteString -> ByteString
-- concatMap _ Empty        = Empty
-- concatMap f (Chunk c0 cs0) = to c0 cs0
--   where
--     go :: ByteString -> P.ByteString -> ByteString -> ByteString
--     go Empty        c' cs' = to c' cs'
--     go (Chunk c cs) c' cs' = Chunk c (go cs c' cs')
--
--     to :: P.ByteString -> ByteString -> ByteString
--     to c cs | S.null c  = case cs of
--         Empty          -> Empty
--         (Chunk c' cs') -> to c' cs'
--             | otherwise = go (f (S.unsafeHead c)) (S.unsafeTail c) cs
--
-- -- | /O(n)/ Applied to a predicate and a ByteString, 'any' determines if
-- -- any element of the 'ByteString' satisfies the predicate.
-- any :: (Word8 -> Bool) -> ByteString -> Bool
-- any f cs = foldrChunks (\c rest -> S.any f c || rest) False cs
-- {-# INLINE any #-}
-- -- todo fuse
--
-- -- | /O(n)/ Applied to a predicate and a 'ByteString', 'all' determines
-- -- if all elements of the 'ByteString' satisfy the predicate.
-- all :: (Word8 -> Bool) -> ByteString -> Bool
-- all f cs = foldrChunks (\c rest -> S.all f c && rest) True cs
-- {-# INLINE all #-}
-- -- todo fuse
--
-- -- | /O(n)/ 'maximum' returns the maximum value from a 'ByteString'
-- maximum :: ByteString -> Word8
-- maximum Empty        = errorEmptyStream "maximum"
-- maximum (Chunk c cs) = foldlChunks (\n c' -> n `max` S.maximum c')
--                                    (S.maximum c) cs
-- {-# INLINE maximum #-}
--
-- -- | /O(n)/ 'minimum' returns the minimum value from a 'ByteString'
-- minimum :: ByteString -> Word8
-- minimum Empty        = errorEmptyStream "minimum"
-- minimum (Chunk c cs) = foldlChunks (\n c' -> n `min` S.minimum c')
--                                      (S.minimum c) cs
-- {-# INLINE minimum #-}
--
-- -- | The 'mapAccumL' function behaves like a combination of 'map' and
-- -- 'foldl'; it applies a function to each element of a ByteString,
-- -- passing an accumulating parameter from left to right, and returning a
-- -- final value of this accumulator together with the new ByteString.
-- mapAccumL :: (acc -> Word8 -> (acc, Word8)) -> acc -> ByteString -> (acc, ByteString)
-- mapAccumL f s0 cs0 = go s0 cs0
--   where
--     go s Empty        = (s, Empty)
--     go s (Chunk c cs) = (s'', Chunk c' cs')
--         where (s',  c')  = S.mapAccumL f s c
--               (s'', cs') = go s' cs
--
-- -- | The 'mapAccumR' function behaves like a combination of 'map' and
-- -- 'foldr'; it applies a function to each element of a ByteString,
-- -- passing an accumulating parameter from right to left, and returning a
-- -- final value of this accumulator together with the new ByteString.
-- mapAccumR :: (acc -> Word8 -> (acc, Word8)) -> acc -> ByteString -> (acc, ByteString)
-- mapAccumR f s0 cs0 = go s0 cs0
--   where
--     go s Empty        = (s, Empty)
--     go s (Chunk c cs) = (s'', Chunk c' cs')
--         where (s'', c') = S.mapAccumR f s' c
--               (s', cs') = go s cs
--
-- -- ---------------------------------------------------------------------
-- -- Building ByteStrings
--
-- -- | 'scanl' is similar to 'foldl', but returns a list of successive
-- -- reduced values from the left. This function will fuse.
-- --
-- -- > scanl f z [x1, x2, ...] == [z, z `f` x1, (z `f` x1) `f` x2, ...]
-- --
-- -- Note that
-- --
-- -- > last (scanl f z xs) == foldl f z xs.
-- scanl :: (Word8 -> Word8 -> Word8) -> Word8 -> ByteString -> ByteString
-- scanl f z = snd . foldl k (z,singleton z)
--  where
--     k (c,acc) a = let n = f c a in (n, acc `snoc` n)
-- {-# INLINE scanl #-}
--
-- ---------------------------------------------------------------------
-- Unfolds and replicates

-- | @'iterate' f x@ returns an infinite ByteString of repeated applications
-- of @f@ to @x@:

-- > iterate f x == [x, f x, f (f x), ...]

iterate :: (Word8 -> Word8) -> Word8 -> ByteString m ()
iterate f = unfoldr (\x -> case f x of !x' -> Just (x', x'))

-- | @'repeat' x@ is an infinite ByteString, with @x@ the value of every
-- element.
--
repeat :: Word8 -> ByteString m ()
repeat w = cs where cs = Chunk (S.replicate BI.smallChunkSize w) cs

-- -- | /O(n)/ @'replicate' n x@ is a ByteString of length @n@ with @x@
-- -- the value of every element.
-- --
-- replicate :: Int64 -> Word8 -> ByteString
-- replicate n w
--     | n <= 0             = Empty
--     | n < fromIntegral smallChunkSize = Chunk (S.replicate (fromIntegral n) w) Empty
--     | r == 0             = cs -- preserve invariant
--     | otherwise          = Chunk (S.unsafeTake (fromIntegral r) c) cs
--  where
--     c      = S.replicate smallChunkSize w
--     cs     = nChunks q
--     (q, r) = quotRem n (fromIntegral smallChunkSize)
--     nChunks 0 = Empty
--     nChunks m = Chunk c (nChunks (m-1))

-- | 'cycle' ties a finite ByteString into a circular one, or equivalently,
-- the infinite repetition of the original ByteString.
--
cycle :: Monad m => ByteString m r -> ByteString m s
cycle (Empty _) = error "cycle" -- errorEmptyStream "cycle"
cycle cs    = cs >> cycle cs -- ' where cs' = foldrChunks Chunk cs' cs

-- | /O(n)/ The 'unfoldr' function is analogous to the Stream \'unfoldr\'.
-- 'unfoldr' builds a ByteString from a seed value.  The function takes
-- the element and returns 'Nothing' if it is done producing the
-- ByteString or returns 'Just' @(a,b)@, in which case, @a@ is a
-- prepending to the ByteString and @b@ is used as the next element in a
-- recursive call.

unfoldr :: (a -> Maybe (Word8, a)) -> a -> ByteString m ()
unfoldr f s0 = unfoldChunk 32 s0
  where unfoldChunk n s =
          case S.unfoldrN n f s of
            (c, Nothing)
              | S.null c  -> Empty ()
              | otherwise -> Chunk c (Empty ())
            (c, Just s')  -> Chunk c (unfoldChunk (n*2) s')

-- | 'unfold' is like 'unfoldr' but stops when the co-algebra 
-- returns 'Left'; the result is the return value of the 'ByteString m r'
-- 'unfoldr uncons = id'
unfold :: (a -> Either r (Word8, a)) -> a -> ByteString m r
unfold f s0 = unfoldChunk 32 s0
  where unfoldChunk n s =
          case unfoldrNE n f s of
            (c, Left r)
              | S.null c  -> Empty r
              | otherwise -> Chunk c (Empty r)
            (c, Right s') -> Chunk c (unfoldChunk (n*2) s')


-- ---------------------------------------------------------------------
-- Substrings

-- | /O(n\/c)/ 'take' @n@, applied to a ByteString @xs@, returns the prefix
-- of @xs@ of length @n@, or @xs@ itself if @n > 'length' xs@.
take :: Monad m => Int64 -> ByteString m r -> ByteString m ()
take i _ | i <= 0 = Empty ()
take i cs0         = take' i cs0
  where take' 0 _            = Empty ()
        take' _ (Empty _)    = Empty ()
        take' n (Chunk c cs) =
          if n < fromIntegral (S.length c)
            then Chunk (S.take (fromIntegral n) c) (Empty ())
            else Chunk c (take' (n - fromIntegral (S.length c)) cs)
        take' n (Go m) = Go (liftM (take' n) m)

-- | /O(n\/c)/ 'drop' @n xs@ returns the suffix of @xs@ after the first @n@
-- elements, or @[]@ if @n > 'length' xs@.
drop  :: Monad m => Int64 -> ByteString m r -> ByteString m r
drop i p | i <= 0 = p
drop i cs0 = drop' i cs0
  where drop' 0 cs           = cs
        drop' _ (Empty r)    = Empty r
        drop' n (Chunk c cs) =
          if n < fromIntegral (S.length c)
            then Chunk (S.drop (fromIntegral n) c) cs
            else drop' (n - fromIntegral (S.length c)) cs
        drop' n (Go m) = Go (liftM (drop' n) m)
        
-- | /O(n\/c)/ 'splitAt' @n xs@ is equivalent to @('take' n xs, 'drop' n xs)@.
splitAt :: Monad m => Int64 -> ByteString m r -> ByteString m (ByteString m r)
splitAt i cs0 | i <= 0 = Empty cs0
splitAt i cs0 = splitAt' i cs0
  where splitAt' 0 cs           = Empty cs
        splitAt' _ (Empty r  )   = Empty (Empty r)
        splitAt' n (Chunk c cs) =
          if n < fromIntegral (S.length c)
            then Chunk (S.take (fromIntegral n) c) $
                     Empty (Chunk (S.drop (fromIntegral n) c) cs)
            else Chunk c (splitAt' (n - fromIntegral (S.length c)) cs)
        splitAt' n (Go m) = Go  (liftM (splitAt' n) m)

-- | 'takeWhile', applied to a predicate @p@ and a ByteString @xs@,
-- returns the longest prefix (possibly empty) of @xs@ of elements that
-- satisfy @p@.
takeWhile :: (Word8 -> Bool) -> ByteString m r -> ByteString m ()
takeWhile f cs0 = takeWhile' cs0
  where takeWhile' (Empty _)        = Empty ()
        takeWhile' (Chunk c cs) =
          case findIndexOrEnd (not . f) c of
            0                  -> Empty ()
            n | n < S.length c -> Chunk (S.take n c) (Empty ())
              | otherwise      -> Chunk c (takeWhile' cs)

-- -- | 'dropWhile' @p xs@ returns the suffix remaining after 'takeWhile' @p xs@.
-- dropWhile :: (Word8 -> Bool) -> ByteString -> ByteString
-- dropWhile f cs0 = dropWhile' cs0
--   where dropWhile' Empty        = Empty
--         dropWhile' (Chunk c cs) =
--           case findIndexOrEnd (not . f) c of
--             n | n < S.length c -> Chunk (S.drop n c) cs
--               | otherwise      -> dropWhile' cs

-- | 'break' @p@ is equivalent to @'span' ('not' . p)@.
break :: Monad m => (Word8 -> Bool) -> ByteString m r -> ByteString m (ByteString m r)
break f cs0 = break' cs0
  where break' (Empty r)        = Empty (Empty r)
        break' (Chunk c cs) =
          case findIndexOrEnd f c of
            0                  -> Empty (Chunk c cs)
            n | n < S.length c -> Chunk (S.take n c) $
                                      Empty (Chunk (S.drop n c) cs)
              | otherwise      -> Chunk c (break' cs)
        break' (Go m) = Go (liftM break' m)

--
-- -- TODO
-- --
-- -- Add rules
-- --
--
-- {-
-- -- | 'breakByte' breaks its ByteString argument at the first occurence
-- -- of the specified byte. It is more efficient than 'break' as it is
-- -- implemented with @memchr(3)@. I.e.
-- --
-- -- > break (=='c') "abcd" == breakByte 'c' "abcd"
-- --
-- breakByte :: Word8 -> ByteString -> (ByteString, ByteString)
-- breakByte c (LPS ps) = case (breakByte' ps) of (a,b) -> (LPS a, LPS b)
--   where breakByte' []     = ([], [])
--         breakByte' (x:xs) =
--           case P.elemIndex c x of
--             Just 0  -> ([], x : xs)
--             Just n  -> (P.take n x : [], P.drop n x : xs)
--             Nothing -> let (xs', xs'') = breakByte' xs
--                         in (x : xs', xs'')
--
-- -- | 'spanByte' breaks its ByteString argument at the first
-- -- occurence of a byte other than its argument. It is more efficient
-- -- than 'span (==)'
-- --
-- -- > span  (=='c') "abcd" == spanByte 'c' "abcd"
-- --
-- spanByte :: Word8 -> ByteString -> (ByteString, ByteString)
-- spanByte c (LPS ps) = case (spanByte' ps) of (a,b) -> (LPS a, LPS b)
--   where spanByte' []     = ([], [])
--         spanByte' (x:xs) =
--           case P.spanByte c x of
--             (x', x'') | P.null x'  -> ([], x : xs)
--                       | P.null x'' -> let (xs', xs'') = spanByte' xs
--                                        in (x : xs', xs'')
--                       | otherwise  -> (x' : [], x'' : xs)
-- -}
--
-- | 'span' @p xs@ breaks the ByteString into two segments. It is
-- equivalent to @('takeWhile' p xs, 'dropWhile' p xs)@
span :: Monad m => (Word8 -> Bool) -> ByteString m r -> ByteString m (ByteString m r)
span p = break (not . p)

-- | /O(n)/ Splits a 'ByteString' into components delimited by
-- separators, where the predicate returns True for a separator element.
-- The resulting components do not contain the separators.  Two adjacent
-- separators result in an empty component in the output.  eg.
--
-- > splitWith (=='a') "aabbaca" == ["","","bb","c",""]
-- > splitWith (=='a') []        == []
--
splitWith :: Monad m => (Word8 -> Bool) -> ByteString m r -> Stream (ByteString m) m r
splitWith _ (Empty r)      = Return r
splitWith p (Chunk c0 cs0) = comb [] (S.splitWith p c0) cs0
  where 
-- comb :: [P.ByteString] -> [P.ByteString] -> ByteString -> [ByteString]
--  comb acc (s:[]) (Empty r)    = Step (revChunks (s:acc) (Return r))
  comb acc [s] (Empty r)    = Step $ L.foldl' (flip Chunk) 
                                              (Empty (Return r)) 
                                              (s:acc) 
  comb acc [s] (Chunk c cs) = comb (s:acc) (S.splitWith p c) cs
  comb acc b (Go m)         = Delay (liftM (comb acc b) m)
  comb acc (s:ss) cs        = Step $ L.foldl' (flip Chunk)  
                                              (Empty (comb [] ss cs)) 
                                              (s:acc)
--  comb acc (s:ss) cs           = Step (revChunks (s:acc) (comb [] ss cs))

{-# INLINE splitWith #-}

-- | /O(n)/ Break a 'ByteString' into pieces separated by the byte
-- argument, consuming the delimiter. I.e.
--
-- > split '\n' "a\nb\nd\ne" == ["a","b","d","e"]
-- > split 'a'  "aXaXaXa"    == ["","X","X","X",""]
-- > split 'x'  "x"          == ["",""]
--
-- and
--
-- > intercalate [c] . split c == id
-- > split == splitWith . (==)
--
-- As for all splitting functions in this library, this function does
-- not copy the substrings, it just constructs new 'ByteStrings' that
-- are slices of the original.
--
split :: Monad m => Word8 -> ByteString m r -> Stream (ByteString m) m r
split w = loop 
  where
  loop !x = case x of
    Empty r      -> Return r
    Go m         -> Delay $ liftM loop m
    Chunk c0 cs0 -> comb [] (S.split w c0) cs0
  comb !acc [] (Empty r)       = Step $ revChunks acc (Return r)
  comb acc [] (Chunk c cs)     = comb acc (S.split w c) cs
  comb !acc (s:[]) (Empty r)   = Step $ revChunks (s:acc) (Return r)
  comb acc (s:[]) (Chunk c cs) = comb (s:acc) (S.split w c) cs
  comb acc b (Go m)            = Delay (liftM (comb acc b) m)
  comb acc (s:ss) cs           = Step $ revChunks (s:acc) (comb [] ss cs)
{-# INLINE split #-}


--
-- | The 'group' function take`5s a ByteString and returns a list of
-- ByteStrings such that the concatenation of the result is equal to the
-- argument.  Moreover, each sublist in the result contains only equal
-- elements.  For example,
--
-- > group "Mississippi" = ["M","i","ss","i","ss","i","pp","i"]
--
-- It is a special case of 'groupBy', which allows the programmer to
-- supply their own equality test.

group :: Monad m => ByteString m r -> Stream (ByteString m) m r
group = go
  where
  go (Empty r)       = Return r
  go (Chunk c cs)
    | S.length c == 1  = Step $ to [c] (S.unsafeHead c) cs
    | otherwise        = Step $ to [S.unsafeTake 1 c] (S.unsafeHead c)
                                     (Chunk (S.unsafeTail c) cs)

  to acc !_ (Empty r)        = revNonEmptyChunks 
                                     acc  
                                     (Empty (Return r))
  to acc !w (Chunk c cs) =
    case findIndexOrEnd (/= w) c of
      0                    -> revNonEmptyChunks 
                                    acc 
                                    (Empty (go (Chunk c cs)))
      n | n == S.length c  -> to (S.unsafeTake n c : acc) w cs
        | otherwise        -> revNonEmptyChunks 
                                    (S.unsafeTake n c : acc)
                                    (Empty (go (Chunk (S.unsafeDrop n c) cs)))

-- -- | The 'groupBy' function is the non-overloaded version of 'group'.
-- --
-- groupBy :: (Word8 -> Word8 -> Bool) -> ByteString -> [ByteString]
-- groupBy k = go
--   where
--     go Empty        = []
--     go (Chunk c cs)
--       | S.length c == 1  = to [c] (S.unsafeHead c) cs
--       | otherwise        = to [S.unsafeTake 1 c] (S.unsafeHead c) (Chunk (S.unsafeTail c) cs)
--
--     to acc !_ Empty        = revNonEmptyChunks acc : []
--     to acc !w (Chunk c cs) =
--       case findIndexOrEnd (not . k w) c of
--         0                    -> revNonEmptyChunks acc
--                               : go (Chunk c cs)
--         n | n == S.length c  -> to (S.unsafeTake n c : acc) w cs
--           | otherwise        -> revNonEmptyChunks (S.unsafeTake n c : acc)
--                               : go (Chunk (S.unsafeDrop n c) cs)
--
-- | /O(n)/ The 'intercalate' function takes a 'ByteString' and a list of
-- 'ByteString's and concatenates the list after interspersing the first
-- argument between each element of the list.
intercalate :: Monad m => ByteString m () -> Stream (ByteString m) m r -> ByteString m r
intercalate s (Return r) = Empty r
intercalate s (Delay m) = Go $ liftM (intercalate s) m
intercalate s (Step bsls) = do  -- this isn't quite right yet
  ls <- bsls
  s 
  loop ls
 where
  loop (Return r) =  Empty r -- concat . (L.intersperse s)
  loop (Delay m) = Go $ liftM loop m
  loop (Step bsls) = do
    ls <- bsls
    case ls of
      Return r -> Empty r  -- no '\n' before end, in this case.
      x -> s >> loop x


-- -- | count returns the number of times its argument appears in the ByteString
-- --
-- -- > count = length . elemIndices
-- --
-- -- But more efficiently than using length on the intermediate list.
-- count :: Word8 -> ByteString -> Int64
-- count w cs = foldlChunks (\n c -> n + fromIntegral (S.count w c)) 0 cs
--
-- -- | The 'findIndex' function takes a predicate and a 'ByteString' and
-- -- returns the index of the first element in the ByteString
-- -- satisfying the predicate.
-- findIndex :: (Word8 -> Bool) -> ByteString -> Maybe Int64
-- findIndex k cs0 = findIndex' 0 cs0
--   where findIndex' _ Empty        = Nothing
--         findIndex' n (Chunk c cs) =
--           case S.findIndex k c of
--             Nothing -> findIndex' (n + fromIntegral (S.length c)) cs
--             Just i  -> Just (n + fromIntegral i)
-- {-# INLINE findIndex #-}
--
-- -- | /O(n)/ The 'find' function takes a predicate and a ByteString,
-- -- and returns the first element in matching the predicate, or 'Nothing'
-- -- if there is no such element.
-- --
-- -- > find f p = case findIndex f p of Just n -> Just (p ! n) ; _ -> Nothing
-- --
-- find :: (Word8 -> Bool) -> ByteString -> Maybe Word8
-- find f cs0 = find' cs0
--   where find' Empty        = Nothing
--         find' (Chunk c cs) = case S.find f c of
--             Nothing -> find' cs
--             Just w  -> Just w
-- {-# INLINE find #-}
--
-- -- | The 'findIndices' function extends 'findIndex', by returning the
-- -- indices of all elements satisfying the predicate, in ascending order.
-- findIndices :: (Word8 -> Bool) -> ByteString -> [Int64]
-- findIndices k cs0 = findIndices' 0 cs0
--   where findIndices' _ Empty        = []
--         findIndices' n (Chunk c cs) = L.map ((+n).fromIntegral) (S.findIndices k c)
--                              ++ findIndices' (n + fromIntegral (S.length c)) cs
--
-- ---------------------------------------------------------------------
-- Searching ByteStrings

-- | /O(n)/ 'filter', applied to a predicate and a ByteString,
-- returns a ByteString containing those characters that satisfy the
-- predicate.
filter :: (Word8 -> Bool) -> ByteString m r -> ByteString m r
filter p s = go s
    where
        go (Empty r )   = Empty r
        go (Chunk x xs) = chunk (S.filter p x) (go xs) 
                            -- should inspect for null
{-# INLINE filter #-}

-- {-
-- -- | /O(n)/ and /O(n\/c) space/ A first order equivalent of /filter .
-- -- (==)/, for the common case of filtering a single byte. It is more
-- -- efficient to use /filterByte/ in this case.
-- --
-- -- > filterByte == filter . (==)
-- --
-- -- filterByte is around 10x faster, and uses much less space, than its
-- -- filter equivalent
-- filterByte :: Word8 -> ByteString -> ByteString
-- filterByte w ps = replicate (count w ps) w
-- {-# INLINE filterByte #-}
--
-- {-# RULES
-- "ByteString specialise filter (== x)" forall x.
--   filter ((==) x) = filterByte x
--
-- "ByteString specialise filter (== x)" forall x.
--  filter (== x) = filterByte x
--   #-}
-- -}
--
-- {-
-- -- | /O(n)/ A first order equivalent of /filter . (\/=)/, for the common
-- -- case of filtering a single byte out of a list. It is more efficient
-- -- to use /filterNotByte/ in this case.
-- --
-- -- > filterNotByte == filter . (/=)
-- --
-- -- filterNotByte is around 2x faster than its filter equivalent.
-- filterNotByte :: Word8 -> ByteString -> ByteString
-- filterNotByte w (LPS xs) = LPS (filterMap (P.filterNotByte w) xs)
-- -}


-- -- ---------------------------------------------------------------------
-- -- Zipping
--
-- -- | /O(n)/ 'zip' takes two ByteStrings and returns a list of
-- -- corresponding pairs of bytes. If one input ByteString is short,
-- -- excess elements of the longer ByteString are discarded. This is
-- -- equivalent to a pair of 'unpack' operations.
-- zip :: ByteString -> ByteString -> [(Word8,Word8)]
-- zip = zipWith (,)
--
-- -- | 'zipWith' generalises 'zip' by zipping with the function given as
-- -- the first argument, instead of a tupling function.  For example,
-- -- @'zipWith' (+)@ is applied to two ByteStrings to produce the list of
-- -- corresponding sums.
-- zipWith :: (Word8 -> Word8 -> a) -> ByteString -> ByteString -> [a]
-- zipWith _ Empty     _  = []
-- zipWith _ _      Empty = []
-- zipWith f (Chunk a as) (Chunk b bs) = go a as b bs
--   where
--     go x xs y ys = f (S.unsafeHead x) (S.unsafeHead y)
--                  : to (S.unsafeTail x) xs (S.unsafeTail y) ys
--
--     to x Empty         _ _             | S.null x       = []
--     to _ _             y Empty         | S.null y       = []
--     to x xs            y ys            | not (S.null x)
--                                       && not (S.null y) = go x  xs y  ys
--     to x xs            _ (Chunk y' ys) | not (S.null x) = go x  xs y' ys
--     to _ (Chunk x' xs) y ys            | not (S.null y) = go x' xs y  ys
--     to _ (Chunk x' xs) _ (Chunk y' ys)                  = go x' xs y' ys
--
-- -- | /O(n)/ 'unzip' transforms a list of pairs of bytes into a pair of
-- -- ByteStrings. Note that this performs two 'pack' operations.
-- unzip :: [(Word8,Word8)] -> (ByteString,ByteString)
-- unzip ls = (pack (L.map fst ls), pack (L.map snd ls))
-- {-# INLINE unzip #-}
--

-- ---------------------------------------------------------------------
-- ByteString IO
--
-- Rule for when to close: is it expected to read the whole file?
-- If so, close when done.
--

-- | Read entire handle contents /lazily/ into a 'ByteString'. Chunks
-- are read on demand, in at most @k@-sized chunks. It does not block
-- waiting for a whole @k@-sized chunk, so if less than @k@ bytes are
-- available then they will be returned immediately as a smaller chunk.
--
-- The handle is closed on EOF.
--
-- Note: the 'Handle' should be placed in binary mode with
-- 'System.IO.hSetBinaryMode' for 'hGetContentsN' to
-- work correctly.
--
hGetContentsN :: Int -> Handle -> ByteString IO ()
hGetContentsN k h = loop -- TODO close on exceptions
  where
--    lazyRead = unsafeInterleaveIO loop
    loop = do
        c <- liftIO (S.hGetSome h k)
        -- only blocks if there is no data available
        if S.null c
          then Go $ hClose h >> return (Empty ())
          else Chunk c loop
{-#INLINE hGetContentsN #-} -- very effective inline pragma

-- | Read @n@ bytes into a 'ByteString', directly from the
-- specified 'Handle', in chunks of size @k@.
--
hGetN :: Int -> Handle -> Int -> ByteString IO ()
hGetN k h n | n > 0 = readChunks n
  where
    readChunks !i = Go $ do
        c <- S.hGet h (min k i)
        case S.length c of
            0 -> return $ Empty ()
            m -> return $ Chunk c (readChunks (i - m))

hGetN _ _ 0 = Empty ()
hGetN _ h n = liftIO $ illegalBufferSize h "hGet" n  -- <--- REPAIR !!!
{-#INLINE hGetN #-}

-- | hGetNonBlockingN is similar to 'hGetContentsN', except that it will never block
-- waiting for data to become available, instead it returns only whatever data
-- is available. Chunks are read on demand, in @k@-sized chunks.
--
hGetNonBlockingN :: Int -> Handle -> Int ->  ByteString IO ()
hGetNonBlockingN k h n | n > 0 = readChunks n
  where
    readChunks !i = Go $ do
        c <- S.hGetNonBlocking h (min k i)
        case S.length c of
            0 -> return (Empty ())
            m -> return (Chunk c (readChunks (i - m)))

hGetNonBlockingN _ _ 0 = Empty ()
hGetNonBlockingN _ h n = liftIO $ illegalBufferSize h "hGetNonBlocking" n


illegalBufferSize :: Handle -> String -> Int -> IO a
illegalBufferSize handle fn sz =
    ioError (mkIOError illegalOperationErrorType msg (Just handle) Nothing)
    --TODO: System.IO uses InvalidArgument here, but it's not exported :-(
    where
      msg = fn ++ ": illegal ByteString size " ++ showsPrec 9 sz []

-- | Read entire handle contents /lazily/ into a 'ByteString'. Chunks
-- are read on demand, using the default chunk size.
--
-- Once EOF is encountered, the Handle is closed.
--
-- Note: the 'Handle' should be placed in binary mode with
-- 'System.IO.hSetBinaryMode' for 'hGetContents' to
-- work correctly.

hGetContents :: Handle -> ByteString IO ()
hGetContents = hGetContentsN defaultChunkSize
{-#INLINE hGetContents #-}

-- | Pipes-style nomenclature for 'hGetContents'
fromHandle  :: Handle -> ByteString IO ()
fromHandle = hGetContents
{-#INLINE fromHandle #-}

-- | Pipes-style nomenclature for 'getContents'
stdin :: ByteString IO ()
stdin =  hGetContents IO.stdin
{-#INLINE stdin #-}

-- | Read @n@ bytes into a 'ByteString', directly from the specified 'Handle'.
--
hGet :: Handle -> Int -> ByteString IO ()
hGet = hGetN defaultChunkSize
{-#INLINE hGet #-}

-- | hGetNonBlocking is similar to 'hGet', except that it will never block
-- waiting for data to become available, instead it returns only whatever data
-- is available.  If there is no data available to be read, 'hGetNonBlocking'
-- returns 'empty'.
--
-- Note: on Windows and with Haskell implementation other than GHC, this
-- function does not work correctly; it behaves identically to 'hGet'.
--
hGetNonBlocking :: Handle -> Int -> ByteString IO ()
hGetNonBlocking = hGetNonBlockingN defaultChunkSize
{-#INLINE hGetNonBlocking #-}

-- | Read an entire file into a chunked 'ByteString IO ()'.
-- The Handle will be held open until EOF is encountered.
--
readFile :: FilePath -> ByteString IO ()
readFile f = Go $ liftM hGetContents (openBinaryFile f ReadMode)
{-#INLINE readFile #-}

-- | Write a 'ByteString' to a file.
--
writeFile :: FilePath -> ByteString IO r -> IO r
writeFile f txt = bracket
    (openBinaryFile f WriteMode)
    hClose
    (\hdl -> hPut hdl txt)

-- | Append a 'ByteString' to a file.
--
appendFile :: FilePath -> ByteString IO r -> IO r
appendFile f txt = bracket
    (openBinaryFile f AppendMode)
    hClose
    (\hdl -> hPut hdl txt)

-- | getContents. Equivalent to hGetContents stdin. Will read /lazily/
--
getContents :: ByteString IO ()
getContents = hGetContents IO.stdin

-- | Outputs a 'ByteString' to the specified 'Handle'.
--
hPut :: Handle -> ByteString IO r -> IO r
hPut h cs = dematerialize cs return (\x y -> S.hPut h x >> y) (>>= id)
{-#INLINE hPut #-}

-- | Pipes nomenclature for 'hPut'
toHandle :: Handle -> ByteString IO r -> IO r
toHandle = hPut
{-#INLINE toHandle #-}

-- | Pipes-style nomenclature for 'putStr'
stdout :: ByteString IO r -> IO r
stdout = hPut IO.stdout
{-#INLINE stdout#-}

-- | Similar to 'hPut' except that it will never block. Instead it returns
-- any tail that did not get written. This tail may be 'empty' in the case that
-- the whole string was written, or the whole original string if nothing was
-- written. Partial writes are also possible.
--
-- Note: on Windows and with Haskell implementation other than GHC, this
-- function does not work correctly; it behaves identically to 'hPut'.
--
hPutNonBlocking :: Handle -> ByteString IO r -> ByteString IO r
hPutNonBlocking _ (Empty r)         = Empty r
hPutNonBlocking h bs@(Chunk c cs) = do
  c' <- lift $ S.hPutNonBlocking h c
  case S.length c' of
    l' | l' == S.length c -> hPutNonBlocking h cs
    0                     -> bs
    _                     -> Chunk c' cs

-- | A synonym for @hPut@, for compatibility
--
-- hPutStr :: Handle -> ByteString IO r -> IO r
-- hPutStr = hPut
--
-- -- | Write a ByteString to stdout
-- putStr :: ByteString IO r -> IO r
-- putStr = hPut IO.stdout

-- -- | Write a ByteString to stdout, appending a newline byte
-- --
-- putStrLn :: ByteString -> IO ()
-- putStrLn ps = hPut stdout ps >> hPut stdout (singleton 0x0a)
--
-- {-# DEPRECATED putStrLn
--     "Use Data.ByteString.Lazy.Char8.putStrLn instead. (Functions that rely on ASCII encodings belong in Data.ByteString.Lazy.Char8)"
--   #-}
--
-- -- | The interact function takes a function of type @ByteString -> ByteString@
-- -- as its argument. The entire input from the standard input device is passed
-- -- to th is function as its argument, and the resulting string is output on the
-- -- standard output device.
-- --
interact :: (ByteString IO () -> ByteString IO r) -> IO r
interact transformer = stdout (transformer stdin)

-- -- ---------------------------------------------------------------------
-- -- Internal utilities
--
-- -- Common up near identical calls to `error' to reduce the number
-- -- constant strings created when compiled:
-- errorEmptyStream :: String -> a
-- errorEmptyStream fun = moduleError fun "empty ByteString"
-- {-# NOINLINE errorEmptyStream #-}
--
-- moduleError :: String -> String -> a
-- moduleError fun msg = error ("Data.ByteString.Lazy." ++ fun ++ ':':' ':msg)
-- {-# NOINLINE moduleError #-}

revNonEmptyChunks :: [P.ByteString] -> ByteString m r -> ByteString m r
revNonEmptyChunks = Prelude.foldr (\bs f -> Chunk bs . f) id 
{-#INLINE revNonEmptyChunks#-}
  -- loop p xs
  -- where
  --   loop !bss [] = bss
  --   loop bss (b:bs) = loop (Chunk b bss) bs
  --   loop' [] = id
  --   loop' (b:bs) = loop' bs . Chunk b
-- L.foldl' (flip Chunk) Empty cs
-- foldr :: Foldable t => (a -> b -> b) -> b -> t a -> b

-- reverse a list of possibly-empty chunks into a lazy ByteString
revChunks :: Monad m => [P.ByteString] -> r -> ByteString m r
revChunks cs r = L.foldl' (flip Chunk) (Empty r) cs
{-#INLINE revChunks #-}
-- | 'findIndexOrEnd' is a variant of findIndex, that returns the length
-- of the string if no element is found, rather than Nothing.
findIndexOrEnd :: (Word8 -> Bool) -> P.ByteString -> Int
findIndexOrEnd k (S.PS x s l) =
    S.accursedUnutterablePerformIO $
      withForeignPtr x $ \f -> go (f `plusPtr` s) 0
  where
    go !ptr !n | n >= l    = return l
               | otherwise = do w <- peek ptr
                                if k w
                                  then return n
                                  else go (ptr `plusPtr` 1) (n+1)
{-# INLINE findIndexOrEnd #-}

zipWithStream
  :: (Monad m)
  =>  (forall x . a -> ByteString m x -> ByteString m x)
  -> [a]
  -> Stream (ByteString m) m r
  -> Stream (ByteString m) m r
zipWithStream op zs = loop zs
  where
    loop [] !ls      = loop zs ls
    loop a@(x:xs)  ls = case ls of
      Return r -> Return r
      Step fls -> Step $ fmap (loop xs) (op x fls)
      Delay mls -> Delay $ liftM (loop a) mls

{-#INLINE zipWithStream #-}
