-- | DuckDB bindings — async (Aff) over the duckdb Node driver.
-- |
-- | Cribbed from the cartography suite's `Database.DuckDB` (CodeExplorer),
-- | trimmed to what Amphora needs, plus a `readField` row accessor so the
-- | store can pull typed columns out of the `Foreign` result objects.
module Amphora.DuckDB
  ( Database
  , Row
  , Rows
  , openDB
  , closeDB
  , exec
  , queryAll
  , queryAllParams
  , run
  , readField
  , param
  , paramN
  , isEmpty
  , firstRow
  ) where

import Prelude

import Control.Promise (Promise, toAffE)
import Data.Maybe (Maybe(..), maybe)
import Data.Nullable (Nullable, toMaybe, toNullable)
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Uncurried (EffectFn3, runEffectFn3)
import Foreign (Foreign, unsafeToForeign)

-- | Opaque database connection handle.
foreign import data Database :: Type

-- | A single result row (a `Foreign` JS object keyed by column name).
type Row = Foreign

-- | Multiple result rows.
type Rows = Array Foreign

foreign import openDB_ :: String -> Effect (Promise Database)
foreign import closeDB_ :: Database -> Effect (Promise Unit)
foreign import exec_ :: Database -> String -> Effect (Promise Unit)
foreign import queryAll_ :: Database -> String -> Effect (Promise Rows)
foreign import queryAllParams_ :: EffectFn3 Database String (Array Foreign) (Promise Rows)
foreign import run_ :: EffectFn3 Database String (Array Foreign) (Promise Unit)
foreign import readField_ :: String -> Foreign -> Nullable String
foreign import firstRow_ :: Rows -> Nullable Foreign

-- | Open (or create) a database file.
openDB :: String -> Aff Database
openDB path = toAffE (openDB_ path)

-- | Close a database connection.
closeDB :: Database -> Aff Unit
closeDB db = toAffE (closeDB_ db)

-- | Execute one or more statements (DDL, or a `;`-joined batch).
exec :: Database -> String -> Aff Unit
exec db sql = toAffE (exec_ db sql)

-- | Run a query, returning all rows.
queryAll :: Database -> String -> Aff Rows
queryAll db sql = toAffE (queryAll_ db sql)

-- | Run a parameterised query (positional `?`), returning all rows.
-- | Also the right call for `INSERT … RETURNING`.
queryAllParams :: Database -> String -> Array Foreign -> Aff Rows
queryAllParams db sql params = toAffE (runEffectFn3 queryAllParams_ db sql params)

-- | Run a parameterised statement that returns nothing.
run :: Database -> String -> Array Foreign -> Aff Unit
run db sql params = toAffE (runEffectFn3 run_ db sql params)

-- | Read a column from a row as a String (numbers/timestamps are
-- | stringified JS-side). `Nothing` for SQL NULL or a missing key.
readField :: String -> Row -> Maybe String
readField key row = toMaybe (readField_ key row)

-- | A non-null String bind parameter.
param :: String -> Foreign
param = unsafeToForeign

-- | A nullable String bind parameter — `Nothing` binds SQL NULL.
paramN :: Maybe String -> Foreign
paramN = maybe (unsafeToForeign (toNullable (Nothing :: Maybe String))) unsafeToForeign

-- | First row, if any.
firstRow :: Rows -> Maybe Row
firstRow rows = toMaybe (firstRow_ rows)

-- | Were there no rows?
isEmpty :: Rows -> Boolean
isEmpty rows = case firstRow rows of
  Nothing -> true
  Just _ -> false
