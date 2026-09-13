# SEATED spec revision — design doc

**Date:** 2026-09-13
**Status:** Approved, pending user review of updated spec
**Source spec:** `ethonline-seated-spec.md`

## Context

The original SEATED spec (restaurant reviews gated on cryptographic proof of attendance, built for ETHOnline) named four sponsor-integration candidates for three submission slots — World, The Graph, Privy, and Arc/Circle — with Arc explicitly flagged as "the cut candidate" since the settled-bill tier is a plain USDC `transferFrom` and needs no Circle SDK. This revision formalizes that cut and adds two product/demo features while staying within the spec's own stated build-risk tolerance (the original cut list already treats most of the 48-hour scope as load-bearing).

This is pre-hackathon planning — the full 48 hours are assumed to still be ahead, despite the spec's stated deadline coinciding with today's date.

## Decisions

**1. Drop Arc/Circle entirely.** No replacement third-track candidate — World, The Graph, and Privy are the three submitted slots outright, not two-plus-a-bonus. Rationale: the product loses nothing (tier 2 never depended on Circle tooling), and simplicity during a 48-hour build is worth more than a fourth sponsor pool.

**2. Add a Venue Leaderboard page** (low build risk). A `/leaderboard` route sorted by settled-tier percentage (client-side sortable by tier %, review count, average rating), sourced entirely from the `VenueStats` subgraph entity the base spec already plans for Scene 4. No new contracts — pure frontend + one subgraph query. Turns Scene 4's one-off natural-language query into a demo that closes on a persistent, browsable product surface instead of freezing on a single venue page.

**3. Add Venue Reply** (moderate build risk). Venues can post one signed reply per review, using the same Privy-governed `signingKey` and policy already used for check-in vouchers — reinforcing that Privy is structural (per the base spec's Privy section) rather than adding a second trust mechanism. This is the deepest lever available for the spec's own "known weakness" answer #1 ("the restaurant can fake check-ins") — it gives the demo a visible moment where the venue's *own* accountable key produces a permanent public artifact.

Chosen over an off-chain-only reply (rejected: loses the tamper-evidence property that's the whole point of the trust model) and over a fully editable/threaded reply (rejected: adds contract/subgraph state for no demo payoff within 48 hours).

## Technical design

### `ReviewRegistry.sol` changes
- `Review` struct gains `address venue` (also simplifies `VenueStats` derivation for the leaderboard — a side benefit beyond replies).
- Reviews get an explicit auto-incrementing `uint256 reviewId`, emitted in `ReviewPosted`.
- New struct: `Reply { bytes32 replyHash; uint64 postedAt; }`, stored in `mapping(uint256 => Reply) public replies`.
- New function: `postReply(uint256 reviewId, bytes32 replyHash, uint64 deadline, bytes signature)`. Verifies the EIP-712 signature recovers to `VenueRegistry.venues[review.venue].signingKey`, checks `block.timestamp < deadline`, checks no existing reply for that `reviewId`.
- New named reverts: `BadVenueSignature` (reused from `AttendanceGate`'s naming convention), `ReplyAlreadyExists`, `UnknownReview`.

### Subgraph changes
- `Review` entity gains nullable `replyHash: Bytes` and `repliedAt: BigInt` fields — no new entity type.
- No change to the `VenueStats` derivation approach beyond it now being able to read `venue` directly off `Review` instead of joining through `CheckIn`/`Settlement`.

### Frontend changes
- New `/leaderboard` route: table of venues, client-side sort toggle across settled-tier %, review count, average rating (dataset is small — 3 seeded venues for the demo — so no server-side sort/pagination needed).
- Review feed component renders a venue's reply inline under the review when `replyHash` is set.
- New venue-owner route to compose a reply; submission goes through an API route that uses the Privy server signer (existing key/policy) to produce the EIP-712 signature before submitting the transaction.

### Demo script changes
- **Scene 3** (settled bill, was 40s) extends to ~55s: after the review posts, cut to the venue owner replying, then back to the feed showing the reply appear live.
- **Scene 4** (query interface, was 35s, unchanged length): after the natural-language answer comes back, click through to `/leaderboard` sorted the same way, and close the demo there instead of on a single venue page.
- Total estimated runtime: ~2:55, still under the 3-minute target.

### Cut-list changes
New features are ordered *ahead* of the original spec's own fallbacks, since they're pure additions on top of an already-tight base:

1. Venue Reply (contract + demo beat) — revert Scene 3 to its original 40s if cut
2. Venue Leaderboard page — Scene 4 closes on the single venue page instead if cut
3. IPFS — put short review bodies directly on-chain as bytes (original spec, unchanged)
4. Venue self-registration UI — pre-register venues by script (original spec, unchanged)
5. Subgraph MCP — cut only if the subgraph itself is failing (original spec, unchanged)
6. Everything else load-bearing

### Timeline placement
No new day-block is introduced. The `Review`/`Reply` contract changes join Saturday morning's existing `ReviewRegistry` work (same test/deploy pass). The leaderboard page and reply UI join Saturday afternoon's existing frontend block.

## Out of scope (explicitly not pursued this round)
- A fourth/replacement sponsor track for the slot Arc leaves — user chose to keep exactly three.
- Trust/security hardening beyond what Venue Reply provides (e.g. dispute/slashing mechanisms) — user's focus areas were product depth and demo strategy, not the trust model itself.
- Reviewer cross-venue profile pages and rating-category breakdowns — considered during brainstorming as "ambitious" tier options, not selected given the "moderate" risk appetite chosen.
