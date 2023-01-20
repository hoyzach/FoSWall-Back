// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title A contract that allows users to mint and own an NFT of their public statement and earn MATIC per like
/// @notice The NFTs minted, and their metadata, are stored completely on the blockchain
/// @custom:experimental This is an experimental contract.
contract FreedomOfSpeech is ERC721URIStorage, ERC2981, Ownable{
  
  uint256 public tokensMinted; //tracks current tokenId
  uint256 public tokensExisting;

  using Strings for uint256; //easily convert uint256 to string

  event ReceivedMATIC(address sender, uint256 amount); //sets event for when Matic is sent to contract

  struct Details {
    string expression;
    uint256 likes;
    uint256 dislikes;
  }
  
  /// @notice Get details of a token
  /// return Expression, likes, and dislikes of a specific token
  mapping(uint256 => Details) public tokenIdToDetails;

  mapping(address => mapping(uint256 => bool)) internal addressToReactionBool;

  /// @notice Get current creation fee
  /// @return Current creation fee in wei
  uint128 public creationFee = 0;

  /// @notice Get current like fee
  /// @return Current like fee in wei
  uint128 public likeFee = 0;
  
  //set name and ticker of ERC721 contract and apply default royalty
  constructor() ERC721("Freedom of Speech", "FoS"){
    _setDefaultRoyalty(msg.sender, 500);
  }

  //modifers -------------------------------------------------------------------------------------------------------------------------------

  //modifer to check if sender has already reacted to a tokenId
  modifier reactOnce(uint256 _tokenId) {
    require(addressToReactionBool[msg.sender][_tokenId] == false, "Can only react to a token once");
    addressToReactionBool[msg.sender][_tokenId] = true;
    _;
  }

  //modifer to check if sender has already reacted to a tokenId
  modifier tokenExists(uint256 _tokenId) {
    require(_exists(_tokenId), "Token does not exist!");
    _;
  }

  //interaction functions ---------------------------------------------------------------------------------------------------------------------

  /// @notice Allows user to mint and hold a token of a given expression
  /// @notice Minting an token requires a creation fee plus gas
  /// @param expression A user determined statement less than 64 bytes long (typically 64 characters)
  function mint(string memory expression) public payable {
    require(msg.value >= creationFee, "Sorry, minimum fee not met!");
    require(bytes(expression).length <= 64 , "The expression is too long");
    uint256 newItemId = tokensMinted;
    tokenIdToDetails[newItemId].expression = expression;
    tokenIdToDetails[newItemId].likes = 0;
    tokenIdToDetails[newItemId].dislikes = 0;
    tokensMinted += 1;
    tokensExisting += 1;
    _safeMint(msg.sender, newItemId);
    _setTokenURI(newItemId, _getTokenURI(newItemId));
  }
    
  /// @notice Allows user to like the expression posted on a token
  /// @notice Requires a small fee to like, which is routed to current token holder
  /// @param _tokenId The token Id issued upon minting the token
  function addLike(uint256 _tokenId) public payable reactOnce(_tokenId) tokenExists(_tokenId) {
    require(msg.value >= likeFee, "Sorry, minimum fee not met!");
    (bool sent, ) = ownerOf(_tokenId).call{value: msg.value}("");
    require(sent, "Failed to send Matic");
    tokenIdToDetails[_tokenId].likes += 1;
    _setTokenURI(_tokenId, _getTokenURI(_tokenId));
  }

  /// @notice Allows user to dislike the expression posted on a token
  /// @param _tokenId The token Id issued upon minting the token
  function addDislike(uint256 _tokenId) public reactOnce(_tokenId) tokenExists(_tokenId) {
    tokenIdToDetails[_tokenId].dislikes += 1;
  }

  /// @notice Allows owner of token to burn token
  /// @param _tokenId The token Id issued upon minting the token
  function burn(uint256 _tokenId) public {
    require(msg.sender == ownerOf(_tokenId), "Nice try, you cannot burn someone elses token!");
    tokensExisting -= 1;
    _burn(_tokenId);
  }
  
  //getter functions ------------------------------------------------------------------------------------------------------------------------

  /// @notice Allows user to retrieve amount of likes of a specific token
  /// @param _tokenId The token Id issued upon minting the token
  /// @return Number of likes of given token
  function getLikes(uint256 _tokenId) public view tokenExists(_tokenId) returns (uint256) {
    uint256 likes = tokenIdToDetails[_tokenId].likes;
    return likes;
  }

  /// @notice Allows user to retrieve amount of dislikes of a specific token
  /// @param _tokenId The token Id issued upon minting the token
  /// @return Number of likes of given token
  function getDislikes(uint256 _tokenId) public view tokenExists(_tokenId) returns (uint256) {
    uint256 dislikes = tokenIdToDetails[_tokenId].dislikes;
    return dislikes;
  }

  /// @notice Allows user to retrieve the expression of a specific token
  /// @param _tokenId The token Id issued upon minting the token
  /// @return Expression of given token
  function getExpression(uint256 _tokenId) public view tokenExists(_tokenId) returns (string memory){
    string memory expression = tokenIdToDetails[_tokenId].expression;
    return expression;
  }

  //ERC721URIStorage and ERC2981 both override supportsInterface - to fix this it's overwritten here as well
  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC2981) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  function totalSupply() external view returns(uint256){
    return tokensExisting;
  }

  //owner functions -------------------------------------------------------------------------------------------------------------------------

  /// @notice onlyOwner - Allows owner of contract to change token creation fee
  /// @param _fee A user determined fee in wei
  function setCreationFee(uint128 _fee) external onlyOwner {
    creationFee = _fee;
  }

  /// @notice onlyOwner - Allows owner of contract to change token like fee
  /// @param _fee A user determined fee in wei
  function setLikeFee(uint128 _fee) external onlyOwner {
    likeFee = _fee;
  }

  /// @notice onlyOwner - Allows owner of contract to withdraw donations and creation fees
  function withdraw() external onlyOwner {
    require(address(this).balance > 0, "No funds in contract");
    payable(owner()).transfer(address(this).balance);
  }

  /// @notice onlyOwner - Allows owner of contract to destroy contract
  function destroy() external onlyOwner {
    selfdestruct(payable(owner()));
  }

  //internal functions ----------------------------------------------------------------------------------------------------------------------

  /**
   * @dev See {ERC721URIStorage-_burn}. This override additionally resets token royalty
   * and details within contract storage.
   */
  function _burn(uint256 _tokenId) internal virtual override {
    super._burn(_tokenId);
    _resetTokenRoyalty(_tokenId);
    _resetTokenDetails(_tokenId);
  }

  /// @dev Resets tokenIdToDetails struct within contract
  function _resetTokenDetails(uint256 _tokenId) internal {
    tokenIdToDetails[_tokenId].expression = "DELETED";
    tokenIdToDetails[_tokenId].likes = 0;
    tokenIdToDetails[_tokenId].dislikes = 0;
  }

  /// @dev Generates svg creation for storing dynamic token images on-chain
  function _generateImage(uint256 _tokenId) internal view returns(string memory){
    bytes memory svg = abi.encodePacked(
        '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350">',
        '<style>.base { fill: white; font-family: serif; font-size: 16px; font-weight: bold; } .exp{ fill: darkturquoise; font-family: serif; font-size: 12px; font-weight: bold;}</style>',
        '<rect width="100%" height="100%" fill="black" />',
        '<text x="50%" y="30%" class="base" dominant-baseline="middle" text-anchor="middle">', "FoS #",_tokenId.toString(),'</text>',
        '<text x="50%" y="50%" class="exp" dominant-baseline="middle" text-anchor="middle">',getExpression(_tokenId),'</text>',
        '<text x="50%" y="70%" class="base" dominant-baseline="middle" text-anchor="middle">', "Likes: ",getLikes(_tokenId).toString(),'</text>',
        '</svg>'
    );
    
    return string(
        abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(svg)
        )    
    );
  }

  /// @dev Generates token URI to be set when token is minted or likes are added
  function _getTokenURI(uint256 _tokenId) internal view returns (string memory){
    bytes memory dataURI = abi.encodePacked(
        '{',
            '"name": "FoS #', _tokenId.toString(), '",',
            '"description": "', getExpression(_tokenId), '",',
            '"image_data": "', _generateImage(_tokenId), '"',
        '}'
    );
    return string(
        abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(dataURI)
        )
    );
  }

  //other functions -------------------------------------------------------------------------------------------------------------------------

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

}
