pragma solidity ^0.4.24;

// import "./ERC20.sol";
import "./SafeMath.sol";
// import "./RNTInterface.sol";
import "./MerkleTreeValidatorInterface.sol";

// About the game
// # Roles
//  * defender : setup the game (only the fee)
//  * player : join the game, max 1000 players, pay 0.01 eth and may win some RNT
//  * validator: provide merkle proof at `end` block
//
// # time line of a game:
//    start ------------ n ------- m -------------------------------- end --------
//          calc           reg to    lottery, each round: 0-n winners     mr submit to chain;
//                         sc        (only on sc)                         withdraw eth/claim reward
//          (period1)      (period2) (period3)
//
//  * sc: state channel; mr: merkle root
//  * period_all = period1 + period2 + period3
//  * during period2 (btw. `n` and `m`) players get tickets on sc
//  * player obtain ticket in the form `ticket[i] = hash(score + bn[m-1] + i)` where 0<=i<5, depend on score
// todo: add an upper limit for the contract to give to players? Such as (the order of) 1000*0.01 eth = 10 eth = 1e5 RNT

contract BattleShip {
	using SafeMath for uint256;
	// Variables
	address public defender;
	address public winner;
	address public validator;
	// address public RNTAddr;
	uint constant public maxPlayer = 1000;
	uint constant public maxTicketNumber = 5;  // per player
	uint constant public maxLotteWins= 10;  // per player
	uint constant public period1 = 7;
	uint constant public period2 = 3;
	uint constant public period3 = 20;
	uint constant public period_all = period1 + period2 + period3;  // shoudl be in the range 30-120
	uint public initHeight;
	uint public lastActivity;
	bytes32 public difficulty = 0x000000000000000000000000000000ffffffffffffffffffffffffffffffffff;
	bytes32 public board;
	uint public fee = 10000000000000000;
	bool public setup = false;
	uint public playercount = 0;
	bytes32[4] private samGroup;
	bytes32 private lastRevived;
	bytes32 public merkleRoot;
        address constant public MerkleTreeAddr = 0x127bfc8AFfdCaeee6043e7eC79239542e5A470B7;

	struct playerInfo {
		address wallet; // msg.sender
		uint since;     // block height when joined
		bytes32 scoreHash;
	}

	struct battleStat {
	        bytes32 merkleRoot;
		bytes32 board;
		address ethWinnerAddr;  // only one winner take eth
		uint ethWinnerReward;
		string ipfsAddr;
	}

	mapping (address => playerInfo) playerDB;
	// mapping (uint => mapping (address => battleStat)) battleHistory;
	mapping (uint => battleStat) battleHistory;
	mapping (address => bool) playerClaimedReward;

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

	modifier gameStalled() {
		require(setup == true && block.number > initHeight + period_all && winner == address(0));
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
		validator = msg.sender;
		// RNTAddr  = _RNTAddr;

		require(fortify(_init) == true);
	}

	// WinnerOnly
	function withdraw() public WinnerOnly returns (bool) {
	        // only one player win eth; make sure winner can claim the reward after next game started
		require(block.number > initHeight + period_all);
		// require(block.number < initHeight + period_all + 7);
		setup = false;
		winner = address(0);
		board = bytes32(0);
		lastRevived = bytes32(0);
		samGroup[3] = bytes32(0);
		playercount = 0;

		// uint256 reward = uint256(address(this).balance).mul(uint256(6)) / uint256(10);
		// require(RNTInterface(RNTAddr).mint(msg.sender) == true);
		// require(msg.sender.send(reward) == true);
		return true;
	}

	function claimLotteReward(
	    bytes32 secret,
	    uint blockNo,
	    bytes32[] memory winningTickets, // arrays winningTickets, submitBlocks, proof, isLeft have same order
	    uint256[] memory submitBlocks,  // the winning blocks the player claimed
	    bytes32[] memory proof,  // TODO: should be "mapping (uint => bytes32) proof" and same for isLeft. But how?
	    bool[] memory isLeft     // mapping/dynamic 2d array is not allowed here. Use proof1, proof2, ...?
	) public returns (bool) {
		require(playerClaimedReward[msg.sender] == false);
		require(winningTickets.length <= maxLotteWins, "you cannot claim more");
	        require(proof.length == isLeft.length && winningTickets.length == submitBlocks.length
	                && submitBlocks.length == proof.length, "wrong proof");
		require(merkleRoot != 0x0, "no merkle root yet");
		require(playerDB[msg.sender].since > initHeight && playerDB[msg.sender].since < initHeight + period1 + period2, "wrong block");
		require(block.number > initHeight + period_all, "wrong block");
		// require(ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(score)))), v, r, s) == msg.sender);

                // No second chance: if one of the following verification failed, the player cannot call this function again.
                playerClaimedReward[msg.sender] = true;
                uint i;
                uint i2;

	        // verification: the secret belongs to the player
		bytes32 score = keccak256(abi.encodePacked(secret, blockhash(blockNo))); // initialize for the loop below
		require(keccak256(abi.encodePacked(score)) == playerDB[msg.sender].scoreHash, "wrong score");

                // verification: tickets are in Merkle Tree
                for (i=0; i<winningTickets.length; i++){
                        require(merkleTreeValidator(proof[i], isLeft[i], keccak256(abi.encodePacked(winningTickets[i])), merkleRoot), 
                                "one or more tickets not in Merkle Tree");
                }

                // verification: winningTickets belongs to the player
		bytes32[] memory tickets = generateTickets(score);
		for (i=0; i<winningTickets.length; i++){
                        for (i2=0; i2<tickets.length; i2++){
                                bool validTicket = false;
                                if (winningTickets[i] == tickets[i2]){
                                        validTicket = true;
                                        break;
                                }
                        }
                        require(validTicket, "The winning ticket is not yours");
                }

                // count number of winning tickets which actually wins (should have done in sc)
                uint winningTicketCounter = 0;
                bytes32 winNumber;
                for (i=0; i<winningTickets.length; i++){
	                winNumber = keccak256(abi.encodePacked(board, blockhash(submitBlocks[i])));
                        if (winNumber[30] == tickets[i][30] && winNumber[31] == tickets[i][31]) {
                                winningTicketCounter += 1;
                        } else {
                            break;
                        }
                }
                require(winningTicketCounter == winningTickets.length, "Oh no! You give a wrong ticket or wrong proofs.");

                // Good job!
		// require(RNTInterface(RNTAddr).mint(msg.sender) == true);
		return true;
        }

        function generateTickets(bytes32 score) public returns (bytes32[]){
                bytes32[] memory tickets;
                uint ticketSeedBlockNo = initHeight + period1 + period2;  // make it global?
		for (uint i = 1; i <= getNumOfTickets(score); i++) {
		        tickets[i-1] = keccak256(abi.encodePacked(score, ticketSeedBlockNo, i));  // i start from 1
                }
                return tickets;
        }

        function getNumOfTickets(bytes32 score) public pure returns(uint){
                if (score > 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) {
                        return 1;  // min: 1 ticket
                } else if (score > 0x000fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) {
                        return 2;
                } else if (score > 0x0000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) {
                        return 3;
                } else if (score > 0x00000fffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) {
                        return 4;
                } else {
                        return 5;  // max: 5 tickets
                }
        }


	// function randomNumber() public view returns (bytes32) {
	// 	require(lastRevived != samGroup[3] && samGroup[3] != bytes32(0));
	// 	require(block.number - lastActivity <= 5);
	// 	return keccak256(abi.encodePacked(samGroup[0], samGroup[1], samGroup[2], samGroup[3], blockhash(block.number - 1)));
	// }

	function getPlayerInfo(address _addr) public view returns (uint, uint, bytes32) {
		return (playerDB[_addr].since, initHeight, playerDB[_addr].scoreHash);
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
		lastRevived = bytes32(0);
		samGroup[3] = bytes32(0);

	        battleHistory[initHeight].board = board;

		return true;
	}

	// Join game
	function challenge(bytes32 scoreHash) public payable feePaid notDefender gameStarted returns (bool) {
		require(playerDB[msg.sender].since < initHeight);
		require(block.number >= initHeight + period1 && block.number < initHeight + period1 + period2);
		require(playercount + 1 <= maxPlayer);

		playerInfo memory newone;

		newone.wallet = msg.sender;
		newone.since  = block.number;
		newone.scoreHash = scoreHash;

		playerDB[msg.sender] = newone;
		playercount += 1;

		return true;
	}

	function testOutcome(bytes32 secret, uint blockNo) public gameStarted view returns (bytes32 _board, bool[32] memory _slots) {
		require(block.number < initHeight + period1 && block.number >= initHeight);
		require(block.number - blockNo < period1);
		require(blockNo <= block.number - 1 && blockNo < initHeight + period1 && blockNo >= initHeight);

		_board = keccak256(abi.encodePacked(msg.sender, secret, blockhash(blockNo)));

		for (uint i = 0; i <= 31; i++) {
			if(_board[i] < board[i]) {
				_slots[i] = true;
			}
		}

		return (_board, _slots);
	}

	// function reviveReward() public gameStarted notDefender returns (bool) {
	// 	require(battleHistory[initHeight][msg.sender].battle == initHeight);
	// 	require(block.number > initHeight + period1 + period2);

	// 	bytes32 _board = keccak256(abi.encodePacked(battleHistory[initHeight][msg.sender].score, blockhash(block.number - 1)));

	// 	assert(_board != samGroup[3]);
			
	// 	if (_board[30] == board[30] && _board[31] == board[31]) {
	// 		battleHistory[initHeight][msg.sender].battle = 0;
	// 		lastRevived = samGroup[3];
	// 		samGroup[3] = _board;
	// 		lastActivity = block.number;
	// 		require(RNTInterface(RNTAddr).mint(msg.sender) == true);
	// 		return true;
	// 	} else {
	// 		revert();
	// 	}
	// }

	// function revealSecret(bytes32 secret, bytes32 score, bool[32] memory slots, uint blockNo, uint8 v, bytes32 r, bytes32 s) public gameStarted notDefender returns (bool) {
	// 	require(score != board);
	// 	require(score != battleHistory[initHeight][msg.sender].score);
	// 	require(playerDB[msg.sender].since > initHeight);
	// 	require(battleHistory[initHeight][msg.sender].battle == 0);
	// 	require(block.number <= initHeight + period1 + period2);
	// 	require(block.number - blockNo < period1);
	// 	require(blockNo <= block.number - 1 && blockNo < initHeight + period1 && blockNo > initHeight);
	// 	// require(merkleRoot[0] != 0x0);
	// 	// todo: require(merkleTreeValidator(proofs, keccak256(score), merkleRoot[0]);
	// 	require(ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(score)))), v, r, s) == msg.sender);

	// 	battleStat memory newbat;
	// 	newbat.battle = initHeight;
	// 	newbat.secret = secret;
	// 	// newbat.bhash = blockhash(blockNo);
	// 	newbat.score = keccak256(abi.encodePacked(secret, blockhash(blockNo))); // initialize for the loop below

	// 	for (uint i = 0; i <= 31; i++) {
	// 		if(slots[i] == false) {
	// 			assert(score[i] == board[i]);
	// 		} else {
	// 			assert(score[i] == newbat.score[i]);
	// 		}
	// 	}

	// 	newbat.score = score;
	// 	battleHistory[initHeight][msg.sender] = newbat;

	// 	// winner and sample group
	// 	// if (winner == address(0) && newbat.score < board) {
	// 	// 	winner = msg.sender;
	// 	// 	samGroup[0] = newbat.score;
	// 	// } else if (newbat.score < battleHistory[initHeight][winner].score) {
	// 	// 	winner = msg.sender;
	// 	// 	samGroup[1] = samGroup[0];
	// 	// 	samGroup[0] = newbat.score;
	// 	// } else {
	// 	// 	samGroup[2] = newbat.score;
	// 	// }

	// 	lastActivity = block.number;
	// 	return true;
	// 	// state channel has to send out ticket after block 'm', i.e., end of revealSecret()
	// }


	// function lottery(bytes32[] tickets) public gameStarted notDefender returns (bool) {
	// 	require(battleHistory[initHeight][msg.sender].battle == initHeight);
	// 	require(block.number > initHeight + period1 + period2 && block.number <= initHeight + period_all);
	// 	require(tickets.length <= 5);
	// 	// todo:
	// 	// require(merkleTreeValidator(proofs, tickets[0], merkleRoot[1]);  // verify existence of ticket
	// 	// require(merkleTreeValidator(proofs, tickets[1], merkleRoot[1]);  // can one loop in 'require'?
	// 	// require(merkleTreeValidator(proofs, tickets[2], merkleRoot[1]);  // or deal with array in the function
	// 	// require(merkleTreeValidator(proofs, tickets[3], merkleRoot[1]);
	// 	// require(merkleTreeValidator(proofs, tickets[4], merkleRoot[1]);

	// 	bytes32 memory _board = keccak256(board, blockhash(block.number - 1)));

                // for (i=0; i<tickets.length; i++) {
                        // _ticket = tickets[i];
                        // if (_board[30] == _ticket[30] && _board[31] == _ticket[31]) {
                                // battleHistory[initHeight][msg.sender].battle = 0;
                                // sampleGroup[2] = _board;
                                // // require(RNTInterface(RNTAddr).mint(msg.sender) == true);
                                // return true;
                        // } else {
                                // revert();
                        // }
                // }
	// }

	function winningNumber(uint blockNo) public view returns (bytes32) {
	        require(blockNo <= block.number - 1);
	        return keccak256(abi.encodePacked(battleHistory[initHeight].board, blockhash(blockNo)));
        }

        function merkleTreeValidator(bytes32[] memory proof, bool[] memory isLeft, bytes32 targetLeaf, bytes32 _merkleRoot) public pure returns (bool) {
                require(proof.length < 16);  // 16 is an arbitrary number, 2**16=65536 shoud be large enough
                require(proof.length == isLeft.length);
                return MerkleTreeValidatorInterface(MerkleTreeAddr).validate(proof, isLeft, targetLeaf, _merkleRoot);
        }

	function subimtIPFSaddr(string _ipfsAddr) external ValidatorOnly returns (bool){
	        battleHistory[initHeight].ipfsAddr = _ipfsAddr;
	        return true;
        }

	function submitMerkleRoot(bytes32 _merkleRoot, string _ipfsAddr) external ValidatorOnly returns (bool) {
		require(block.number >= initHeight + period1 + period2 && block.number < initHeight + period1 + period2 + 3);
	        // merkleRoot = _merkleRoot;
	        battleHistory[initHeight].merkleRoot = _merkleRoot;

	        return true;
        }

        function getBlockhash(uint blockNo) external view returns (bytes32) {
                return blockhash(blockNo);
        }

        function convertScoreString(string scoreString) internal pure returns (bool[32]) {
                // i.g., convert string "01001...." to bool[32]: [false, true, false, false, true, ...]
                bytes memory scoreStr = bytes(scoreString);
                bool[32] memory score;
                for (uint i = 0; i < scoreStr.length; i++) {
                        if(scoreStr[i] == '1') {
                            score[i] = true;
                        } else {
                            score[i] = false;
                        }
                }
                return score;
        }

        // fallback
        function () defenderOnly gameStalled external { 
            winner = defender; 
            require(withdraw()); 
        }
}
