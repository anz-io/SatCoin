// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import "base64-sol/base64.sol";

contract SatCoinNFT is Ownable2StepUpgradeable, ERC721Upgradeable {

    // --- Data Structures ---

    using Strings for uint256;
    using Strings for address;

    struct Trait {
        string key;
        string value;
        string displayType;
    }

    string public constant ETHEREUM_SIGN_PREFIX = "\x19Ethereum Signed Message:\n";
    

    // --- State Variables ---

    // Total number of tokens minted
    uint256 public totalSupply;

    // Address of the backend signer authorized to permit mints
    address public signerAddress;

    // Mapping for replay protection
    mapping(bytes32 => bool) public minted;

    // Mapping from tokenId to its encoded attributes payload
    mapping(uint256 => bytes) public attributePayload;

    // SatCoin NFT has different types, each type should be added only by admin
    mapping(uint16 => string) public typeIdToTypeName;

    // The same type of NFT has the same image url
    mapping(uint16 => string) public typeIdToImageUrl;

    // Each token has a type
    mapping(uint256 => uint16) public tokenTypeId;


    // --- Events ---

    event TypeInfoSet(uint16 indexed typeId, string typeName, string imageUrl);
    event Minted(address indexed to, uint256 indexed tokenId);


    // --- Initializer ---

    /**
     * @notice Initializes the contract, setting up the name, symbol, owner, and signer.
     * @param name The name of the NFT collection.
     * @param symbol The symbol of the NFT collection.
     * @param initialOwner The address that will initially own the contract.
     * @param initialSigner The address of the backend service authorized to sign minting permits.
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


    // --- Internal Helper Functions ---

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

    function _formatTrait(Trait memory trait) internal pure returns (string memory) {
        string memory valuePart = string(abi.encodePacked(
            '{"trait_type":"', trait.key,
            '","value":"', trait.value, '"'
        ));

        if (bytes(trait.displayType).length > 0) {
            valuePart = string(abi.encodePacked(
                valuePart,
                ',"display_type":"', trait.displayType,'"'
            ));
        }

        return string(abi.encodePacked(valuePart, "}"));
    }


    // --- Pure & View functions ---

    function prefixedHash(string memory message) internal pure returns (bytes32) {
        uint256 length = bytes(message).length;
        return keccak256(abi.encodePacked(ETHEREUM_SIGN_PREFIX, length.toString(), message));
    }

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

    function constructMessage(address to, uint16 typeId, Trait[] calldata traits) public view returns (string memory) {
        bytes32 traitsDigest = hashTraits(traits);
        string memory message = string(abi.encodePacked(
            "SatCoinNFT Minting: chainId=", block.chainid.toString(),
            ", typeId=", uint256(typeId).toString(),
            ", contract=", address(this).toHexString(),
            ", address=", to.toHexString(),
            ", traits_digest=", uint256(traitsDigest).toHexString()
        ));
        return message;
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


    // --- Public Minting Function ---

    /**
     * @notice Mints a new NFT with a dynamic set of traits, authorized by a backend signature.
     * @param traits The array of traits that define this NFT's metadata.
     * @param signature The signature from the backend `signerAddress`.
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
        uint256 newTokenId = totalSupply;
        totalSupply++;
        minted[messageHash] = true;
        attributePayload[newTokenId] = abi.encode(traits);
        tokenTypeId[newTokenId] = typeId;

        // Execute mint
        _safeMint(to, newTokenId);

        // Event
        emit Minted(to, newTokenId);
    }


    // --- Admin Functions ---

    /**
     * @notice Updates the backend signer address. Only callable by the contract owner.
     * @param newSigner The address of the new signer.
     */
    function setSigner(address newSigner) public onlyOwner {
        require(newSigner != address(0), "Signer cannot be zero address");
        signerAddress = newSigner;
    }

    /**
     * @notice Sets the name and image URL for a given type ID.
     * @param typeId The numeric ID for the NFT type (e.g., 1).
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