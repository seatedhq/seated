# SEATED — contracts handoff

State: contracts complete, 74/74 tests, **not yet deployed**. Everything below is
what the next plans (subgraph, frontend, demo assets) need and cannot infer from code.

## Before you deploy

`ReviewRegistry`'s `epochLength` and the World ID app id are baked in at construction
and **cannot be changed afterwards**. Decide both before broadcasting.

Run, in order, with your own credentials:

```bash
cp .env.example .env          # fill PRIVATE_KEY, ETHERSCAN_API_KEY, WORLD_ID_APP_ID
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" --broadcast --verify -vvvv
```

Then fill `deployments/base-sepolia.json` — the four addresses **and `startBlock`**,
which the script now prints. Fund the three venue addresses, then:

```bash
forge script script/SeedVenues.s.sol:SeedVenues \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" --broadcast -vvvv
```

If verification times out, re-run `forge verify-contract` alone rather than redeploying.

## Frontend: three things that will silently break you

**1. The World ID action rotates.** The contract verifies against
`"<baseAction>-<epoch>"`, not the bare action. Call
`reviews.actionForEpoch(reviews.currentEpoch())` and pass that exact string to IDKit.
Using `WORLD_ID_BASE_ACTION` directly makes every `postReview` revert inside the
router with an opaque error.

**2. The World ID signal is `(venue, msg.sender)`,** not the venue alone. IDKit's
signal must be `abi.encodePacked(venue, callerAddress)`. The caller binding exists
because an unbound signal let an attacker replay a proof lifted from the mempool and
permanently burn the victim's nullifier at that venue.

**3. A static printed per-table QR cannot work.** `CheckIn` commits to `diner` at
signing time and `redeem` requires `msg.sender == checkIn.diner`, so a fixed QR would
embed one predetermined wallet. Check-in must be a round trip: diner presents address
-> venue signer signs a per-diner voucher -> voucher returns to the diner. This binding
is what stops voucher resale, so it is correct — but the spec's Scene 1 wording implies
a static QR and needs reframing.

## Subgraph

Index `VenueRegistered`, `SigningKeyUpdated`, `VenueActiveSet`, `CheckInRedeemed`,
`BillSettled`, `ReviewPosted`, `ReplyPosted`. Event coverage was verified complete for
a storage-blind indexer: every state write emits, and `coversOnDay`, `settlementCount`
and `reviewCount` are all derivable by counting. `VenueStats`' tier ratio comes from
`ReviewPosted.tier`; venue metadata rides on `VenueRegistered.metadataURI`.

- Use the real `startBlock`. Too high loses `VenueRegistered` events, and venue
  metadata exists nowhere else — unrecoverable.
- `ReplyPosted` carries `address indexed venue`, so replies need no join back through
  `reviewId`.
- `Review` storage has **no author field**; the author is only in `ReviewPosted.diner`.
  `getReview()` cannot tell you who wrote a review.
- `CheckInRedeemed.seatedAt` is venue-asserted. Future values are now rejected on-chain,
  but backdating within the past is still possible. Treat `redeemedAt` as authoritative.
- `deployments/base-sepolia.json` carries an extra `_status` key — tolerate unknown keys.

## Demo

The 50-wallet personhood scene must target the **120-cover venue**. At the 40- and
24-cover venues, wallets past the cap fail in `redeem` with `CapacityExceeded` before
reaching `postReview`, so the scene would show the wrong error and never demonstrate
the World ID check.

Scene 2's two reverts are `NoAttendanceProof` (no voucher) and `AlreadyReviewedVenue`
(one human, many wallets). Both were verified to fire ahead of the World ID verifier,
so neither shows an opaque router error.

## Deliberate properties that look like bugs

- **One review per venue per epoch** (90 days by default), via a rotating action string.
  Boundary: a proof minted just before a flip may need retrying after it; and a human
  can review seconds either side of a flip, so the guarantee is a fixed window, not a
  rolling one.
- **No `isActive` check in `ReviewRegistry`** — a review can be posted from a validly
  earned proof after a venue deactivates. Intentional: you were there, so you may say
  so, and the alternative would let a venue censor pending criticism by deactivating.
- **`maxCoversPerDay` has no setter.** An adjustable cap would gut the self-signing
  defense. It also buckets by UTC day, so up to 2x capacity is redeemable across a
  single midnight; the long-run rate is still capped.
- **Unregistered venues surface as `VenueNotActive`** in `AttendanceGate` and
  `BillSettlement`, since an unregistered venue reads as inactive by default.

## Unverified

Whether the Worldcoin Developer Portal requires each distinct action string to be
pre-registered per app. If it does, a rotating action needs a per-epoch registration
step. Check Worldcoin's docs before relying on epochs in production.
