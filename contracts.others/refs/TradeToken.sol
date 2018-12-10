pragma solidity ^0.4.15;

import "./SafeMath.sol";
import "./StandardToken.sol";

contract TradeToken is StandardToken {
        string public name = "Trade Test Token";
        string public symbol = "TTT";
        uint public decimals = 8;

	// constructor
	function TradeToken() {
                balances[msg.sender] = uint(9000000).mul(uint(10**decimals));
	}
}

