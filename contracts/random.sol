pragma solidity ^0.4.15;

contract random {

	uint256 public r = 0;

	function random() {}
	function reset() returns (bool) { r = 0;  return true; }
	function rand(uint i) constant returns (uint256) { return r - i; }
	function set(uint i) returns (bool) { r = r - i; return true; }
	function mset(uint i) returns (bool) { r = r ** i; return true; }
	function () payable { revert(); }
}
