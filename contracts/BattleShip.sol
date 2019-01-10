pragma solidity ^0.4.24;

import "./ERC20.sol";
import "./SafeMath.sol";
// import "./RNTInterface.sol";
import "./MerkleTreeValidatorInterface.sol";

// About the game
// # Roles
//  * defender : setup the game (only the fee)
//  * player : join the game, max 1000 players, pay 0.01 eth and can win 150 RNT potentially
//  * validator: provide merkle proof in block `n` (a tiny amount)
//
// # state channel (sc):
//  * users send hashed-score (signed) before `n`
//  * validator provide a merkle root, and put the root on-chain at block `n`
//    - validator (or player) generate tickets, but players can only use the ticket if they `revealSecret()`
//  * [?] another merkle tree based on tickets generated at block `m`
// 
// # time line of a game:
//    start ------------ n ------- m -------------------------------- end
//          calc and reg   reveal    lottery, each round: 0-n winners
//          submit to sc   secret    and random number
//          (period1)      (period2) (period3)
//
//  * period_all = period1 + period2 + period3
//  * during period2 (btw. `n` and `m`): generate tickets for players (verify on sc, also stored on sc?)
//  * there is a winner of battleship game at block `m`, who can withdraw btw. the end and several blocks after end
//  * probably, at block `n` and `m` players do nothing. Leave these as buffer for sc to do something
//  * player obtain ticket in the form `ticket[i] = hash(score + bn[m-1] + i)` where 1<=i<=5, depend on score
// todo: add an upper limit for the contract to give to players? Such as (the order of) 1000*0.01 eth = 10 eth = 1e5 RNT

contract BattleShip {
	using SafeMath for uint256;
	address public defender;
	address public winner;
	address public validator;
	// address public RNTAddr;  // add these back later
	uint constant public maxPlayer = 1000;
	uint constant public period1 = 5;
	uint constant public period2 = 3;
	uint constant public period3 = 22;
	uint constant public period_all = period1 + period2 + period3  // shoudl be in the range 30-120
	uint public initHeight;
	// bytes32 public difficulty = 0x000000000000000000000000000000ffffffffffffffffffffffffffffffffff;
	bytes32 public board;
	uint public fee = 10000000000000000;
	bool public setup = false;
	uint public playercount = 0;
	bytes32[3] private sampleGroup;  // [0],[1] are best 2 scores, [2] is the last submitted
	bytes32[2] public merkleRoot; // leaves of 1st tree: hash(score), 2nd: tickets. submitted by validator

        address constant public MerkleTreeAddr = 0x127bfc8AFfdCaeee6043e7eC79239542e5A470B7;

	struct playerInfo {
		address wallet; // msg.sender
		uint since;     // block height when joined
	}

	struct battleStat {
		uint battle;
		// uint height;
		bytes32 secret;
		bytes32 score;
		// bytes32 bhash;
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

	modifier ValidatorOnly() {
	        require(validator != address(0) && msg.sender == validator);
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


	// modifier gameStalled() {
	// 	require(setup == true && block.number > initHeight + period_all && winner == address(0));
	// 	_;
	// }

	modifier notDefender() {
		require(msg.sender != defender);
		_;
	}

	// Contract constructor
	constructor(bytes32 _init, address _validator) public payable {
		require(msg.value >= fee);
		defender = msg.sender;
		validator = _validator;
		// RNTAddr  = _RNTAddr;

		require(fortify(_init) == true);
	}

	function fortify(bytes32 defense) internal payable feePaid defenderOnly NewGameOnly returns (bool) {
		// require(defense > difficulty);
		playerInfo memory newone;

		newone.wallet = msg.sender;
		newone.since  = block.number;
		board = defense;

		initHeight = block.number;
		playerDB[msg.sender] = newone;
		playercount += 1;  // or '=1' since playercount should be 0?
		setup = true;

		return true;
	}

	// Join game
	function challenge() public payable feePaid notDefender gameStarted returns (bool) {
		require(playerDB[msg.sender].since < initHeight);
		require(playercount + 1 <= maxPlayer);
		// how to make sure the state channel is synced with playerDB? Can one make sc
		// obtain data from chain? Or simply giveup playerDB here?
		playerInfo memory newone;

		newone.wallet = msg.sender;
		newone.since  = block.number;

		playerDB[msg.sender] = newone;
		playercount += 1;

		return true;
	}

	function testOutcome(bytes32 secret, uint blockNo) public gameStarted view returns (bytes32 _board, bool[32] memory _slots) {
		require(block.number < initHeight + period1 && block.number >= initHeight);
		require(blockNo <= block.number - 1 && blockNo < initHeight + period1);

		_board = keccak256(abi.encodePacked(secret, blockhash(blockNo)));

		for (uint i = 0; i <= 31; i++) {
			if(_board[i] < board[i]) {
				_slots[i] = true;
			}
		}
		return (_board, _slots);
	}

	function revealSecret(bytes32 secret, bytes32 score, bool[32] memory slots, uint blockNo, uint8 v, bytes32 r, bytes32 s, bytes32[] proofs) public gameStarted notDefender returns (bool) {
		require(playerDB[msg.sender].since > initHeight);
		require(battleHistory[initHeight][msg.sender].battle == 0);  // one of the few places use the ".battle", alternatives?
		require(block.number <= initHeight + period_all && block.number >= playerDB[msg.sender].since + period1);
		require(block.number - blockNo <= period1 + period2);
		require(blockNo > initHeight && blockNo < initHeight + period1);  // or '<' for right boundary 
		require(merkleRoot[0] != 0x0)
		// require(merkleProofValidate(proofs, keccak256(score), merkleRoot[0])
		require(ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(score))), v, r, s) == msg.sender);

		battleStat memory newbat;
		newbat.battle = initHeight;
		newbat.secret = secret;
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

                // determine winner and sample group
		if (winner == address(0) && newbat.score < board) {
			winner = msg.sender;
			sampleGroup[0] = newbat.score;
		} else if (newbat.score < battleHistory[initHeight][winner].score) {
			winner = msg.sender;
			sampleGroup[1] = sampleGroup[0];
			sampleGroup[0] = newbat.score;
		}

		sampleGroup[2] = newbat.score;

		// At block `m`: calculate/give ticket in sc, a second merkle tree contain the tickets, validator submit merkle root at block m
		// function count_zeros(score) returns (int zeros)
		// if (zeros > 5) {zeros = 5} else if (zeros == 0) {zeros = 1}  // btw. 1-5 tickets
		// function give_tickets(uint zeros) returns (bytes32[] tickets); playerDB[msg.sender].tickets = tickets (or in state channel?)

		return true;
	}

	function lottery(bytes32[] tickets[]) public gameStarted notDefender returns (bool) {
		require(battleHistory[initHeight][msg.sender].battle == initHeight);
		require(block.number > initHeight + period1 + period2 && block.number <= initHeight + period_all);
		require(tickets.length <= 5);
		// require(merkleProofValidate(proofs, tickets[0], merkleRoot[1]);  // verify existence of ticket
		// require(merkleProofValidate(proofs, tickets[1], merkleRoot[1]);  // can one loop in 'require'?
		// require(merkleProofValidate(proofs, tickets[2], merkleRoot[1]);  // maybe add a wrapper of the validator.
		// require(merkleProofValidate(proofs, tickets[3], merkleRoot[1]);
		// require(merkleProofValidate(proofs, tickets[4], merkleRoot[1]);

		bytes32 memory _board = keccak256(board, blockhash(block.number - 1)));

                for (i=0; i<tickets.length; i++) {
                        _ticket = tickets[i];
                        if (_board[30] == _ticket[30] && _board[31] == _ticket[31]) {
                                battleHistory[initHeight][msg.sender].battle = 0;
                                sampleGroup[2] = _board;
                                // require(RNTInterface(RNTAddr).mint(msg.sender) == true);
                                return true;
                        } else {
                                revert();
                        }
                }
	}

	function randomNumber public view returns (bytes32) {
		return keccak256(abi.encodePacked(sampleGroup[0], sampleGroup[1], sampleGroup[2], blockhash(block.number - 1)));
	}

	function myInfo() public view returns (uint, uint8, bytes32, bytes32, uint) {
		return (playerDB[msg.sender].since, playerDB[msg.sender].v, playerDB[msg.sender].r, playerDB[msg.sender].s, initHeight);
	}


        function MerkleTreeValidator(bytes32[] memory proof, bool[] memory isLeft, bytes32 targetLeaf, bytes32 merkleRoot) external view returns (bool) {
                require(proof.length < 16);  // 16 is an arbitrary number, 2**16=65536 shoud be large enough
                require(proof.length == isLeft.length);
                MerkleTreeValidatorInterface(MerkleTreeAddr).validate(proof, isLeft, targetLeaf, merkleRoot);
                return true;
        }

	function submitMerkleRoot(bytes32 _merkleRoot, uint i) external view ValidatorOnly returns (bool) {
	        require(i==0 or i==1);
	        merkleRoot[i] = _merkleRoot;
	        return true;
        }

	// WinnerOnly
	function withdraw() public WinnerOnly returns (bool) {
		require(block.number > initHeight + period_all);
		setup = false;
		winner = address(0);
		board = bytes32(0);
		playercount = 0;

		uint256 reward = uint256(address(this).balance).mul(uint256(6)) / uint256(10);
		// require(RNTInterface(RNTAddr).mint(msg.sender) == true);
		require(msg.sender.send(reward) == true);

		return true;
	}

	// fallback
  	function () defenderOnly gameStalled external { 
  	    winner = defender; 
  	    require(withdraw()); 
  	}
}
