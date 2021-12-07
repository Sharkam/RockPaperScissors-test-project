//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

/**
 @notice Allows to create games of Rock paper scissors between 2 addresses
         Any number of games can be created and waged with the initialized erc-20 token
         A game will timeout after one day if no players has made any move
         The creator of the game can call the delete function to get back a little bit of his gas used to create the game
 @author Julien Fontanel
 */
contract RockPaperScissors {
    using SafeERC20 for IERC20;

    //ERC-20 token used to wager in a game
    address public tokenWagerAddr;

    //Game timeout
    uint256 public gameTimeOut = 1 days;

    //Move options
    enum Move {
        NOT_DEFINED,
        ROCK,
        PAPER,
        SCISSORS
    }

    //Game object
    struct Game {
        uint256 gameId;
        address player1;
        address player2;
        Move player1Move;
        Move player2Move;
        bool player1CanPlay;
        bool player2CanPlay;
        uint256 wagerAmount;
        uint256 lastUpdate;
        address winner;
        uint256 player1Rewards;
        uint256 player2Rewards;
    }

    uint256 public gamesCount;

    mapping(address => uint256[]) public gameIdsByPlayer;
    //Games are private to keep the playerMove hidden
    mapping(uint256 => Game) private games;

    /**
     @notice Makes sure the sender can play this game
     @param gameId uint256 The game Id
     */
    modifier canPlay(uint256 gameId) {
        if (games[gameId].player1 == msg.sender) {
            require(games[gameId].player1CanPlay, "PLAYER_1_ALREADY_PLAYED");
        } else {
            require(
                games[gameId].player2 == msg.sender ||
                    games[gameId].player2 == address(0),
                "PLAYER_2_ALREADY_TAKEN"
            );
            require(games[gameId].player2CanPlay, "PLAYER_2_ALREADY_PLAYED");
        }
        _;
    }

    /**
     @notice Cheks if a game has timeout
     @param gameId uint256 The game id to check
     */
    modifier hasNotTimeOut(uint256 gameId) {
        require(!hasTimeout(gameId));
        _;
    }

    /**
     @notice Makes sure the move is an authorized
     @param move uint8 The move Id
     */
    modifier isAuthorizedMove(uint8 move) {
        require(0 < move && move <= 3);
        _;
    }

    /**
     @param _tokenWagerAddr address The address of erc-20 token for the game's wager
     */
    constructor(address _tokenWagerAddr) {
        tokenWagerAddr = _tokenWagerAddr;
    }

    /**
     @notice Creates a new game of rock paper scissors
     @param _wagerAmount uint256 The amount of erc-20 token to wage in that game
     */
    function createGame(uint256 _wagerAmount) external {
        gamesCount++;
        Game memory newGame = Game({
            gameId: gamesCount,
            player1: msg.sender,
            player2: address(0),
            player1Move: Move.NOT_DEFINED,
            player2Move: Move.NOT_DEFINED,
            player1CanPlay: true,
            player2CanPlay: true,
            wagerAmount: _wagerAmount,
            lastUpdate: block.timestamp,
            winner: address(0),
            player1Rewards: _wagerAmount,
            player2Rewards: 0
        });

        gameIdsByPlayer[msg.sender].push(gamesCount);
        games[gamesCount] = newGame;

        IERC20(tokenWagerAddr).safeTransferFrom(
            msg.sender,
            address(this),
            _wagerAmount
        );
    }

    /**
     @notice One player decides to make a move in an existing game
     @param gameId uint256 The game id to play
     @param move uint8 The move chosen by the player
     */
    function play(uint256 gameId, uint8 move)
        external
        canPlay(gameId)
        hasNotTimeOut(gameId)
        isAuthorizedMove(move)
    {
        //First we transfer the funds for the wager to make sure the player has the funds to play if he has not paid yet
        if (
            msg.sender != games[gameId].player1 &&
            msg.sender != games[gameId].player2
        ) {
            IERC20(tokenWagerAddr).safeTransferFrom(
                msg.sender,
                address(this),
                games[gameId].wagerAmount
            );
        }

        if (msg.sender == games[gameId].player1) {
            games[gameId].player1Move = getMove(move);
            games[gameId].player1CanPlay = false;
        } else {
            games[gameId].player2Move = getMove(move);
            games[gameId].player2CanPlay = false;
            //Saves gas if already player already saved
            if (games[gameId].player2 == address(0)) {
                games[gameId].player2 = msg.sender;
                games[gameId].player2Rewards = games[gameId].wagerAmount;
                gameIdsByPlayer[msg.sender].push(gameId);
            }
        }

        //Check if the game is over and update
        if (!games[gameId].player1CanPlay && !games[gameId].player2CanPlay) {
            //check results
            address winner = getWinner(games[gameId]);
            if (winner != address(0)) {
                //Game over we have a winner
                games[gameId].winner = winner;
                if (winner == games[gameId].player1) {
                    games[gameId].player1Rewards =
                        games[gameId].wagerAmount *
                        2;
                    games[gameId].player2Rewards = 0;
                } else {
                    games[gameId].player2Rewards =
                        games[gameId].wagerAmount *
                        2;
                    games[gameId].player1Rewards = 0;
                }
            } else {
                //Draw, reset moves
                games[gameId].player1Move = Move.NOT_DEFINED;
                games[gameId].player1CanPlay = true;
                games[gameId].player2Move = Move.NOT_DEFINED;
                games[gameId].player2CanPlay = true;
            }
        }

        games[gameId].lastUpdate = block.timestamp;
    }

    /**
     @notice Claims the rewards for the winner of the game
     @param gameId uint256 The game id to claim from
     */
    function claimRewards(uint256 gameId) external {
        require(
            hasTimeout(gameId) || games[gameId].winner != address(0),
            "NO_TIMEOUT_OR_WINNER_YET"
        );
        require(
            games[gameId].player1 == msg.sender ||
                games[gameId].player2 == msg.sender,
            "NOT_A_PLAYER"
        );

        uint256 toClaim = 0;

        if (games[gameId].player1 == msg.sender) {
            require(games[gameId].player1Rewards > 0, "NOTHING_TO_CLAIM");
            toClaim = games[gameId].player1Rewards;
            games[gameId].player1Rewards = 0;
        } else {
            require(games[gameId].player2Rewards > 0, "NOTHING_TO_CLAIM");
            toClaim = games[gameId].player2Rewards;
            games[gameId].player1Rewards = 0;
        }

        IERC20(tokenWagerAddr).approve(address(this), toClaim);
        IERC20(tokenWagerAddr).safeTransferFrom(
            address(this),
            msg.sender,
            toClaim
        );
    }

    /**
     @notice Delete a game from the contract to get back gas, only can be done if the 
     game has timeout or the game is over and if the winner has claimed his winnings.
     Only the creator of the game can execute this function
     @param gameId uint256 The game id to delete
     */
    function deleteGame(uint256 gameId) external {
        require(games[gameId].player1 == msg.sender, "NOT_GAME_OWNER");
        require(
            (games[gameId].winner == address(0) && hasTimeout(gameId)) ||
                (games[gameId].player1Rewards == 0 &&
                    games[gameId].player2Rewards == 0),
            "CANT_DELETE_YET"
        );
        for (uint256 i; i < gameIdsByPlayer[msg.sender].length; i++) {
            if (gameIdsByPlayer[msg.sender][i] == gameId) {
                delete gameIdsByPlayer[msg.sender][i];
                break;
            }
        }
        delete games[gameId];
    }

    function getMove(uint8 move) internal pure returns (Move) {
        if (move == 1) {
            return Move.ROCK;
        } else if (move == 2) {
            return Move.PAPER;
        } else if (move == 3) {
            return Move.SCISSORS;
        }
        return Move.NOT_DEFINED;
    }

    function getWinner(Game memory game) internal pure returns (address) {
        if (game.player1Move == Move.ROCK) {
            if (game.player2Move == Move.SCISSORS) {
                return game.player1;
            } else if (game.player2Move == Move.PAPER) {
                return game.player2;
            }
        }

        if (game.player1Move == Move.SCISSORS) {
            if (game.player2Move == Move.PAPER) {
                return game.player1;
            } else if (game.player2Move == Move.ROCK) {
                return game.player2;
            }
        }

        if (game.player1Move == Move.PAPER) {
            if (game.player2Move == Move.ROCK) {
                return game.player1;
            } else if (game.player2Move == Move.SCISSORS) {
                return game.player2;
            }
        }

        //Draw
        return address(0);
    }

    function hasTimeout(uint256 gameId) internal view returns (bool) {
        uint256 toCheck = block.timestamp - gameTimeOut;
        return games[gameId].lastUpdate < toCheck;
    }

    /**
     @notice Get the game information for the game id passed in parameters
     @param gameId uint256 The game id to get the information
     @dev We don't return the players's move if the game if not over for obvious reasons
     */
    function getGameInfo(uint256 gameId) public view returns (Game memory) {
        Game memory gameInfo = games[gameId];
        if (games[gameId].winner == address(0) && !hasTimeout(gameId)) {
            //Game is not over we don't send the players's moves
            gameInfo.player1Move = Move.NOT_DEFINED;
            gameInfo.player2Move = Move.NOT_DEFINED;
        }
        return gameInfo;
    }

    /**
     @notice Get all the game Ids for the user
     @return uint256[] The list of game Ids
     */
    function getGameIds(address user) public view returns (uint256[] memory) {
        //Return the list of vaults the user has created
        return gameIdsByPlayer[user];
    }
}
