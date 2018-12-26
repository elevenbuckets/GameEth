pragma solidity ^0.4.24;

import "./ERC20.sol";

contract Battleship {
	// Variables
	address public defender;
	address public winner;
	uint constant public maxPlayer = 1000;
	uint constant public period = 25;
	uint public initHeight;
	bytes32 public board;
	uint public fee = 10000000000000000;
	bool public setup = false;
	uint public playercount = 0;

	struct playerInfo {
		address wallet; // msg.sender
		uint since;     // block height when joined
		uint8 v;
		bytes32 r;
		bytes32 s; 
	}

	struct battleStat {
		uint battle;
		uint height;
		bytes32 merkleRoot;
		bytes32 secret;
		bytes32 score;
		bytes32 bhash;
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

	modifier gameStalled() {
		require(setup == true && block.number > initHeight + period && winner == address(0));
		_;
	}

	modifier notDefender() {
		require(msg.sender != defender);
		_;
	}

	// Contract constructor
	constructor(bytes32 _init) public payable {
		require(msg.value >= fee);
		defender = msg.sender;

		require(fortify(_init) == true);
	}

	// WinnerOnly
	function withdraw() public WinnerOnly returns (bool) {
		require(block.number > initHeight + period);
		setup = false;
		winner = address(0);
		board = bytes32(0);
		playercount = 0;
		require(msg.sender.send(address(this).balance) == true);

		return true;
	}

	// Constant functions
	function equalTest(bytes32 a, bytes32 b, uint slot) public pure returns (byte, byte) {
		return (a[slot], b[slot]);
	}

	function myInfo() public view returns (uint, uint8, bytes32, bytes32, uint) {
		return (playerDB[msg.sender].since, playerDB[msg.sender].v, playerDB[msg.sender].r, playerDB[msg.sender].s, initHeight);
	}

	function fortify(bytes32 defense) public payable feePaid defenderOnly NewGameOnly returns (bool) {
		playerInfo memory newone;

		newone.wallet = msg.sender;
		newone.since  = block.number;
		board = defense;

		initHeight = block.number;
		playerDB[msg.sender] = newone;
		playercount += 1;
		setup = true;

		return true;
	}

	// Join game
	function challenge(uint8 v, bytes32 r, bytes32 s) public payable feePaid notDefender gameStarted returns (bool) {
		require(playerDB[msg.sender].since < initHeight);
		require(playercount + 1 <= maxPlayer);

		playerInfo memory newone;

		newone.wallet = msg.sender;
		newone.since  = block.number;
		newone.v = v; newone.r = r; newone.s = s;

		playerDB[msg.sender] = newone;
		playercount += 1;

		return true;
	}

	function revealSecret(bytes32 secret, bytes32 score, bool[32] memory slots) public notDefender returns (bool) {
		require(block.number <= initHeight + period && block.number >= initHeight + 5);
		require(playerDB[msg.sender].since > initHeight);
		require(ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", secret)), playerDB[msg.sender].v, playerDB[msg.sender].r, playerDB[msg.sender].s) == msg.sender);

		battleStat memory newbat;
		newbat.battle = initHeight;
		newbat.secret = secret;
		newbat.bhash = blockhash(block.number - 1);
		newbat.score = keccak256(abi.encodePacked(secret, blockhash(block.number - 1))); // initialize for the loop below

		for (uint i = 0; i <= 31; i++) {
			if(slots[i] == false) {
				assert(score[i] == board[i]);
			} else {
				assert(score[i] == newbat.score[i]);
			}
		}

		newbat.score = score;
		battleHistory[initHeight][msg.sender] = newbat;

		// ToDo: majority merkle root voting and checking of each submission 
		if (winner == address(0) && newbat.score < board) {
			winner = msg.sender;
		} else if (newbat.score < battleHistory[initHeight][winner].score) {
			winner = msg.sender;
		}

		return true;
	}

	// fallback
  	function () defenderOnly gameStalled external { winner = defender; return withdraw(); }
}
