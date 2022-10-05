// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract FreedomOfSpeech is ERC721URIStorage, ERC2981, Pausable, Ownable{
  using Counters for Counters.Counter;
  using Strings for uint256;
  using Strings for uint64;
  Counters.Counter private _tokenIds;

  event ReceivedMATIC(uint256 amount);

  //mapping(uint256 => uint256) public tokenIdLikes;
  //mapping(uint256 => uint256) public tokenIdDislikes;

  struct Details {
    string expression;
    uint128 likes;
    uint128 dislikes;
    uint64 creationTime; //uint48 more efficient
  }

  mapping(uint256 => Details) public tokenIdToDetails;
  
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

  //generate svg creation for storing dynamic token images on-chain
  function generateImage(uint256 tokenId) internal view returns(string memory){
    bytes memory svg = abi.encodePacked(
        '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350">',
        '<style>.base { fill: white; font-family: serif; font-size: 14px; }</style>',
        '<rect width="100%" height="100%" fill="black" />',
        '<text x="50%" y="40%" class="base" dominant-baseline="middle" text-anchor="middle">',getExpression(tokenId),'</text>',
        '<text x="50%" y="50%" class="base" dominant-baseline="middle" text-anchor="middle">', "Likes: ",getLikes(tokenId),'</text>',
        '<text x="50%" y="50%" class="base" dominant-baseline="middle" text-anchor="middle">',getCreationDate(tokenId),'</text>',
        '</svg>'
    );
    return string(
        abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(svg)
        )    
    );
  }

  function addLike(uint256 tokenId) public payable {
    require(_exists(tokenId), "Please react to an existing token");
    require(msg.value == 1e17, "Sorry, it costs 0.1 matic to like!");

    tokenIdToDetails[tokenId].likes += 1;
    _setTokenURI(tokenId, getTokenURI(tokenId));

    address to = ownerOf(tokenId);
    (bool sent, bytes memory data) = to.call{value: msg.value}("");
    require(sent, "Failed to send Ether");
  }

  function getLikes(uint256 tokenId) public view returns (string memory) {
    uint256 likes = tokenIdToDetails[tokenId].likes;
    return likes.toString();
  }

  function addDislike(uint256 tokenId) public {
    require(_exists(tokenId), "Please react to an existing token");
    tokenIdToDetails[tokenId].dislikes += 1;
  }

  function getDislikes(uint256 tokenId) public view returns (string memory) {
    uint256 dislikes = tokenIdToDetails[tokenId].dislikes;
    return dislikes.toString();
  }

  function getExpression(uint256 tokenId) public view returns (string memory){
    string memory expression = tokenIdToDetails[tokenId].expression;
    return expression;
  }

  function getCreationDate(uint256 tokenId) public view returns (string memory){
    uint64 date = tokenIdToDetails[tokenId].creationTime;
    return date.toString();
  }

  function getTokenURI(uint256 tokenId) internal view returns (string memory){
    bytes memory dataURI = abi.encodePacked(
        '{',
            '"name": "FoS #', tokenId.toString(), '",',
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

  function mint(string memory expression) public payable {
    require(msg.value == 5e17, "Sorry, it costs 0.5 matic to post!");
    _tokenIds.increment();
    uint256 newItemId = _tokenIds.current();
    _safeMint(msg.sender, newItemId);
    tokenIdToDetails[newItemId].expression = expression;
    tokenIdToDetails[newItemId].creationTime = uint64(block.timestamp);
    tokenIdToDetails[newItemId].likes = 0;
    tokenIdToDetails[newItemId].dislikes = 0;
    _setTokenURI(newItemId, getTokenURI(newItemId));
  }

  //not yet implemented
  function pause() public onlyOwner {
    _pause();
  }
  //not yet implemented
  function unpause() public onlyOwner {
    _unpause();
  }

  function fundme() public payable {
      emit ReceivedMATIC(msg.value);
  }

  receive() external payable  { 
      fundme();
  }

  fallback() external payable {
      fundme();
  }

  //ensure MATIC cannot be trapped within the contract leaving enough gas for profit routing
  function withdraw(uint256 amount) external onlyOwner {
    require(address(this).balance > amount + 1e18, "Not enough funds in contract");
    payable(msg.sender).transfer(amount);
  }

}
