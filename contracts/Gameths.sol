pragma solidity ^0.4.15;

import "./ERC20.sol";

contract Gameths {
	// Variables
	address public owner;
	address public token;
	uint public maxPlayer;
	uint public initHeight;
	uint public difficulty = 3;
	bool public setup = false;
	uint public period = 5;
	uint public futureBlockCovered;
	uint public fee = 5000000000000000;
	uint public closerCount;

	struct playerInfo {
		address wallet; // msg.sender
		uint since;     // block height when joined
		bytes32 ticket; // sha3(wallet + block.blockhash(block.number - 1)
		uint canCall; 
	}

	mapping (address => playerInfo) playerDB;
	mapping (uint => address) playerList;

	// Modifiers
	modifier OwnerOnly() {
		require(msg.sender == owner);
		_;
	}

	modifier NewGameOnly() {
		require(setup == false);
		_;
	}

	modifier feePaid() {
		require(msg.value >= fee);
		_;
	}

	modifier gameStarted() {
		require(setup == true);
		_;
	}

	// Contract constructor
	function Gameths() {
		owner = msg.sender;
		initHeight = block.number;
	}

	// Setup function, only can be called once per round.
	function setupGame(address _token, uint amount, uint _maxPlayer) OwnerOnly NewGameOnly returns (bool) {
		require(ERC20(token).balanceOf(msg.sender) >= amount);

		token = _token;
		maxPlayer = _maxPlayer;

		require(ERC20(token).transferFrom(msg.sender, this, amount) == true);

		setup = true;

		return setup;
	}

	// OwnerOnly
	function withdraw() OwnerOnly returns (bool) {
		require(msg.sender.send(this.balance));

		return true;
	}

	// DEBUG OwnerOnly
	function changeDiff(uint newdiff) OwnerOnly returns (bool) {
		require(newdiff < 32 && newdiff > 0);
		difficulty = newdiff;

		return true;
	}

	// Constant functions
	function equalTest(bytes32 a, bytes32 b, uint slot) constant returns (byte, byte) {
		return (a[slot], b[slot]);
	}

	/*
	function bytes32ArrayToString (bytes32[] data) constant returns (string) {
    		bytes memory bytesString = new bytes(data.length * 32);
    		uint totalLength;

    		for (uint i=0; i<data.length; i++) {
        		for (uint j=0; j<32; j++) {
            			byte char = data[i][j];
            			if (char != 0) {
                			bytesString[totalLength] = char;
                			totalLength += 1;
            			}
        		}
    		}

    		bytes memory bytesStringTrimmed = new bytes(totalLength);
    		for (i=0; i<totalLength; i++) {
        		bytesStringTrimmed[i] = bytesString[i];
    		}

    		return string(bytesStringTrimmed);
	}
        */

        // for debug purposes, we commented out won condition check
	function checkMinedTickets(bytes32 _blockhash_won, bytes32 minedTicket) constant returns (bool) {
		//require(won == true);

		for (uint i=31; i>(31-difficulty); i--) {
			if (byte(_blockhash_won[i]) != byte(minedTicket[i])) return false;
		}

		return true;
	}

	// for debug purposes, we allow returning bytes32.
	function miningTicket(address player, uint nonce) constant returns (bytes32) {
		require(playerDB[player].since != 0);

		return sha3(sha3(bytes32(uint(playerDB[player].ticket) + nonce)));
	}

	function checkTickets(bytes32 _blockhash, address player) constant returns (bool) {
		if (playerDB[player].since == 0) return false;

		for (uint i=31; i>(31-difficulty); i--) {
			if (byte(_blockhash[i]) != byte(playerDB[player].ticket[i])) return false;
		}

		return true;
	}

	function myInfo() constant returns (uint, bytes32) {
		return (playerDB[msg.sender].since, playerDB[msg.sender].ticket);
	}

	// Join game (registration)
	// for debug no gameStarted modifier yet ...
	function register() payable feePaid returns (bool) {
		require(playerDB[msg.sender].since == 0);

		playerInfo memory newone;
		closerCount += 1;

		newone.wallet = msg.sender;
		newone.since  = block.number;
		newone.ticket = sha3(sha3(msg.sender));

		playerDB[msg.sender] = newone;
		playerList[closerCount] = msg.sender;

		return true;
	}

	// Jackpot
	// for debug, no gameStarted modifier yet...
	// for debug, turning it into constant function.
	function Jackpot() constant returns (uint, bytes32, bool) {
		require(playerDB[msg.sender].since != 0);
		require(block.number - playerDB[msg.sender].since > 6);

		return ((block.number - 1), block.blockhash(block.number - 1), checkTickets(block.blockhash(block.number - 1), msg.sender));
	}

	// fallback
  	function () payable { revert(); }

}
