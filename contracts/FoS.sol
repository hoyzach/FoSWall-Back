// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/// @title A contract that allows users to mint and own an NFT of their own expression and earn MATIC per like
/// @notice The NFTs minted, and their metadata, are stored completely on the blockchain
/// @custom:experimental This is an experimental contract.

//---------------------------------------------------------------------------------------------------------------------------------------------------!
// Freedom of Speech NFT Disclaimer:

// By minting a Freedom of Speech Non-Fungible Token (FoS Token) through this platform, you ("the Creator") understand and accept the following:
// (1) You are the sole author of the expression minted on your FoS Token, or you have obtained all necessary rights, permissions, licenses, or clearances 
//      to lawfully use the expression.
// (2) The expression minted on your FoS Token does not infringe upon the copyright, trademark, patent, trade secret, or any other intellectual property 
//      rights of any third party.
// (3) The expression minted on your FoS Token does not expose, disseminate, or otherwise utilize sensitive information that does not legally belong to 
//      you or is not authorized for use by you.
// (4) The Creator shall be solely responsible for any and all claims, damages, liabilities, costs, and expenses (including but not limited to legal 
//      fees and expenses) arising out of or related to any breach of the above statements or any use of this smart contract that violates any law, 
//      rule, or regulation, or the rights of any third party.

// By engaging with this smart contract and minting an FoS Token, you affirm that your actions comply with all applicable laws and regulations, 
// and you acknowledge that the contract owners shall not be liable for any unlawful or unauthorized activities.
//---------------------------------------------------------------------------------------------------------------------------------------------------!

contract FreedomOfSpeech is ERC721URIStorage, ERC2981, Ownable{
  
  uint256 public tokensMinted; //tracks current tokenId
  uint256 public totalActiveSupply;

  using Strings for uint256; //easily convert uint256 to string

  event ReceivedMATIC(address indexed _address, uint256 _amount);
  event LikeFeeChange(uint256 _amount);
  event DislikeFeeChange(uint256 _amount);
  event MintFeeChange(uint256 _amount);
  event DislikeThresholdChange(uint256 _amount);
  event Withdraw(address indexed _address, uint256 _amount);
  event AcceptedDisclaimer(address indexed _accepter);
  event TokenMinted(uint256 indexed _tokenId, address indexed _minter);
  event TokenLiked(uint256 indexed _tokenId, address indexed _liker);
  event TokenDisliked(uint256 indexed _tokenId, address indexed _disliker);
  event TokenClaimed(uint256 indexed _tokenId, address indexed _claimer, uint256 _amount);
  event TokenNullified(uint256 indexed _tokenId, uint256 feesLost);

  uint256 public totalUserMatic;

  struct Details {
    string expression;
    uint256 likes;
    uint256 dislikes;
    uint256 feesAccrued;
  }

  mapping(uint256 => Details) public tokenIdToDetails;

  mapping(address => mapping(uint256 => bool)) internal addressToReactionBool;
  mapping(uint256 => bool) internal inactive;
  mapping(address => bool) internal acceptedDisclaimer;

  uint64 public mintFee;
  uint64 public likeFee;
  uint64 public dislikeFee;
  uint64 public dislikeThreshold;
  uint256 public maxLikes;
  uint256 public maxDislikes;

  bytes32 constant RESERVE_EXPRESSION_NULLIFIED = keccak256(abi.encodePacked("NULLIFIED"));
  bytes32 constant RESERVE_EXPRESSION_CLAIMED = keccak256(abi.encodePacked("CLAIMED"));
  
  //set name and ticker of ERC721 contract and apply default royalty
  constructor() ERC721("Freedom of Speech", "FoS"){
    _setDefaultRoyalty(msg.sender, 100);
    setMintFee(500000000000000000); // 0.5 matic
    setLikeFee(100000000000000000); // 0.1 matic
    setDislikeFee(50000000000000000); // 0.05 matic
    setDislikeThreshold(2);
  }

  //interaction functions ---------------------------------------------------------------------------------------------------------------------

  /// @notice Grants address ability to mint after accepting disclaimer
  function acceptDisclaimer() external {
    address _accepter = msg.sender;
    require(!acceptedDisclaimer[_accepter], "Disclaimer already accepted");
    acceptedDisclaimer[_accepter] = true;
    emit AcceptedDisclaimer(_accepter);
  }
  
  /// @notice Allows user to mint and hold a token of a given expression
  /// @notice Minting a token requires a mint fee plus gas
  /// @param _expression A user determined statement less than 64 bytes long (typically 64 characters)
  function mint(string memory _expression) external payable returns(uint256){
    require(acceptedDisclaimer[msg.sender], "Disclaimer not accepted");
    require(msg.value >= mintFee, "Minimum fee not met!");
    require(bytes(_expression).length > 0 && !isOnlyWhitespace(_expression), "Expression cannot be null or only whitespace");
    require(bytes(_expression).length <= 56 , "Expression is too long");
    require(
      keccak256(abi.encodePacked(_expression)) != RESERVE_EXPRESSION_NULLIFIED &&
      keccak256(abi.encodePacked(_expression)) != RESERVE_EXPRESSION_CLAIMED, 
      "Expression denied"
    );
    totalActiveSupply += 1;
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
    require(!inactive[_tokenId], "Token has been nullified or claimed");
    require(addressToReactionBool[msg.sender][_tokenId] == false, "Can only react to a token once");
    addressToReactionBool[msg.sender][_tokenId] = true;
    uint256 _fee = msg.value;
    require(_fee >= likeFee, "Minimum fee not met!");
    totalUserMatic += _fee;
    tokenIdToDetails[_tokenId].likes += 1;
    tokenIdToDetails[_tokenId].feesAccrued += _fee;
    if (tokenIdToDetails[_tokenId].likes > maxLikes) {
      maxLikes = tokenIdToDetails[_tokenId].likes;
    }
    _setTokenURI(_tokenId, _generateTokenURI(_tokenId));
    emit TokenLiked(_tokenId, msg.sender);
  }

  /// @notice Allows user to dislike the expression posted on a token
  /// @notice Requires a small fee to dislike, which is routed to all other token holders' reserves
  /// @notice If the number of dislikes is over the threshold AND greater than 2 x the tokens likes,
  ///         the token is nullified and it's fee reserve is distributed to all other token holders' reserves
  /// @param _tokenId The token Id issued upon minting the token
  function addDislike(uint256 _tokenId) external payable {
    require(!inactive[_tokenId], "Token has been nullified or claimed");
    require(addressToReactionBool[msg.sender][_tokenId] == false, "Can only react to a token once");
    addressToReactionBool[msg.sender][_tokenId] = true;
    uint256 _fee = msg.value;
    require(_fee >= dislikeFee, "Minimum fee not met!");
    tokenIdToDetails[_tokenId].dislikes += 1;
    if (tokenIdToDetails[_tokenId].dislikes > maxDislikes) {
      maxDislikes = tokenIdToDetails[_tokenId].dislikes;
    }
    uint256 _tokensActive = totalActiveSupply;
    uint256 _tokensMinted = tokensMinted;
    uint256 _dislikes = tokenIdToDetails[_tokenId].dislikes;
    if(_dislikes >= dislikeThreshold && _dislikes > (tokenIdToDetails[_tokenId].likes*2)){
      uint256 _feesAccruedForToken = tokenIdToDetails[_tokenId].feesAccrued;
      _nullify(_tokenId);
      if(_tokensActive > 1) {
        uint256 totalFee = _fee + _feesAccruedForToken;
        uint256 distributedFee = 0;        
        for(uint i = 1; i <= _tokensMinted; i++) {
            if(i != _tokenId && !inactive[i]) {
                uint256 individualFee = totalFee / (_tokensActive - 1);
                if (distributedFee + individualFee > totalFee) {
                    individualFee = totalFee - distributedFee;
                }
                tokenIdToDetails[i].feesAccrued += individualFee;
                distributedFee += individualFee;
            }
        }
        totalUserMatic += distributedFee - _feesAccruedForToken;
      }
      emit TokenNullified(_tokenId, _feesAccruedForToken);
         
    } else {
      if(_tokensActive > 1){
        uint256 distributedFee = 0;  
        for(uint i = 1; i <= _tokensMinted; i++){
            if(i != _tokenId && !inactive[i]) {
                uint256 individualFee = _fee / (_tokensActive - 1);
                if (distributedFee + individualFee > _fee) {
                    individualFee = _fee - distributedFee;
                }
                tokenIdToDetails[i].feesAccrued += individualFee;
                distributedFee += individualFee;
            }
        }
        totalUserMatic += distributedFee; 
      }
      _setTokenURI(_tokenId, _generateTokenURI(_tokenId));
    }
    emit TokenDisliked(_tokenId, msg.sender);
  }

  /// @notice Allows owner of token to burn token
  /// @param _tokenId The token Id issued upon minting the token
  function claimToken(uint256 _tokenId) external {
    require(!inactive[_tokenId], "Token has been nullified or claimed");
    address _sender = msg.sender;
    require(_sender == ownerOf(_tokenId), "Not Owner!");
    uint256 _funds = tokenIdToDetails[_tokenId].feesAccrued;
    tokenIdToDetails[_tokenId].feesAccrued = 0;
    tokenIdToDetails[_tokenId].expression = "CLAIMED";
    totalActiveSupply -= 1;
    inactive[_tokenId] = true;
    totalUserMatic -= _funds;
    if(_funds > 0){
      payable(_sender).transfer(_funds);
    }
    _setTokenURI(_tokenId, _generateTokenURI(_tokenId));
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
    require(!inactive[_tokenId], "Token inactive!");
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
  function supportsInterface(bytes4 _interfaceId) public view virtual override(ERC721URIStorage, ERC2981) returns (bool) {
    return super.supportsInterface(_interfaceId);
  }

  //owner functions -------------------------------------------------------------------------------------------------------------------------

  /// @notice onlyOwner - Allows owner of contract to change token mint fee
  /// @param _fee An owner determined fee in wei
  function setMintFee(uint64 _fee) public onlyOwner {
    mintFee = _fee;
    emit MintFeeChange(_fee);
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

  /// @notice onlyOwner - Allows owner of contract to withdraw donations and mint fees
  function withdraw(uint256 _amount, address _address) external onlyOwner {
    require(_address != address(0), "Invalid address");
    require(_amount != 0, "Amount cannot be 0");
    require(address(this).balance > totalUserMatic, "No contract funds available");
    require(_amount <= (address(this).balance - totalUserMatic), "Amount too high");
    payable(_address).transfer(_amount);
  }

  //internal functions ----------------------------------------------------------------------------------------------------------------------

  /// @dev Check if given expression entered is only whitespace
  function isOnlyWhitespace(string memory str) internal pure returns (bool) {
      bytes memory b = bytes(str);
      for (uint i; i < b.length; i++) {
          if (b[i] != 0x20 && b[i] != 0x09 && b[i] != 0x0A && b[i] != 0x0D) {
              return false;
          }
      }
      return true;
  }

  /// @dev Replaces tokens expression with "Nullified", makes the token inactive, and removes token royalty
  function _nullify(uint256 _tokenId) internal virtual {
    totalActiveSupply -= 1;
    tokenIdToDetails[_tokenId].feesAccrued = 0;
    tokenIdToDetails[_tokenId].expression = "NULLIFIED";
    inactive[_tokenId] = true;
    _resetTokenRoyalty(_tokenId);
    _setTokenURI(_tokenId, _generateTokenURI(_tokenId));
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
            '"attributes": [',
                '{"trait_type": "likes", "value": ', _likes, ', "max_value": ', maxLikes.toString(), '}, ',
                '{"trait_type": "dislikes", "value": ', _dislikes, ', "max_value": ', maxDislikes.toString(), '} ',
            ']'
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
