# Venue metadata

Off-chain metadata for the demo venues. `VenueRegistry.registerVenue` stores only
a `metadataURI` string on-chain; everything a venue page displays lives here.

**This is permanent.** `VenueRegistry` has no `setMetadataURI`. Whatever URI a
venue registers with is that venue's identity for the life of the contract. Pin
these before seeding, and pin them somewhere durable.

## The venues

All three are **fictional**, flagged `"demoData": true`. They are registered on a
public chain with review data attached, so using a real restaurant's name and
address would create a permanent public record misrepresenting a real business.

| File | Name | `maxCoversPerDay` | `.env` slot |
|---|---|---|---|
| `venues/saltmarsh.json` | Saltmarsh | 40 | `VENUE_1_METADATA_URI` |
| `venues/cinder-and-rye.json` | Cinder & Rye | 120 | `VENUE_2_METADATA_URI` |
| `venues/counter-nine.json` | Counter Nine | 24 | `VENUE_3_METADATA_URI` |

The `maxCoversPerDay` in each file must match the value `script/SeedVenues.s.sol`
registers on-chain for that slot (40 / 120 / 24, in that order). The contract's
value is authoritative; the copy here is so a venue page can display the capacity
commitment without an extra RPC call.

**Counter Nine is the capacity story.** 24 covers a day is what makes "this venue
cannot have produced 400 reviews a week" arithmetic rather than assertion.

**Cinder & Rye is the demo venue.** The 50-wallet personhood scene must target it —
at 40 or 24 covers the surplus wallets fail in `AttendanceGate.redeem` with
`CapacityExceeded` before ever reaching `postReview`, which would show the wrong
revert and never exercise the World ID check.

## Schema

| Field | Notes |
|---|---|
| `schemaVersion` | `1`. Bump on any breaking change; the frontend should branch on it |
| `demoData` | `true` for seeded demo venues. Absent or `false` for real ones |
| `name` | Display name |
| `description` | One or two sentences for the venue page |
| `cuisine` | Array of tags, used for filtering |
| `priceBand` | `$` to `$$$$` |
| `maxCoversPerDay` | Must match the on-chain registration |
| `address` | `street`, `city`, `region`, `postalCode`, `country` (ISO-3166-1 alpha-2) |
| `geo` | `lat` / `lng`, for map pins |
| `contact` | `website` and `phone`, both nullable |
| `hours` | Free text for now |
| `image` | `ipfs://<cid>` or `null`. **The frontend must handle `null`** — these ship without photos |

## Pinning

Any pinning service works. With the web3.storage CLI:

```bash
w3 up metadata/venues/saltmarsh.json
w3 up metadata/venues/cinder-and-rye.json
w3 up metadata/venues/counter-nine.json
```

Or upload the three files through the Pinata web UI.

Then put the resulting CIDs in `.env` as `ipfs://<cid>`, matching the slots in the
table above, and run `script/SeedVenues.s.sol`.

Verify each URI resolves before seeding — a CID that 404s is baked in permanently:

```bash
curl -sL https://ipfs.io/ipfs/<cid> | jq .name
```
