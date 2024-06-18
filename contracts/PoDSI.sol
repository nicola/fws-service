pragma solidity >=0.6.12 <0.9.0;

bytes32 constant TRUNCATOR = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff3f;

struct ProofData {
    uint64 index;
    bytes32[] path;
}

library PoDSILib {
  function computeRoot(ProofData memory d, bytes32 subtree) internal pure returns (bytes32) {
    require(d.path.length < 64, "merkleproofs with depths greater than 63 are not supported");
    require(d.index >> d.path.length == 0, "index greater than width of the tree");

    bytes32 carry = subtree;
    uint64 index = d.index;
    uint64 right = 0;

    for (uint64 i = 0; i < d.path.length; i++) {
      (right, index) = (index & 1, index >> 1);
      if (right == 1) {
        carry = computeNode(d.path[i], carry);
      } else {
        carry = computeNode(carry, d.path[i]);
      }
    }

    return carry;
  }

  // computeNode computes the parent node of two child nodes
  function computeNode(bytes32 left, bytes32 right) internal pure returns (bytes32) {
    bytes32 digest = sha256(abi.encodePacked(left, right));
    return truncate(digest);
  }

  // truncate truncates a node to 254 bits.
  function truncate(bytes32 n) internal pure returns (bytes32) {
    // Set the two lowest-order bits of the last byte to 0
    return n & TRUNCATOR;
  }

  function verify(
    ProofData memory proof,
    bytes32 root,
    bytes32 leaf
  ) internal pure returns (bool) {
    return computeRoot(proof, leaf) == root;
  }
}