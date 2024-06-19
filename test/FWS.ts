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

    const Escrow = await hre.ethers.getContractFactory("Escrow");
    const DealSLA = await hre.ethers.getContractFactory("DealSLANoCurrentFault");
    const SimplePDP = await hre.ethers.getContractFactory("SimplePDPService");

    const escrow = await Escrow.deploy();
    const dealSLA = await DealSLA.deploy();

    const simplePDP = await SimplePDP.deploy(escrow.getAddress());

    return { escrow, dealSLA, simplePDP, owner, provider, client };
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
      await simplePDP.update(proofSetID.value, [], [], [])
    });

    it("Lifecyle", async function () {
      const { simplePDP, escrow, dealSLA, provider, client} = await loadFixture(deployAllContractsFixture);

      // provider creates a proofSet withe frequency 100
      const proofSetID = await simplePDP.connect(provider)
        .create(100)

      // provider updates the proofset with new deal
      const newDeals = [{
        CID: hre.ethers.encodeBytes32String("deal 0"),
        client: await client.getAddress(),
        provider: await provider.getAddress(),
        service: await simplePDP.getAddress(),
        dealSLA: await dealSLA.getAddress(),
        size: 10,
      }, {
        CID: hre.ethers.encodeBytes32String("deal 1"),
        client: await client.getAddress(),
        provider: await provider.getAddress(),
        service: await simplePDP.getAddress(),
        dealSLA: await dealSLA.getAddress(),
        size: 10,
      }]

      const domain = {
        name: "FWS Escrow",
        version: "v0.0.1",
        chainId: 1,
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

      // Signed deals
      const signatures = await Promise.all(newDeals.map(async deal => {
        const signature = await client.signTypedData(domain, types, deal);
        return signature;
      }))

      await simplePDP.connect(provider)
        .update(proofSetID.value, [], newDeals, signatures)
        

      const deal0 = (await escrow.getDeal(0))
      const deal1 = (await escrow.getDeal(1))
    });
  });

});
