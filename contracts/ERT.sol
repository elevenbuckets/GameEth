pragma solidity ^0.5.2;
// ERC721 adapted from https://github.com/0xcert/ethereum-erc721
import "./ERC721/tokens/nf-token-enumerable.sol";
import "./ERC721/tokens/nf-token-metadata.sol";
import "./ERC721/ownership/ownable.sol";

contract Erebor is NFTokenEnumerable, NFTokenMetadata, Ownable {
    constructor() public {
        nftName = "Erebor Token";
        nftSymbol = "ERT";
    }

    function mint(address _to, uint256 _tokenId, string calldata _uri) external onlyOwner {
        super._mint(_to, _tokenId);
        super._setTokenUri(_tokenId, _uri);
    }

    function burn(uint256 _tokenId) external onlyOwner{
        super._burn(_tokenId);
    }

    function transferOwnership(address _newOwner) public onlyOwner{
        super.transferOwnership(_newOwner);
    }
}
