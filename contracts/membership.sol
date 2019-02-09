pragma solidity ^0.5.2;

// import "./RNTInterface.sol";
import "./erc721_interface.sol";

contract membership {
    address public owner;
    address[3] public managers;
    address public ELEM;
    uint public fee = 10000000000000000;
    uint public memberPeriod = 20000; // 20000 blocks ~ a week, for test only
    bytes32 public difficulty = 0x0000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    struct memberInfo{
        address addr;
        uint since;  // beginning blockNo of previous membership
        uint penalty;  // the membership is valid until: since + memberPeriod - penalty
        bytes32 kycid;  // know your customer id, leave it for future
        string notes;
    }
    mapping (uint => memberInfo) memberDB;  // NFT to memberInfo
    mapping (address => uint) addressToId;  // address to membership (is this essential?)

    constructor(address _ELEMAddr) public {
        owner = msg.sender;
        managers = [0xB440ea2780614b3c6a00e512f432785E7dfAFA3E,
                    0x4AD56641C569C91C64C28a904cda50AE5326Da41,
                    0x362ea687b8a372a0235466a097e578d55491d37f];
        ELEMAddr = _ELEMAddr;
        // RNTAddr  = _RNTAddr;
        // allocate membership here?
    }

    modifier managerOnly()  {
        require(msg.sender == managers[0] || msg.sender == managers[1] || msg.sender == managers[2]);
        _;
    }

    modifier feePaid() {
        require(msg.value >= fee);  // or "=="?
        _;
    }

    modifier isMember(uint _tokenId) {
        require(memberDB[_tokenId].addr == msg.sender && msg.sender != address(0));
        require(memberDB[_tokenId].since > 0);
        // require(addressToId(msg.sender) == _tokenId);
        _;
    }

    modifier isActiveMember(uint _tokenId) {
        require(memberDB[_tokenId].addr == msg.sender && msg.sender != address(0));
        require(memberDB[_tokenId].since + memberPeriod - memberDB[_tokenId].penalty > block.number);
        _;
    }

    modifier isNFTOwner(uint _tokenId) {
        require(ERC721(ELEMAddr).idToOwner[_tokenId] == msg.sender && msg.sender != address(0));
    }

    // modifier isSynced(uint _tokenId){ // where/when to use it?
    //     require(ERC721(ELEMAddr).idToOwner[_tokenId] == memberDB[_tokenId].addr);
    // }

    modifier validNFT(uint256 _tokenId) {
        require(ERC721(ELEMAddr).idToOwner[_tokenId] != address(0));
        _;
    }

    function getMembership(uint _tokenId) public validNFT(_tokenId) isNFTOwner(_tokenId){
        require(memberDB[_tokenId].since == 0 && memberDB[_tokenId].addr == address(0));
	require(_tokenId > difficulty);  // tokens with "id < difficulty" are for special purpose
	require(addressToId[msg.sender] == 0);  // not yet bind to any NFT id
        // require ...
        memberDB[_tokenId] = memberInfo(msg.sender, block.number, 0, bytes32(0), '');
        addressToId[msg.sender] = _tokenId;
    }

    function giveupMember(uint _tokenId) public validNFT(_tokenId) isMember(_tokenId){
        require(memberDB[_tokenId].since + memberPeriod - memberDB[_tokenId].penalty < block.number);  // not an active member
        memberDB[_tokenId] = memberInfo(address(0), 0, 0, bytes32(0), '');
        addressToId[msg.sender] = 0;
    }

    function assginKYCid(uint _tokenId, bytes32 _kycid) external managerOnly validNFT(_tokenId) {
        // instead of "managerOnly", probably add another group to do that
        require(memberDB[_tokenId].since > 0 && memberDB[_tokenId].addr != address(0));
        // require ...
        memberDB[_tokenId].kycid = _kycid;
    }

    function renewMembership(uint _tokenId) public payable validNFT(_tokenId) isMember(_tokenId) isNFTOwner(_tokenId){
        require(block.number > memberDB[_tokenId].since + memberPeriod - 10000);  // arbitrary, ~3.5 days before expiration
        // require ...
        memberDB[_tokenId].since = block.number;
    }

    function membershipGiveaway(address _addr, uint _tokenId) public managerOnly validNFT(_tokenId) {
        require(memberDB[_tokenId].addr == address(0));  // no one use the token
        require(addressToId[_addr] == 0);  // the addr is not yet a member
        // require ...
        require(ERC721(ELEMAddr).mint(msg.sender, _tokenId) == true);
    }

}
