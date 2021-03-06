{-|
Module      : ReplyQueue
Description : Tests for Network.Kademlia.ReplyQueue

Tests specific to Network.Kademlia.ReplyQueue
-}

module ReplyQueue where

import Test.QuickCheck
import Test.QuickCheck.Monadic

import Control.Concurrent.Chan
import Control.Concurrent.STM
import Data.Maybe (isJust)

import Network.Kademlia.ReplyQueue
import Network.Kademlia.Types

import TestTypes

-- | Check wether registered reply handlers a used
repliesCheck :: Signal IdType String -> Signal IdType String -> Property
repliesCheck sig1 sig2 = monadicIO $ do
    let reg1 = toRegistration sig1
    let reg2 = toRegistration sig2

    pre $ isJust reg1 && isJust reg2

    let (Just replyReg1) = reg1
    let (Just replyReg2) = reg2

    contents <- run $ do
        rq <- emptyReplyQueue
        chan <- newChan :: IO (Chan (Reply IdType String))

        register replyReg1 rq chan
        register replyReg2 rq chan

        dispatch (Answer sig1) rq
        dispatch (Answer sig2) rq

        contents <- getChanContents chan

        return contents

    assert . not . null $ contents

    let [reply1, reply2] = take 2 contents

    assert $ reply1 /= Closed
    assert $ reply2 /= Closed

    let (Answer unwrapped1) = reply1
    let (Answer unwrapped2) = reply2

    assert $ unwrapped1 == sig1
    assert $ unwrapped2 == sig2

-- | Check wether registered reply handlers are removed after usage
removedCheck :: Signal IdType String -> Property
removedCheck sig = monadicIO $ do
    let reg = toRegistration sig
    case reg of
        -- Discard the test case
        Nothing -> pre False
        Just reg -> do
            removed <- run $ do
                rq <- emptyReplyQueue
                chan <- newChan :: IO (Chan (Reply IdType String))
                register reg rq chan
                dispatch (Answer sig) rq
                fmap null (atomically . readTVar . queue $ rq)
            assert removed

-- | Convert a Signal into its ReplyRegistration representation
toRegistration :: Signal i a -> Maybe (ReplyRegistration i)
toRegistration sig = case rType . command $ sig of
                        Nothing -> Nothing
                        Just rt -> Just (RR [rt] origin)
    where origin = nodeId . source $ sig

          rType :: Command i a -> Maybe (ReplyType i)
          rType  PONG               = Just  R_PONG
          rType (RETURN_VALUE id _) = Just (R_RETURN_VALUE id)
          rType (RETURN_NODES id _) = Just (R_RETURN_NODES id)
          rType _ = Nothing
