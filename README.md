# SEATED

Restaurant reviews where every review is backed by cryptographic proof that the
reviewer was actually at the table.

Roughly a third of reviews on the major platforms are unverifiable — nobody can
check whether the author ever set foot in the place. SEATED makes attendance a
precondition for speech, on-chain and checkable by anyone.

## Proof tiers

Every review is posted against one of two proofs, and the tier is visible on
the review itself:

- **Tier 1 — venue-signed check-in.** The venue's signing key signs an EIP-712
  voucher when a diner is seated. Redeeming that voucher (once, before it
  expires, within the venue's declared daily capacity) mints a single-use
  attendance proof. Works anywhere with no crypto adoption from the venue
  beyond holding a signing key.
- **Tier 2 — settled bill.** The diner pays the bill in USDC. The settlement
  itself is the proof — unforgeable, no trusted party, but only works where
  the venue accepts crypto.

**World ID sits across both tiers.** It caps each human to one review per
venue, so tier 1 (which a venue could otherwise over-sign) can't be farmed by
one person running many wallets.

## Contracts

| Contract | Responsibility |
|---|---|
| `src/VenueRegistry.sol` | Registers venues: owner, signing key, declared daily capacity, metadata URI, active flag. |
| `src/AttendanceGate.sol` | Verifies a tier-1 check-in voucher, enforces expiry/replay/daily-capacity, and mints the attendance proof. |
| `src/BillSettlement.sol` | Moves a USDC bill payment from diner to venue owner in one call and mints the tier-2 proof. |
| `src/ReviewRegistry.sol` | Consumes a tier-1 or tier-2 proof plus a World ID proof of personhood, stores the review, and holds signed venue replies. |

## Flow

```
 venue                     diner                        chain
   │                         │                             │
   │  sign CheckIn voucher   │                             │
   ├────────────────────────>│                             │
   │                         │  AttendanceGate.redeem()    │
   │                         ├────────────────────────────>│  mints proofId
   │                         │                             │  (tier 1)
   │                         │  ReviewRegistry.postReview() │
   │                         │  (proofId + World ID proof) │
   │                         ├────────────────────────────>│  review stored
   │                         │                             │
   │  postReply(reviewId,…)  │                             │
   ├─────────────────────────┼────────────────────────────>│  reply stored
```

(Tier 2 is the same shape, minus the voucher: `BillSettlement.settle()` mints
the proof directly from a USDC payment.)

## Build and test

```shell
forge build
forge test
```

74 tests pass as of this fix wave.

## Deployment

- `script/Deploy.s.sol` deploys all four contracts and logs their addresses
  plus the deployment block number (`startBlock`), which a subgraph needs to
  begin indexing from.
- `.env.example` lists the environment variables the script and the venue
  seeding script expect (deployer key, RPC URL, World ID app config, USDC and
  World ID router addresses, per-venue seeding keys).
- `deployments/base-sepolia.json` — populated from a real Base Sepolia
  deployment. Carries the four contract addresses and the `startBlock` the
  subgraph should index from.

## Demo notes

`script/SeedVenues.s.sol` seeds three demo venues with declared daily
capacities of 40, 120, and 24 covers. A demo scene that fires 50 wallets'
worth of check-ins at a single venue must target **venue 2 (120 covers)** —
venues 1 and 3 don't have headroom for 50, so wallets past their cap would
revert in `AttendanceGate.redeem` with `CapacityExceeded` before ever
reaching `postReview`, showing the wrong error and never exercising the
World ID personhood check that scene is meant to demonstrate.

## Design notes

A few properties are deliberate, not bugs, even though each looks like one on
first read:

1. **One human gets one review per venue per epoch, not permanently.**
   `ReviewRegistry` computes the World ID external nullifier per epoch by
   appending the epoch number to the action string
   (`ReviewRegistry.actionForEpoch`), so each epoch rotates every human's
   World ID nullifier for that venue and yields a fresh review. Epoch length
   is fixed at deployment (`epochLength`, 90 days by default) via
   `REVIEW_EPOCH_LENGTH`. One caveat: a proof generated right at an epoch
   boundary whose transaction lands in the next epoch will fail verification
   and must simply be retried. The reverse side of the same boundary is a
   safety tradeoff, not just a liveness one: because epochs are fixed
   calendar windows rather than a rolling window per human, one person can
   legitimately post a review one second before an epoch flips and another
   one second after — two reviews seconds apart despite the nominal 90-day
   guarantee. This is inherent to fixed windows and accepted, not a bug.
2. **`ReviewRegistry` does not check whether a venue is still active.** A
   validly-earned proof can still back a review after the venue deactivates.
   This is intentional: the diner was there, so they may say so — the
   alternative would let a venue silence pending criticism simply by
   deactivating itself.
3. **The daily capacity cap in `AttendanceGate` buckets by UTC calendar day,**
   not a rolling 24-hour window. A venue can therefore redeem up to roughly
   2x its committed `maxCoversPerDay` across a single UTC midnight (a few
   vouchers just before, a full day's worth just after). The long-run
   average rate is still correctly capped — it's an order-of-magnitude
   honesty check on capacity, not an audit boundary.

## Frontend integration: the World ID action rotates

`ReviewRegistry` does not verify proofs against a fixed action string. It
composes one per epoch (`"<baseAction>-<epoch>"`, e.g. `post-review-231`) and
verifies against that. The frontend **must not** hardcode or reuse the bare
`WORLD_ID_BASE_ACTION` value from `.env.example` when calling IDKit — it must
read the live action off the contract immediately before generating each
proof:

```js
const action = await reviews.actionForEpoch(await reviews.currentEpoch());
// pass `action` (not the .env base action) as the `action` prop to IDKit
```

A proof generated against a stale action reverts inside the World ID router
with an opaque error — see the epoch-boundary note above and the NatSpec on
`postReview`.

**OPEN QUESTION (unverified):** it is not yet confirmed whether the Worldcoin
Developer Portal requires each distinct action string to be pre-registered
for an app. If it does, a rotating per-epoch action needs a per-epoch
registration step, which would need to happen out-of-band before each new
epoch's proofs can verify. Neither confirmed nor ruled out here — check
Worldcoin's docs before relying on this in production.

## Deployed addresses

Base Sepolia (chain 84532), all verified on BaseScan. Indexed from block
`46773870`. Machine-readable copy in `deployments/base-sepolia.json`.

| Contract | Address |
|---|---|
| VenueRegistry | [`0xf24e76f7df7e566db21c0b36f79fb03f3b64a7ed`](https://sepolia.basescan.org/address/0xf24e76f7df7e566db21c0b36f79fb03f3b64a7ed) |
| AttendanceGate | [`0x827a00529e7cc7b7608f0f93a231f93aa7ac8e22`](https://sepolia.basescan.org/address/0x827a00529e7cc7b7608f0f93a231f93aa7ac8e22) |
| BillSettlement | [`0xc3720d832f97d19d9f8303bcb64ca8eda1cf0e55`](https://sepolia.basescan.org/address/0xc3720d832f97d19d9f8303bcb64ca8eda1cf0e55) |
| ReviewRegistry | [`0xe4299049145bef1d2cd78c216d521d7d6a424730`](https://sepolia.basescan.org/address/0xe4299049145bef1d2cd78c216d521d7d6a424730) |

External: USDC `0x036CbD53842c5426634e7929541eC2318f3dCF7e`, World ID router
`0x42FF98C4E85212a5D31358ACbFe76a621b50fC02`.

The live World ID action at time of deployment is `post-review-230`. It rotates
every epoch — always read it with `actionForEpoch(currentEpoch())` rather than
hardcoding.
