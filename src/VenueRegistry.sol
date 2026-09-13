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
        address indexed venueId, address indexed owner, address signingKey, uint32 maxCoversPerDay, string metadataURI
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
