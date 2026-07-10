-- | SHA-256 of a canonical payload string — the content address.
-- |
-- | The *client* owns canonicalisation (e.g. Lepidoptera's byte-stable
-- | print/parse round-trip); Amphora hashes exactly the bytes it is given.
-- | This keeps the server dumb and the address reproducible anywhere the
-- | same canonical form is produced.
module Amphora.Hash
  ( sha256Hex
  ) where

import Effect (Effect)

foreign import sha256Hex :: String -> Effect String
