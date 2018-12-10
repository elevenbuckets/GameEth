pragma solidity ^0.4.15;

import "./Calculate.sol";
import "./BKDBI.sol";
import "./ERC20.sol";

contract Buckets {
	address public DB; // orderlist and stocklist, and simple struct that records scount, shead, SCOUNT_MAX, and swrap;
	address public bucketToken; // platform token address;
	address public C;
	address public token;
	address public owner;

	struct bucketStats {
        	uint currentPrice;
        	uint nextPrice; // new price from oracle to be updated
        	uint minPerStock;
        	uint ethbalance; // total ether collected from sale to be settled
        	uint extraReward; // additional reward for first closer to update the price get by oracle
        	// these 3 are all in token minimal unit
        	uint tokenSold;
        	uint tokenSettled;
        	uint totalSupply;
	}

	struct closerInfo {
		uint sinceBlock; // when (block number) did the closer signed up for duty
		uint lastSeen; // last time when the closer performs closer duty, initialized with sinceBlock;
		uint canDoClosing; // block number of next closing duty call
		uint nextAssign; // block number of next close period reassignment
		uint doneClosing; // how many times the closer already performed successful closing
		uint signUpToClose; // how many times the closer needs to close 
		uint reward; // in Wei, reset whenever withdrawed
		uint listNo;  // index no. in closerlist
	}

	mapping (uint => bucketStats) internal marketlist;
	mapping (address => closerInfo) internal closerQueue;
	mapping (uint => address) internal closerlist;
	mapping (address => bool) internal isStaff; 

	bool locked;
	bool public paused;

	uint public tokendecimals;
        uint public atoken;

	uint public makerfee = 1000000000000000;
	uint public priceUpdateReward;
	uint public exchangefee;
	uint public decimals = 18;
        uint public precisions = 10 ** decimals;

	uint public futureBlockCovered;
	uint public closerCount;
	uint public maxCloserCount = 100;
	uint public closerRewards = 0;
	uint public dutyStake = 2000000000000; // 20000 BUCK tokens holding to become closer;
	uint public buckDecimals = 8;
	uint public salePeriod;
	uint public periodEnds;

        uint public takerRate;
        uint public exchangeRate;
        uint public rewardRate;

	// modifiers
        modifier OwnerOnly() {
                require(msg.sender == owner);
                _;
        }

        modifier feePaid() {
                require(msg.value == makerfee);
                _;
        }

        modifier notPaused() {
                require(paused == false);
                _;
        }

        modifier isPaused() {
                require(paused == true);
                _;
        }

        modifier NoReentrancy() {
                require(locked == false);

                locked = true;
                _;
                locked = false;
        }

	// constructor
        function Buckets() {
                owner = msg.sender;
                salePeriod = 20;
                periodEnds = block.number + 5;
                paused = true;
		isStaff[owner] = true;
        }

	function setupToken(address tokenTrade, uint tokenunit) OwnerOnly returns (bool) {
                require(token == address(0));

                token = tokenTrade;
                tokendecimals = tokenunit;
                atoken = 10 ** tokendecimals;

                return true;
        }

	function setupPlatform(address stakeToken, address dbi, address calculate) OwnerOnly returns (bool) {
		bucketToken = stakeToken;
                C = calculate;
		DB = dbi;

                // fee rates for Takers: 0.3%, in which: 0.25% goes to exchange, and 0.05% goes to oracle reward
                takerRate   = SafeCal(C).add(SafeCal(C).percent(3, 1000, decimals), precisions);
                exchangeRate = SafeCal(C).percent(25, 30, decimals);
                rewardRate  = SafeCal(C).percent(5, 30, decimals);

		return true;
	}

	// constant functions
	function marketSummary(uint bucketNo) public constant returns(uint, uint, uint, uint, uint) {
                require(bucketNo >= 1 && bucketNo <= 11);
                return ( marketlist[bucketNo].tokenSold,
                         marketlist[bucketNo].tokenSettled,
                         marketlist[bucketNo].totalSupply,
                         marketlist[bucketNo].currentPrice,
                         marketlist[bucketNo].minPerStock);
        }

        function marketFinance(uint bucketNo) public constant returns(uint, uint) {
                require(bucketNo >= 1 && bucketNo <= 11);
                return ( marketlist[bucketNo].ethbalance, marketlist[bucketNo].extraReward );
        }

        function tokenSupply(uint bucketNo) public constant returns(uint) {
                require(bucketNo >= 0 && bucketNo <= 11); // '0' is for sum of all 11 buckets total supply

                if (bucketNo == 0) {
                        return ERC20(token).balanceOf(this);
                } else {
                        return marketlist[bucketNo].totalSupply;
                }
        }

	function handleRefund(uint refund) private returns(bool) {
		if (refund <= 0) {
			return true;
		} else if (msg.sender.send(refund)) {
	                return true;
	        } else {
	                return false;
	        }
	}
	
	function withdraw(uint amount) private returns(bool) {
                require(amount > 0);
                require(ERC20(token).balanceOf(this) >= amount);
                require(ERC20(token).transfer(msg.sender, amount));

                return true;
        }

	function rotate(uint times) private returns(bool) {
		if (closerQueue[msg.sender].sinceBlock == 0 && times >= 10) {
			closerCount += 1;
			closerlist[closerCount] = msg.sender;
			closerQueue[msg.sender].sinceBlock = block.number;
			closerQueue[msg.sender].signUpToClose = times;
			closerQueue[msg.sender].doneClosing = 0;
			closerQueue[msg.sender].reward = 0;
		}

		closerQueue[msg.sender].lastSeen = block.number;

		if (closerCount == 1 || futureBlockCovered <= block.number) {
			closerQueue[msg.sender].canDoClosing = block.number + 1;
			futureBlockCovered = block.number + salePeriod;
		} else if (futureBlockCovered > block.number) {
			closerQueue[msg.sender].canDoClosing = futureBlockCovered + 1;
			futureBlockCovered += salePeriod;
		}

		closerQueue[msg.sender].nextAssign = futureBlockCovered;

		return true;
	}

	function dismiss() private returns(bool) {
		// when the cancelled closer not the last one, replace its spot with last closer
		// so that closerlist remains an array without holes.
		if (closerQueue[msg.sender].listNo < closerCount) {
			closerQueue[closerlist[closerCount]].listNo = closerQueue[msg.sender].listNo;
			closerlist[closerQueue[msg.sender].listNo] = closerlist[closerCount];
		}	
		delete closerQueue[msg.sender];
		closerCount -= 1;

		return true;
	}

	function closerDuty(uint times) NoReentrancy returns (bool) {
		require(times >= 10);
		require(closerQueue[msg.sender].sinceBlock == 0);
		require(closerCount <= maxCloserCount);
	
		uint bucks = times * (10 ** buckDecimals);
	
		require(ERC20(bucketToken).balanceOf(msg.sender) >= dutyStake + bucks);
	
		if (ERC20(bucketToken).transferFrom(msg.sender, this, bucks) && rotate(times)) {
			return true;
		} else {
			revert();
		}
	}

	function closerStat() constant returns (uint, uint, uint, uint, uint, uint, uint) {
		return (
			closerQueue[msg.sender].sinceBlock,
			closerQueue[msg.sender].lastSeen,
			closerQueue[msg.sender].canDoClosing,
			closerQueue[msg.sender].signUpToClose,
			closerQueue[msg.sender].doneClosing,
			closerQueue[msg.sender].reward, 
			closerQueue[msg.sender].nextAssign );
	}
	
	function cancelDuty() NoReentrancy returns (bool) {
		require(closerQueue[msg.sender].sinceBlock != 0);
		uint bucks;
	        uint fee;	
		uint reward = closerQueue[msg.sender].reward;
	
		if (closerQueue[msg.sender].doneClosing >= closerQueue[msg.sender].signUpToClose) {
			bucks = closerQueue[msg.sender].signUpToClose * (10 ** buckDecimals);
		} else {
			bucks = closerQueue[msg.sender].doneClosing * (10 ** buckDecimals);
			fee   = (closerQueue[msg.sender].signUpToClose - closerQueue[msg.sender].doneClosing) * (10 ** buckDecimals);
		}

		if (fee > 0) {
			if (!ERC20(bucketToken).transfer(owner, fee)) revert();
		}

		closerRewards -= reward;

		if (dismiss() && handleRefund(reward) && ERC20(bucketToken).transfer(msg.sender, bucks)) {
			return true;
		} else {
			revert();
		}
	}

	function addStaff(address employee) OwnerOnly returns (bool) {
		isStaff[employee] = true;

		return true;
	}

	function activeStaff(address employee) constant returns (bool) {
		return isStaff[employee];
	}
/*
	// how does owner get closer address?
	function kickCloser(address closer) OwnerOnly returns (bool) {
		require(block.number - closerQueue[closer].lastSeen > 60);
		// withdraw reward and Bucks for ourselves to punish closer for holding the closer queue spot!!!
	}	
*/
	
	function cancelStock(uint bucketNo) payable notPaused feePaid NoReentrancy returns (bool) {
		require(bucketNo >= 1 && bucketNo <= 11);

		require(BKDBI(DB).isSeller(bucketNo, msg.sender) == true);
		require(BKDBI(DB).isCancelled(bucketNo, msg.sender) == false);
	
	        marketlist[bucketNo].ethbalance += makerfee;

		uint unsettled = marketlist[bucketNo].tokenSold - marketlist[bucketNo].tokenSettled;
		uint delist = BKDBI(DB).getStock(bucketNo, msg.sender);
		uint partsold = 0;
	
		if ( unsettled == 0 && BKDBI(DB).isHot(bucketNo, msg.sender) == true ){
	                partsold = BKDBI(DB).getEarnings(bucketNo, msg.sender);
	                marketlist[bucketNo].ethbalance -= partsold;
		} else if (marketlist[bucketNo].totalSupply >= (delist + unsettled)) {
			partsold = 0;
		} else if (unsettled > 0) {
			revert();
		}
	
		marketlist[bucketNo].totalSupply -= delist;
	
		if (BKDBI(DB).doCancel(bucketNo, msg.sender) && handleRefund(partsold) && withdraw(delist)) {
			return true;
		} else {
			revert();
		} 
	}
	
	function closing(uint bucketNo, uint slots) notPaused NoReentrancy returns (bool) {
		require(slots > 0);
	        require(bucketNo >= 1 && bucketNo <= 11);
		require(ERC20(bucketToken).balanceOf(msg.sender) >= dutyStake);
		require(closerQueue[msg.sender].sinceBlock > 0 || isStaff[msg.sender] == true);
		require(closerQueue[msg.sender].signUpToClose >= 10 || isStaff[msg.sender] == true);

		// closer queue related managements
		if ( isStaff[msg.sender] != true && closerQueue[msg.sender].doneClosing >= closerQueue[msg.sender].signUpToClose ) {
			uint pay   = closerQueue[msg.sender].reward;
			uint bucks = closerQueue[msg.sender].signUpToClose * (10 ** buckDecimals);
			closerRewards -= pay;

			if (dismiss() && handleRefund(pay) && ERC20(bucketToken).transfer(msg.sender, bucks)) {
				return true;
			} else {
				revert();
			}
		} else if ( isStaff[msg.sender] != true && closerQueue[msg.sender].nextAssign < block.number ) {
			// here we call rotate() with its argument enquals 0.
			// since function closing() is only callable by already enrolled closer
			return rotate(0);
		}

		require(closerQueue[msg.sender].canDoClosing <= block.number || isStaff[msg.sender] == true);
	
		uint unsettled = marketlist[bucketNo].tokenSold - marketlist[bucketNo].tokenSettled;
	
	        require(unsettled > 0 || marketlist[bucketNo].totalSupply == 0 || ( unsettled == 0 && block.number > periodEnds ));
	        require(unsettled * marketlist[bucketNo].currentPrice <= marketlist[bucketNo].ethbalance);

	        uint reward = 0;
		bool done = false;
	
		// function closer(uint bucketNo, uint slots, uint unsettled, uint makerfee, uint unitprice) returns (bool done, uint reward, uint unsettled);
		(done, reward, unsettled) = BKDBI(DB).closer(bucketNo, slots, unsettled, makerfee, marketlist[bucketNo].currentPrice);
	
		assert(done == true);
		require(reward > 0 || (block.number > periodEnds && unsettled == 0));
	        marketlist[bucketNo].tokenSettled = marketlist[bucketNo].tokenSold - unsettled;
	        marketlist[bucketNo].ethbalance -= reward;
	
	        if (marketlist[bucketNo].tokenSold == marketlist[bucketNo].tokenSettled) {
	                // pause and call oracle, and claim 90% of priceUpdateReward. Update currentPrice of this bucket (bucketNo)
	                if ( block.number > periodEnds ) {
	                        paused = true;
	                        reward += SafeCal(C).ratio(SafeCal(C).percent(9, 10, decimals), precisions, priceUpdateReward); // not part of bucket ethblance
	                        priceUpdateReward = SafeCal(C).ratio(SafeCal(C).percent(1, 10, decimals), precisions, priceUpdateReward);
	                        marketlist[bucketNo].extraReward = 0;
	                } else if ( block.number <= periodEnds && marketlist[bucketNo].nextPrice > 0 ) {
	                        marketlist[bucketNo].tokenSold = 0;
	                        marketlist[bucketNo].tokenSettled = 0;
	                        marketlist[bucketNo].currentPrice = marketlist[bucketNo].nextPrice;
	                        marketlist[bucketNo].minPerStock = uint(1000000000000000000) / marketlist[bucketNo].currentPrice;
	                        marketlist[bucketNo].nextPrice = 0;
	                        reward += marketlist[bucketNo].extraReward; // *is* part of bucket ethblance
	                        marketlist[bucketNo].ethbalance -= marketlist[bucketNo].extraReward;
	                        marketlist[bucketNo].extraReward = 0;
	                }
	        }
	
		if (isStaff[msg.sender] == true) {
			exchangefee += reward;
		} else {
	        	closerQueue[msg.sender].reward += reward;
	        	closerQueue[msg.sender].doneClosing += 1;
	        	closerQueue[msg.sender].lastSeen = block.number;
			closerRewards += reward;
		}
	
	        return true;
	}
	
	function depositStock(uint bucketNo, uint amount) notPaused NoReentrancy returns (bool) {
		require(amount >= marketlist[bucketNo].minPerStock);
	        require(bucketNo >= 1 && bucketNo <= 11);
		require(BKDBI(DB).isSeller(bucketNo, msg.sender) == false);
	
		if (ERC20(token).transferFrom(msg.sender, this, amount) && BKDBI(DB).createList(bucketNo, msg.sender, amount)) {
	               	marketlist[bucketNo].totalSupply += amount;
	        } else {
	                revert();
	        }
	
	        return true;
	}
	
	function payOut(uint bucketNo) NoReentrancy returns(bool) {
	        require(bucketNo >= 1 && bucketNo <= 11);
	
		bool done = false;
		uint value = 0;
	
		(done, value) = BKDBI(DB).canPayOut(bucketNo, msg.sender);
	
		assert(done == true);
	
	        marketlist[bucketNo].ethbalance -= value;
	
	        if (BKDBI(DB).deleteList(bucketNo, msg.sender) && msg.sender.send(value)) {
	                return true;
	        } else {
	                revert();
	        }
	}

	function buyStock(uint bucketNo) payable notPaused NoReentrancy returns (bool) {
                require(bucketNo >= 1 && bucketNo <= 11);
                require(msg.value > 10000000000);
                require(msg.sender != address(0));

                // taking fee out of msg.value before calculation
                // fee rates for Takers: 0.3%, 
                // in which: 0.25% goes to exchange, and 0.05% goes to oracle reward

                uint purchaseValue = SafeCal(C).percent(msg.value, takerRate, decimals);
                uint tips = purchaseValue % marketlist[bucketNo].currentPrice;
                uint amount = (purchaseValue - tips) / marketlist[bucketNo].currentPrice;

                require(amount >= 1);

                if (marketlist[bucketNo].totalSupply < amount) revert();

                // depositing fee
                priceUpdateReward = SafeCal(C).add(priceUpdateReward, SafeCal(C).ratio(rewardRate, precisions, (msg.value - purchaseValue))); // 0.05% oracle reward
                exchangefee = SafeCal(C).add(exchangefee, SafeCal(C).ratio(exchangeRate, precisions, (msg.value - purchaseValue))); // 0.25% exchange fee
                exchangefee += tips;

                marketlist[bucketNo].tokenSold = SafeCal(C).add(marketlist[bucketNo].tokenSold, amount);
                marketlist[bucketNo].ethbalance = SafeCal(C).add(marketlist[bucketNo].ethbalance, (purchaseValue - tips));
                marketlist[bucketNo].totalSupply = SafeCal(C).sub(marketlist[bucketNo].totalSupply, amount);

                if (withdraw(amount)) {
                        return true;
                } else {
                        revert();
                }
        }

	function changePrice(uint newPrice) isPaused OwnerOnly NoReentrancy returns (bool) {
                assert(block.number > periodEnds);
                assert(newPrice > 0);

                for (uint i = 1; i<= 11; i++) {
                        if (marketlist[i].tokenSold == marketlist[i].tokenSettled) {
                                 // in wei. Represending the price of the minial unit of the token
                                marketlist[i].currentPrice = newPrice * (uint(95) + uint(i-1)) / uint(100);
                                marketlist[i].nextPrice = 0;
                                marketlist[i].minPerStock = uint(1000000000000000000) / marketlist[i].currentPrice;
                                marketlist[i].tokenSold = 0;
                                marketlist[i].tokenSettled = 0;
                                continue;
                        } else if (marketlist[i].tokenSold != marketlist[i].tokenSettled) {
                                // in wei. Represending the price of the minial unit of the token
                                marketlist[i].nextPrice = newPrice * (uint(95) + uint(i-1)) / uint(100);
                                marketlist[i].extraReward = SafeCal(C).ratio(SafeCal(C).percent(1, 10, decimals), precisions, priceUpdateReward);
                                priceUpdateReward -= marketlist[i].extraReward;
                                marketlist[i].ethbalance += marketlist[i].extraReward;
                        }
                }

                exchangefee = SafeCal(C).add(exchangefee, priceUpdateReward);
                priceUpdateReward = 0;
                periodEnds = block.number + salePeriod;
                paused = false;

                return true;
        }

	function withdrawExchangeFee() OwnerOnly NoReentrancy returns (bool) {
                require(exchangefee > 0);
                uint takeout = exchangefee;
                exchangefee = 0;

                if (!msg.sender.send(takeout)) {
                        revert();
                }
        }
}
