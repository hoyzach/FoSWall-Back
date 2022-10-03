// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract FoS is ERC721URIStorage, ERC2981, Pausable, Ownable{
  using Counters for Counters.Counter;
  using Strings for uint256;
  Counters.Counter private _tokenIds;

  //mapping(uint256 => uint256) public tokenIdLikes;
  //mapping(uint256 => uint256) public tokenIdDislikes;

  struct Reactions {
    uint128 likes;
    uint128 dislikes;
  }

  mapping(uint256 => Reactions) public tokenIdReactions;
  
  constructor() ERC721("Freedom of Speech", "FoS"){
    _setDefaultRoyalty(msg.sender, 500);
  }
  //ERC721URIStorage and ERC2981 both override supportsInterface - to fix this we override it as well
  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC2981) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  //burn override since inheriting ERC2981 instead of ERC721Royalty
  function _burn(uint256 tokenId) internal virtual override{
    super._burn(tokenId);
    _resetTokenRoyalty(tokenId);
  }

  function generateImage(uint256 tokenId) internal view returns(string memory){
    bytes memory svg = abi.encodePacked(
        '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350">',
        '<style>.base { fill: white; font-family: serif; font-size: 14px; }</style>',
        '<rect width="100%" height="100%" fill="black" />',
        '<text x="50%" y="40%" class="base" dominant-baseline="middle" text-anchor="middle">',"Warrior",'</text>',
        '<text x="50%" y="50%" class="base" dominant-baseline="middle" text-anchor="middle">', "Likes: ",getLikes(tokenId),'</text>',
        '</svg>'
    );
    return string(
        abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(svg)
        )    
    );
  }

  function getLikes(uint256 tokenId) public view returns (string memory) {
    uint256 likes = tokenIdReactions[tokenId].likes;
    return likes.toString();
  }

  function getTokenURI(uint256 tokenId) internal view returns (string memory){
    bytes memory dataURI = abi.encodePacked(
        '{',
            '"name": "FAFS #', tokenId.toString(), '",',
            '"description": "', getExpression(tokenId), '"',
            '"image": "', generateImage(tokenId), '"',
        '}'
    );
    return string(
        abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(dataURI)
        )
    );
  }

  function getExpression(uint256 tokenId) internal view returns (string memory){

  }

  function mintNFT(address recipient, string memory tokenURI) public onlyOwner returns (uint256) {
    _tokenIds.increment();

    uint256 newItemId = _tokenIds.current();
    _safeMint(recipient, newItemId);
    _setTokenURI(newItemId, tokenURI);

    return newItemId;
  }

  function pause() public onlyOwner {
    _pause();
  }

  function unpause() public onlyOwner {
    _unpause();
  }


}
