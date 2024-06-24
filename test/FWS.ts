import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import "@nomicfoundation/hardhat-ethers";
import hre from "hardhat";

describe("FWS", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployAllContractsFixture() {
    // Contracts are deployed using the first signer/account by default
    const [owner, provider, client] = await hre.ethers.getSigners();

    // Setup contracts
    const Escrow = await hre.ethers.getContractFactory("Escrow");
    const DealSLA = await hre.ethers.getContractFactory("DealSLANoCurrentFault");
    const SimplePDP = await hre.ethers.getContractFactory("SimplePDPService");

    const escrow = await Escrow.deploy();
    const dealSLA = await DealSLA.deploy();
    const simplePDP = await SimplePDP.deploy(escrow.getAddress());

    const chainId = await escrow.getChainId();

    // Setup ERC712
    // client signs the deals
    const domain = {
      name: "FWS Escrow",
      version: "v0.0.1",
      chainId: chainId,
      verifyingContract: await escrow.getAddress()
    }

    const types = {
      Deal: [
        { name: "CID", type: "bytes32" },
        { name: "client", type: "address" },
        { name: "provider", type: "address" },
        { name: "service", type: "address" },
        { name: "dealSLA", type: "address" },
        { name: "size", type: "uint256" },
      ]
    };
    const EIP712 = {domain, types}

    

    return { escrow, dealSLA, simplePDP, owner, provider, client, EIP712 };
  }

  describe("Deployment", function () {
    it("Should set the right escrow address", async function () {
      const { simplePDP, escrow } = await loadFixture(deployAllContractsFixture);
      expect(await simplePDP.escrowAddress()).to.equal(await escrow.getAddress());
    });
  });

  describe("SimplePDP", function () {
    it("Should not fail an empty update", async function () {
      const { simplePDP, escrow, dealSLA } = await loadFixture(deployAllContractsFixture);

      const proofSetID = await simplePDP.create(100)
      await simplePDP.updateSync(proofSetID.value, [], [], [])
    });

    it("Lifecyle Sync", async function () {
      const { simplePDP, escrow, dealSLA, provider, client, EIP712} = await loadFixture(deployAllContractsFixture);

      // provider creates a proofSet with frequency 100
      const proofSetID = await simplePDP.connect(provider)
        .create(100)

      // client makes two deals
      const CID0 = hre.ethers.encodeBytes32String("deal 0")
      const CID1 = hre.ethers.encodeBytes32String("deal 1")

      const newDeals = [{
        CID: CID0,
        client: await client.getAddress(),
        provider: await provider.getAddress(),
        service: await simplePDP.getAddress(),
        dealSLA: await dealSLA.getAddress(),
        size: 10,
      }, {
        CID: CID1,
        client: await client.getAddress(),
        provider: await provider.getAddress(),
        service: await simplePDP.getAddress(),
        dealSLA: await dealSLA.getAddress(),
        size: 10,
      }]

      const signatures = await Promise.all(newDeals.map(async deal => {
        const signature = await client.signTypedData(EIP712.domain, EIP712.types, deal);
        return signature;
      }))

      // client sends signed deals to provider
      // provider posts the new deals and respective signatures 
      await simplePDP.connect(provider)
        .updateSync(proofSetID.value, [], newDeals, signatures)
        

      // new deals are now onchain
      const deal0 = (await escrow.getDeal(0))
      const deal1 = (await escrow.getDeal(1))
      expect(CID0  == deal0.CID)
      expect(CID1  == deal1.CID)
    });
  });

});
