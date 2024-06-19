pragma solidity >=0.6.12 <0.9.0;

// Structs

import {PoDSILib, ProofData} from "./PoDSI.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// -- Deal
struct Deal {
  bytes32 CID;
  address client;
  address provider;
  address service;
  address dealSLA;
  uint256 size;
}

// -- Faults
struct Faults {
  uint256 from;
  uint256 to;
}

// -- ProofSet
struct ProofSet {
  uint256 frequency; // how often it is proven
  address provider;
  uint256 latestProofEpoch; // epoch when the latest valid proof was received
}

// Contracts

// -- DealSLAs
interface IDeal {
  function canRemoveDeal (Deal memory deal, uint256 escrowID) external view returns (bool);
}

contract DealSLANoCurrentFault {
  function canRemoveDeal (Deal memory deal, uint256 escrowID) external view returns (bool) {
    return IService(deal.service).dealFaults(deal, escrowID) == 0;
  }
}

// -- Escrow
contract Escrow {
  mapping(uint escrowID => Deal deal) deals;
  mapping(address => uint256) deposits; // ID

  uint256 IDCounter;
  
  string private constant EIP712_DOMAIN = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
  bytes32 constant private EIP712_DOMAIN_TYPEHASH = keccak256(abi.encodePacked(EIP712_DOMAIN));
  string private constant DEAL_TYPE = "Deal(bytes32 CID,address client,address provider,address service,address dealSLA,uint256 size)";
  bytes32 constant private DEAL_TYPEHASH = keccak256(abi.encodePacked(DEAL_TYPE));

  bytes32 private DOMAIN_SEPARATOR = keccak256(abi.encode(
        EIP712_DOMAIN_TYPEHASH,
        keccak256("FWS Escrow"),
        keccak256("v0.0.1"),
        1, // replace this with your chain id
        address(this)
    ));

  function hashDeal(Deal memory deal) private view returns (bytes32) {
    return keccak256(abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        keccak256(abi.encode(
            DEAL_TYPEHASH,
            deal.CID,
            deal.client,
            deal.provider,
            deal.service,
            deal.dealSLA,
            deal.size
        ))
    ));
  }

  function verifyDealSignature(Deal memory deal, bytes memory signature) public view returns (address) {
    bytes32 digest = hashDeal(deal);
    address signer = ECDSA.recover(digest, signature);
    require(deal.client == signer, "signer not the same as signature");
  }



  function start(Deal calldata deal, bytes calldata signature) public returns (uint256) {
    // TODO only the provider (via the service) can do this

    verifyDealSignature(deal, signature);

    deals[IDCounter] = deal;

    return IDCounter++;
  }

  function remove(uint256 dealID) public {
    // TODO either the user or the provider can do this

    Deal memory deal = deals[dealID];

    require(
      IDeal(deal.dealSLA).canRemoveDeal(deal, dealID),
      "Cannot remove"
    );

    delete deals[dealID];
  }

  function deposit() public payable {
    deposits[msg.sender] += msg.value;
  }

  function getDeal(uint256 escrowID) public view returns (Deal memory deal) {
    return deals[escrowID];
  }

  function withdraw(uint256 amount) public payable {
    // TODO
    // check if you can withdraw
    // check how much it can be withdrew
    // dealSLA.checkService

    deposits[msg.sender] -= amount;
  }
}

// -- Services

interface IService {
  function dealFaults(Deal calldata deal, uint256 escrowID) external view returns (uint);
}

// ---- Proof Set service (a set of deals proven together)
contract ProofSetService {
  //Events
  event NewProofSet(uint256 ID);
  event FaultsEvent(uint256 ID, uint256 latestEpoch, uint256 missed);
  // State
  uint256 IDCounter = 0;
  mapping(uint256 ID => ProofSet) proofSets;
  mapping(uint256 proofSetID => Faults[]) faults;

  // Creates a dataset to be proven
  function create(uint256 frequency) public returns (uint256 ID) {
    // Map the ID to CommD and StorageProvider
    proofSets[ID] = ProofSet({
      frequency: frequency,
      latestProofEpoch: block.number,
      provider: msg.sender
    });
    // Map the ID to creationEpoch
    proofSets[ID].latestProofEpoch = block.number; //this should be the function setting current epoch
    // Emit the event
    emit NewProofSet(ID);
    // Returns the ID
    return IDCounter++;
  }

  function currentFaults (uint256 ID) public virtual view returns (uint faults) {
    require(ID < IDCounter, "Out of boundary");
    return ((block.number - proofSets[ID].latestProofEpoch) / proofSets[ID].frequency);
  }

  function _onValidProof(uint256 ID) internal {

    // If previous proofs were missed
    uint proofsMissed = this.currentFaults(ID);
    if (proofsMissed > 0) {       
      emit FaultsEvent(ID, proofSets[ID].latestProofEpoch, proofsMissed);
      faults[ID].push(Faults(proofSets[ID].latestProofEpoch, block.number));
    }

    proofSets[ID].latestProofEpoch = block.number;
  }

  // an escrow will run the sync
  function sync(uint256 ID) public virtual returns (uint256) {
    // require that the owner can call this
    uint256 faultsToDate = faults[ID].length;
    delete faults[ID];

    return faultsToDate;
  }

  // terminate a dataset 
  function terminateProofSet(uint256 ID) public virtual returns (bool) {
    // TODO require that the owner can call this

    delete proofSets[ID];
    return true;
  }

  // Read methods
  function getProofSetById(uint256 ID) public virtual view returns (ProofSet memory) {
    ProofSet memory proofSet = proofSets[ID];
    return proofSet;
  }
}

// ---- Deal Stored Onchain is a service where deals are proven together and stored on-chain
contract DealStoredOnchain is ProofSetService {
  struct ProofSetIndex {
    uint256 index;
    uint256 proofSetID;
  }

  mapping(uint proofSetID => uint256[] escrowID) dealsMap;
  mapping(uint256 escrowID => ProofSetIndex psIndex) dealsIndex;
  address public escrowAddress;

  function dealFaults(uint256 escrowID) public view returns (uint) {
    return currentFaults(dealsIndex[escrowID].proofSetID);
  }

  function update (uint256 proofSetID, uint256[] calldata removeDeals, Deal[] calldata newDeals, bytes[] calldata newDealsSignature) public virtual {
    require(currentFaults(proofSetID) == 0, "Proof set is faulty, can not be updated");
    uint proofSetLength = dealsMap[proofSetID].length;

    for (uint i = 0; i < removeDeals.length; i++) {
      require(removeDeals[i] < proofSetLength, "Deal ID is out of bounds");

      uint256 escrowID = removeDeals[i];
      ProofSetIndex memory psIndex = dealsIndex[escrowID];
      require(psIndex.proofSetID == proofSetID, "Deal is not in the same proof set");

      uint256 index = psIndex.index;

      // Remove from escrow
      Escrow(escrowAddress).remove(escrowID);

      if (i < newDeals.length) {
        // If new deals are added, update the index
        uint256 newEscrowID = Escrow(escrowAddress).start(newDeals[i], newDealsSignature[i]);
        dealsMap[proofSetID][index] = newEscrowID;
        dealsIndex[escrowID] = ProofSetIndex(index, proofSetID);

      } else {
        // If no new deals are added, remove the index by moving the last element here
        uint lastIndex = dealsMap[proofSetID].length - 1;
        uint lastEscrowID = dealsMap[proofSetID][lastIndex];
        dealsMap[proofSetID][index] = lastEscrowID;
        dealsIndex[lastEscrowID] = ProofSetIndex(index, proofSetID);
        dealsMap[proofSetID].pop();
      }
    }

    uint index = dealsMap[proofSetID].length;
    for (uint i = removeDeals.length; i < newDeals.length; i++) {
      // If there are more new deals than removed deals, add them at the end of the list
      uint256 escrowID = Escrow(escrowAddress).start(newDeals[i], newDealsSignature[i]);
      dealsMap[proofSetID].push(escrowID);
      dealsIndex[escrowID] = ProofSetIndex(index, proofSetID);
      index++;
    }
  }
}

// ---- Simple PDP Service

// Finally, this is a usable Simple PDP Service
contract SimplePDPService is ProofSetService, DealStoredOnchain {
  constructor (address _escrow)  {
    escrowAddress = _escrow;
  }

  function prove (
    uint256 proofSetID,
    uint256 challenge,
    ProofData calldata proof,
    bytes32 leaf
  ) public {
    uint256 challengedIndex = challenge % dealsMap[proofSetID].length;
    uint256 challengedEscrowID = dealsMap[proofSetID][challengedIndex];

    // TODO potentially move this into the service state
    Deal memory deal = Escrow(escrowAddress).getDeal(challengedEscrowID);

    // TODO verify proof
    require(PoDSILib.verify(proof, leaf, deal.CID), "Proof did not verify");

    super._onValidProof(proofSetID);
  }
}