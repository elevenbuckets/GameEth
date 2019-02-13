pragma solidity ^0.5.2;

// import "./RNTInterface.sol";
import "./ELEMInterface.sol";
// import "./erc721_interface.sol";
// import "./erc721-enumerable.sol";


contract MemberShip {
    address public owner;
    address[3] public managers;
    address public ELEMAddr;
    uint public fee = 10000000000000000;
    uint public memberPeriod = 20000; // 20000 blocks ~ a week, for test only
    bytes32 public difficulty = 0x0000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    bool public paused = false;

    struct MemberInfo {
        address addr;
        uint since;  // beginning blockNo of previous membership
        // addPenalty() make sure penalty is always less than block.number
        uint penalty;  // the membership is valid until: since + memberPeriod - penalty;
        bytes32 kycid;  // know your customer id, leave it for future
        string notes;
    }

    mapping (uint => MemberInfo) internal memberDB;  // NFT to MemberInfo
    mapping (address => uint) internal addressToId;  // address to membership (is this essential?)

    mapping (address => bool) public appWhitelist; //

    constructor(address _ELEMAddr) public {
        owner = msg.sender;
        managers = [0xB440ea2780614b3c6a00e512f432785E7dfAFA3E,
                    0x4AD56641C569C91C64C28a904cda50AE5326Da41,
                    0x362ea687b8a372a0235466a097e578d55491d37f];
        ELEMAddr = _ELEMAddr;
        // RNTAddr  = _RNTAddr;
        // allocate membership here?
    }

    modifier ownerOnly() {
        require(msg.sender == owner);
        _;
    }

    modifier coreManagerOnly() {
        require(msg.sender == managers[0] || msg.sender == managers[1] || msg.sender == managers[2]);
        _;
    }

    modifier managerOnly(uint _tokenId) {
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
        // is it possible that penalty >= since or block.number?
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

    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    modifier whenPaused {
        require(paused);
        _;
    }

    // function buyMembership() public feePaid returns(bool) {
    // // One can only obtain token via trading and use these tokens to bind membership.
    // // The first tokens are mined and sold by manager with relatively low price
    // }

    function bindMembership(uint _tokenId) public isNFTOwner(_tokenId) isNotSpecialToken(_tokenId) whenNotPaused returns (bool) {
        require(memberDB[_tokenId].since == 0 && memberDB[_tokenId].addr == address(0));
        require(addressToId[msg.sender] == 0);  // the address is not yet bind to any NFT id
        // require ...
        memberDB[_tokenId] = MemberInfo(msg.sender, block.number, 0, bytes32(0), "");
        addressToId[msg.sender] = _tokenId;
        return true;
    }

    function unbindMembership(uint _tokenId) public isNFTOwner(_tokenId) isMember(_tokenId) whenNotPaused returns (bool) {
        // active member cannot unbind, i.e., cannot trasnfer membership/Token
        require(memberDB[_tokenId].since + memberPeriod - memberDB[_tokenId].penalty < block.number);
        memberDB[_tokenId] = MemberInfo(address(0), 0, 0, bytes32(0), "");
        addressToId[msg.sender] = 0;
        return true;
    }

    function renewMembership(uint _tokenId) public payable isMember(_tokenId) isNFTOwner(_tokenId) whenNotPaused returns (uint) {
        require(block.number > memberDB[_tokenId].since + memberPeriod - 10000);  // arbitrary, ~3.5 days before expiration
        // require ...
        memberDB[_tokenId].since = block.number;
        return block.number;
    }

    function assginKYCid(uint _tokenId, bytes32 _kycid) external managerOnly(_tokenId) returns (bool) {
        // instead of "managerOnly", probably add another group to do that
        require(memberDB[_tokenId].since > 0 && memberDB[_tokenId].addr != address(0));
        // require ...
        memberDB[_tokenId].kycid = _kycid;
        return true;
    }

    function addWhitelistApps(address _addr) public coreManagerOnly returns (bool) {
        appWhitelist[_addr] = true;
        return true;
    }

    function addPenalty(uint _tokenId, uint _penalty) external returns (uint) {
        require(appWhitelist[msg.sender] == true);
        require(memberDB[_tokenId].since > 0);  // is a member
        require(_penalty < memberPeriod);  // prevent too much penalty

        // extreme case which is unlike to happen
        if (memberDB[_tokenId].penalty + _penalty > block.number) {
            memberDB[_tokenId].penalty = block.number - 1;  // if 0 then not a member
        } else {
            memberDB[_tokenId].penalty += _penalty;
        }
        return memberDB[_tokenId].penalty;
    }

    function readNotes(uint _tokenId) external view returns (string memory) {
        require(memberDB[_tokenId].since > 0);
        return memberDB[_tokenId].notes;
    }

    function addNotes(uint _tokenId, string calldata _notes) external managerOnly(_tokenId) {
        require(memberDB[_tokenId].since > 0);
        memberDB[_tokenId].notes = _notes;
    }

    // function membershipGiveaway(address _addr, uint _tokenId) public coreManagerOnly(_tokenId) isNFTOwner(_tokenId) returns (bool){
    //     // assume the token is valid and owned by manager
    //     require(memberDB[_tokenId].addr == address(0));  // no one use the token as member
    //     require(addressToId[_addr] == 0);  // the addr is not yet a member
    //     // require ...
    //     memberDB[_tokenId] = MemberInfo(_addr, block.number, 0, bytes32(0), '');
    //     addressToId[_addr] = _tokenId;
    //     string memory uri = '';
    //     require(iELEM(ELEMAddr).mint(_addr, _tokenId, uri) == true);
    //     return true;
    // }

    // some query functions
    function addrIsMember(address _addr) external view returns (bool) {
        require(_addr != address(0));
        if (addressToId[_addr] != 0) {
            return true;
        } else {
            return false;
        }
    }

    function addrIsActiveMember(address _addr) external view returns (bool) {
        require(_addr != address(0));
        uint _tokenId = addressToId[_addr];
        if (_tokenId != 0 && memberDB[_tokenId].since + memberPeriod - memberDB[_tokenId].penalty > block.number) {
            return true;
        }
        return false;
    }

    function tokenIsMember(uint _tokenId) external view returns (bool) {
        if (memberDB[_tokenId].addr != address(0)) {
            return true;
        } else {
            return false;
        }
    }

    function tokenIsActiveMember(uint _tokenId) external view returns (bool) {
        if (memberDB[_tokenId].since + memberPeriod - memberDB[_tokenId].penalty > block.number) {
            return true;
        } else {
            return false;
        }
    }

    function addrToTokenId(address _addr) external view returns (uint) {
        return addressToId[_addr];
    }

    // upgradable
    function pause() external coreManagerOnly whenNotPaused {
        paused = true;
    }

    function unpause() public ownerOnly whenPaused {
        // set to ownerOnly in case accounts of other managers are compromised
        paused = false;
    }

    function updateELEMAddr(address _addr) external ownerOnly {
        //require(ELEMAddr == address(0)); // comment to allow this to be changed many times
        ELEMAddr = _addr;
    }

}
