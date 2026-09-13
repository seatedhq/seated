# SEATED — build spec
**ETHOnline 2026 · submission deadline Sunday 13 September, 12:00 EDT**

---

## 1. Pitch

> Restaurant reviews where every review is backed by cryptographic proof that the reviewer was actually at the table.

One sentence, no jargon, and a judge understands the problem in it. Roughly a third of reviews on the major platforms are fake, and nobody can check whether a reviewer ever set foot in the place. Seated makes attendance the precondition for speech.

---

## 2. The core mechanism

Two tiers of proof. Both are visible in the interface, always, on every review.

**Tier 1 — venue-signed check-in.**
You scan a QR code at the table. The restaurant's key signs an EIP-712 voucher saying you were seated. That voucher is what lets you post. Works at any restaurant on earth, needs no crypto adoption from the venue beyond a signing key.

**Tier 2 — settled bill.**
You pay the bill in USDC through the app. The settled payment is itself the attendance proof. Unforgeable, needs no trusted party, but only works where the venue accepts crypto.

**Proof of personhood sits across both.** World ID gives one human one review per venue per period. Without it, tier 1 is farmable by one person with many wallets.

### Why two tiers instead of one

Tier 2 alone is the pure answer and has almost no addressable world. Tier 1 alone reintroduces a trusted party — the restaurant can sign fake vouchers for itself. Running both, and showing which one backs each review, means the weak tier's weakness is visible and priced rather than hidden.

### The self-signing problem, and the answer

A judge will ask this. Have the answer ready.

A venue can sign vouchers for wallets that never came in. Three things constrain it:

1. **Capacity commitment.** On registration, the venue commits to `maxCoversPerDay` on-chain. The gate contract enforces it. A venue can fake up to its seating capacity but not beyond, and a 40-seat restaurant producing 400 reviews a week is arithmetically impossible.
2. **Public tier ratio.** Every venue page shows the share of its reviews backed by settled payment versus self-signed check-in. A venue with 100% self-signed reviews is publicly visible as such.
3. **Attestations are permanent and attributable.** A venue that fakes vouchers has signed a permanent, public record of doing so.

You are not claiming tier 1 is trustless. You are claiming it is *accountable*, which is strictly more than any Web2 review platform offers today.

---

## 3. Demo script

Four scenes, under three minutes. The adversarial scene is the one that matters — it's the pattern every ETHGlobal finalist this year shares.

**Scene 1 — the honest path (35s).**
Sign in with email. No seed phrase, no extension. Scan the table QR. Post a review. It appears with a check-in badge.

**Scene 2 — the review farm fails, live (50s).**
Run a script that spins up 50 wallets and fires 50 reviews at the same venue. Every one reverts on-chain. Show the revert reason: `NoAttendanceProof`. Then run a second attack — one human, 50 wallets, all with valid vouchers. World ID nullifier rejects 49 of them. Show the counter.

This is the scene. Do not cut it.

**Scene 3 — the settled bill, and a reply (55s).**
Pay a bill in USDC. The transfer confirms. The review posts with a gold settled-bill badge. Show the two badges side by side so the tier distinction is obvious without narration. Then cut to the venue owner's dashboard: they post a signed reply to the review. Cut back to the feed — the reply appears live under the review. This is the accountability loop from section 2 made visible: the same key that signs check-in vouchers just signed a permanent public reply.

**Scene 4 — the corpus, queried (35s).**
Open the query interface. Ask in plain language: *which venues have the highest share of payment-settled reviews*. The answer comes back from live indexed data. This is the Graph integration doing something a judge can see, rather than a JSON blob. Click through to the venue leaderboard, sorted the same way — the natural-language answer and the persistent product surface agree.

Close on the leaderboard.

Total estimated runtime: ~2:55.

---

## 4. Architecture

```
┌─────────────────────────────────────────────┐
│  Next.js frontend (Vercel)                  │
│  email login → embedded wallet              │
│  QR scan · review composer · venue pages    │
└────────────┬────────────────────────────────┘
             │
      ┌──────┴──────┬─────────────┐
      │             │             │
┌─────▼─────┐ ┌─────▼──────┐ ┌────▼─────────┐
│ Contracts │ │ World ID   │ │ Subgraph +   │
│           │ │ verifier   │ │ MCP query    │
└─────┬─────┘ └────────────┘ └──────────────┘
      │
 ┌────┴────────────────────────────────┐
 │ VenueRegistry · AttendanceGate      │
 │ ReviewRegistry · BillSettlement     │
 └─────────────────────────────────────┘
```

### Contracts

**`VenueRegistry.sol`**
Registers a venue: owner address, signing key, metadata URI, `maxCoversPerDay`. The signing key is separate from the owner so it can live on a phone or a server signer without holding funds.

```solidity
struct Venue {
    address owner;
    address signingKey;
    uint32  maxCoversPerDay;
    string  metadataURI;
    bool    active;
}
```

**`AttendanceGate.sol`**
The heart of it. Verifies an EIP-712 check-in voucher, enforces the daily cap, burns a nullifier so each voucher is single-use, and returns a `proofId` the review contract will accept.

```solidity
struct CheckIn {
    address venue;
    address diner;
    uint64  seatedAt;
    uint64  expiry;
    bytes32 salt;
}

// nullifier = keccak256(abi.encode(venue, diner, salt))
```

Checks in order: signature recovers to the venue's registered `signingKey`; `block.timestamp < expiry`; nullifier unused; daily counter for `venue` below `maxCoversPerDay`. Any failure reverts with a named error — the revert names are what you show on screen in Scene 2, so make them legible: `BadVenueSignature`, `VoucherExpired`, `VoucherUsed`, `CapacityExceeded`.

**`BillSettlement.sol`**
Records a USDC payment from diner to venue and emits a `proofId` of tier 2. Simplest correct version: the contract pulls USDC via `transferFrom` and forwards it to the venue in the same call, recording the amount and parties. Do not build an escrow. You do not have time and it adds no points.

**`ReviewRegistry.sol`**
Stores the review against its proof.

```solidity
struct Review {
    uint256 reviewId;       // auto-incrementing, assigned on post
    address venue;
    bytes32 proofId;        // from gate or settlement
    uint8   tier;           // 1 = check-in, 2 = settled bill
    uint8   rating;         // 1-5
    bytes32 contentHash;    // IPFS CID of the review body
    uint64  postedAt;
    uint256 worldIdNullifier;
}
```

Review bodies go to IPFS; only the hash goes on-chain. Keep gas boring.

**Venue reply.** One signed reply per review, using the same Privy-governed `signingKey` that signs check-in vouchers — the accountability loop from section 2 made concrete: the venue's own key produces a second permanent public artifact.

```solidity
struct Reply {
    bytes32 replyHash;      // IPFS CID of the reply body
    uint64  postedAt;
}

// postReply(reviewId, replyHash, deadline, signature)
// signature must recover to VenueRegistry.venues[review.venue].signingKey
```

Checks in order: review exists; no reply already recorded for `reviewId`; signature recovers to the review's venue's registered `signingKey`; `block.timestamp < deadline`. Reverts: `UnknownReview`, `ReplyAlreadyExists`, `BadVenueSignature`. Emits `ReplyPosted(reviewId, replyHash, postedAt)` for the subgraph.

**Venue leaderboard.** A `/leaderboard` frontend route, sortable client-side by settled-tier percentage, review count, and average rating — sourced entirely from the `VenueStats` subgraph entity below. No new contract surface.

### The World ID signal

Use the venue address as the World ID signal and an action of `post-review`. That gives one human one review *per venue*, not one review globally — which is what you actually want, since people eat at more than one restaurant.

---

## 5. Sponsor integrations

Three candidates, three submission slots. Below, each one with its qualification bar and how load-bearing it actually is.

### World — $7,000 · **keep**
Proof of personhood is not decoration here, it is the thing that stops the farm in Scene 2. Thematically the tightest match on the whole board. Use IDKit in the frontend and verify on-chain so the rejection is visible in a transaction rather than in your backend logs.

### The Graph — $15,000 · **keep**
Biggest pool. The bar is real: a single subgraph query does **not** qualify. You need two or more Graph products composed, on live data, with no mocked datasets.

Cheapest way to clear it:
- A subgraph indexing `VenueRegistered`, `CheckInRedeemed`, `BillSettled`, `ReviewPosted`, `ReplyPosted`.
- **Subgraph MCP** on top, so the natural-language query in Scene 4 runs against the live subgraph.

Two products, genuine composition, and the second one is the demo moment rather than plumbing. Entities to model: `Venue`, `CheckIn`, `Settlement`, `Review` (with nullable `replyHash`/`repliedAt` fields, and a direct `venue` reference so `VenueStats` doesn't need to join through `CheckIn`/`Settlement`), plus a derived `VenueStats` carrying the tier ratio so the frontend doesn't compute it client-side. `VenueStats` also backs the `/leaderboard` page.

Also required: public repo, and a 2–4 minute video.

### Privy — $5,000 · **keep, and it's better than I first said**
I told you earlier to cut this. I was wrong about how it fits. Privy's bar is to use at least one Privy *control* — policies, signers, key quorums, or intents — not just login.

The venue's signing key is exactly that. Run it as a Privy server signer with a policy that caps how many check-in vouchers it can sign per day, enforced off-chain by the policy and on-chain by `maxCoversPerDay`. That makes Privy structural rather than a login button, and it strengthens the self-signing answer in section 2.

Plus the ordinary use: email login, embedded wallet, no seed phrase for diners. Scene 1 depends on it.

**The three submitted slots: World, The Graph, Privy.** Tier 2 never required a sponsor slot in the first place — a USDC `transferFrom` is a plain ERC-20 call, so the settled-bill tier ships on any chain with USDC without touching a payments SDK. No fourth candidate needed.

---

## 6. Stack and deployment

| Layer | Choice |
|---|---|
| Contracts | Solidity 0.8.28, Foundry |
| Chain | Base Sepolia (testnet); production path is Base mainnet, no contract changes needed beyond redeployment and re-verification |
| Frontend | Next.js 15, wagmi + viem, deployed on Vercel |
| Auth/wallet | Privy embedded wallets |
| Personhood | World ID (IDKit), on-chain verification |
| Indexing | Graph subgraph + Subgraph MCP |
| Content | IPFS for review bodies |
| QR | Venue signs client-side; voucher encoded in the QR payload |

Keep it to one chain for the main flow. Cross-chain adds nothing to the story and will eat hours.

---

## 7. Two-day plan

You are at roughly 48 hours. This is tight but it is not a scratch build in the hard sense — the contracts are small.

**Friday night**
- Repo, Foundry scaffold, CI. Start committing immediately; incremental history matters.
- `VenueRegistry` + `AttendanceGate` written and unit-tested. EIP-712 domain fixed early — changing it later breaks the frontend.
- Deploy both to Base Sepolia, verified.

**Saturday morning**
- `ReviewRegistry` (including the `venue` field, `reviewId`, and `postReply`) + `BillSettlement`, tested, deployed, verified.
- Subgraph scaffolded against the deployed addresses and syncing. Do this early — subgraph sync problems are the classic Sunday-morning disaster.

**Saturday afternoon**
- Frontend: Privy login, venue page, QR scan, review composer, review feed with tier badges and inline venue replies, `/leaderboard` page.
- World ID wired into the post-review path.

**Saturday evening**
- The attack script for Scene 2. Write it as a real Foundry script or a node script, not a mock. It must genuinely fail on-chain.
- Subgraph MCP connected, Scene 4 query working.

**Sunday before 08:00 EDT**
- Seed realistic data: 3 venues, ~20 reviews across both tiers, so the tier ratio on a venue page is meaningful.
- Record the video. Do this before you are tired. Two takes maximum.
- README: architecture diagram, deployed addresses, what each sponsor SDK does.
- Deploy frontend, test the live link from a different device.

**Stop building at 08:00 EDT. Submit by 11:00, not 11:55.**

---

## 8. Known weaknesses, with prepared answers

**"The restaurant can fake check-ins."**
Yes, up to its committed seating capacity, and it does so on a permanent public record. The tier ratio on every venue page — and on the leaderboard — makes a self-signing venue visible. A venue can also reply to reviews with the same signing key, which is a second permanent artifact from the same accountable identity, not a separate trust mechanism. Tier 2 removes the problem entirely where crypto payment exists. No Web2 platform offers either property.

**"Nobody pays for dinner in USDC."**
Correct, today. That is why tier 1 exists and is the default path. Tier 2 is the stronger proof where it's available, not the required one.

**"What stops someone selling their check-in voucher?"**
The voucher binds to the diner address at signing time. Selling it means selling the account. World ID then caps that account to one review per venue regardless.

**"Reviews are subjective — what does on-chain give you?"**
Nothing about the opinion. Everything about the standing to have one. The claim is narrow and defensible: this person was at this table.

---

## 9. Cut list, in order

If you're behind, cut from the top. The venue reply and leaderboard are pure additions on top of the core product, so they go before any of the original fallbacks:

1. Venue reply (contract + demo beat) — revert Scene 3 to its original 40s
2. Venue leaderboard page — Scene 4 closes on the single venue page instead
3. IPFS — put short review bodies directly on-chain as bytes
4. Venue self-registration UI — pre-register venues by script
5. Subgraph MCP — costs you the Graph prize, so cut this only if the subgraph itself is failing
6. Everything else is load-bearing

Never cut: the attack script in Scene 2, the tier badges, World ID.

---

## 10. Admin checklist

- [ ] Public repo, real incremental commit history
- [ ] 2–4 minute demo video
- [ ] All contracts verified on the explorer
- [ ] README with architecture diagram and deployed addresses
- [ ] Frontend live on Vercel, tested from a second device
- [ ] Exactly three sponsor SDKs declared at submission
- [ ] No hard-coded values in the demo path
- [ ] Submitted by 11:00 EDT Sunday

---

## 11. Prior art

Checked. What exists on ETHGlobal's showcase is thin: a generic decentralised restaurant review project, a proof-of-testimonial tool using off-chain attestations, an on-chain code review tool, and one project using proof-of-personhood alone for review authenticity.

None of them gate reviews on venue-signed attendance, and none combine that with settled-payment proof as a second tier. The gap you're building into is real, but the personhood-only angle has been done — so the attendance gate, not World ID, is what you lead with in the pitch.
