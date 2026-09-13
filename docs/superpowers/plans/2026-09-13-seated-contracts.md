# SEATED Contracts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, test, and deploy the four Solidity contracts that make attendance a precondition for posting a restaurant review.

**Architecture:** `VenueRegistry` holds venue identity and the venue's separate signing key. `AttendanceGate` verifies EIP-712 check-in vouchers signed by that key, enforcing a daily capacity cap and single-use nullifiers, and records an attendance proof. `BillSettlement` records a USDC payment as an alternative (stronger) proof. `ReviewRegistry` accepts a review only when it can resolve a valid, unused, caller-owned proof from one of those two contracts, plus a World ID proof of personhood, and additionally lets a venue post one signed reply per review.

**Tech Stack:** Solidity 0.8.28, Foundry (forge/anvil/cast), OpenZeppelin Contracts v5 (ECDSA, EIP712, SafeERC20), World ID on-chain verifier, Base Sepolia.

## Global Constraints

- Solidity pragma is exactly `pragma solidity 0.8.28;` in every `.sol` file.
- EIP-712 domain is `name = "Seated"`, `version = "1"` in **every** contract that uses EIP-712. Fixing this now is load-bearing — changing it later breaks the frontend and any QR code already generated.
- Every revert is a named custom error, never a string. The error names appear on screen during the demo, so they must read as English: `BadVenueSignature`, `VoucherExpired`, `VoucherUsed`, `CapacityExceeded`, `NoAttendanceProof`.
- Chain is Base Sepolia (testnet). No cross-chain, no second chain.
- Tier constants are `1 = check-in`, `2 = settled bill`, everywhere, with no exceptions.
- Every state-changing function emits an event — the subgraph (Plan 2) indexes these and cannot read storage.
- Review bodies and reply bodies never go on-chain. Only a `bytes32` content hash does.
- Commit after every task. The hackathon submission checklist requires real incremental commit history.

## File Structure

| File | Responsibility |
|---|---|
| `foundry.toml` | Compiler version, optimizer, remappings, test config |
| `src/VenueRegistry.sol` | Venue identity, signing key, capacity commitment |
| `src/AttendanceGate.sol` | EIP-712 voucher verification, nullifiers, daily cap, tier-1 proofs |
| `src/BillSettlement.sol` | USDC transfer + tier-2 proofs |
| `src/ReviewRegistry.sol` | Review storage, proof resolution, World ID gate, venue replies |
| `src/interfaces/IWorldID.sol` | Minimal World ID verifier interface |
| `src/libraries/ByteHasher.sol` | Hash-to-field helper required by World ID |
| `test/mocks/MockUSDC.sol` | 6-decimal ERC-20 for settlement tests |
| `test/mocks/MockWorldID.sol` | Configurable World ID verifier for tests |
| `test/*.t.sol` | One test file per contract |
| `script/Deploy.s.sol` | Deploys all four contracts in dependency order |
| `script/SeedVenues.s.sol` | Registers the three demo venues |

---

### Task 1: Foundry scaffold, dependencies, CI

**Files:**
- Create: `foundry.toml`
- Create: `.github/workflows/ci.yml`
- Modify: `.gitignore`
- Create: `test/Scaffold.t.sol` (deleted at the end of this task)

**Interfaces:**
- Consumes: nothing (first task)
- Produces: a working `forge build` / `forge test` in the repo root, with `@openzeppelin/contracts/` and `forge-std/` remappings available to all later tasks.

- [ ] **Step 1: Initialize Foundry in the existing repo**

The repo already has files (the spec and design doc), so `forge init` needs `--force`. `--no-commit` keeps the spec commit clean.

```bash
cd "/home/linoux/eth online"
forge init --force --no-git
rm -rf src/Counter.sol script/Counter.s.sol test/Counter.t.sol
```

- [ ] **Step 2: Install OpenZeppelin Contracts v5**

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
```

- [ ] **Step 3: Write `foundry.toml`**

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
test = "test"
script = "script"
solc_version = "0.8.28"
optimizer = true
optimizer_runs = 200
via_ir = false
remappings = [
    "forge-std/=lib/forge-std/src/",
    "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/",
]

[fmt]
line_length = 120
tab_width = 4
bracket_spacing = false

[rpc_endpoints]
base_sepolia = "${BASE_SEPOLIA_RPC_URL}"

[etherscan]
base_sepolia = {key = "${ETHERSCAN_API_KEY}", chain = 84532}
```

- [ ] **Step 4: Append Foundry entries to `.gitignore`**

The file currently contains only `*:Zone.Identifier`. Append:

```
# Foundry
cache/
out/
broadcast/
docs/book/

# Secrets
.env
```

- [ ] **Step 5: Write a scaffold test to prove the toolchain works**

Create `test/Scaffold.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract ScaffoldTest is Test {
    function test_remappingsResolve() public {
        (address signer,,) = ECDSA.tryRecover(keccak256("seated"), hex"");
        assertEq(signer, address(0));
    }
}
```

- [ ] **Step 6: Run the scaffold test**

Run: `forge test --match-contract ScaffoldTest -vv`
Expected: PASS. If remappings are wrong this fails at compile time with "File not found".

- [ ] **Step 7: Delete the scaffold test**

It existed only to prove remappings resolve. Delete it so it does not accumulate.

```bash
rm test/Scaffold.t.sol
```

- [ ] **Step 8: Write CI workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - uses: foundry-rs/foundry-toolchain@v1

      - name: Check formatting
        run: forge fmt --check

      - name: Build
        run: forge build --sizes

      - name: Test
        run: forge test -vvv
```

- [ ] **Step 9: Verify the full build is clean**

Run: `forge fmt && forge build`
Expected: compiles with no errors. (`lib/` is gitignored by `forge init`'s own `.gitignore` handling — confirm `git status` does not list `lib/openzeppelin-contracts` contents individually. If it does, the install used submodules and that is fine; commit the `.gitmodules` file.)

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "chore: scaffold Foundry project with OpenZeppelin and CI"
```

---

### Task 2: VenueRegistry

**Files:**
- Create: `src/VenueRegistry.sol`
- Test: `test/VenueRegistry.t.sol`

**Interfaces:**
- Consumes: Task 1's build setup.
- Produces:
  - `struct Venue {address owner; address signingKey; uint32 maxCoversPerDay; string metadataURI; bool active;}`
  - `registerVenue(address signingKey, uint32 maxCoversPerDay, string calldata metadataURI) external`
  - `signingKeyOf(address venueId) external view returns (address)`
  - `ownerOf(address venueId) external view returns (address)`
  - `maxCoversPerDayOf(address venueId) external view returns (uint32)`
  - `isActive(address venueId) external view returns (bool)`
  - `getVenue(address venueId) external view returns (Venue memory)`
  - `event VenueRegistered(address indexed venueId, address indexed owner, address signingKey, uint32 maxCoversPerDay, string metadataURI)`

**Design note for the implementer:** a venue is identified by the address that registered it (`venueId == msg.sender` at registration). The `owner` field starts equal to that but is stored separately so ownership can move later without changing the venue's identity. The `signingKey` is deliberately a third address — it lives on a phone or a Privy server signer and never holds funds.

- [ ] **Step 1: Write the failing test**

Create `test/VenueRegistry.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";

contract VenueRegistryTest is Test {
    VenueRegistry internal registry;

    address internal venueId = makeAddr("venue");
    address internal signingKey = makeAddr("signingKey");
    address internal stranger = makeAddr("stranger");

    event VenueRegistered(
        address indexed venueId,
        address indexed owner,
        address signingKey,
        uint32 maxCoversPerDay,
        string metadataURI
    );

    function setUp() public {
        registry = new VenueRegistry();
    }

    function _register() internal {
        vm.prank(venueId);
        registry.registerVenue(signingKey, 40, "ipfs://venue-metadata");
    }

    function test_registerVenue_storesAllFields() public {
        _register();

        VenueRegistry.Venue memory v = registry.getVenue(venueId);
        assertEq(v.owner, venueId);
        assertEq(v.signingKey, signingKey);
        assertEq(v.maxCoversPerDay, 40);
        assertEq(v.metadataURI, "ipfs://venue-metadata");
        assertTrue(v.active);
    }

    function test_registerVenue_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit VenueRegistered(venueId, venueId, signingKey, 40, "ipfs://venue-metadata");

        vm.prank(venueId);
        registry.registerVenue(signingKey, 40, "ipfs://venue-metadata");
    }

    function test_registerVenue_revertsOnDoubleRegistration() public {
        _register();

        vm.prank(venueId);
        vm.expectRevert(VenueRegistry.VenueAlreadyRegistered.selector);
        registry.registerVenue(signingKey, 40, "ipfs://other");
    }

    function test_registerVenue_revertsOnZeroSigningKey() public {
        vm.prank(venueId);
        vm.expectRevert(VenueRegistry.ZeroSigningKey.selector);
        registry.registerVenue(address(0), 40, "ipfs://venue-metadata");
    }

    function test_registerVenue_revertsOnZeroCapacity() public {
        vm.prank(venueId);
        vm.expectRevert(VenueRegistry.ZeroCapacity.selector);
        registry.registerVenue(signingKey, 0, "ipfs://venue-metadata");
    }

    function test_setSigningKey_rotatesKey() public {
        _register();
        address newKey = makeAddr("newKey");

        vm.prank(venueId);
        registry.setSigningKey(venueId, newKey);

        assertEq(registry.signingKeyOf(venueId), newKey);
    }

    function test_setSigningKey_revertsForNonOwner() public {
        _register();

        vm.prank(stranger);
        vm.expectRevert(VenueRegistry.NotVenueOwner.selector);
        registry.setSigningKey(venueId, stranger);
    }

    function test_setActive_deactivatesVenue() public {
        _register();

        vm.prank(venueId);
        registry.setActive(venueId, false);

        assertFalse(registry.isActive(venueId));
    }

    function test_unregisteredVenue_readsAsInactive() public view {
        assertFalse(registry.isActive(venueId));
        assertEq(registry.signingKeyOf(venueId), address(0));
        assertEq(registry.maxCoversPerDayOf(venueId), 0);
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `forge test --match-contract VenueRegistryTest -vv`
Expected: FAIL at compile time — `Source "../src/VenueRegistry.sol" not found`.

- [ ] **Step 3: Write the implementation**

Create `src/VenueRegistry.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title VenueRegistry
/// @notice Registry of restaurants that can sign attendance vouchers.
/// @dev A venue is keyed by the address that registered it ("venueId"). The signing
///      key is separate from the owner so it can live on a phone or a server signer
///      without ever holding funds.
contract VenueRegistry {
    struct Venue {
        address owner;
        address signingKey;
        uint32 maxCoversPerDay;
        string metadataURI;
        bool active;
    }

    mapping(address => Venue) private _venues;

    event VenueRegistered(
        address indexed venueId,
        address indexed owner,
        address signingKey,
        uint32 maxCoversPerDay,
        string metadataURI
    );
    event SigningKeyUpdated(address indexed venueId, address newSigningKey);
    event VenueActiveSet(address indexed venueId, bool active);

    error VenueAlreadyRegistered();
    error VenueNotRegistered();
    error NotVenueOwner();
    error ZeroSigningKey();
    error ZeroCapacity();

    /// @notice Register the caller as a venue. The caller's address becomes the venue id.
    /// @param signingKey Address that will sign EIP-712 check-in vouchers.
    /// @param maxCoversPerDay Public capacity commitment enforced by AttendanceGate.
    /// @param metadataURI IPFS URI for name, address, cuisine, photos.
    function registerVenue(address signingKey, uint32 maxCoversPerDay, string calldata metadataURI) external {
        if (_venues[msg.sender].owner != address(0)) revert VenueAlreadyRegistered();
        if (signingKey == address(0)) revert ZeroSigningKey();
        if (maxCoversPerDay == 0) revert ZeroCapacity();

        _venues[msg.sender] = Venue({
            owner: msg.sender,
            signingKey: signingKey,
            maxCoversPerDay: maxCoversPerDay,
            metadataURI: metadataURI,
            active: true
        });

        emit VenueRegistered(msg.sender, msg.sender, signingKey, maxCoversPerDay, metadataURI);
    }

    function setSigningKey(address venueId, address newSigningKey) external {
        Venue storage v = _venues[venueId];
        if (v.owner == address(0)) revert VenueNotRegistered();
        if (v.owner != msg.sender) revert NotVenueOwner();
        if (newSigningKey == address(0)) revert ZeroSigningKey();

        v.signingKey = newSigningKey;
        emit SigningKeyUpdated(venueId, newSigningKey);
    }

    function setActive(address venueId, bool active) external {
        Venue storage v = _venues[venueId];
        if (v.owner == address(0)) revert VenueNotRegistered();
        if (v.owner != msg.sender) revert NotVenueOwner();

        v.active = active;
        emit VenueActiveSet(venueId, active);
    }

    function getVenue(address venueId) external view returns (Venue memory) {
        return _venues[venueId];
    }

    function signingKeyOf(address venueId) external view returns (address) {
        return _venues[venueId].signingKey;
    }

    function ownerOf(address venueId) external view returns (address) {
        return _venues[venueId].owner;
    }

    function maxCoversPerDayOf(address venueId) external view returns (uint32) {
        return _venues[venueId].maxCoversPerDay;
    }

    function isActive(address venueId) external view returns (bool) {
        return _venues[venueId].active;
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `forge test --match-contract VenueRegistryTest -vv`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
forge fmt
git add src/VenueRegistry.sol test/VenueRegistry.t.sol
git commit -m "feat: add VenueRegistry with capacity commitment and separate signing key"
```

---

### Task 3: AttendanceGate

**Files:**
- Create: `src/AttendanceGate.sol`
- Test: `test/AttendanceGate.t.sol`

**Interfaces:**
- Consumes: `VenueRegistry` (`isActive`, `signingKeyOf`, `maxCoversPerDayOf`) from Task 2.
- Produces:
  - `struct CheckIn {address venue; address diner; uint64 seatedAt; uint64 expiry; bytes32 salt;}`
  - `struct AttendanceProof {address venue; address diner; uint64 redeemedAt;}`
  - `constructor(VenueRegistry registry_)`
  - `hashCheckIn(CheckIn calldata checkIn) external view returns (bytes32)` — the EIP-712 digest; the frontend and tests both sign this
  - `redeem(CheckIn calldata checkIn, bytes calldata signature) external returns (bytes32 proofId)`
  - `proofOf(bytes32 proofId) external view returns (AttendanceProof memory)`
  - `event CheckInRedeemed(bytes32 indexed proofId, address indexed venue, address indexed diner, uint64 seatedAt, uint64 redeemedAt)`

**Design notes for the implementer:**
- `proofId` **is** the nullifier: `keccak256(abi.encode(venue, diner, salt))`. One voucher, one proof, one redemption.
- Check order is fixed by the spec and the demo depends on it: signature → expiry → nullifier → capacity.
- Use `ECDSA.tryRecover`, not `ECDSA.recover`. `recover` reverts with OpenZeppelin's own error on a malformed signature, which would put an illegible error on screen. `tryRecover` lets a bad signature surface as `BadVenueSignature`.
- The daily counter buckets by `block.timestamp / 1 days`. That is UTC-aligned, not restaurant-local — acceptable and worth a code comment.

- [ ] **Step 1: Write the failing test**

Create `test/AttendanceGate.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {AttendanceGate} from "../src/AttendanceGate.sol";

contract AttendanceGateTest is Test {
    VenueRegistry internal registry;
    AttendanceGate internal gate;

    address internal venueId = makeAddr("venue");
    address internal diner = makeAddr("diner");

    uint256 internal signerPk = 0xA11CE;
    address internal signingKey;

    uint32 internal constant CAPACITY = 3;

    function setUp() public {
        signingKey = vm.addr(signerPk);

        registry = new VenueRegistry();
        gate = new AttendanceGate(registry);

        vm.prank(venueId);
        registry.registerVenue(signingKey, CAPACITY, "ipfs://venue");

        // Move off timestamp 0 so `expiry` arithmetic is meaningful.
        vm.warp(1_800_000_000);
    }

    function _voucher(address diner_, bytes32 salt) internal view returns (AttendanceGate.CheckIn memory) {
        return AttendanceGate.CheckIn({
            venue: venueId,
            diner: diner_,
            seatedAt: uint64(block.timestamp),
            expiry: uint64(block.timestamp + 2 hours),
            salt: salt
        });
    }

    function _sign(AttendanceGate.CheckIn memory checkIn, uint256 pk) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, gate.hashCheckIn(checkIn));
        return abi.encodePacked(r, s, v);
    }

    function test_redeem_storesProofAndReturnsNullifierAsProofId() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));

        vm.prank(diner);
        bytes32 proofId = gate.redeem(c, _sign(c, signerPk));

        assertEq(proofId, keccak256(abi.encode(venueId, diner, c.salt)));

        AttendanceGate.AttendanceProof memory p = gate.proofOf(proofId);
        assertEq(p.venue, venueId);
        assertEq(p.diner, diner);
        assertEq(p.redeemedAt, uint64(block.timestamp));
    }

    function test_redeem_revertsOnWrongSigner() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        uint256 attackerPk = 0xBAD;

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.BadVenueSignature.selector);
        gate.redeem(c, _sign(c, attackerPk));
    }

    function test_redeem_revertsOnMalformedSignature() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.BadVenueSignature.selector);
        gate.redeem(c, hex"deadbeef");
    }

    function test_redeem_revertsWhenExpired() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        bytes memory sig = _sign(c, signerPk);

        vm.warp(c.expiry + 1);

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.VoucherExpired.selector);
        gate.redeem(c, sig);
    }

    function test_redeem_revertsOnReplay() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        bytes memory sig = _sign(c, signerPk);

        vm.prank(diner);
        gate.redeem(c, sig);

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.VoucherUsed.selector);
        gate.redeem(c, sig);
    }

    function test_redeem_revertsWhenCallerIsNotTheNamedDiner() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        bytes memory sig = _sign(c, signerPk);

        vm.prank(makeAddr("someoneElse"));
        vm.expectRevert(AttendanceGate.NotVoucherDiner.selector);
        gate.redeem(c, sig);
    }

    function test_redeem_enforcesDailyCapacity() public {
        // Fill the venue to its committed capacity with distinct diners.
        for (uint256 i = 0; i < CAPACITY; i++) {
            address d = address(uint160(0x1000 + i));
            AttendanceGate.CheckIn memory c = _voucher(d, bytes32(i));
            vm.prank(d);
            gate.redeem(c, _sign(c, signerPk));
        }

        address overflowDiner = address(uint160(0x2000));
        AttendanceGate.CheckIn memory overflow = _voucher(overflowDiner, bytes32(uint256(99)));

        vm.prank(overflowDiner);
        vm.expectRevert(AttendanceGate.CapacityExceeded.selector);
        gate.redeem(overflow, _sign(overflow, signerPk));
    }

    function test_redeem_capacityResetsNextDay() public {
        for (uint256 i = 0; i < CAPACITY; i++) {
            address d = address(uint160(0x1000 + i));
            AttendanceGate.CheckIn memory c = _voucher(d, bytes32(i));
            vm.prank(d);
            gate.redeem(c, _sign(c, signerPk));
        }

        vm.warp(block.timestamp + 1 days);

        address nextDayDiner = address(uint160(0x3000));
        AttendanceGate.CheckIn memory c2 = _voucher(nextDayDiner, bytes32(uint256(77)));

        vm.prank(nextDayDiner);
        bytes32 proofId = gate.redeem(c2, _sign(c2, signerPk));

        assertEq(gate.proofOf(proofId).diner, nextDayDiner);
    }

    function test_redeem_revertsForInactiveVenue() public {
        vm.prank(venueId);
        registry.setActive(venueId, false);

        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.VenueNotActive.selector);
        gate.redeem(c, _sign(c, signerPk));
    }

    function test_proofOf_unknownIdIsEmpty() public view {
        AttendanceGate.AttendanceProof memory p = gate.proofOf(bytes32(uint256(0xdead)));
        assertEq(p.redeemedAt, 0);
        assertEq(p.venue, address(0));
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `forge test --match-contract AttendanceGateTest -vv`
Expected: FAIL at compile time — `Source "../src/AttendanceGate.sol" not found`.

- [ ] **Step 3: Write the implementation**

Create `src/AttendanceGate.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {VenueRegistry} from "./VenueRegistry.sol";

/// @title AttendanceGate
/// @notice Turns a venue-signed EIP-712 check-in voucher into a single-use, capped
///         attendance proof that ReviewRegistry will accept as tier 1.
contract AttendanceGate is EIP712 {
    struct CheckIn {
        address venue;
        address diner;
        uint64 seatedAt;
        uint64 expiry;
        bytes32 salt;
    }

    struct AttendanceProof {
        address venue;
        address diner;
        uint64 redeemedAt;
    }

    bytes32 public constant CHECKIN_TYPEHASH =
        keccak256("CheckIn(address venue,address diner,uint64 seatedAt,uint64 expiry,bytes32 salt)");

    VenueRegistry public immutable registry;

    mapping(bytes32 => AttendanceProof) private _proofs;
    /// @dev nullifier => redeemed. The nullifier doubles as the proofId.
    mapping(bytes32 => bool) public nullifierUsed;
    /// @dev venue => UTC day index => covers redeemed that day.
    mapping(address => mapping(uint256 => uint32)) public coversOnDay;

    event CheckInRedeemed(
        bytes32 indexed proofId, address indexed venue, address indexed diner, uint64 seatedAt, uint64 redeemedAt
    );

    error BadVenueSignature();
    error VoucherExpired();
    error VoucherUsed();
    error CapacityExceeded();
    error VenueNotActive();
    error NotVoucherDiner();

    constructor(VenueRegistry registry_) EIP712("Seated", "1") {
        registry = registry_;
    }

    /// @notice EIP-712 digest the venue's signing key must sign. Exposed so the
    ///         frontend builds the QR payload against the same hash the gate checks.
    function hashCheckIn(CheckIn calldata checkIn) external view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CHECKIN_TYPEHASH, checkIn.venue, checkIn.diner, checkIn.seatedAt, checkIn.expiry, checkIn.salt
                )
            )
        );
    }

    /// @notice Redeem a check-in voucher for an attendance proof.
    /// @dev Check order is deliberate and demo-visible: signature, expiry, replay, capacity.
    function redeem(CheckIn calldata checkIn, bytes calldata signature) external returns (bytes32 proofId) {
        if (msg.sender != checkIn.diner) revert NotVoucherDiner();
        if (!registry.isActive(checkIn.venue)) revert VenueNotActive();

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CHECKIN_TYPEHASH, checkIn.venue, checkIn.diner, checkIn.seatedAt, checkIn.expiry, checkIn.salt
                )
            )
        );
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || signer != registry.signingKeyOf(checkIn.venue)) {
            revert BadVenueSignature();
        }

        if (block.timestamp >= checkIn.expiry) revert VoucherExpired();

        bytes32 nullifier = keccak256(abi.encode(checkIn.venue, checkIn.diner, checkIn.salt));
        if (nullifierUsed[nullifier]) revert VoucherUsed();

        // Capacity buckets are UTC days, not restaurant-local days. Good enough:
        // the commitment is an order-of-magnitude honesty check, not an audit.
        uint256 day = block.timestamp / 1 days;
        uint32 used = coversOnDay[checkIn.venue][day];
        if (used >= registry.maxCoversPerDayOf(checkIn.venue)) revert CapacityExceeded();

        nullifierUsed[nullifier] = true;
        coversOnDay[checkIn.venue][day] = used + 1;

        proofId = nullifier;
        _proofs[proofId] =
            AttendanceProof({venue: checkIn.venue, diner: checkIn.diner, redeemedAt: uint64(block.timestamp)});

        emit CheckInRedeemed(proofId, checkIn.venue, checkIn.diner, checkIn.seatedAt, uint64(block.timestamp));
    }

    function proofOf(bytes32 proofId) external view returns (AttendanceProof memory) {
        return _proofs[proofId];
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `forge test --match-contract AttendanceGateTest -vv`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
forge fmt
git add src/AttendanceGate.sol test/AttendanceGate.t.sol
git commit -m "feat: add AttendanceGate with EIP-712 vouchers, nullifiers and daily cap"
```

---

### Task 4: BillSettlement

**Files:**
- Create: `src/BillSettlement.sol`
- Create: `test/mocks/MockUSDC.sol`
- Test: `test/BillSettlement.t.sol`

**Interfaces:**
- Consumes: `VenueRegistry` (`isActive`, `ownerOf`) from Task 2.
- Produces:
  - `struct SettlementProof {address venue; address diner; uint256 amount; uint64 settledAt;}`
  - `constructor(VenueRegistry registry_, IERC20 usdc_)`
  - `settle(address venue, uint256 amount) external returns (bytes32 proofId)`
  - `proofOf(bytes32 proofId) external view returns (SettlementProof memory)`
  - `event BillSettled(bytes32 indexed proofId, address indexed venue, address indexed diner, uint256 amount, uint64 settledAt)`

**Design note for the implementer:** no escrow. The contract moves USDC from the diner straight to the venue owner in one `transferFrom` and records that it happened. An escrow adds days of work and zero points. `settlementCount` is an incrementing nonce that guarantees `proofId` uniqueness when the same diner pays the same venue the same amount twice in one block.

- [ ] **Step 1: Write the mock USDC**

Create `test/mocks/MockUSDC.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Six decimals, matching real USDC.
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
```

- [ ] **Step 2: Write the failing test**

Create `test/BillSettlement.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {BillSettlement} from "../src/BillSettlement.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract BillSettlementTest is Test {
    VenueRegistry internal registry;
    BillSettlement internal settlement;
    MockUSDC internal usdc;

    address internal venueId = makeAddr("venue");
    address internal diner = makeAddr("diner");

    uint256 internal constant BILL = 42_500_000; // 42.50 USDC

    function setUp() public {
        registry = new VenueRegistry();
        usdc = new MockUSDC();
        settlement = new BillSettlement(registry, IERC20(address(usdc)));

        vm.prank(venueId);
        registry.registerVenue(makeAddr("signingKey"), 40, "ipfs://venue");

        usdc.mint(diner, 1_000_000_000);
        vm.prank(diner);
        usdc.approve(address(settlement), type(uint256).max);

        vm.warp(1_800_000_000);
    }

    function test_settle_movesUsdcToVenueOwner() public {
        vm.prank(diner);
        settlement.settle(venueId, BILL);

        assertEq(usdc.balanceOf(venueId), BILL);
        assertEq(usdc.balanceOf(diner), 1_000_000_000 - BILL);
        assertEq(usdc.balanceOf(address(settlement)), 0, "settlement must not hold funds");
    }

    function test_settle_recordsProof() public {
        vm.prank(diner);
        bytes32 proofId = settlement.settle(venueId, BILL);

        BillSettlement.SettlementProof memory p = settlement.proofOf(proofId);
        assertEq(p.venue, venueId);
        assertEq(p.diner, diner);
        assertEq(p.amount, BILL);
        assertEq(p.settledAt, uint64(block.timestamp));
    }

    function test_settle_producesUniqueProofIdsForIdenticalPaymentsInSameBlock() public {
        vm.prank(diner);
        bytes32 first = settlement.settle(venueId, BILL);

        vm.prank(diner);
        bytes32 second = settlement.settle(venueId, BILL);

        assertTrue(first != second, "proofId collision");
    }

    function test_settle_revertsOnZeroAmount() public {
        vm.prank(diner);
        vm.expectRevert(BillSettlement.ZeroAmount.selector);
        settlement.settle(venueId, 0);
    }

    function test_settle_revertsForInactiveVenue() public {
        vm.prank(venueId);
        registry.setActive(venueId, false);

        vm.prank(diner);
        vm.expectRevert(BillSettlement.VenueNotActive.selector);
        settlement.settle(venueId, BILL);
    }

    function test_settle_revertsWithoutAllowance() public {
        address broke = makeAddr("broke");
        usdc.mint(broke, BILL);

        vm.prank(broke);
        vm.expectRevert();
        settlement.settle(venueId, BILL);
    }

    function test_proofOf_unknownIdIsEmpty() public view {
        BillSettlement.SettlementProof memory p = settlement.proofOf(bytes32(uint256(0xdead)));
        assertEq(p.settledAt, 0);
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `forge test --match-contract BillSettlementTest -vv`
Expected: FAIL at compile time — `Source "../src/BillSettlement.sol" not found`.

- [ ] **Step 4: Write the implementation**

Create `src/BillSettlement.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VenueRegistry} from "./VenueRegistry.sol";

/// @title BillSettlement
/// @notice Records a USDC bill payment as a tier-2 attendance proof.
/// @dev Deliberately not an escrow. Funds move diner -> venue owner in one call;
///      the contract never holds a balance.
contract BillSettlement {
    using SafeERC20 for IERC20;

    struct SettlementProof {
        address venue;
        address diner;
        uint256 amount;
        uint64 settledAt;
    }

    VenueRegistry public immutable registry;
    IERC20 public immutable usdc;

    /// @dev Nonce ensuring proofId uniqueness for identical payments in one block.
    uint256 public settlementCount;

    mapping(bytes32 => SettlementProof) private _proofs;

    event BillSettled(
        bytes32 indexed proofId, address indexed venue, address indexed diner, uint256 amount, uint64 settledAt
    );

    error VenueNotActive();
    error ZeroAmount();

    constructor(VenueRegistry registry_, IERC20 usdc_) {
        registry = registry_;
        usdc = usdc_;
    }

    /// @notice Pay a venue's bill in USDC and receive a tier-2 proof.
    function settle(address venue, uint256 amount) external returns (bytes32 proofId) {
        if (!registry.isActive(venue)) revert VenueNotActive();
        if (amount == 0) revert ZeroAmount();

        usdc.safeTransferFrom(msg.sender, registry.ownerOf(venue), amount);

        proofId = keccak256(abi.encode(venue, msg.sender, amount, block.timestamp, settlementCount));
        unchecked {
            settlementCount += 1;
        }

        _proofs[proofId] =
            SettlementProof({venue: venue, diner: msg.sender, amount: amount, settledAt: uint64(block.timestamp)});

        emit BillSettled(proofId, venue, msg.sender, amount, uint64(block.timestamp));
    }

    function proofOf(bytes32 proofId) external view returns (SettlementProof memory) {
        return _proofs[proofId];
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `forge test --match-contract BillSettlementTest -vv`
Expected: PASS, 7 tests.

- [ ] **Step 6: Commit**

```bash
forge fmt
git add src/BillSettlement.sol test/BillSettlement.t.sol test/mocks/MockUSDC.sol
git commit -m "feat: add BillSettlement recording USDC payments as tier-2 proofs"
```

---

### Task 5: ReviewRegistry — posting reviews

**Files:**
- Create: `src/interfaces/IWorldID.sol`
- Create: `src/libraries/ByteHasher.sol`
- Create: `src/ReviewRegistry.sol`
- Create: `test/mocks/MockWorldID.sol`
- Test: `test/ReviewRegistry.t.sol`

**Interfaces:**
- Consumes: `VenueRegistry` (Task 2), `AttendanceGate.proofOf` + `AttendanceGate.AttendanceProof` (Task 3), `BillSettlement.proofOf` + `BillSettlement.SettlementProof` (Task 4).
- Produces:
  - `struct Review {uint256 reviewId; address venue; bytes32 proofId; uint8 tier; uint8 rating; bytes32 contentHash; uint64 postedAt; uint256 worldIdNullifier;}`
  - `constructor(VenueRegistry registry_, AttendanceGate gate_, BillSettlement settlement_, IWorldID worldId_, string memory appId, string memory action)`
  - `postReview(address venue, bytes32 proofId, uint8 tier, uint8 rating, bytes32 contentHash, uint256 worldIdRoot, uint256 worldIdNullifier, uint256[8] calldata worldIdProof) external returns (uint256 reviewId)`
  - `getReview(uint256 reviewId) external view returns (Review memory)`
  - `reviewCount() external view returns (uint256)`
  - `event ReviewPosted(uint256 indexed reviewId, address indexed venue, address indexed diner, bytes32 proofId, uint8 tier, uint8 rating, bytes32 contentHash, uint64 postedAt, uint256 worldIdNullifier)`
- Task 6 extends this same contract with replies.

**Design notes for the implementer — read before writing code:**

1. **World ID gives per-venue uniqueness via the storage key, not the action string.** A World ID `nullifierHash` is derived from the identity and the external nullifier (app id + action); the *signal* does not enter it. So with a fixed action `post-review`, one human has one stable nullifier across all venues. Per-venue uniqueness therefore comes from keying the used-map as `venueNullifierUsed[venue][nullifierHash]` — the same human's nullifier can be spent once at each venue. The venue address is passed as the *signal*, which binds the proof to the venue it was generated for.
2. **Check order is demo-critical.** Scene 2 attack 1 (wallets with no voucher at all) must revert `NoAttendanceProof`, so proof resolution comes before World ID verification. Scene 2 attack 2 (one human, 50 wallets, all holding valid vouchers) must revert `AlreadyReviewedVenue`, which therefore comes after proof resolution.
3. `reviewId` starts at 1, never 0, so `postedAt == 0` is an unambiguous "no such review" sentinel for Task 6.

- [ ] **Step 1: Write the World ID interface**

Create `src/interfaces/IWorldID.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal surface of the World ID router needed for on-chain verification.
/// @dev Reverts on an invalid proof; returns nothing on success.
interface IWorldID {
    function verifyProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifierHash,
        uint256[8] calldata proof
    ) external view;
}
```

- [ ] **Step 2: Write the ByteHasher library**

Create `src/libraries/ByteHasher.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library ByteHasher {
    /// @dev Hashes bytes into a field element of the BN254 scalar field, which is
    ///      what World ID's circuits expect. Shifting right by 8 bits keeps the
    ///      result below the field modulus.
    function hashToField(bytes memory value) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(value))) >> 8;
    }
}
```

- [ ] **Step 3: Write the mock World ID verifier**

The real router's `verifyProof` is `view`, so this mock cannot record calls into storage. Tests assert on the signal with `vm.expectCall` instead, which is why the mock only needs to model accept/reject.

Create `test/mocks/MockWorldID.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IWorldID} from "../../src/interfaces/IWorldID.sol";

/// @dev Test double for the World ID router. `verifyProof` is `view` on the real
///      router, so this mock cannot record calls — tests assert on the signal by
///      recomputing the expected hash and using `vm.expectCall`.
contract MockWorldID is IWorldID {
    error MockWorldIdRejected();

    bool public shouldReject;

    function setShouldReject(bool value) external {
        shouldReject = value;
    }

    function verifyProof(uint256, uint256, uint256, uint256, uint256, uint256[8] calldata) external view {
        if (shouldReject) revert MockWorldIdRejected();
    }
}
```

- [ ] **Step 4: Write the failing test**

Create `test/ReviewRegistry.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {AttendanceGate} from "../src/AttendanceGate.sol";
import {BillSettlement} from "../src/BillSettlement.sol";
import {ReviewRegistry} from "../src/ReviewRegistry.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";
import {ByteHasher} from "../src/libraries/ByteHasher.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockWorldID} from "./mocks/MockWorldID.sol";

contract ReviewRegistryTest is Test {
    using ByteHasher for bytes;

    VenueRegistry internal registry;
    AttendanceGate internal gate;
    BillSettlement internal settlement;
    ReviewRegistry internal reviews;
    MockUSDC internal usdc;
    MockWorldID internal worldId;

    address internal venueId = makeAddr("venue");
    address internal otherVenueId = makeAddr("otherVenue");
    address internal diner = makeAddr("diner");

    uint256 internal signerPk = 0xA11CE;
    address internal signingKey;

    uint256 internal constant WORLD_ROOT = 111;
    uint256 internal constant NULLIFIER = 222;
    uint256[8] internal zeroProof;

    bytes32 internal constant CONTENT = keccak256("the sea bass was excellent");

    function setUp() public {
        signingKey = vm.addr(signerPk);

        registry = new VenueRegistry();
        gate = new AttendanceGate(registry);
        usdc = new MockUSDC();
        settlement = new BillSettlement(registry, IERC20(address(usdc)));
        worldId = new MockWorldID();
        reviews = new ReviewRegistry(registry, gate, settlement, IWorldID(address(worldId)), "app_seated", "post-review");

        vm.prank(venueId);
        registry.registerVenue(signingKey, 40, "ipfs://venue");
        vm.prank(otherVenueId);
        registry.registerVenue(signingKey, 40, "ipfs://other");

        usdc.mint(diner, 1_000_000_000);
        vm.prank(diner);
        usdc.approve(address(settlement), type(uint256).max);

        vm.warp(1_800_000_000);
    }

    function _redeemCheckIn(address venue, address diner_, bytes32 salt) internal returns (bytes32) {
        AttendanceGate.CheckIn memory c = AttendanceGate.CheckIn({
            venue: venue,
            diner: diner_,
            seatedAt: uint64(block.timestamp),
            expiry: uint64(block.timestamp + 2 hours),
            salt: salt
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, gate.hashCheckIn(c));

        vm.prank(diner_);
        return gate.redeem(c, abi.encodePacked(r, s, v));
    }

    function _post(address caller, address venue, bytes32 proofId, uint8 tier, uint256 nullifier)
        internal
        returns (uint256)
    {
        vm.prank(caller);
        return reviews.postReview(venue, proofId, tier, 5, CONTENT, WORLD_ROOT, nullifier, zeroProof);
    }

    // --- tier 1 ---

    function test_postReview_tier1_storesReview() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));
        uint256 id = _post(diner, venueId, proofId, 1, NULLIFIER);

        assertEq(id, 1, "review ids start at 1");

        ReviewRegistry.Review memory r = reviews.getReview(id);
        assertEq(r.reviewId, 1);
        assertEq(r.venue, venueId);
        assertEq(r.proofId, proofId);
        assertEq(r.tier, 1);
        assertEq(r.rating, 5);
        assertEq(r.contentHash, CONTENT);
        assertEq(r.postedAt, uint64(block.timestamp));
        assertEq(r.worldIdNullifier, NULLIFIER);
    }

    /// The Scene 2 attack: a wallet with no voucher at all.
    function test_postReview_revertsWithNoAttendanceProof_forUnknownProofId() public {
        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.NoAttendanceProof.selector);
        reviews.postReview(venueId, bytes32(uint256(0xdead)), 1, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    function test_postReview_revertsWhenProofBelongsToSomeoneElse() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(makeAddr("thief"));
        vm.expectRevert(ReviewRegistry.ProofNotOwnedByCaller.selector);
        reviews.postReview(venueId, proofId, 1, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    function test_postReview_revertsWhenProofIsForADifferentVenue() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.VenueMismatch.selector);
        reviews.postReview(otherVenueId, proofId, 1, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    function test_postReview_revertsWhenProofAlreadySpent() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));
        _post(diner, venueId, proofId, 1, NULLIFIER);

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.ProofAlreadyUsed.selector);
        reviews.postReview(venueId, proofId, 1, 5, CONTENT, WORLD_ROOT, NULLIFIER + 1, zeroProof);
    }

    // --- the Scene 2 sybil defence ---

    /// One human, many wallets, every wallet holding a genuinely valid voucher.
    /// The first review lands; all the others are rejected by the World ID nullifier.
    function test_postReview_oneHumanCannotReviewSameVenueTwice() public {
        address walletA = address(uint160(0x1000));
        address walletB = address(uint160(0x1001));

        bytes32 proofA = _redeemCheckIn(venueId, walletA, bytes32(uint256(1)));
        bytes32 proofB = _redeemCheckIn(venueId, walletB, bytes32(uint256(2)));

        _post(walletA, venueId, proofA, 1, NULLIFIER);

        vm.prank(walletB);
        vm.expectRevert(ReviewRegistry.AlreadyReviewedVenue.selector);
        reviews.postReview(venueId, proofB, 1, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    /// ...but the same human may review a *different* venue.
    function test_postReview_sameHumanMayReviewADifferentVenue() public {
        bytes32 proofHere = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));
        bytes32 proofThere = _redeemCheckIn(otherVenueId, diner, bytes32(uint256(2)));

        _post(diner, venueId, proofHere, 1, NULLIFIER);
        uint256 second = _post(diner, otherVenueId, proofThere, 1, NULLIFIER);

        assertEq(second, 2);
    }

    function test_postReview_revertsWhenWorldIdProofIsInvalid() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));
        worldId.setShouldReject(true);

        vm.prank(diner);
        vm.expectRevert(MockWorldID.MockWorldIdRejected.selector);
        reviews.postReview(venueId, proofId, 1, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    /// The World ID signal must be the venue, so a proof cannot be replayed elsewhere.
    function test_postReview_passesVenueAsWorldIdSignal() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.expectCall(
            address(worldId),
            abi.encodeWithSelector(
                IWorldID.verifyProof.selector,
                WORLD_ROOT,
                uint256(1),
                abi.encodePacked(venueId).hashToField(),
                NULLIFIER,
                reviews.externalNullifierHash(),
                zeroProof
            )
        );

        _post(diner, venueId, proofId, 1, NULLIFIER);
    }

    // --- tier 2 ---

    function test_postReview_tier2_acceptsSettlementProof() public {
        vm.prank(diner);
        bytes32 proofId = settlement.settle(venueId, 42_500_000);

        uint256 id = _post(diner, venueId, proofId, 2, NULLIFIER);

        ReviewRegistry.Review memory r = reviews.getReview(id);
        assertEq(r.tier, 2);
        assertEq(r.proofId, proofId);
    }

    function test_postReview_tier2_revertsForUnknownSettlement() public {
        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.NoSettlementProof.selector);
        reviews.postReview(venueId, bytes32(uint256(0xdead)), 2, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    /// A tier-1 proofId must not be accepted when the caller claims tier 2.
    function test_postReview_revertsWhenTierDoesNotMatchProofSource() public {
        bytes32 checkInProof = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.NoSettlementProof.selector);
        reviews.postReview(venueId, checkInProof, 2, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    // --- validation ---

    function test_postReview_revertsOnInvalidTier() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.InvalidTier.selector);
        reviews.postReview(venueId, proofId, 3, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    function test_postReview_revertsOnRatingZero() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.InvalidRating.selector);
        reviews.postReview(venueId, proofId, 1, 0, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    function test_postReview_revertsOnRatingAboveFive() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.InvalidRating.selector);
        reviews.postReview(venueId, proofId, 1, 6, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }
}
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `forge test --match-contract ReviewRegistryTest -vv`
Expected: FAIL at compile time — `Source "../src/ReviewRegistry.sol" not found`.

- [ ] **Step 6: Write the implementation**

Create `src/ReviewRegistry.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {VenueRegistry} from "./VenueRegistry.sol";
import {AttendanceGate} from "./AttendanceGate.sol";
import {BillSettlement} from "./BillSettlement.sol";
import {IWorldID} from "./interfaces/IWorldID.sol";
import {ByteHasher} from "./libraries/ByteHasher.sol";

/// @title ReviewRegistry
/// @notice Reviews, each bound to a proof that the reviewer was actually there.
/// @dev Extends EIP712 for the venue-reply signature added in Task 6.
contract ReviewRegistry is EIP712 {
    using ByteHasher for bytes;

    struct Review {
        uint256 reviewId;
        address venue;
        bytes32 proofId;
        uint8 tier;
        uint8 rating;
        bytes32 contentHash;
        uint64 postedAt;
        uint256 worldIdNullifier;
    }

    uint8 public constant TIER_CHECKIN = 1;
    uint8 public constant TIER_SETTLED = 2;

    /// @dev World ID's Orb-verified group.
    uint256 internal constant WORLD_ID_GROUP_ID = 1;

    VenueRegistry public immutable registry;
    AttendanceGate public immutable gate;
    BillSettlement public immutable settlement;
    IWorldID public immutable worldId;

    /// @notice hash(appId, action) that every World ID proof must be scoped to.
    uint256 public immutable externalNullifierHash;

    uint256 public reviewCount;

    mapping(uint256 => Review) private _reviews;
    /// @dev Each attendance/settlement proof backs exactly one review.
    mapping(bytes32 => bool) public proofUsed;
    /// @dev venue => World ID nullifier => used. Keyed per venue so one human gets
    ///      one review *per venue* rather than one review globally.
    mapping(address => mapping(uint256 => bool)) public venueNullifierUsed;

    event ReviewPosted(
        uint256 indexed reviewId,
        address indexed venue,
        address indexed diner,
        bytes32 proofId,
        uint8 tier,
        uint8 rating,
        bytes32 contentHash,
        uint64 postedAt,
        uint256 worldIdNullifier
    );

    error NoAttendanceProof();
    error NoSettlementProof();
    error ProofAlreadyUsed();
    error ProofNotOwnedByCaller();
    error VenueMismatch();
    error InvalidRating();
    error InvalidTier();
    error AlreadyReviewedVenue();

    constructor(
        VenueRegistry registry_,
        AttendanceGate gate_,
        BillSettlement settlement_,
        IWorldID worldId_,
        string memory appId,
        string memory action
    ) EIP712("Seated", "1") {
        registry = registry_;
        gate = gate_;
        settlement = settlement_;
        worldId = worldId_;
        externalNullifierHash = abi.encodePacked(abi.encodePacked(appId).hashToField(), action).hashToField();
    }

    /// @notice Post a review backed by a tier-1 check-in or a tier-2 settled bill.
    /// @dev Order matters and is demo-visible: proof resolution runs before World ID
    ///      so a wallet with no voucher fails with NoAttendanceProof, while a second
    ///      wallet belonging to an already-seen human fails with AlreadyReviewedVenue.
    function postReview(
        address venue,
        bytes32 proofId,
        uint8 tier,
        uint8 rating,
        bytes32 contentHash,
        uint256 worldIdRoot,
        uint256 worldIdNullifier,
        uint256[8] calldata worldIdProof
    ) external returns (uint256 reviewId) {
        if (rating == 0 || rating > 5) revert InvalidRating();
        if (proofUsed[proofId]) revert ProofAlreadyUsed();

        if (tier == TIER_CHECKIN) {
            AttendanceGate.AttendanceProof memory p = gate.proofOf(proofId);
            if (p.redeemedAt == 0) revert NoAttendanceProof();
            if (p.diner != msg.sender) revert ProofNotOwnedByCaller();
            if (p.venue != venue) revert VenueMismatch();
        } else if (tier == TIER_SETTLED) {
            BillSettlement.SettlementProof memory p = settlement.proofOf(proofId);
            if (p.settledAt == 0) revert NoSettlementProof();
            if (p.diner != msg.sender) revert ProofNotOwnedByCaller();
            if (p.venue != venue) revert VenueMismatch();
        } else {
            revert InvalidTier();
        }

        if (venueNullifierUsed[venue][worldIdNullifier]) revert AlreadyReviewedVenue();

        worldId.verifyProof(
            worldIdRoot,
            WORLD_ID_GROUP_ID,
            abi.encodePacked(venue).hashToField(),
            worldIdNullifier,
            externalNullifierHash,
            worldIdProof
        );

        venueNullifierUsed[venue][worldIdNullifier] = true;
        proofUsed[proofId] = true;

        reviewId = ++reviewCount;
        _reviews[reviewId] = Review({
            reviewId: reviewId,
            venue: venue,
            proofId: proofId,
            tier: tier,
            rating: rating,
            contentHash: contentHash,
            postedAt: uint64(block.timestamp),
            worldIdNullifier: worldIdNullifier
        });

        emit ReviewPosted(
            reviewId, venue, msg.sender, proofId, tier, rating, contentHash, uint64(block.timestamp), worldIdNullifier
        );
    }

    function getReview(uint256 reviewId) external view returns (Review memory) {
        return _reviews[reviewId];
    }
}
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `forge test --match-contract ReviewRegistryTest -vv`
Expected: PASS, 15 tests. Pay particular attention to `test_postReview_oneHumanCannotReviewSameVenueTwice` — that is Scene 2 of the demo in test form.

- [ ] **Step 8: Run the whole suite**

Run: `forge test -vv`
Expected: PASS, all contracts.

- [ ] **Step 9: Commit**

```bash
forge fmt
git add src/ReviewRegistry.sol src/interfaces/IWorldID.sol src/libraries/ByteHasher.sol test/ReviewRegistry.t.sol test/mocks/MockWorldID.sol
git commit -m "feat: add ReviewRegistry gating reviews on attendance proof and World ID"
```

---

### Task 6: ReviewRegistry — venue replies

**Files:**
- Modify: `src/ReviewRegistry.sol`
- Test: `test/ReviewRegistryReply.t.sol`

**Interfaces:**
- Consumes: everything from Task 5, plus `VenueRegistry.signingKeyOf` from Task 2.
- Produces:
  - `struct Reply {bytes32 replyHash; uint64 postedAt;}`
  - `REPLY_TYPEHASH = keccak256("Reply(uint256 reviewId,bytes32 replyHash,uint64 deadline)")`
  - `hashReply(uint256 reviewId, bytes32 replyHash, uint64 deadline) external view returns (bytes32)`
  - `postReply(uint256 reviewId, bytes32 replyHash, uint64 deadline, bytes calldata signature) external`
  - `getReply(uint256 reviewId) external view returns (Reply memory)`
  - `event ReplyPosted(uint256 indexed reviewId, bytes32 replyHash, uint64 postedAt)`

**Design note for the implementer:** the reply is signed by the **same** `signingKey` the venue uses for check-in vouchers — the point is that one accountable key produces both artifacts. Anyone may submit the transaction; only the signature must come from the venue's key. Check order per the spec: review exists → no existing reply → signature valid → deadline not passed.

- [ ] **Step 1: Write the failing test**

Create `test/ReviewRegistryReply.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {AttendanceGate} from "../src/AttendanceGate.sol";
import {BillSettlement} from "../src/BillSettlement.sol";
import {ReviewRegistry} from "../src/ReviewRegistry.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockWorldID} from "./mocks/MockWorldID.sol";

contract ReviewRegistryReplyTest is Test {
    VenueRegistry internal registry;
    AttendanceGate internal gate;
    BillSettlement internal settlement;
    ReviewRegistry internal reviews;
    MockWorldID internal worldId;

    address internal venueId = makeAddr("venue");
    address internal diner = makeAddr("diner");
    address internal relayer = makeAddr("relayer");

    uint256 internal signerPk = 0xA11CE;
    address internal signingKey;

    uint256[8] internal zeroProof;
    bytes32 internal constant REPLY_BODY = keccak256("thank you, we've passed this to the kitchen");

    uint256 internal reviewId;
    uint64 internal deadline;

    event ReplyPosted(uint256 indexed reviewId, bytes32 replyHash, uint64 postedAt);

    function setUp() public {
        signingKey = vm.addr(signerPk);

        registry = new VenueRegistry();
        gate = new AttendanceGate(registry);
        MockUSDC usdc = new MockUSDC();
        settlement = new BillSettlement(registry, IERC20(address(usdc)));
        worldId = new MockWorldID();
        reviews = new ReviewRegistry(registry, gate, settlement, IWorldID(address(worldId)), "app_seated", "post-review");

        vm.prank(venueId);
        registry.registerVenue(signingKey, 40, "ipfs://venue");

        vm.warp(1_800_000_000);
        deadline = uint64(block.timestamp + 1 hours);

        AttendanceGate.CheckIn memory c = AttendanceGate.CheckIn({
            venue: venueId,
            diner: diner,
            seatedAt: uint64(block.timestamp),
            expiry: uint64(block.timestamp + 2 hours),
            salt: bytes32(uint256(1))
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, gate.hashCheckIn(c));
        vm.prank(diner);
        bytes32 proofId = gate.redeem(c, abi.encodePacked(r, s, v));

        vm.prank(diner);
        reviewId = reviews.postReview(venueId, proofId, 1, 4, keccak256("good"), 111, 222, zeroProof);
    }

    function _signReply(uint256 id, bytes32 body, uint64 dl, uint256 pk) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, reviews.hashReply(id, body, dl));
        return abi.encodePacked(r, s, v);
    }

    function test_postReply_storesReply() public {
        reviews.postReply(reviewId, REPLY_BODY, deadline, _signReply(reviewId, REPLY_BODY, deadline, signerPk));

        ReviewRegistry.Reply memory reply = reviews.getReply(reviewId);
        assertEq(reply.replyHash, REPLY_BODY);
        assertEq(reply.postedAt, uint64(block.timestamp));
    }

    function test_postReply_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ReplyPosted(reviewId, REPLY_BODY, uint64(block.timestamp));

        reviews.postReply(reviewId, REPLY_BODY, deadline, _signReply(reviewId, REPLY_BODY, deadline, signerPk));
    }

    /// The signature carries the authority, so any relayer may submit it.
    function test_postReply_anyoneMaySubmitAVenueSignedReply() public {
        vm.prank(relayer);
        reviews.postReply(reviewId, REPLY_BODY, deadline, _signReply(reviewId, REPLY_BODY, deadline, signerPk));

        assertEq(reviews.getReply(reviewId).replyHash, REPLY_BODY);
    }

    function test_postReply_revertsForUnknownReview() public {
        uint256 missing = 999;

        vm.expectRevert(ReviewRegistry.UnknownReview.selector);
        reviews.postReply(missing, REPLY_BODY, deadline, _signReply(missing, REPLY_BODY, deadline, signerPk));
    }

    function test_postReply_revertsOnSecondReply() public {
        reviews.postReply(reviewId, REPLY_BODY, deadline, _signReply(reviewId, REPLY_BODY, deadline, signerPk));

        bytes32 second = keccak256("actually, on reflection");
        vm.expectRevert(ReviewRegistry.ReplyAlreadyExists.selector);
        reviews.postReply(reviewId, second, deadline, _signReply(reviewId, second, deadline, signerPk));
    }

    function test_postReply_revertsWhenSignedByWrongKey() public {
        vm.expectRevert(ReviewRegistry.BadVenueSignature.selector);
        reviews.postReply(reviewId, REPLY_BODY, deadline, _signReply(reviewId, REPLY_BODY, deadline, 0xBAD));
    }

    function test_postReply_revertsOnMalformedSignature() public {
        vm.expectRevert(ReviewRegistry.BadVenueSignature.selector);
        reviews.postReply(reviewId, REPLY_BODY, deadline, hex"deadbeef");
    }

    /// Tampering with the body invalidates the signature.
    function test_postReply_revertsWhenBodyDoesNotMatchSignature() public {
        bytes memory sig = _signReply(reviewId, REPLY_BODY, deadline, signerPk);

        vm.expectRevert(ReviewRegistry.BadVenueSignature.selector);
        reviews.postReply(reviewId, keccak256("something else entirely"), deadline, sig);
    }

    function test_postReply_revertsAfterDeadline() public {
        bytes memory sig = _signReply(reviewId, REPLY_BODY, deadline, signerPk);
        vm.warp(deadline + 1);

        vm.expectRevert(ReviewRegistry.ReplyDeadlineExpired.selector);
        reviews.postReply(reviewId, REPLY_BODY, deadline, sig);
    }

    /// A rotated signing key can reply; the old key cannot.
    function test_postReply_followsSigningKeyRotation() public {
        uint256 newPk = 0xB0B;
        vm.prank(venueId);
        registry.setSigningKey(venueId, vm.addr(newPk));

        vm.expectRevert(ReviewRegistry.BadVenueSignature.selector);
        reviews.postReply(reviewId, REPLY_BODY, deadline, _signReply(reviewId, REPLY_BODY, deadline, signerPk));

        reviews.postReply(reviewId, REPLY_BODY, deadline, _signReply(reviewId, REPLY_BODY, deadline, newPk));
        assertEq(reviews.getReply(reviewId).replyHash, REPLY_BODY);
    }

    function test_getReply_isEmptyBeforeAnyReply() public view {
        assertEq(reviews.getReply(reviewId).postedAt, 0);
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `forge test --match-contract ReviewRegistryReplyTest -vv`
Expected: FAIL at compile time — `Member "hashReply" not found`.

- [ ] **Step 3: Add the ECDSA import to ReviewRegistry**

In `src/ReviewRegistry.sol`, add to the existing import block:

```solidity
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
```

- [ ] **Step 4: Add the Reply struct, typehash, storage, event and errors**

In `src/ReviewRegistry.sol`, add the struct immediately after the `Review` struct:

```solidity
    struct Reply {
        bytes32 replyHash;
        uint64 postedAt;
    }
```

Add the typehash next to the tier constants:

```solidity
    bytes32 public constant REPLY_TYPEHASH = keccak256("Reply(uint256 reviewId,bytes32 replyHash,uint64 deadline)");
```

Add the storage mapping next to `_reviews`:

```solidity
    mapping(uint256 => Reply) private _replies;
```

Add the event after `ReviewPosted`:

```solidity
    event ReplyPosted(uint256 indexed reviewId, bytes32 replyHash, uint64 postedAt);
```

Add the errors after `AlreadyReviewedVenue`:

```solidity
    error UnknownReview();
    error ReplyAlreadyExists();
    error ReplyDeadlineExpired();
    error BadVenueSignature();
```

- [ ] **Step 5: Add hashReply, postReply and getReply**

In `src/ReviewRegistry.sol`, add after `getReview`:

```solidity
    /// @notice EIP-712 digest the venue's signing key must sign to reply.
    function hashReply(uint256 reviewId, bytes32 replyHash, uint64 deadline) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(REPLY_TYPEHASH, reviewId, replyHash, deadline)));
    }

    /// @notice Record a venue's public reply to a review. One reply per review.
    /// @dev Signed by the same key that signs check-in vouchers: one accountable
    ///      identity produces both artifacts. Anyone may relay the transaction.
    function postReply(uint256 reviewId, bytes32 replyHash, uint64 deadline, bytes calldata signature) external {
        Review memory r = _reviews[reviewId];
        if (r.postedAt == 0) revert UnknownReview();
        if (_replies[reviewId].postedAt != 0) revert ReplyAlreadyExists();

        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(REPLY_TYPEHASH, reviewId, replyHash, deadline)));
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || signer != registry.signingKeyOf(r.venue)) {
            revert BadVenueSignature();
        }

        if (block.timestamp >= deadline) revert ReplyDeadlineExpired();

        _replies[reviewId] = Reply({replyHash: replyHash, postedAt: uint64(block.timestamp)});
        emit ReplyPosted(reviewId, replyHash, uint64(block.timestamp));
    }

    function getReply(uint256 reviewId) external view returns (Reply memory) {
        return _replies[reviewId];
    }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `forge test --match-contract ReviewRegistryReplyTest -vv`
Expected: PASS, 11 tests.

- [ ] **Step 7: Run the whole suite**

Run: `forge test -vv`
Expected: PASS, everything.

- [ ] **Step 8: Commit**

```bash
forge fmt
git add src/ReviewRegistry.sol test/ReviewRegistryReply.t.sol
git commit -m "feat: add venue replies signed by the venue's check-in signing key"
```

---

### Task 7: Deployment scripts and Base Sepolia deployment

**Files:**
- Create: `script/Deploy.s.sol`
- Create: `script/SeedVenues.s.sol`
- Create: `.env.example`
- Create: `deployments/base-sepolia.json`
- Test: `test/Deploy.t.sol`

**Interfaces:**
- Consumes: all four contracts from Tasks 2-6.
- Produces: verified Base Sepolia addresses recorded in `deployments/base-sepolia.json`. **Plan 2 (subgraph) and Plan 3 (frontend) both read this file** — its shape is a contract between plans.

**Reference values (Base Sepolia, chain id 84532):**
- USDC: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`
- World ID Router: `0x42FF98C4E85212a5D31358ACbFe76a621b50fC02`
- World ID app id and action are taken from env so the demo can point at a real Developer Portal app.

- [ ] **Step 1: Write the failing deployment test**

This test runs the deploy script against a local fork-free chain and asserts the contracts are wired to each other correctly. Create `test/Deploy.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {AttendanceGate} from "../src/AttendanceGate.sol";
import {BillSettlement} from "../src/BillSettlement.sol";
import {ReviewRegistry} from "../src/ReviewRegistry.sol";

contract DeployTest is Test {
    function test_run_wiresContractsTogether() public {
        Deploy deployer = new Deploy();
        Deploy.Deployment memory d =
            deployer.deploy(makeAddr("usdc"), makeAddr("worldId"), "app_seated", "post-review");

        assertEq(address(AttendanceGate(d.gate).registry()), d.registry);
        assertEq(address(BillSettlement(d.settlement).registry()), d.registry);
        assertEq(address(ReviewRegistry(d.reviews).registry()), d.registry);
        assertEq(address(ReviewRegistry(d.reviews).gate()), d.gate);
        assertEq(address(ReviewRegistry(d.reviews).settlement()), d.settlement);
    }

    function test_run_usesSeatedEip712DomainInBothSigningContracts() public {
        Deploy deployer = new Deploy();
        Deploy.Deployment memory d =
            deployer.deploy(makeAddr("usdc"), makeAddr("worldId"), "app_seated", "post-review");

        (, string memory gateName, string memory gateVersion,,,,) = AttendanceGate(d.gate).eip712Domain();
        (, string memory reviewName, string memory reviewVersion,,,,) = ReviewRegistry(d.reviews).eip712Domain();

        assertEq(gateName, "Seated");
        assertEq(gateVersion, "1");
        assertEq(reviewName, "Seated");
        assertEq(reviewVersion, "1");
    }
}
```

The USDC and World ID addresses are only stored by the constructors, never called, so `makeAddr` stand-ins are sufficient for these wiring assertions.

- [ ] **Step 2: Run the test to verify it fails**

Run: `forge test --match-contract DeployTest -vv`
Expected: FAIL at compile time — `Source "../script/Deploy.s.sol" not found`.

- [ ] **Step 3: Write the deploy script**

Create `script/Deploy.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {AttendanceGate} from "../src/AttendanceGate.sol";
import {BillSettlement} from "../src/BillSettlement.sol";
import {ReviewRegistry} from "../src/ReviewRegistry.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";

contract Deploy is Script {
    struct Deployment {
        address registry;
        address gate;
        address settlement;
        address reviews;
    }

    /// @dev Pure deployment logic, callable from tests without broadcasting.
    function deploy(address usdc, address worldIdRouter, string memory appId, string memory action)
        public
        returns (Deployment memory)
    {
        VenueRegistry registry = new VenueRegistry();
        AttendanceGate gate = new AttendanceGate(registry);
        BillSettlement settlement = new BillSettlement(registry, IERC20(usdc));
        ReviewRegistry reviews =
            new ReviewRegistry(registry, gate, settlement, IWorldID(worldIdRouter), appId, action);

        return Deployment({
            registry: address(registry),
            gate: address(gate),
            settlement: address(settlement),
            reviews: address(reviews)
        });
    }

    function run() external {
        address usdc = vm.envAddress("USDC_ADDRESS");
        address worldIdRouter = vm.envAddress("WORLD_ID_ROUTER");
        string memory appId = vm.envString("WORLD_ID_APP_ID");
        string memory action = vm.envString("WORLD_ID_ACTION");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        Deployment memory d = deploy(usdc, worldIdRouter, appId, action);
        vm.stopBroadcast();

        console2.log("VenueRegistry  ", d.registry);
        console2.log("AttendanceGate ", d.gate);
        console2.log("BillSettlement ", d.settlement);
        console2.log("ReviewRegistry ", d.reviews);
    }
}
```

- [ ] **Step 4: Run the deployment test to verify it passes**

Run: `forge test --match-contract DeployTest -vv`
Expected: PASS, 2 tests.

- [ ] **Step 5: Write `.env.example`**

Create `.env.example`:

```bash
# Deployer key. Use a throwaway key funded with Base Sepolia ETH only.
PRIVATE_KEY=0x

BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
ETHERSCAN_API_KEY=

# Base Sepolia canonical addresses
USDC_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e
WORLD_ID_ROUTER=0x42FF98C4E85212a5D31358ACbFe76a621b50fC02

# From the Worldcoin Developer Portal
WORLD_ID_APP_ID=app_staging_replace_me
WORLD_ID_ACTION=post-review
```

- [ ] **Step 6: Commit the scripts before touching a live network**

```bash
forge fmt
git add script/Deploy.s.sol test/Deploy.t.sol .env.example
git commit -m "feat: add deployment script with wiring tests"
```

- [ ] **Step 7: Deploy to Base Sepolia**

Copy `.env.example` to `.env`, fill in `PRIVATE_KEY`, `ETHERSCAN_API_KEY` and `WORLD_ID_APP_ID`, then run:

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --broadcast \
  --verify \
  -vvvv
```

Expected: four contracts deployed, each reporting `Contract successfully verified`. If verification times out, re-run verification alone rather than redeploying:

```bash
forge verify-contract <ADDRESS> src/VenueRegistry.sol:VenueRegistry \
  --chain 84532 --etherscan-api-key "$ETHERSCAN_API_KEY" --watch
```

- [ ] **Step 8: Record the addresses**

Create `deployments/base-sepolia.json`, substituting the real addresses printed by the script. Plan 2 and Plan 3 read this file, so the key names matter:

```json
{
  "chainId": 84532,
  "network": "base-sepolia",
  "startBlock": 0,
  "contracts": {
    "VenueRegistry": "0x0000000000000000000000000000000000000000",
    "AttendanceGate": "0x0000000000000000000000000000000000000000",
    "BillSettlement": "0x0000000000000000000000000000000000000000",
    "ReviewRegistry": "0x0000000000000000000000000000000000000000"
  },
  "external": {
    "USDC": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
    "WorldIDRouter": "0x42FF98C4E85212a5D31358ACbFe76a621b50fC02"
  }
}
```

Set `startBlock` to the block number of the `VenueRegistry` deployment transaction — the subgraph in Plan 2 starts indexing there, and getting it right saves a long sync. Read it from the broadcast log:

```bash
cat broadcast/Deploy.s.sol/84532/run-latest.json | grep -m1 blockNumber
```

- [ ] **Step 9: Write the venue seeding script**

Three demo venues with different capacity commitments, so the capacity story is visible. Create `script/SeedVenues.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";

/// @dev Registers the three demo venues. Each venue is registered by its own key,
///      because the registering address becomes the venue id.
contract SeedVenues is Script {
    function run() external {
        VenueRegistry registry = VenueRegistry(vm.envAddress("VENUE_REGISTRY"));

        uint256[3] memory venuePks = [
            vm.envUint("VENUE_1_PRIVATE_KEY"),
            vm.envUint("VENUE_2_PRIVATE_KEY"),
            vm.envUint("VENUE_3_PRIVATE_KEY")
        ];
        address[3] memory signingKeys =
            [vm.envAddress("VENUE_1_SIGNING_KEY"), vm.envAddress("VENUE_2_SIGNING_KEY"), vm.envAddress("VENUE_3_SIGNING_KEY")];
        uint32[3] memory capacities = [uint32(40), uint32(120), uint32(24)];
        string[3] memory metadata = [
            vm.envString("VENUE_1_METADATA_URI"),
            vm.envString("VENUE_2_METADATA_URI"),
            vm.envString("VENUE_3_METADATA_URI")
        ];

        for (uint256 i = 0; i < 3; i++) {
            vm.startBroadcast(venuePks[i]);
            registry.registerVenue(signingKeys[i], capacities[i], metadata[i]);
            vm.stopBroadcast();

            console2.log("Registered venue", vm.addr(venuePks[i]));
        }
    }
}
```

- [ ] **Step 10: Extend `.env.example` with the venue keys**

Append to `.env.example`:

```bash
# Filled in after deployment
VENUE_REGISTRY=0x

# Three demo venues. Each needs Base Sepolia ETH to send its own registration tx.
VENUE_1_PRIVATE_KEY=0x
VENUE_1_SIGNING_KEY=0x
VENUE_1_METADATA_URI=ipfs://
VENUE_2_PRIVATE_KEY=0x
VENUE_2_SIGNING_KEY=0x
VENUE_2_METADATA_URI=ipfs://
VENUE_3_PRIVATE_KEY=0x
VENUE_3_SIGNING_KEY=0x
VENUE_3_METADATA_URI=ipfs://
```

- [ ] **Step 11: Seed the venues on Base Sepolia**

Fund the three venue addresses with a small amount of Base Sepolia ETH first, then:

```bash
source .env
forge script script/SeedVenues.s.sol:SeedVenues \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" --broadcast -vvvv
```

Expected: three `VenueRegistered` events. Confirm on the explorer that each venue reads back with the right `maxCoversPerDay`.

- [ ] **Step 12: Verify the whole suite still passes**

Run: `forge test -vv && forge fmt --check && forge build --sizes`
Expected: all tests pass, formatting clean, no contract near the 24KB limit.

- [ ] **Step 13: Commit**

```bash
git add script/SeedVenues.s.sol deployments/base-sepolia.json .env.example
git commit -m "feat: add venue seeding script and record Base Sepolia addresses"
git push
```

---

## What this plan deliberately leaves out

These belong to later plans and must not be built here:

- **Plan 2 — Subgraph + Subgraph MCP.** Indexes `VenueRegistered`, `CheckInRedeemed`, `BillSettled`, `ReviewPosted`, `ReplyPosted`; derives `VenueStats` with the tier ratio.
- **Plan 3 — Frontend.** Privy login, QR scan, review composer, tier badges, venue reply UI, `/leaderboard`.
- **Plan 4 — Demo assets.** The Scene 2 attack script, review seeding, the video, the README.

## Notes for the implementer

- **Do not change the EIP-712 domain** after Task 3 is committed. `"Seated"` / `"1"` is referenced by the frontend, the QR payload, and the Privy signer policy.
- If `forge install` creates git submodules, commit `.gitmodules` — CI checks out with `submodules: recursive` and will fail without it.
- Run `forge fmt` before every commit. CI runs `forge fmt --check` and will fail the build on formatting drift.
- Task 7 steps 7-11 touch a live network and spend testnet funds. Everything before them is local and reversible.
