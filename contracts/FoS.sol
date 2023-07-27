// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "./CustomERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/// @title A contract that allows users to mint and own an NFT of their public statement and earn MATIC per like
/// @notice The NFTs minted, and their metadata, are stored completely on the blockchain
/// @custom:experimental This is an experimental contract.
contract FreedomOfSpeech is CustomERC721URIStorage, ERC2981, Ownable{
  
  uint256 public tokensMinted; //tracks current tokenId
  uint256 public totalSupply;

  using Strings for uint256; //easily convert uint256 to string

  event ReceivedMATIC(address indexed _address, uint256 _amount);
  event LikeFeeChange(uint256 _amount);
  event DislikeFeeChange(uint256 _amount);
  event CreationFeeChange(uint256 _amount);
  event DislikeThresholdChange(uint256 _amount);
  event Withdraw(address indexed _address, uint256 _amount);
  event TokenMinted(uint256 indexed _tokenId, address _minter);
  event TokenLiked(uint256 indexed _tokenId, address _liker);
  event TokenDisliked(uint256 indexed _tokenId, address _disliker);
  event TokenClaimed(uint256 indexed _tokenId, address _claimer, uint256 _amount);
  event TokenBurnedDown(uint256 indexed _tokenId, uint256 feesLost);

  uint256 public totalUserMatic;

  struct Details {
    string expression;
    uint256 likes;
    uint256 dislikes;
    uint256 feesAccrued;
  }

  mapping(uint256 => Details) public tokenIdToDetails;

  mapping(address => mapping(uint256 => bool)) internal addressToReactionBool;

  uint64 public creationFee;
  uint64 public likeFee;
  uint64 public dislikeFee;
  uint64 public dislikeThreshold;

  bytes32 constant RESERVE_EXPRESSION = keccak256(abi.encodePacked("BURNED"));
  
  //set name and ticker of ERC721 contract and apply default royalty
  constructor() ERC721("Freedom of Speech", "FoS"){
    _setDefaultRoyalty(msg.sender, 250);
    setCreationFee(500000000000000000); // 0.5 matic
    setLikeFee(100000000000000000); // 0.1 matic
    setDislikeFee(50000000000000000); // 0.05 matic
    setDislikeThreshold(2);
  }

  //interaction functions ---------------------------------------------------------------------------------------------------------------------

  /// @notice Allows user to mint and hold a token of a given expression
  /// @notice Minting a token requires a creation fee plus gas
  /// @param _expression A user determined statement less than 64 bytes long (typically 64 characters)
  function mint(string memory _expression) external payable returns(uint256){
    require(msg.value >= creationFee, "Minimum fee not met!");
    require(bytes(_expression).length <= 64 , "Expression is too long");
    require(keccak256(abi.encodePacked(_expression)) != RESERVE_EXPRESSION, "Expression denied");
    totalSupply += 1;
    tokensMinted += 1;
    uint256 newItemId = tokensMinted;
    tokenIdToDetails[newItemId] = Details(_expression, 0, 0, 0);
    _safeMint(msg.sender, newItemId);
    emit TokenMinted(newItemId, msg.sender);
    _setTokenURI(newItemId, _generateTokenURI(newItemId));
    return newItemId;
  }
    
  /// @notice Allows user to like the expression posted on a token
  /// @notice Requires a small fee to like, which is routed to the current token holders reserve
  /// @param _tokenId The token Id issued upon minting the token
  function addLike(uint256 _tokenId) external payable {
    require(addressToReactionBool[msg.sender][_tokenId] == false, "Can only react to a token once");
    addressToReactionBool[msg.sender][_tokenId] = true;
    uint256 _fee = msg.value;
    require(_fee >= likeFee, "Minimum fee not met!");
    totalUserMatic += _fee;
    tokenIdToDetails[_tokenId].likes += 1;
    tokenIdToDetails[_tokenId].feesAccrued += _fee;
    _setTokenURI(_tokenId, _generateTokenURI(_tokenId));
    emit TokenLiked(_tokenId, msg.sender);
  }

  /// @notice Allows user to dislike the expression posted on a token
  /// @notice Requires a small fee to dislike, which is routed to all other token holders' reserves
  /// @notice If the number of dislikes is over the threshold AND greater than 2 x the tokens likes,
  ///         the token is burned and it's fee reserve is distributed to all other token holders' reserves
  /// @param _tokenId The token Id issued upon minting the token
  function addDislike(uint256 _tokenId) external payable {
    require(addressToReactionBool[msg.sender][_tokenId] == false, "Can only react to a token once");
    addressToReactionBool[msg.sender][_tokenId] = true;
    uint256 _fee = msg.value;
    require(_fee >= dislikeFee, "Minimum fee not met!");
    totalUserMatic += _fee;
    tokenIdToDetails[_tokenId].dislikes += 1;
    uint256 _tokensExisting = totalSupply;
    uint256 _tokensMinted = tokensMinted;
    uint256 _dislikes = tokenIdToDetails[_tokenId].dislikes;
    if(_dislikes >= dislikeThreshold && _dislikes >= (tokenIdToDetails[_tokenId].likes*2)){
      uint256 _feesAccruedForToken = tokenIdToDetails[_tokenId].feesAccrued;
      _burn(_tokenId);
      for(uint i = 1; i <= _tokensMinted; i++){
        if(i != _tokenId){
          if(_exists(i)){
            tokenIdToDetails[i].feesAccrued += (_fee + _feesAccruedForToken) / (_tokensExisting - 1);
          }
        }
      }
      emit TokenBurnedDown(_tokenId, _feesAccruedForToken);
         
    } else {
        for(uint i = 1; i <= _tokensMinted; i++){
          if(i != _tokenId){
            if(_exists(i)){
              tokenIdToDetails[i].feesAccrued += _fee / (_tokensExisting - 1);
            }
          }
        }
      _setTokenURI(_tokenId, _generateTokenURI(_tokenId));
    }
    emit TokenDisliked(_tokenId, msg.sender);
  }

  /// @notice Allows owner of token to burn token
  /// @param _tokenId The token Id issued upon minting the token
  function claimToken(uint256 _tokenId) external {
    address _sender = msg.sender;
    require(_sender == ownerOf(_tokenId), "Not Owner!");
    uint256 _funds = tokenIdToDetails[_tokenId].feesAccrued;
    totalUserMatic -= _funds;
    _burn(_tokenId);
    if(_funds > 0){
      payable(_sender).transfer(_funds);
    }
    emit TokenClaimed(_tokenId, _sender, _funds);
  }
  
  //getter functions ------------------------------------------------------------------------------------------------------------------------

  /// @notice Allows user to retrieve amount of likes of a specific token
  /// @param _tokenId The token Id issued upon minting the token
  /// @return Number of likes of given token
  function getLikes(uint256 _tokenId) public view returns (uint256) {
    require(_exists(_tokenId), "Token does not exist!");
    uint256 likes = tokenIdToDetails[_tokenId].likes;
    return likes;
  }

  /// @notice Allows user to retrieve amount of dislikes of a specific token
  /// @param _tokenId The token Id issued upon minting the token
  /// @return Number of dislikes of given token
  function getDislikes(uint256 _tokenId) public view returns (uint256) {
    require(_exists(_tokenId), "Token does not exist!");
    uint256 dislikes = tokenIdToDetails[_tokenId].dislikes;
    return dislikes;
  }
  
  /// @notice Allows user to retrieve amount of dislikes of a specific token
  /// @param _tokenId The token Id issued upon minting the token
  /// @return Total fees accrued for a specified token
  function getfeesAccrued(uint256 _tokenId) public view returns (uint256) {
    require(_exists(_tokenId), "Token does not exist!");
    uint256 fees = tokenIdToDetails[_tokenId].feesAccrued;
    return fees;
  }

  /// @notice Allows user to retrieve the expression of a specific token
  /// @param _tokenId The token Id issued upon minting the token
  /// @return Expression of given token
  function getExpression(uint256 _tokenId) public view returns (string memory){
    require(_exists(_tokenId), "Token does not exist!");
    string memory expression = tokenIdToDetails[_tokenId].expression;
    return expression;
  }

  //ERC721URIStorage and ERC2981 both override supportsInterface - to fix this it's overwritten here as well
  function supportsInterface(bytes4 _interfaceId) public view virtual override(CustomERC721URIStorage, ERC2981) returns (bool) {
    return super.supportsInterface(_interfaceId);
  }

  //owner functions -------------------------------------------------------------------------------------------------------------------------

  /// @notice onlyOwner - Allows owner of contract to change token creation fee
  /// @param _fee An owner determined fee in wei
  function setCreationFee(uint64 _fee) public onlyOwner {
    creationFee = _fee;
    emit CreationFeeChange(_fee);
  }

  /// @notice onlyOwner - Allows owner of contract to change token like fee
  /// @param _fee An owner determined fee in wei
  function setLikeFee(uint64 _fee) public onlyOwner {
    likeFee = _fee;
    emit LikeFeeChange(_fee);
  }

  /// @notice onlyOwner - Allows owner of contract to change token like fee
  /// @param _fee An owner determined fee in wei
  function setDislikeFee(uint64 _fee) public onlyOwner {
    dislikeFee = _fee;
    emit DislikeFeeChange(_fee);
  }

    /// @notice onlyOwner - Allows owner of contract to change token like fee
  /// @param _dislikes An owner determined value for automatic burn
  function setDislikeThreshold(uint64 _dislikes) public onlyOwner {
    dislikeThreshold = _dislikes;
    emit DislikeThresholdChange(_dislikes);
  }

  /// @notice onlyOwner - Allows owner of contract to withdraw donations and creation fees
  function withdraw(uint256 _amount, address _address) external onlyOwner {
    require(_address != address(0), "Invalid address");
    require(_amount != 0, "Amount cannot be 0");
    require(address(this).balance > totalUserMatic, "No contract funds available");
    require(_amount <= (address(this).balance - totalUserMatic), "Amount too high");
    payable(_address).transfer(_amount);
  }

  //internal functions ----------------------------------------------------------------------------------------------------------------------

  /**
   * @dev See {CustomERC721URIStorage-_burn}. This override additionally resets token royalty
   * and details within contract storage.
   */
  function _burn(uint256 _tokenId) internal virtual override {
    totalSupply -= 1;
    _resetTokenRoyalty(_tokenId);
    _resetTokenDetails(_tokenId);
    _setTokenURI(_tokenId, _generateTokenURI(_tokenId));
    ERC721._burn(_tokenId);
  }

  /// @dev Resets tokenIdToDetails struct within contract
  function _resetTokenDetails(uint256 _tokenId) internal {
    tokenIdToDetails[_tokenId] = Details("BURNED", 0, 0, 0);
  }

  /// @dev Generates svg creation for storing dynamic token images on-chain
  function _generateImage(string memory _tokenId, string memory _expression, string memory _likes, string memory _dislikes) internal pure returns(string memory){
    bytes memory svg = abi.encodePacked(
        '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350">',
        '<style>.base{ fill: white; font-family: serif; font-size: 14px; font-weight: bold;} .exp{ fill: darkturquoise; font-family: serif; font-size: 12px;} .stats{ fill: white; font-family: serif; font-size: 12px;}</style>',
        '<rect width="100%" height="100%" fill="black" />',
        '<text x="50%" y="25%" class="base" dominant-baseline="middle" text-anchor="middle">', "FoS #", _tokenId,'</text>',
        '<text x="50%" y="50%" class="exp" dominant-baseline="middle" text-anchor="middle">', _expression,'</text>',
        '<text x="50%" y="70%" class="stats" dominant-baseline="middle" text-anchor="middle">', "Likes: ", _likes,'</text>',
        '<text x="50%" y="80%" class="stats" dominant-baseline="middle" text-anchor="middle">', "Dislikes: ", _dislikes,'</text>',
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
  function _generateTokenURI(uint256 tokenId) internal view returns (string memory){

    string memory _tokenId = tokenId.toString();
    string memory _expression = getExpression(tokenId);
    string memory _likes = getLikes(tokenId).toString();
    string memory _dislikes = getDislikes(tokenId).toString();

    bytes memory dataURI = abi.encodePacked(
        '{',
            '"name": "FoS #', _tokenId, '",',
            '"external_url": " ",',
            '"description": "', _expression, '",',
            '"image_data": "', _generateImage(_tokenId, _expression, _likes, _dislikes), '",',
            '"attributes": [{"trait_type": "likes", "value": ', _likes,'}, {"trait_type": "dislikes", "value": ', _dislikes,'}, {"trait_type": "fees accrued", "value": ', tokenIdToDetails[tokenId].feesAccrued.toString(),'}]'
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
