{-# LANGUAGE PackageImports #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ExistentialQuantification #-}

module Propellor.Types
	( Host(..)
	, Attr
	, HostName
	, Propellor(..)
	, Property(..)
	, RevertableProperty(..)
	, IsProp
	, describe
	, toProp
	, setAttr
	, requires
	, Desc
	, Result(..)
	, ActionResult(..)
	, CmdLine(..)
	, PrivDataField(..)
	, GpgKeyId
	, SshKeyType(..)
	, module Propellor.Types.OS
	) where

import Data.Monoid
import Control.Applicative
import System.Console.ANSI
import "mtl" Control.Monad.Reader
import "MonadCatchIO-transformers" Control.Monad.CatchIO

import Propellor.Types.Attr
import Propellor.Types.OS

data Host = Host [Property] SetAttr

-- | Propellor's monad provides read-only access to attributes of the
-- system.
newtype Propellor p = Propellor { runWithAttr :: ReaderT Attr IO p }
	deriving
		( Monad
		, Functor
		, Applicative
		, MonadReader Attr 
		, MonadIO
		, MonadCatchIO
		)

-- | The core data type of Propellor, this represents a property
-- that the system should have, and an action to ensure it has the
-- property.
data Property = Property
	{ propertyDesc :: Desc
	, propertySatisfy :: Propellor Result
	-- ^ must be idempotent; may run repeatedly
	, propertyAttr :: SetAttr
	-- ^ a property can affect the overall Attr
	}

-- | A property that can be reverted.
data RevertableProperty = RevertableProperty Property Property

class IsProp p where
	-- | Sets description.
	describe :: p -> Desc -> p
	toProp :: p -> Property
	-- | Indicates that the first property can only be satisfied
	-- once the second one is.
	requires :: p -> Property -> p
	setAttr :: p -> SetAttr

instance IsProp Property where
	describe p d = p { propertyDesc = d }
	toProp p = p
	setAttr = propertyAttr
	x `requires` y = Property (propertyDesc x) satisfy attr
	  where
	  	attr = propertyAttr x . propertyAttr y
		satisfy = do
			r <- propertySatisfy y
			case r of
				FailedChange -> return FailedChange
				_ -> propertySatisfy x
			

instance IsProp RevertableProperty where
	-- | Sets the description of both sides.
	describe (RevertableProperty p1 p2) d = 
		RevertableProperty (describe p1 d) (describe p2 ("not " ++ d))
	toProp (RevertableProperty p1 _) = p1
	(RevertableProperty p1 p2) `requires` y =
		RevertableProperty (p1 `requires` y) p2
	-- | Return the SetAttr of the currently active side.
	setAttr (RevertableProperty p1 _p2) = setAttr p1

type Desc = String

data Result = NoChange | MadeChange | FailedChange
	deriving (Read, Show, Eq)

instance Monoid Result where
	mempty = NoChange

	mappend FailedChange _ = FailedChange
	mappend _ FailedChange = FailedChange
	mappend MadeChange _ = MadeChange
	mappend _ MadeChange = MadeChange
	mappend NoChange NoChange = NoChange

-- | Results of actions, with color.
class ActionResult a where
	getActionResult :: a -> (String, ColorIntensity, Color)

instance ActionResult Bool where
	getActionResult False = ("failed", Vivid, Red)
	getActionResult True = ("done", Dull, Green)

instance ActionResult Result where
	getActionResult NoChange = ("ok", Dull, Green)
	getActionResult MadeChange = ("done", Vivid, Green)
	getActionResult FailedChange = ("failed", Vivid, Red)

data CmdLine
	= Run HostName
	| Spin HostName
	| Boot HostName
	| Set HostName PrivDataField
	| AddKey String
	| Continue CmdLine
	| Chain HostName
	| Docker HostName
  deriving (Read, Show, Eq)

-- | Note that removing or changing field names will break the
-- serialized privdata files, so don't do that!
-- It's fine to add new fields.
data PrivDataField
	= DockerAuthentication
	| SshPubKey SshKeyType UserName
	| SshPrivKey SshKeyType UserName
	| SshAuthorizedKeys UserName
	| Password UserName
	| PrivFile FilePath
	| GpgKey GpgKeyId
	deriving (Read, Show, Ord, Eq)

type GpgKeyId = String

data SshKeyType = SshRsa | SshDsa | SshEcdsa | SshEd25519
	deriving (Read, Show, Ord, Eq)
