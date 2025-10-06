// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import "base64-sol/base64.sol";

/**
 * @title SatCoinNFT
 * @author wyf-ACCEPT
 * @notice An upgradeable ERC721 NFT contract with on-chain metadata generation
 * and signature-based minting. It supports different NFT types and a flexible 
 * attribute system compatible with OpenSea.
 */
contract SatCoinNFT is Ownable2StepUpgradeable, ERC721EnumerableUpgradeable {

    // ============================= Constants =============================

    using Strings for uint256;
    using Strings for address;

    struct Trait {
        string key;
        string value;
        string displayType;
    }

    string public constant ETHEREUM_SIGN_PREFIX = "\x19Ethereum Signed Message:\n";

    bytes32 public constant KECCAK256_NUMBER = keccak256(bytes("number"));
    bytes32 public constant KECCAK256_BOOST_NUMBER = keccak256(bytes("boost_number"));
    bytes32 public constant KECCAK256_BOOST_PERCENTAGE = keccak256(bytes("boost_percentage"));


    // ============================= Variables =============================

    address public signerAddress;
    mapping(bytes32 => bool) public minted;
    mapping(uint256 => bytes) public attributePayload;
    mapping(uint16 => string) public typeIdToTypeName;
    mapping(uint16 => string) public typeIdToImageUrl;
    mapping(uint256 => uint16) public tokenTypeId;


    // =============================== Events ==============================

    event TypeInfoSet(uint16 indexed typeId, string typeName, string imageUrl);
    event Minted(address indexed to, uint256 indexed tokenId);


    // ======================= Modifier & Initializer ======================

    /**
     * @notice Initializes the contract.
     * @dev Sets up the name, symbol, owner, and the backend signer address.
     * This function can only be called once on the implementation contract.
     * @param name The name of the NFT collection.
     * @param symbol The symbol of the NFT collection.
     * @param initialOwner The address that will initially own the contract.
     * @param initialSigner The address authorized to sign minting permits.
     */
    function initialize(
        string memory name,
        string memory symbol,
        address initialOwner,
        address initialSigner
    ) public initializer {
        __Ownable2Step_init();
        __Ownable_init(initialOwner);
        __ERC721_init(name, symbol);

        require(initialSigner != address(0), "Signer cannot be zero address");
        signerAddress = initialSigner;
    }


    // ========================= Internal functions ========================

    /**
     * @dev Builds a JSON array string from a list of traits.
     * @param traits The array of Trait structs.
     * @return A string representing the JSON array of attributes.
     */
    function _buildAttributesJson(Trait[] memory traits) internal pure returns (string memory) {
        string memory json;
        for (uint i = 0; i < traits.length; i++) {
            json = string(abi.encodePacked(json, _formatTrait(traits[i])));
            if (i < traits.length - 1) {
                json = string(abi.encodePacked(json, ","));
            }
        }
        return json;
    }

    /**
     * @dev Formats a single Trait struct into a JSON object string.
     * @dev Handles numeric types by not wrapping their values in quotes.
     * @param trait The Trait struct to format.
     * @return A string representing the JSON object for the trait.
     */
    function _formatTrait(Trait memory trait) internal pure returns (string memory) {
        // Start building the JSON with the trait_type key
        string memory json = string(abi.encodePacked('{"trait_type":"', trait.key, '",'));

        // Check if the display_type is "number"
        bytes32 displayTypeHash = keccak256(bytes(trait.displayType));
        if (
            displayTypeHash == KECCAK256_NUMBER ||
            displayTypeHash == KECCAK256_BOOST_NUMBER ||
            displayTypeHash == KECCAK256_BOOST_PERCENTAGE
        ) {
            json = string(abi.encodePacked(json, '"value":', trait.value));
        } else {
            json = string(abi.encodePacked(json, '"value":"', trait.value, '"'));
        }

        // Add the display_type key if it exists
        if (bytes(trait.displayType).length > 0) {
            json = string(abi.encodePacked(json, ',"display_type":"', trait.displayType, '"'));
        }

        // Add the closing brace
        return string(abi.encodePacked(json, "}"));
    }


    // ======================= Pure & View functions =======================

    /**
     * @dev Hashes a message with the Ethereum signed message prefix.
     * @param message The message to hash.
     * @return The EIP-191 compliant hash.
     */
    function prefixedHash(string memory message) internal pure returns (bytes32) {
        uint256 length = bytes(message).length;
        return keccak256(abi.encodePacked(ETHEREUM_SIGN_PREFIX, length.toString(), message));
    }

    /**
     * @dev Hashes an array of Trait structs to a single digest.
     * @param traits The array of Trait structs.
     * @return A bytes32 digest representing the traits.
     */
    function hashTraits(Trait[] calldata traits) public pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](traits.length);
        for (uint i = 0; i < traits.length; i++) {
            hashes[i] = keccak256(abi.encode(
                keccak256(bytes(traits[i].key)),
                keccak256(bytes(traits[i].value)),
                keccak256(bytes(traits[i].displayType))
            ));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    /**
     * @dev Constructs the message string that needs to be signed for minting.
     * @param to The address that will receive the NFT.
     * @param typeId The numeric ID of the NFT type.
     * @param traits The array of Trait structs for the NFT.
     * @return The message string to be signed.
     */
    function constructMessage(
        address to, 
        uint16 typeId, 
        Trait[] calldata traits
    ) public view returns (string memory) {
        bytes32 traitsDigest = hashTraits(traits);
        return string(abi.encodePacked(
            "SatCoinNFT Minting: chainId=", block.chainid.toString(),
            ", typeId=", uint256(typeId).toString(),
            ", contract=", address(this).toHexString(),
            ", address=", to.toHexString(),
            ", traits_digest=", uint256(traitsDigest).toHexString()
        ));
    }


    /**
     * @notice Returns the URI for a given token ID, generating the metadata fully on-chain.
     * @param tokenId The ID of the token.
     * @return A string containing the data URI with Base64 encoded JSON metadata.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // Check constraints
        bytes memory payload = attributePayload[tokenId];
        require(payload.length > 0, "SatCoinNFT: Not minted");

        // Decode traits
        Trait[] memory traits = abi.decode(payload, (Trait[]));
        string memory baseAttributesJson = _buildAttributesJson(traits);

        // Load type info
        uint16 typeId = tokenTypeId[tokenId];
        string memory typeName = typeIdToTypeName[typeId];
        string memory imageUrl = typeIdToImageUrl[typeId];
        string memory typeAttributeJson = _formatTrait(Trait({
            key: "NFT Type",
            value: typeName,
            displayType: ""
        }));

        // Concat the traits
        string memory finalAttributesJson;
        if (bytes(baseAttributesJson).length > 0) {
            finalAttributesJson = string(abi.encodePacked(typeAttributeJson, ",", baseAttributesJson));
        } else {
            finalAttributesJson = typeAttributeJson;
        }

        // Build the final JSON
        string memory json = string(
            abi.encodePacked(
                '{"name": "', name(), ' #', tokenId.toString(), '",',
                '"description": "An NFT collection for the SatCoin community.",',
                '"image": "', imageUrl, '",',
                '"attributes": [', finalAttributesJson, ']}'
            )
        );

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }


    // ========================== Write functions ==========================

    /**
     * @notice Mints a new NFT with a dynamic set of traits, authorized by a backend signature.
     * @dev Verifies the signature, checks for replays, and then mints the token.
     * @param to The address that will receive the NFT.
     * @param typeId The numeric ID of the NFT type.
     * @param traits The traits that define this NFT's metadata (excluding the "NFT Type" trait).
     * @param signature The ignature from the backend `signerAddress`.
     */
    function mint(
        address to,
        uint16 typeId,
        Trait[] calldata traits,
        bytes calldata signature
    ) public {
        // Verify signature
        require(bytes(typeIdToTypeName[typeId]).length > 0, "SatCoinNFT: Invalid typeId");
        string memory message = constructMessage(to, typeId, traits);
        bytes32 messageHash = prefixedHash(message);
        require(!minted[messageHash], "SatCoinNFT: Already minted");
        require(
            SignatureChecker.isValidSignatureNow(signerAddress, messageHash, signature),
            "SatCoinNFT: Invalid signature"
        );

        // Update states
        uint256 newTokenId = totalSupply();
        minted[messageHash] = true;
        attributePayload[newTokenId] = abi.encode(traits);
        tokenTypeId[newTokenId] = typeId;

        // Execute mint
        _safeMint(to, newTokenId);

        // Event
        emit Minted(to, newTokenId);
    }


    // ========================== Admin functions ==========================

    /**
     * @notice Updates the backend signer address.
     * @dev Only callable by the contract owner.
     * @param newSigner The address of the new signer.
     */
    function setSigner(address newSigner) public onlyOwner {
        require(newSigner != address(0), "Signer cannot be zero address");
        signerAddress = newSigner;
    }

    /**
     * @notice Sets the name and image URL for a given type ID.
     * @dev Only callable by the contract owner.
     * @param typeId The numeric ID for the NFT type.
     * @param typeName The display name for the type (e.g., "Holders NFT").
     * @param imageUrl The IPFS or gateway URL for the image.
     */
    function setTypeInfo(
        uint16 typeId,
        string calldata typeName,
        string calldata imageUrl
    ) public onlyOwner {
        typeIdToImageUrl[typeId] = imageUrl;
        typeIdToTypeName[typeId] = typeName;
        emit TypeInfoSet(typeId, typeName, imageUrl);
    }

}