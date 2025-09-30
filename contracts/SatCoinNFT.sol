// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import "base64-sol/base64.sol";

contract SatCoinNFT is Ownable2StepUpgradeable, ERC721Upgradeable {

    // --- Data Structures ---

    using Strings for uint256;

    struct Trait {
        string key;
        string value;
        string displayType;
    }

    string public constant ETHEREUM_SIGN_PREFIX = "\x19Ethereum Signed Message:\n";
    

    // --- State Variables ---

    // Total number of tokens minted
    uint256 public totalSupply;

    // Mapping for replay protection
    mapping(bytes => bool) public signatureUsed;

    // Address of the backend signer authorized to permit mints
    address public signerAddress;

    // Mapping from tokenId to its encoded attributes payload
    mapping(uint256 => bytes) public attributePayload;


    // --- Events ---

    event SignatureConsumed(bytes signature);
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
        __ERC721_init(name, symbol);
        __Ownable2Step_init();
        __Ownable_init(initialOwner);

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

    function constructMessage(address to, Trait[] calldata traits) public view returns (string memory) {
        bytes32 traitsDigest = hashTraits(traits);
        return string(abi.encodePacked(
            "SatCoinNFT Minting: chainId=", Strings.toString(block.chainid),
            ", address=", Strings.toHexString(to),
            ", traits_digest=", traitsDigest
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

        // Build attributes JSON
        Trait[] memory traits = abi.decode(payload, (Trait[]));
        string memory attributesJson = _buildAttributesJson(traits);

        string memory json = string(
            abi.encodePacked(
                '{"name": "', name(), ' #', tokenId.toString(), '",',
                '"description": "An NFT collection for the SatCoin community.",',
                '"image": "ipfs://your_image_cid_or_gateway_url_here",',
                '"attributes": [', attributesJson, ']}'
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
     * @param signature The EIP-712 signature from the backend `signerAddress`.
     */
    function mint(
        Trait[] calldata traits,
        bytes calldata signature
    ) public {
        // Check replay protection
        require(!signatureUsed[signature], "SatCoinNFT: Signature already used");

        // Verify signature
        address to = _msgSender();
        string memory message = constructMessage(to, traits);
        bytes32 messageHash = prefixedHash(message);
        require(
            SignatureChecker.isValidSignatureNow(signerAddress, messageHash, signature), 
            "SatCoinNFT: Invalid signature"
        );

        // Update states
        uint256 newTokenId = totalSupply;
        signatureUsed[signature] = true;
        attributePayload[newTokenId] = abi.encode(traits);
        _safeMint(to, newTokenId);
        totalSupply++;

        // Event
        emit SignatureConsumed(signature);
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

}