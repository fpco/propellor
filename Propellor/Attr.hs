{-# LANGUAGE PackageImports #-}

module Propellor.Attr where

import Propellor.Types
import Propellor.Types.Attr

import "mtl" Control.Monad.Reader
import qualified Data.Set as S
import qualified Data.Map as M
import Control.Applicative

pureAttrProperty :: Desc -> (Attr -> Attr) -> AttrProperty 
pureAttrProperty desc = AttrProperty $ Property ("has " ++ desc)
	(return NoChange)

hostname :: HostName -> AttrProperty
hostname name = pureAttrProperty ("hostname " ++ name) $
	\d -> d { _hostname = name }

getHostName :: Propellor HostName
getHostName = asks _hostname

os :: System -> AttrProperty
os system = pureAttrProperty ("Operating " ++ show system) $
	\d -> d { _os = Just system }

getOS :: Propellor (Maybe System)
getOS = asks _os

cname :: Domain -> AttrProperty
cname domain = pureAttrProperty ("cname " ++ domain) (addCName domain)

cnameFor :: IsProp p => Domain -> (Domain -> p) -> AttrProperty
cnameFor domain mkp =
	let p = mkp domain
	in AttrProperty p (addCName domain)

addCName :: HostName -> Attr -> Attr
addCName domain d = d { _cnames = S.insert domain (_cnames d) }

sshPubKey :: String -> AttrProperty
sshPubKey k = pureAttrProperty ("ssh pubkey known") $
	\d -> d { _sshPubKey = Just k }

getSshPubKey :: Propellor (Maybe String)
getSshPubKey = asks _sshPubKey

hostnameless :: Attr
hostnameless = newAttr (error "hostname Attr not specified")

hostAttr :: Host -> Attr
hostAttr (Host _ mkattrs) = mkattrs hostnameless

hostProperties :: Host -> [Property]
hostProperties (Host ps _) = ps

hostMap :: [Host] -> M.Map HostName Host
hostMap l = M.fromList $ zip (map (_hostname . hostAttr) l) l 

findHost :: [Host] -> HostName -> Maybe Host
findHost l hn = M.lookup hn (hostMap l)

-- | Lifts an action into a different host.
--
-- For example, `fromHost hosts "otherhost" getSshPubKey`
fromHost :: [Host] -> HostName -> Propellor a -> Propellor (Maybe a)
fromHost l hn getter = case findHost l hn of
	Nothing -> return Nothing
	Just h -> liftIO $ Just <$>
		runReaderT (runWithAttr getter) (hostAttr h)
