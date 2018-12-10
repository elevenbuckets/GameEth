pragma solidity ^0.4.15;

import "./SafeMath.sol";
import "./StandardToken.sol";

contract BucketToken is StandardToken {
        string public name = "Bucket Token";
        string public symbol = "BUCK";
        uint public decimals = 8;

	// constructor
	function BucketToken() {
                balances[msg.sender] = uint(40000000).mul(uint(10**decimals));
	}
}

