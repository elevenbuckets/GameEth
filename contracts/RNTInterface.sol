pragma solidity ^0.4.24;
import "./StandardToken.sol";

contract RNTInterface is StandardToken {
    function symbol() public view returns (string);
    function decimals() public view returns (uint8);
    function setMining(address miningAddress) external returns (bool); 
    function mint(address toAddress) external returns (bool);
    function burn(uint256 amount) external returns (bool);
}
