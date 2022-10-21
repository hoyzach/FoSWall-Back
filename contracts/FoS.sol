// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title A contract that allows users to mint and own an NFT of their public statement and earn MATIC per like
/// @notice The NFTs minted are stored completely on the blockchain
/// @custom:experimental This is an experimental contract.
contract FreedomOfSpeech is ERC721URIStorage, ERC2981, Ownable{
  
  using Counters for Counters.Counter; 
  Counters.Counter private _tokenIds; //tracks current tokenId

  using Strings for uint256; //easily convert uint256 to string

  event ReceivedMATIC(address sender, uint256 amount); //sets event for when Matic is sent to contract

  struct Details {
    string expression;
    uint256 likes;
    uint256 dislikes;
  }

  mapping(uint256 => Details) public tokenIdToDetails;
  mapping(address => mapping(uint256 => bool)) public addressToReactionBool;

  uint128 public creationFee = 0 ether;
  uint128 public likeFee = 0 ether;
  
  //set name and ticker of ERC721 contract and apply default royalty
  constructor() ERC721("Freedom of Speech", "FoS"){
    _setDefaultRoyalty(msg.sender, 500);
  }

  //modifers -------------------------------------------------------------------------------------------------------------------------------

  //modifer to check if sender has already reacted to a tokenId
  modifier reactOnce(uint256 tokenId) {
    require(addressToReactionBool[msg.sender][tokenId] == false, "Can only react to a token once");
    addressToReactionBool[msg.sender][tokenId] = true;
    _;
  }

  //internal functions ---------------------------------------------------------------------------------------------------------------------

  //ERC721URIStorage and ERC2981 both override supportsInterface - to fix this it's overwritten here as well
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

  /// @notice Allows owner of token to burn token
  /// @param tokenId The token Id issued upon minting the token
  function burn(uint256 tokenId) public {
    require(msg.sender == ownerOf(tokenId), "Nice try, you cannot burn someone elses token!");
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
        '<text x="50%" y="70%" class="base" dominant-baseline="middle" text-anchor="middle">', "Likes: ",getLikes(tokenId).toString(),'</text>',
        '</svg>'
    );
    
    return string(
        abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(svg)
        )    
    );
  }

  /// @notice Allows user to like the expression posted on a token
  /// @notice Requires 0.1 matic to like which is routed to current token holder
  /// @param tokenId The token Id issued upon minting the token
  function addLike(uint256 tokenId) public payable reactOnce(tokenId) {
    require(_exists(tokenId), "Please react to an existing token");
    require(msg.value == 1e17, "Sorry, it costs 0.1 matic to like!");
    tokenIdToDetails[tokenId].likes += 1;
    _setTokenURI(tokenId, getTokenURI(tokenId));
    address to = ownerOf(tokenId);
    (bool sent, ) = to.call{value: msg.value}("");
    require(sent, "Failed to send Ether");
  }

  /// @notice Allows user to retrieve amount of likes of a specific token
  /// @param tokenId The token Id issued upon minting the token
  /// @return Number of likes of given token
  function getLikes(uint256 tokenId) public view returns (uint256) {
    uint256 likes = tokenIdToDetails[tokenId].likes;
    return likes;
  }

  /// @notice Allows user to dislike the expression posted on a token
  /// @param tokenId The token Id issued upon minting the token
  function addDislike(uint256 tokenId) public reactOnce(tokenId) {
    require(_exists(tokenId), "Please react to an existing token");
    tokenIdToDetails[tokenId].dislikes += 1;
  }

  /// @notice Allows user to retrieve amount of dislikes of a specific token
  /// @param tokenId The token Id issued upon minting the token
  /// @return Number of likes of given token
  function getDislikes(uint256 tokenId) public view returns (uint256) {
    uint256 dislikes = tokenIdToDetails[tokenId].dislikes;
    return dislikes;
  }

  /// @notice Allows user to retrieve the expression of a specific token
  /// @param tokenId The token Id issued upon minting the token
  /// @return Expression of given token
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
  /// @notice Allows owner of contract to change token creation fee
  /// @param _fee A user determined fee
  function setCreationFee(uint128 _fee) external onlyOwner {
    creationFee = _fee;
  }

  /// @notice Allows user to mint and hold a token of a given expression
  /// @notice Minting an token requires a creation fee plus gas
  /// @param expression A user determined statement less than 64 bytes long (typically 64 characters)
  function mint(string memory expression) public payable {
    require(msg.value == creationFee, "Sorry, it costs " + creationFee.toString() + " to post!");
    require(bytes(expression).length <= 64 , "The expression is too long");
    _tokenIds.increment();
    uint256 newItemId = _tokenIds.current();
    tokenIdToDetails[newItemId].expression = expression;
    tokenIdToDetails[newItemId].likes = 0;
    tokenIdToDetails[newItemId].dislikes = 0;
    _setTokenURI(newItemId, getTokenURI(newItemId));
    _safeMint(msg.sender, newItemId);
  }

  /// @notice Donate Matic to contract
  function fundme() public payable {
      emit ReceivedMATIC(msg.sender, msg.value);
  }

  /// @notice Donate Matic to contract
  receive() external payable  { 
      fundme();
  }

  /// @notice Donate Matic to contract
  fallback() external payable {
      fundme();
  }

  /// @notice Allows owner of contract to withdraw donations and creation fees
  function withdraw() external onlyOwner {
    require(address(this).balance > 0, "No funds in contract");
    payable(owner()).transfer(address(this).balance);
  }

  /// @notice Allows owner of contract to destroy contract
  function destroy() external onlyOwner {
    selfdestruct(payable(owner()));
  }

}
