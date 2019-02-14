pragma solidity ^0.5.2;
import './erc721_interface.sol';
import './erc721-enumerable.sol';

contract iELEM is ERC721, ERC721Enumerable {
    function mint(address _to, uint256 _tokenId, string calldata _uri) external returns (bool);
    function burn(uint256 _tokenId) external returns (bool);
    function pause() external;
    function unpause() public;
    function setMining(address miningAddress, uint8 idx) external returns (bool);
    function addManager(address _newAddr, uint8 idx) external returns (bool);
}
