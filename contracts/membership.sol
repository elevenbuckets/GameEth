pragma solidity ^0.5.2;

// import "./RNTInterface.sol";
import "./ELEMInterface.sol";
// import "./erc721_interface.sol";
// import "./erc721-enumerable.sol";

contract membership {
    address public owner;
    address[3] public managers;
    address public ELEMAddr;
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

    modifier managerOnly(uint _tokenId)  {
        require(msg.sender == managers[0] || msg.sender == managers[1] || msg.sender == managers[2]
	        || _tokenId % 7719472615821079694904732333912527190217998977709370935963838933860875309329 == 0);
	// uint256(0x1111111111111111111111111111111111111111111111111111111111111111 = 7.71947....e72
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
        // is it possible that penalty >= since?
        _;
    }

    modifier isNFTOwner(uint _tokenId) {
        require(iELEM(ELEMAddr).ownerOf(_tokenId) == msg.sender);
        _;
    }

    modifier validNFT(uint256 _tokenId) {
        require(iELEM(ELEMAddr).ownerOf(_tokenId) != address(0));
        _;
    }

    // modifier isSynced(uint _tokenId){ // where/when to use it?
    //     require(ERC721(ELEMAddr).idToOwner[_tokenId] == memberDB[_tokenId].addr);
    // }

    modifier isNotSpecialToken(uint _tokenId) {
	// require(_tokenId > uint256(0x0000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff));
	// require(_tokenId % uint256(0x1111111111111111111111111111111111111111111111111111111111111111 != 0));
	require(_tokenId > 1766847064778384329583297500742918515827483896875618958121606201292619775);
	require(_tokenId % 7719472615821079694904732333912527190217998977709370935963838933860875309329 != 0);
        _;
    }

    // function buyMembership() public feePaid returns(bool) {
    // // One can only obtain token via trading and use these tokens to bind membership.
    // // The first tokens are mined and sold by manager with relatively low price
    // }

    function bindMembership(uint _tokenId) public isNFTOwner(_tokenId) isNotSpecialToken(_tokenId) returns (bool){
        require(memberDB[_tokenId].since == 0 && memberDB[_tokenId].addr == address(0));
	require(addressToId[msg.sender] == 0);  // the address is not yet bind to any NFT id
        // require ...
        memberDB[_tokenId] = memberInfo(msg.sender, block.number, 0, bytes32(0), '');
        addressToId[msg.sender] = _tokenId;
        return true;
    }

    function unbindMembership(uint _tokenId) public isNFTOwner(_tokenId) isMember(_tokenId) returns (bool){
        // active member cannot unbind, i.e., cannot trasnfer membership/Token
        require(memberDB[_tokenId].since + memberPeriod - memberDB[_tokenId].penalty < block.number);
        memberDB[_tokenId] = memberInfo(address(0), 0, 0, bytes32(0), '');
        addressToId[msg.sender] = 0;
        return true;
    }

    function renewMembership(uint _tokenId) public payable isMember(_tokenId) isNFTOwner(_tokenId) returns (uint){
        require(block.number > memberDB[_tokenId].since + memberPeriod - 10000);  // arbitrary, ~3.5 days before expiration
        // require ...
        memberDB[_tokenId].since = block.number;
        return block.number;
    }

    function assginKYCid(uint _tokenId, bytes32 _kycid) external managerOnly(_tokenId) returns (bool){
        // instead of "managerOnly", probably add another group to do that
        require(memberDB[_tokenId].since > 0 && memberDB[_tokenId].addr != address(0));
        // require ...
        memberDB[_tokenId].kycid = _kycid;
        return true;
    }

    // function membershipGiveaway(address _addr, uint _tokenId) public managerOnly(_tokenId) isNFTOwner(_tokenId) returns (bool){
    //     // assume the token is valid and one of the managers owns the token
    //     require(memberDB[_tokenId].addr == address(0));  // no one use the token as member
    //     require(addressToId[_addr] == 0);  // the addr is not yet a member
    //     // require ...
    //     memberDB[_tokenId] = memberInfo(_addr, block.number, 0, bytes32(0), '');
    //     addressToId[_addr] = _tokenId;
    //     string memory uri = '';
    //     require(iELEM(ELEMAddr).mint(_addr, _tokenId, uri) == true);
    //     return true;
    // }

}
