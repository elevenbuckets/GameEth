pragma solidity ^0.4.24;

import "./ERC20.sol";
import "./SafeMath.sol";
import "./RNTInterface.sol";

contract BattleShip {
	using SafeMath for uint256;
	// Variables
	address public defender;
	address public winner;
	address public RNTAddr;
	uint constant public maxPlayer = 1000;
	uint constant public period = 11;
	uint public initHeight;
	bytes32 public difficulty = 0x000000000000000000000000000000ffffffffffffffffffffffffffffffffff;
	bytes32 public board;
	uint public fee = 10000000000000000;
	bool public setup = false;
	uint public playercount = 0;
	bytes32[3] private samGroup;

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
	constructor(bytes32 _init, address _RNTAddr) public payable {
		require(msg.value >= fee);
		defender = msg.sender;
		RNTAddr  = _RNTAddr;

		require(fortify(_init) == true);
	}

	// WinnerOnly
	function withdraw() public WinnerOnly returns (bool) {
		require(block.number > initHeight + period);
		setup = false;
		winner = address(0);
		board = bytes32(0);
		playercount = 0;

		uint256 reward = uint256(address(this).balance).mul(uint256(6)) / uint256(10);
		require(RNTInterface(RNTAddr).mint(msg.sender) == true);
		require(msg.sender.send(reward) == true);

		return true;
	}

	function randomNumber() public view returns (bytes32) {
		return keccak256(abi.encodePacked(samGroup[0], samGroup[1], samGroup[2], blockhash(block.number - 1)));
	}

	function myInfo() public view returns (uint, uint8, bytes32, bytes32, uint) {
		return (playerDB[msg.sender].since, playerDB[msg.sender].v, playerDB[msg.sender].r, playerDB[msg.sender].s, initHeight);
	}

	function fortify(bytes32 defense) public payable feePaid defenderOnly NewGameOnly returns (bool) {
		require(defense > difficulty);
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

	function testOutcome(bytes32 secret, uint blockNo) public gameStarted view returns (bytes32 _board, bool[32] memory _slots) {
		require(block.number <= initHeight + period && block.number >= initHeight);
		require(block.number - blockNo < period - 5);
		require(blockNo <= block.number - 1 && blockNo < initHeight + period && blockNo >= initHeight + 5);

		_board = keccak256(abi.encodePacked(secret, blockhash(blockNo)));

		for (uint i = 0; i <= 31; i++) {
			if(_board[i] < board[i]) {
				_slots[i] = true;
			}
		}

		return (_board, _slots);
	}

	function reviveReward() public gameStarted notDefender returns (bool) {
		require(battleHistory[initHeight][msg.sender].battle == initHeight);
		require(block.number == initHeight + period);

		bytes32 _board = keccak256(abi.encodePacked(battleHistory[initHeight][msg.sender].score, blockhash(block.number - 1)));

		if (_board[30] == board[30] && _board[31] == board[31]) {
			battleHistory[initHeight][msg.sender].battle = 0;
			samGroup[2] = _board;
			require(RNTInterface(RNTAddr).mint(msg.sender) == true);
			return true;
		} else {
			revert();
		}
	}

	function revealSecret(bytes32 secret, bytes32 score, bool[32] memory slots, uint blockNo) public gameStarted notDefender returns (bool) {
		require(playerDB[msg.sender].since > initHeight);
		require(battleHistory[initHeight][msg.sender].battle == 0);
		require(block.number <= initHeight + period && block.number >= playerDB[msg.sender].since + 5);
		require(block.number - blockNo < period - 5);
		require(blockNo <= block.number - 1 && blockNo < initHeight + period && blockNo >= initHeight + 5);
		require(ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", secret)), playerDB[msg.sender].v, playerDB[msg.sender].r, playerDB[msg.sender].s) == msg.sender);

		battleStat memory newbat;
		newbat.battle = initHeight;
		newbat.secret = secret;
		newbat.bhash = blockhash(blockNo);
		newbat.score = keccak256(abi.encodePacked(secret, blockhash(blockNo))); // initialize for the loop below

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
			samGroup[0] = newbat.score;
		} else if (newbat.score < battleHistory[initHeight][winner].score) {
			winner = msg.sender;
			samGroup[1] = samGroup[0];
			samGroup[0] = newbat.score;
		}

		samGroup[2] = newbat.score;

		return true;
	}

	// fallback
  	function () defenderOnly gameStalled external { 
  	    winner = defender; 
  	    require(withdraw()); 
  	}
}
