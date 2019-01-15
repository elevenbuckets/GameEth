pragma solidity ^0.4.24;

contract MerkleTreeValidatorInterface {
    function uploadMerkleRoot(uint256 blockNo, bytes32 root, bytes32 bufmessage) external returns (bool);
    function validate(bytes32[] memory proof, bool[] memory isLeft, bytes32 targetLeaf, bytes32 merkleRoot) public pure returns (bool);
}
