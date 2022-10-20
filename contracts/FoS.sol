// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract FreedomOfSpeech is ERC721URIStorage, ERC2981, Ownable{
  using Counters for Counters.Counter;
  using Strings for uint256;
  Counters.Counter private _tokenIds;

  event ReceivedMATIC(address sender, uint256 amount);

  struct Details {
    string expression;
    uint256 likes;
    uint256 dislikes;
  }

  mapping(uint256 => Details) public tokenIdToDetails;
  mapping(address => mapping(uint256 => bool)) public addressToReactionBool;
  
  constructor() ERC721("Freedom of Speech", "FoS"){
    _setDefaultRoyalty(msg.sender, 500);
  }
  //modifer to check if sender has already reacted to a tokenId
  modifier reactOnce(uint256 tokenId) {
    require(addressToReactionBool[msg.sender][tokenId] == false, "Can only react to a token once");
    addressToReactionBool[msg.sender][tokenId] = true;
    _;
  }

  //ERC721URIStorage and ERC2981 both override supportsInterface - to fix this we override it as well
  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC2981) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  function resetTokenDetails(uint256 tokenId) internal {
    tokenIdToDetails[tokenId].expression = " ";
    tokenIdToDetails[tokenId].likes = 0;
    tokenIdToDetails[tokenId].dislikes = 0;
  }

  //burn override since inheriting ERC2981 instead of ERC721Royalty
  function _burn(uint256 tokenId) internal virtual override{
    super._burn(tokenId);
    _resetTokenRoyalty(tokenId);
    resetTokenDetails(tokenId);
    _setTokenURI(tokenId, getTokenURI(tokenId));
  }

  //Allows owner of token to burn their token
  function burn(uint256 tokenId) public {
    require(msg.sender == ownerOf(tokenId), "Nice try, you cannot burn someone elses token!");
    _burn(tokenId);
  }

  //Allows owner of contract to burn any token
  function ownerBurn(uint256 tokenId) public onlyOwner {
    _burn(tokenId);
  }

  //generate svg creation for storing dynamic token images on-chain
  function generateImage(uint256 tokenId) internal view returns(string memory){
    bytes memory svg = abi.encodePacked(
        '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350">',
        '<style>.base { fill: white; font-family: serif; font-size: 16px; font-weight: bold; } .exp{ fill: darkturquoise; font-family: serif; font-size: 12px; font-weight: bold;}</style>',
        '<rect width="100%" height="100%" fill="black" />',
        '<text x="50%" y="30%" class="base" dominant-baseline="middle" text-anchor="middle">', "FoS #",tokenId.toString(),'</text>',
        '<text x="50%" y="50%" class="exp" dominant-baseline="middle" text-anchor="middle">',getExpression(tokenId),'</text>',
        '<text x="50%" y="70%" class="base" dominant-baseline="middle" text-anchor="middle">', "Likes: ",getLikes(tokenId),'</text>',
        '</svg>'
    );
    
    return string(
        abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(svg)
        )    
    );
  }

  //Given tokenId, adds a like and requests 0.1 matic to be routed to the token holder
  function addLike(uint256 tokenId) public payable reactOnce(tokenId) {
    require(_exists(tokenId), "Please react to an existing token");
    require(msg.value == 1e17, "Sorry, it costs 0.1 matic to like!");
    tokenIdToDetails[tokenId].likes += 1;
    _setTokenURI(tokenId, getTokenURI(tokenId));
    address to = ownerOf(tokenId);
    (bool sent, bytes memory data) = to.call{value: msg.value}("");
    require(sent, "Failed to send Ether");
  }
  //Returns token likes as a string given tokenId
  function getLikes(uint256 tokenId) public view returns (string memory) {
    uint256 likes = tokenIdToDetails[tokenId].likes;
    return likes.toString();
  }
  //Given tokenId, adds a dislike
  function addDislike(uint256 tokenId) public reactOnce(tokenId) {
    require(_exists(tokenId), "Please react to an existing token");
    tokenIdToDetails[tokenId].dislikes += 1;
  }
  //Returns token dislikes as a string given tokenId
  function getDislikes(uint256 tokenId) public view returns (string memory) {
    uint256 dislikes = tokenIdToDetails[tokenId].dislikes;
    return dislikes.toString();
  }

  //Returns token expression as a string given tokenId
  function getExpression(uint256 tokenId) public view returns (string memory){
    string memory expression = tokenIdToDetails[tokenId].expression;
    return expression;
  }

  //Returns token URI given tokenId
  function getTokenURI(uint256 tokenId) internal view returns (string memory){
    bytes memory dataURI = abi.encodePacked(
        '{',
            '"name": "FoS #', tokenId.toString(), '",',
            '"description": "', getExpression(tokenId), '",',
            '"image_data": "', generateImage(tokenId), '"',
        '}'
    );
    return string(
        abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(dataURI)
        )
    );
  }

  //Given a string and 0.5 matic, creates new token and initializes reactions, generates URI
  function mint(string memory expression) public payable {
    require(msg.value == 5e17, "Sorry, it costs 0.5 matic to post!");
    require(bytes(expression).length <= 64 , "The expression is too long");
    _tokenIds.increment();
    uint256 newItemId = _tokenIds.current();
    _safeMint(msg.sender, newItemId);
    tokenIdToDetails[newItemId].expression = expression;
    tokenIdToDetails[newItemId].likes = 0;
    tokenIdToDetails[newItemId].dislikes = 0;
    _setTokenURI(newItemId, getTokenURI(newItemId));
  }

  //donation function
  function fundme() public payable {
      emit ReceivedMATIC(msg.sender, msg.value);
  }

  receive() external payable  { 
      fundme();
  }

  fallback() external payable {
      fundme();
  }

  //ensure MATIC cannot be trapped within the contract
  function withdraw() external onlyOwner {
    require(address(this).balance > 0, "No funds in contract");
    payable(owner()).transfer(address(this).balance);
  }

  function destroy() external onlyOwner {
    selfdestruct(payable(owner()));
  }

}
