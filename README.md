# Welcome to FoSWall!



## What is FoS?

Freedom of Speech is a smart contract deployed on the Polygon Mumbai test chain. It allows users to mint Non-Fungible Tokens called FoS Tokens, which display a custom expression. FoS Tokens can earn fees, tracked by its fees accrued balance, through users liking the token or disliking other FoS Tokens.



## What is on an FoS Token?

At the top of the FoS Token is the FoS#, ordered sequentially per mint. The expression is displayed in the middle, followed by the token's total number of both likes and dislikes displayed below it.



## Minting an FoS Token

Users are able to mint as many FoS Tokens as desired paying a mint fee for each one. When selecting an expression to display on your FoS Token, please follow all the rules outlined in the Freedom of Speech disclaimer. The maximum length of an expression is 56 bytes.



## Interacting with FoS Tokens

Users can like or dislike active tokens for a small fee. Only one of these actions may be performed once per FoS Token per wallet address.



## Earning Fees

When an active FoS token is liked, the like fee is added to its fees accrued balance. When any other FoS Token is disliked, the dislike fee is divided evenly between all other 'active' FoS Tokens and added to their respective fees accrued balance.



## Claiming Fees

The fees accrued for an FoS Token can be claimed in lump sum, one time only. After that, the expression on the FoS Token will be replaced with 'CLAIMED', making it inactive and ineligible for further likes or dislikes. As a result, it will no longer be able to earn fees.



## Losing Fees

The fees accrued for an FoS Token can be lost if its number of dislikes exceeds twice its number of likes, as long as the number of dislikes is over the current dislike threshold. If this occurs, the token is nullified, becoming inactive. Its expression is then replaced with 'NULLIFIED', and its total fees accrued balance is divided evenly among the remaining active FoS Tokens. As a result, it will no longer be able to earn fees.



## Inactive Token

When an FoS Token is claimed or nullified, it becomes inactive, and its expression is altered permanently, while all other aspects of the token remain unchanged.  Inactive tokens lose the ability to be further liked, disliked, claimed, or nullified.  Inactive FoS Tokens are not burned and can still be transferred to different wallet addresses.



This is a [Next.js](https://nextjs.org/) project bootstrapped with [`create-next-app`](https://github.com/vercel/next.js/tree/canary/packages/create-next-app) and deployed on Vercel.