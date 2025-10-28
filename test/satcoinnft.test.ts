import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { SatCoinNFT, SatCoinNFTTest } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

type Trait = {
  key: string;
  value: string;
  displayType: string;
};

describe("SatCoinNFT", function () {

  async function deployContracts() {
    const [owner, signer, user1, user2] = await ethers.getSigners();

    const SatCoinNFTFactory = await ethers.getContractFactory("SatCoinNFT");
    const nft = (await upgrades.deployProxy(
      SatCoinNFTFactory,
      ["SatCoin NFT", "SCNFT", owner.address, signer.address],
    )) as unknown as SatCoinNFT;
    await nft.waitForDeployment();

    return { nft, owner, signer, user1, user2 };
  }
  

  async function getMintSignature(
    nft: SatCoinNFT,
    signer: HardhatEthersSigner,
    to: string,
    typeId: number,
    traits: Trait[]
  ) {
    // 1. Clone hashTraits
    const hashedTraits = traits.map((trait) =>
      ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["bytes32", "bytes32", "bytes32"],
          [
            ethers.keccak256(ethers.toUtf8Bytes(trait.key)),
            ethers.keccak256(ethers.toUtf8Bytes(trait.value)),
            ethers.keccak256(ethers.toUtf8Bytes(trait.displayType)),
          ]
        )
      )
    );
    const traitsDigest = ethers.keccak256(ethers.solidityPacked(["bytes32[]"], [hashedTraits]));

    // 2. Clone constructMessage
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const message = `SatCoinNFT Minting: chainId=${chainId}, typeId=${typeId}, contract=${(await nft.getAddress()).toLowerCase()}, address=${to.toLowerCase()}, traits_digest=${traitsDigest}`;

    // 3. Backend signs
    // ethers.hashMessage will automatically add "\x19Ethereum Signed Message:\n" prefix
    const messageHash = ethers.hashMessage(message);
    const signature = await signer.signMessage(message);

    return { message, messageHash, signature };
  }


  it("should deploy correctly", async function () {
    const { nft, owner, signer } = await loadFixture(deployContracts);
    expect(await nft.name()).to.equal("SatCoin NFT");
    expect(await nft.symbol()).to.equal("SCNFT");
    expect(await nft.owner()).to.equal(owner.address);
    expect(await nft.signerAddress()).to.equal(signer.address);
    expect(await nft.totalSupply()).to.equal(0);
  });


  it("should handle admin functions correctly", async function () {
    const { nft, owner, user1 } = await loadFixture(deployContracts);

    await expect(nft.connect(owner).setTypeInfo(1, "Holders NFT", "ipfs://holders"))
      .to.emit(nft, "TypeInfoSet")
      .withArgs(1, "Holders NFT", "ipfs://holders");

    await expect(
      nft.connect(user1).setTypeInfo(1, "Holders NFT", "ipfs://holders")
    ).to.be.revertedWithCustomError(nft, "OwnableUnauthorizedAccount");

    await expect(nft.setTypeInfo(1, "Holders NFT", "ipfs://holders"))
      .to.emit(nft, "TypeInfoSet")
      .withArgs(1, "Holders NFT", "ipfs://holders");

    expect(await nft.typeIdToTypeName(1)).to.equal("Holders NFT");
    expect(await nft.typeIdToImageUrl(1)).to.equal("ipfs://holders");

    await expect(
      nft.connect(user1).setSigner(user1.address)
    ).to.be.revertedWithCustomError(nft, "OwnableUnauthorizedAccount");

    await nft.setSigner(user1.address);
    expect(await nft.signerAddress()).to.equal(user1.address);
  });


  it("should allow a user to mint with a valid signature", async function () {
    const { nft, signer, user1 } = await loadFixture(deployContracts);

    // Admin first sets up the type
    await nft.setTypeInfo(1, "Holders NFT", "ipfs://holders");

    const typeId = 1;
    const baseTraits: Trait[] = [
      { key: "Level", value: "5", displayType: "number" },
    ];

    const { signature, messageHash } = await getMintSignature(
      nft,
      signer,
      user1.address,
      typeId,
      baseTraits
    );

    await expect(nft.connect(user1).mint(user1.address, typeId, baseTraits, signature))
      .to.emit(nft, "Minted")
      .withArgs(user1.address, 0, messageHash);

    // Verify state changes
    expect(await nft.totalSupply()).to.equal(1);
    expect(await nft.ownerOf(0)).to.equal(user1.address);
    expect(await nft.balanceOf(user1.address)).to.equal(1);
    expect(await nft.tokenTypeId(0)).to.equal(typeId);
    expect(await nft.minted(messageHash)).to.be.true;
  });


  it("should reject minting with invalid signatures or parameters", async function () {
    const { nft, signer, user1, user2 } = await loadFixture(deployContracts);

    await nft.setTypeInfo(1, "Holders NFT", "ipfs://holders");
    const typeId = 1;
    const baseTraits: Trait[] = [];

    const { signature } = await getMintSignature(
      nft,
      signer,
      user1.address,
      typeId,
      baseTraits
    );

    // 1. Reject invalid typeId
    await expect(
      nft.connect(user1).mint(user1.address, 99, baseTraits, signature)
    ).to.be.revertedWith("SatCoinNFT: Invalid typeId");

    // 2. Reject replay attack
    await nft.connect(user1).mint(user1.address, typeId, baseTraits, signature);
    await expect(
      nft.connect(user1).mint(user1.address, typeId, baseTraits, signature)
    ).to.be.revertedWith("SatCoinNFT: Already minted");

    // 3. Reject invalid signer
    const { signature: invalidSignature } = await getMintSignature(
      nft,
      user2,
      user2.address,
      typeId,
      baseTraits
    );
    await expect(
      nft.connect(user2).mint(user2.address, typeId, baseTraits, invalidSignature)
    ).to.be.revertedWith("SatCoinNFT: Invalid signature");
  });


  it("should return the correct tokenURI with dynamic data", async function () {
    const { nft, signer, user1 } = await loadFixture(deployContracts);

    // 1. Set type and mint an NFT
    await nft.setTypeInfo(1, "Holders NFT", "ipfs://holders/image.png");
    const typeId = 1;
    const baseTraits: Trait[] = [
      { key: "Level", value: "10", displayType: "number" },
      { key: "Power", value: "Super", displayType: "" },
    ];
    const { signature } = await getMintSignature(
      nft,
      signer,
      user1.address,
      typeId,
      baseTraits
    );
    await nft.connect(user1).mint(user1.address, typeId, baseTraits, signature);

    // 2. Get and parse tokenURI
    const tokenURI = await nft.tokenURI(0);
    expect(tokenURI.startsWith("data:application/json;base64,")).to.be.true;

    const base64Data = tokenURI.split(",")[1];
    const metadataJson = Buffer.from(base64Data, "base64").toString("utf-8");
    const metadata = JSON.parse(metadataJson);

    // 3. Verify metadata content
    expect(metadata.name).to.equal("SatCoin NFT #0");
    expect(metadata.image).to.equal("ipfs://holders/image.png");
    expect(metadata.attributes).to.be.an("array").with.lengthOf(3);

    // Verify dynamically added type attributes
    const typeTrait = metadata.attributes.find(
      (t: any) => t.trait_type === "NFT Type"
    );
    expect(typeTrait).to.not.be.undefined;
    expect(typeTrait.value).to.equal("Holders NFT");

    // Verify base attributes
    const levelTrait = metadata.attributes.find(
      (t: any) => t.trait_type === "Level"
    );
    expect(levelTrait).to.not.be.undefined;
    expect(levelTrait.value).to.equal(10n);
    expect(levelTrait.display_type).to.equal("number");
  });


  it("should return a valid tokenURI when minted without base traits", async function () {
    const { nft, signer, user1 } = await loadFixture(deployContracts);

    // 1. Set type and mint an NFT with an empty traits array
    await nft.setTypeInfo(2, "Basic NFT", "ipfs://basic/image.png");
    const typeId = 2;
    const baseTraits: Trait[] = []; // Empty traits array
    const { signature } = await getMintSignature(
      nft,
      signer,
      user1.address,
      typeId,
      baseTraits
    );
    await nft.connect(user1).mint(user1.address, typeId, baseTraits, signature);

    // 2. Get and parse tokenURI
    const tokenURI = await nft.tokenURI(0);
    const base64Data = tokenURI.split(",")[1];
    const metadataJson = Buffer.from(base64Data, "base64").toString("utf-8");
    const metadata = JSON.parse(metadataJson);

    // 3. Verify metadata content, especially the attributes
    expect(metadata.name).to.equal("SatCoin NFT #0");
    expect(metadata.image).to.equal("ipfs://basic/image.png");
    expect(metadata.attributes).to.be.an("array").with.lengthOf(1);

    const typeTrait = metadata.attributes[0];
    expect(typeTrait.trait_type).to.equal("NFT Type");
    expect(typeTrait.value).to.equal("Basic NFT");
  });


  it("should work with mock contract", async function () {
    const [owner, signer, user1] = await ethers.getSigners();
    const SatCoinNFTTestFactory = await ethers.getContractFactory("SatCoinNFTTest");
    const nft = (await upgrades.deployProxy(
      SatCoinNFTTestFactory,
      ["SatCoin NFT", "SCNFT", owner.address, signer.address],
    )) as unknown as SatCoinNFTTest;
    await nft.waitForDeployment();

    await nft.setTypeInfo(2, "Basic NFT", "ipfs://basic/image.png");
    const typeId = 2;
    const baseTraits: Trait[] = []; // Empty traits array
    const { signature } = await getMintSignature(
      nft,
      signer,
      user1.address,
      typeId,
      baseTraits
    );
    await nft.connect(user1).mint(user1.address, typeId, baseTraits, signature);

    await nft.updateAllTokenURIs();
    await nft.clearAllNFTs();
    expect(await nft.totalSupply()).to.equal(0);
  })

});