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
    const [owner, otherAccount] = await hre.ethers.getSigners();

    const Escrow = await hre.ethers.getContractFactory("Escrow");
    const DealSLA = await hre.ethers.getContractFactory("DealSLANoCurrentFault");
    const SimplePDP = await hre.ethers.getContractFactory("SimplePDPService");

    const escrow = await Escrow.deploy();
    const dealSLA = await DealSLA.deploy();

    const simplePDP = await SimplePDP.deploy(escrow.getAddress());

    return { escrow, dealSLA, simplePDP, owner, otherAccount };
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
      const emptyUpdate = await simplePDP.update(proofSetID.value, [], [])
    });

    it("Lifecyle", async function () {
      const { simplePDP, escrow, dealSLA, otherAccount, owner} = await loadFixture(deployAllContractsFixture);

      const proofSetID = await simplePDP.create(100)
      const updateWithADeal = await simplePDP.update(proofSetID.value, [], [{
        CID: hre.ethers.encodeBytes32String("hi"),
        client: await otherAccount.getAddress(),
        provider: await owner.getAddress(),
        service: await simplePDP.getAddress(),
        dealSLA: await dealSLA.getAddress(),
        size: 10,
      }])
    });
  });

});
