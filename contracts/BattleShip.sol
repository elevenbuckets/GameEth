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
//          (period1)      (period2) (period3)                            could start next round
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
	uint constant public period_all = 30;  // 7 + 3 + 20
	uint public initHeight;
	// uint public lastActivity;
	// bytes32 public difficulty = 0x000000000000000000000000000000ffffffffffffffffffffffffffffffffff;
	uint public fee = 10000000000000000;
	bool public setup = false;
	uint public playercount = 0;
        address constant public MerkleTreeAddr = 0x127bfc8AFfdCaeee6043e7eC79239542e5A470B7;

	struct playerInfo {
		// address wallet; // msg.sender
		// uint since;     // block height when joined
		uint initHeightJoined;
		bytes32 scoreHash;
		bool claimed;
	}

        struct battleStat{
            bytes32 merkleRoot;
            string ipfsAddr;
        }

        bytes32 public board;
        bytes32 public prevboard;
        // address ethWinnerAddr;  // only one winner take eth
        // uint ethWinnerReward;

	mapping (address => playerInfo) playerDB;
	// mapping (uint => mapping (address => battleStat)) battleHistory;
	mapping (uint => battleStat) battleHistory;

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
		// require(setup == true && block.number > initHeight + period_all && winner == address(0));
		require(setup == true && block.number > initHeight + 10 && winner == address(0));
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
		require(block.number > playerDB[msg.sender].initHeightJoined + period_all);
		// require(block.number < playerDB[msg.sender].initHeightJoined + period_all + 7);
		setup = false;
		winner = address(0);
		board = bytes32(0);
		playercount = 0;

		uint256 reward = uint256(address(this).balance).mul(uint256(6)) / uint256(10);
		// require(RNTInterface(RNTAddr).mint(msg.sender) == true);
		require(msg.sender.send(reward) == true);
		return true;
	}


	function claimLotteReward( // this happens after end of a game, next round may started
	    bytes32 secret,
	    string memory slots,
	    uint blockNo,
	    uint[] memory submitBlocks,  // the winning blocks the player claimed
	    uint[] memory winningTickets, // the idx of generateTickets. same order as submitBlocks
	    bytes32[] memory proof,
	    bool[] memory isLeft,
	    bytes32 score
	) public returns (bool) {
		require(playerDB[msg.sender].claimed == false, "already claimed");
		require(winningTickets.length <= 10, "you cannot claim more tickets");
	        require(proof.length == isLeft.length, "len of proof/isLeft mismatch");
	        require(winningTickets.length == submitBlocks.length, "submitBlocks and winningTickets mismatch");
		require(battleHistory[playerDB[msg.sender].initHeightJoined].merkleRoot != bytes32(0), "no merkle root yet");
		require(block.number > playerDB[msg.sender].initHeightJoined + period_all, "too early");
		require(block.number < playerDB[msg.sender].initHeightJoined + period_all + 7, "too late");

		// require(ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(score)))), v, r, s) == msg.sender);
		bytes32 _board;
		if (playerDB[msg.sender].initHeightJoined == initHeight) {
		        _board = board;
                } else if (initHeight - playerDB[msg.sender].initHeightJoined > period_all) {
                        _board = prevboard;
                } else {
                        revert();
                }

                // No second chance: if one of the following verification failed, the player cannot call this function again.
                playerDB[msg.sender].claimed = true;
                uint i;

	        // verification: the secret belongs to the player
		bytes32 newscore = keccak256(abi.encodePacked(msg.sender, secret, blockhash(blockNo))); // initialize for the loop below
		bool[32] memory _slots = convertString32ToBool(slots); 
                for (i = 0; i <= 31; i++) {
			if(_slots[i] == false) {
				assert(score[i] == board[i]);
			} else {
				assert(score[i] == newscore[i]);
			}
		}

		require(keccak256(abi.encodePacked(score)) == playerDB[msg.sender].scoreHash,
		        "wrong score base on the given secret/blockNo");

                // generate "claimhash", which is hash(msg.sender, submitBlocks[i], winningTickets[i], ...) where i=0,1,2,...
		bytes32[5] memory genTickets = generateTickets(score);
                bytes32[] memory claimHashElements;
                claimHashElements[0] = bytes20(msg.sender);
                for (i=0; i<winningTickets.length; i++){
                        claimHashElements[i*2+1] = bytes32(submitBlocks[i]);
                        claimHashElements[i*2+2] = bytes32(genTickets[winningTickets[i]]);
                }
                // bytes32 claimHash = keccak256(abi.encodePacked(claimHashElements));
                require(merkleTreeValidator(proof, isLeft, keccak256(abi.encodePacked(claimHashElements)),
                                            battleHistory[playerDB[msg.sender].initHeightJoined].merkleRoot));

                // count number of winning tickets
                require(verifyWinnumber(_board, submitBlocks, winningTickets, genTickets) == true);
		return true;
        }

        function verifyWinnumber(bytes32 _board, uint[] submitBlocks, uint[] winningTickets, bytes32[5] genTickets) public view returns(bool){
                bytes32 winNumber;
                for (uint i=0; i<submitBlocks.length; i++){
                            winNumber = keccak256(abi.encodePacked(_board, blockhash(submitBlocks[i])));
                            // require(winNumber[30] == genTickets[winningTickets[i]][30] && winNumber[31] == genTickets[winningTickets[i]][31])
                            require(winNumber[31] == genTickets[winningTickets[i]][31], "found a wrong ticket");  // for debug only
                            // require(RNTInterface(RNTAddr).mint(msg.sender) == true);
                }
                return true;
        }

        function generateTickets(bytes32 score) public view returns (bytes32[5] memory){
                require(score != '0x0');
                bytes32[5] memory tickets;
                uint ticketSeedBlockNo = playerDB[msg.sender].initHeightJoined + 8;
		for (uint i = 0; i < getNumOfTickets(score); i++) {
		        tickets[i] = keccak256(abi.encodePacked(score, blockhash(ticketSeedBlockNo), i+1));  // idx of ticket start from 1
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

	function getPlayerInfo(address _addr) public view returns (uint, bytes32) {
		return (playerDB[_addr].initHeightJoined, playerDB[_addr].scoreHash);
	}

	function fortify(bytes32 defense) public payable feePaid defenderOnly NewGameOnly returns (bool) {
		// require(defense > difficulty);

		winner = address(0);

		initHeight = block.number;

		playerDB[msg.sender].initHeightJoined = initHeight;
		playercount += 1;
		setup = true;

	        prevboard = board;
	        board = defense;

		return true;
	}

	// Join game
	function challenge(bytes32 scoreHash) public payable feePaid notDefender gameStarted returns (bool) {
		require(playerDB[msg.sender].initHeightJoined < initHeight, "challange: 1");
		require(block.number > initHeight + 7 && block.number <= initHeight + 10, "challange: 2");
		require(playercount + 1 <= maxPlayer, "challange: 3");

		playerDB[msg.sender].claimed == false;
		playerDB[msg.sender].initHeightJoined = initHeight;
		playerDB[msg.sender].scoreHash = scoreHash;

		playercount += 1;

		return true;
	}

	function testOutcome(bytes32 secret, uint blockNo) public gameStarted view returns (bytes32 _board, bool[32] memory _slots) {
		require(block.number > initHeight + 7 && block.number <= initHeight + 10, 'testoutcome: 1');
		require(block.number - blockNo < 7, 'testoutcome: 2');
		require(blockNo <= block.number - 1 && blockNo >= initHeight + 7 && blockNo < initHeight + 10, 'testoutcome: 3');

		_board = keccak256(abi.encodePacked(msg.sender, secret, blockhash(blockNo)));

		for (uint i = 0; i <= 31; i++) {
			if(_board[i] < board[i]) {
				_slots[i] = true;
			}
		}

		return (_board, _slots);
	}

	function winningNumber(uint blockNo) public view returns (bytes32) {
	        require(blockNo <= block.number - 1);
	        return keccak256(abi.encodePacked(board, blockhash(blockNo)));
        }

        function merkleTreeValidator(bytes32[] memory proof, bool[] memory isLeft, bytes32 targetLeaf, bytes32 _merkleRoot) public pure returns (bool) {
                require(proof.length < 16);  // 16 is an arbitrary number, 2**16=65536 shoud be large enough
                require(proof.length == isLeft.length);
                return MerkleTreeValidatorInterface(MerkleTreeAddr).validate(proof, isLeft, targetLeaf, _merkleRoot);
        }

	function submitMerkleRoot(uint _initHeight, bytes32 _merkleRoot, string memory _ipfsAddr) public ValidatorOnly returns (bool) {
		require(block.number >= _initHeight + period_all && block.number <= _initHeight + period_all + 3);
	        battleHistory[_initHeight].merkleRoot = _merkleRoot;
	        battleHistory[_initHeight].ipfsAddr = _ipfsAddr;
	        return true;
        }

        function getBlockInfo(uint _initHeight) public view returns(bytes32, string){
	        return (battleHistory[_initHeight].merkleRoot, battleHistory[_initHeight].ipfsAddr);
        }

        function getBlockhash(uint blockNo) external view returns (bytes32) {
                return blockhash(blockNo);
        }

        function convertString32ToBool(string memory s32) internal pure returns (bool[32] memory) {
                // i.g., convert string "01001...." to bool[32]: [false, true, false, false, true, ...]
                bytes memory s32Bytes = bytes(s32);
                bool[32] memory result;
                for (uint i = 0; i < s32Bytes.length; i++) {
                        if(s32Bytes[i] == '1') {
                            result[i] = true;
                        } else {
                            result[i] = false;
                        }
                }
                return result;
        }

        function newValidator(address _newValidator) public defenderOnly returns (bool){
                require(_newValidator != address(0));
                validator = _newValidator;
                return true;
        }

        // fallback
        function () defenderOnly gameStalled external { 
            winner = defender; 
            // require(withdraw());
            setup = false;
            board = bytes32(0);
            playercount = 0;
	    require(msg.sender.send(address(this).balance) == true);
        }
}
