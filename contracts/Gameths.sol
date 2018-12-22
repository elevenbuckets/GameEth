pragma solidity ^0.4.24;

import "./ERC20.sol";

contract Battleship {
	// Variables
	address public playerA;
	address public winner;
	uint constant public maxPlayer = 1000;
	uint constant public period = 5;
	uint public initHeight;
	bytes32 public difficulty;
	uint public fee = 10000000000000000;
	bool public setup = false;
	uint public playercount = 0;

	struct playerInfo {
		address wallet; // msg.sender
		uint since;     // block height when joined
		bytes32 ticket; // board
		uint8[64] slots;
		uint8 v;
		bytes32 r;
		bytes32 s; 
	}

	mapping (address => playerInfo) playerDB;
	mapping (uint => address) playerList;

	// Modifiers
	modifier WinnerOnly() {
		require(winner != address(0) && msg.sender == winner);
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

	modifier notYourself() {
		require(msg.sender != playerA);
		_;
	}

	// Contract constructor
	constructor(bytes32 _difficulty) payable feePaid {
		playerA = msg.sender;
		initHeight = block.number;
		difficulty = _difficulty;

		// PlayerA board
		playerInfo memory newone;

		newone.wallet = msg.sender;
		newone.since  = block.number;
		newone.ticket = sha3(sha3(abi.encodePacked(msg.sender, blockhash(block.number - 1))));

		playerDB[msg.sender] = newone;
		playerList[playercount] = msg.sender; 
		playercount += 1;
	}

	// WinnerOnly
	function withdraw() WinnerOnly returns (bool) {
		require(msg.sender.send(this.balance));
		return true;
	}

	// Constant functions
	function equalTest(bytes32 a, bytes32 b, uint slot) constant returns (byte, byte) {
		return (a[slot], b[slot]);
	}

	function myInfo() constant returns (uint, bytes32) {
		return (playerDB[msg.sender].since, playerDB[msg.sender].ticket);
	}

	// Join game (registration)
	function register(uint8 v, bytes32 r, bytes32 s, uint[64] slots) payable feePaid notYourself returns (bool) {
		require(playerDB[msg.sender].since == 0);
		require(playercount + 1 <= maxPlayer);

		playerInfo memory newone;

		newone.wallet = msg.sender;
		newone.since  = block.number;
		newone.v = v; newone.r = r; newone.s = s;

		playerDB[msg.sender] = newone;
		playerList[playercount] = msg.sender; 
		playercount += 1;

		return true;
	}

	function revealSecret(bytes32 secret) returns (bool) {
	}

	// fallback
  	function () payable { revert(); }

}
