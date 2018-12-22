pragma solidity ^0.4.24;

import "./ERC20.sol";

contract Battleship {
	// Variables
	address public defender;
	address public winner;
	uint constant public maxPlayer = 1000;
	uint constant public period = 10;
	uint public initHeight;
	bytes32 public difficulty;
	uint public fee = 10000000000000000;
	bool public setup = false;
	uint public playercount = 0;

	struct playerInfo {
		address wallet; // msg.sender
		uint since;     // block height when joined
		bytes32 ticket; // board
		bool[32] slots;
		uint8 v;
		bytes32 r;
		bytes32 s; 
	}

	struct battleStat {
		uint battle;
		bytes32 merkleRoot;
		bytes32 secret;
		bytes32 score;
	}

	mapping (address => playerInfo) playerDB;
	mapping (uint => mapping (address => battleStat)) battleHistory;

	// Modifiers
	modifier defenderOnly() {
		require(msg.sender == defender);
		_;
	}

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

	modifier notDefender() {
		require(msg.sender != defender);
		_;
	}

	// Contract constructor
	constructor(bytes32 _difficulty, bytes32 _init) payable feePaid {
		defender = msg.sender;
		difficulty = _difficulty;

		fortify(_init);
	}

	// WinnerOnly
	function withdraw() WinnerOnly returns (bool) {
		require(block.number > initHeight + period);
		require(msg.sender.send(this.balance));
		setup = false;
		winner = address(0);
		playercount = 0;

		return true;
	}

	// Constant functions
	function equalTest(bytes32 a, bytes32 b, uint slot) constant returns (byte, byte) {
		return (a[slot], b[slot]);
	}

	function myInfo() constant returns (uint, bytes32) {
		return (playerDB[msg.sender].since, playerDB[msg.sender].ticket);
	}

	function fortify(bytes32 defense) defenderOnly NewGameOnly returns (bool) {
		playerInfo memory newone;

		newone.wallet = msg.sender;
		newone.since  = block.number;
		newone.ticket = defense;

		initHeight = block.number;
		playerDB[msg.sender] = newone;
		playercount += 1;

		return true;
	}

	// Join game
	function challenge(uint8 v, bytes32 r, bytes32 s, bool[32] slots) payable feePaid notDefender returns (bool) {
		require(playerDB[msg.sender].since < initHeight);
		require(playercount + 1 <= maxPlayer);

		playerInfo memory newone;

		newone.wallet = msg.sender;
		newone.since  = block.number;
		newone.v = v; newone.r = r; newone.s = s;
		newone.slots = slots;

		playerDB[msg.sender] = newone;
		playercount += 1;

		return true;
	}

	function revealSecret(bytes32 secret) notDefender returns (bool) {
		require(block.number <= initHeight + period && block.number >= initHeight + 5);
		require(playerDB[msg.sender].since > initHeight);
		require(ecrecover(sha3("\x19Ethereum Signed Message:\n32", sha256(secret)), playerDB[msg.sender].v, playerDB[msg.sender].r, playerDB[msg.sender].s) == msg.sender);

		battleStat memory newbat;
		newbat.battle = initHeight;
		newbat.secret = secret;
		newbat.score  = keccak256(abi.encodePacked(secret, blockhash(initHeight))); // initialize for the loop below

		for (uint i = 0; i <= 31; i++) {
			if(playerDB[msg.sender].slots[i] == false) {
				newbat.score[i] = playerDB[defender].ticket[i];
			}
		}

		battleHistory[initHeight][msg.sender] = newbat;

		if (Winner == address(0) && newbat.score < playerDB[defender].ticket) {
			Winner = msg.sender;
		} else if (newbat.score < battleHistory[initHeight][Winner].score) {
			Winner = msg.sender;
		}

		return true;
	}

	// fallback
  	function () payable { revert(); }

}
