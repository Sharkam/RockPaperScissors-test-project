const { time } = require("@openzeppelin/test-helpers");
const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RockPaperScissors", function () {
    let rockPaperScissors, rockPaperScissors2, erc20, erc20_2, accounts;
    const wagerAmount = "10";
    const wagerAmountBN = BigNumber.from(wagerAmount);
    const MOVES = { NOT_DEFINED: 0, ROCK: 1, PAPER: 2, SCISSORS: 3 };

    beforeEach(async () => {
        //Get the ERC-20 token test first
        const ERC20Basic = await ethers.getContractFactory("ERC20Basic");
        erc20 = await ERC20Basic.deploy(1000000000);
        // Load Contracts with that erc-20 token contract
        const RockPaperScissors = await ethers.getContractFactory(
            "RockPaperScissors"
        );
        rockPaperScissors = await RockPaperScissors.deploy(erc20.address);

        //Distribute tokens to other accounts
        accounts = await ethers.getSigners();
        accounts.forEach(async (account) => {
            await erc20.transfer(account.address, 10000);
        });
        rockPaperScissors2 = await rockPaperScissors.connect(accounts[1]);
        erc20_2 = await erc20.connect(accounts[1]);
    });
    it("Should be able to create a new game of Rock Paper Scissors", async function () {
        erc20.approve(rockPaperScissors.address, wagerAmount);
        await rockPaperScissors.createGame(wagerAmount);
        const gamesCount = await rockPaperScissors.gamesCount();
        expect(gamesCount.toString()).to.equal("1");
    });

    it("Should be able to make a move in an existing game", async function () {
        erc20.approve(rockPaperScissors.address, wagerAmount);
        await rockPaperScissors.createGame(wagerAmount);
        const gameIds = await rockPaperScissors.getGameIds(accounts[0].address);
        await rockPaperScissors.play(gameIds[0], MOVES.PAPER);
    });

    it("Should not be able to play twice before the other player has played", async function () {
        erc20.approve(rockPaperScissors.address, wagerAmount);
        await rockPaperScissors.createGame(wagerAmount);
        const gameIds = await rockPaperScissors.getGameIds(accounts[0].address);
        await rockPaperScissors.play(gameIds[0], MOVES.PAPER);

        await expect(
            rockPaperScissors.play(gameIds[0], MOVES.PAPER)
        ).to.be.revertedWith("PLAYER_1_ALREADY_PLAYED");
    });

    it("Should be able to finish a game", async function () {
        erc20.approve(rockPaperScissors.address, wagerAmount);
        await rockPaperScissors.createGame(wagerAmount);
        const gameIds = await rockPaperScissors.getGameIds(accounts[0].address);
        await rockPaperScissors.play(gameIds[0], MOVES.PAPER);

        //Check if getGameInfo method does not return the moves before the game has ended
        let gameInfo = await rockPaperScissors.getGameInfo(gameIds[0]);
        expect(gameInfo.player1Move).equal(MOVES.NOT_DEFINED);
        expect(gameInfo.player2Move).equal(MOVES.NOT_DEFINED);

        await erc20_2.approve(rockPaperScissors.address, wagerAmount);
        await rockPaperScissors2.play(gameIds[0], MOVES.ROCK);

        //Check if getGameInfo method does return the moves info now that the game has ended
        gameInfo = await rockPaperScissors.getGameInfo(gameIds[0]);
        expect(gameInfo.player1Move).equal(MOVES.PAPER);
        expect(gameInfo.player2Move).equal(MOVES.ROCK);

        //Player 1 has won, player 2 can not play or withdraw his winnings
        await expect(
            rockPaperScissors2.play(gameIds[0], MOVES.ROCK)
        ).to.be.revertedWith("PLAYER_2_ALREADY_PLAYED");

        await expect(
            rockPaperScissors2.claimRewards(gameIds[0])
        ).to.be.revertedWith("NOTHING_TO_CLAIM");

        //Player 1 can not play anymore but can claims his winnings
        await expect(
            rockPaperScissors.play(gameIds[0], MOVES.ROCK)
        ).to.be.revertedWith("PLAYER_1_ALREADY_PLAYED");

        const balanceBefore = BigNumber.from(
            await erc20.balanceOf(accounts[0].address)
        );
        await rockPaperScissors.claimRewards(gameIds[0]);
        const balanceAfter = BigNumber.from(
            await erc20.balanceOf(accounts[0].address)
        );

        const rewards = balanceAfter.sub(balanceBefore);

        expect(rewards.toString()).to.be.equal(wagerAmountBN.mul(2).toString());
    });

    it("Should be able to delete a game after it's finished", async function () {
        erc20.approve(rockPaperScissors.address, wagerAmount);
        await rockPaperScissors.createGame(wagerAmount);
        const gameIds = await rockPaperScissors.getGameIds(accounts[0].address);
        await rockPaperScissors.play(gameIds[0], MOVES.PAPER);

        await erc20_2.approve(rockPaperScissors.address, wagerAmount);
        await rockPaperScissors2.play(gameIds[0], MOVES.ROCK);

        //Game finished player 2 can not delete the game, only player 1 can
        await expect(
            rockPaperScissors2.deleteGame(gameIds[0])
        ).to.be.revertedWith("NOT_GAME_OWNER");

        //Player 1 can't delete the game before has claimed his winnings
        await expect(
            rockPaperScissors.deleteGame(gameIds[0])
        ).to.be.revertedWith("CANT_DELETE_YET");
        await rockPaperScissors.claimRewards(gameIds[0]);

        //Player 1 can now delete the game
        await rockPaperScissors.deleteGame(gameIds[0]);

        //Check if the game has been deleted
        const newGameIds = await rockPaperScissors.getGameIds(
            accounts[0].address
        );
        expect(newGameIds[0].toString()).to.be.equal("0");
    });

    it("Should be able to claim the funds and delete a game after it has timeout", async function () {
        erc20.approve(rockPaperScissors.address, wagerAmount);
        await rockPaperScissors.createGame(wagerAmount);
        const gameIds = await rockPaperScissors.getGameIds(accounts[0].address);
        await rockPaperScissors.play(gameIds[0], MOVES.PAPER);

        //Try to claim before the timeout
        await expect(
            rockPaperScissors.claimRewards(gameIds[0])
        ).to.be.revertedWith("NO_TIMEOUT_OR_WINNER_YET");

        //Simulate 2 days have passed
        await time.increaseTo((await time.latest()).add(time.duration.days(2)));

        //Now player 1 can claim his funds since no player 2 has made a move in 2 days
        const balanceBefore = BigNumber.from(
            await erc20.balanceOf(accounts[0].address)
        );
        await rockPaperScissors.claimRewards(gameIds[0]);
        const balanceAfter = BigNumber.from(
            await erc20.balanceOf(accounts[0].address)
        );

        const rewards = balanceAfter.sub(balanceBefore);

        expect(rewards.toString()).to.be.equal(wagerAmountBN.toString());
    });
});
