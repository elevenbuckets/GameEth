pragma solidity ^0.4.15;

import "./SafeMath.sol";
import "./StandardToken.sol";

contract LotteryToken is StandardToken {
        string public name = "Lottery Token";
        string public symbol = "GLT";
        uint public decimals = 8;

	// constructor
	function LotteryToken() {
                balances[msg.sender] = uint(90000000).mul(uint(10**decimals));
	}
}

