pragma solidity ^0.4.15;

import "./BKDBI.sol";

contract BucketDB is BKDBI {
	uint constant SCOUNT_MAX = 25;
	
	struct dbIndex {
		uint scount;
		uint shead;
		uint swrap;
	}
	
	struct balance {
	        address seller;
	        uint stock;
	        uint sold;
	        uint earnings;
	}
	
	struct bookings {
	        address seller;
	        bool owe;
	        bool canceled;
	        uint listnum;
	        bool hotseat;
	}
	
	mapping (uint => dbIndex) internal bucketIndex; 
	mapping (uint => mapping (address => bookings)) internal orderlist;
	mapping (uint => mapping (uint => balance)) internal stocklist; 
	
	// constructor
	function BucketDB(address exAddr) {
		exchange = exAddr;
		admin = msg.sender;
	}

	// public read functions intended for everyone
	function sellerStat(uint bucketNo) constant returns(uint, uint, uint, uint, bool, bool, bool) {
                require(orderlist[bucketNo][msg.sender].seller == msg.sender);
                require(stocklist[bucketNo][orderlist[bucketNo][msg.sender].listnum].seller == msg.sender);
                require(bucketNo >= 1 && bucketNo <= 11);

                return (orderlist[bucketNo][msg.sender].listnum,
                        stocklist[bucketNo][orderlist[bucketNo][msg.sender].listnum].stock,
                        stocklist[bucketNo][orderlist[bucketNo][msg.sender].listnum].sold,
                        stocklist[bucketNo][orderlist[bucketNo][msg.sender].listnum].earnings,
                        orderlist[bucketNo][msg.sender].canceled,
                        orderlist[bucketNo][msg.sender].owe,
                        orderlist[bucketNo][msg.sender].hotseat);
        }	

	function browseStock(uint bucketNo, uint start, uint end) constant returns (bytes32[3][] results) {
                require(end >= 0);
                require(start >= 0);
                require(end >= start);
                require(bucketNo >= 1 && bucketNo <= 11);

                assert(bucketIndex[bucketNo].scount != 0 );
                uint length;
                uint i;

                if (bucketIndex[bucketNo].shead > start) start = bucketIndex[bucketNo].shead;
                if (end + 1 > bucketIndex[bucketNo].scount ) end = bucketIndex[bucketNo].scount - 1;

                length = end - start + 1;

                if ( bucketIndex[bucketNo].scount == SCOUNT_MAX && bucketIndex[bucketNo].swrap > 0) {
                        length = SCOUNT_MAX - start + bucketIndex[bucketNo].swrap;
                }

                results = new bytes32[3][](length);
                for (i = start; i <= end; i++) {
                        results[i-start][0] = bytes32(i);
                        results[i-start][1] = bytes32(stocklist[bucketNo][i].seller);
                        results[i-start][2] = bytes32(stocklist[bucketNo][i].stock);
                }

                if ( bucketIndex[bucketNo].scount == SCOUNT_MAX && bucketIndex[bucketNo].swrap > 0 ) {
                        for (i = 1; i <= bucketIndex[bucketNo].swrap; i++) {
                                results[i+end-start][0] = bytes32(i+end);
                                results[i+end-start][1] = bytes32(stocklist[bucketNo][i-1].seller);
                                results[i+end-start][2] = bytes32(stocklist[bucketNo][i-1].stock);
                        }
                }

                return results;
        }	

	function bucketLimits(uint bucketNo) constant returns (uint, uint, uint, uint) {
                require(bucketNo >= 1 && bucketNo <= 11);
                return (SCOUNT_MAX, bucketIndex[bucketNo].scount, bucketIndex[bucketNo].swrap, bucketIndex[bucketNo].shead);
        }

	// public read function used in exchange ops. as a result, dedicated argument 'maker' address is needed, instead of just use msg.sender
	function isSeller(uint bucketNo, address maker) constant returns (bool) {
                require(bucketNo >= 1 && bucketNo <= 11);
		if (orderlist[bucketNo][maker].seller == maker && stocklist[bucketNo][orderlist[bucketNo][maker].listnum].seller == maker) {
			return true;
		} else {
			return false;
		}
	}

	function isCancelled(uint bucketNo, address maker) constant returns (bool) {
                require(bucketNo >= 1 && bucketNo <= 11);
		require(isSeller(bucketNo, maker) == true);

		return orderlist[bucketNo][maker].canceled;
	}

	function isHot(uint bucketNo, address maker) constant returns (bool) {
                require(bucketNo >= 1 && bucketNo <= 11);
		require(isSeller(bucketNo, maker) == true);

		return orderlist[bucketNo][maker].hotseat;
	}

	function getStock(uint bucketNo, address maker) constant returns (uint) {
                require(bucketNo >= 1 && bucketNo <= 11);
		require(isSeller(bucketNo, maker) == true);
	
		return stocklist[bucketNo][orderlist[bucketNo][maker].listnum].stock;	
	}

	function getEarnings(uint bucketNo, address maker) constant returns (uint) {
                require(bucketNo >= 1 && bucketNo <= 11);
		require(isSeller(bucketNo, maker) == true);
	
		return stocklist[bucketNo][orderlist[bucketNo][maker].listnum].earnings;	
	}

	function canPayOut(uint bucketNo, address maker) constant returns (bool, uint) {
                require(bucketNo >= 1 && bucketNo <= 11);
		require(stocklist[bucketNo][orderlist[bucketNo][maker].listnum].stock == 0);
	        require(stocklist[bucketNo][orderlist[bucketNo][maker].listnum].sold > 0);
	        require(orderlist[bucketNo][maker].owe == true);
	
	        assert(stocklist[bucketNo][orderlist[bucketNo][maker].listnum].earnings > 0);
	        assert(orderlist[bucketNo][maker].seller == maker);
	        assert(orderlist[bucketNo][maker].seller == stocklist[bucketNo][orderlist[bucketNo][maker].listnum].seller);
	
		return (true, stocklist[bucketNo][orderlist[bucketNo][maker].listnum].earnings);
	}

	// exchange only functions	
	function doCancel(uint bucketNo, address maker) returns (bool) {
		require(msg.sender == exchange);
                require(bucketNo >= 1 && bucketNo <= 11);
		require(isSeller(bucketNo, maker) == true);

		uint delist = stocklist[bucketNo][orderlist[bucketNo][maker].listnum].stock;
		stocklist[bucketNo][orderlist[bucketNo][maker].listnum].stock = 0;
		stocklist[bucketNo][orderlist[bucketNo][maker].listnum].sold = 0;
		stocklist[bucketNo][orderlist[bucketNo][maker].listnum].earnings = 0;

		orderlist[bucketNo][maker].canceled = true;
		
		return true;
	}

	function deleteList(uint bucketNo, address maker) returns (bool) {
		require(msg.sender == exchange);
                require(bucketNo >= 1 && bucketNo <= 11);
		require(isSeller(bucketNo, maker) == true);
	
		delete stocklist[bucketNo][orderlist[bucketNo][maker].listnum];
		delete orderlist[bucketNo][maker];
	
		return true;
	}
	
	function closer(uint bucketNo, uint slots, uint unsettled, uint makerfee, uint unitprice) returns (bool, uint, uint) {
		require(msg.sender == exchange);
                require(bucketNo >= 1 && bucketNo <= 11);
	
		uint reward = 0;
	
		require(bucketIndex[bucketNo].shead + slots <= bucketIndex[bucketNo].scount);
	
		uint tshead = bucketIndex[bucketNo].shead;
	
		for (uint i = bucketIndex[bucketNo].shead; i <= bucketIndex[bucketNo].shead + slots; i++) {
	                if (stocklist[bucketNo][i].stock == 0 && orderlist[bucketNo][stocklist[bucketNo][i].seller].canceled == true) {
	                        reward += makerfee;
	                        if (orderlist[bucketNo][stocklist[bucketNo][i].seller].hotseat == true) tshead += 1;
	
	                        delete orderlist[bucketNo][stocklist[bucketNo][i].seller];
	                        delete stocklist[bucketNo][i];
	
	                        if (tshead == SCOUNT_MAX || i == SCOUNT_MAX - 1) break;
	
	                        continue;
	                }
	
	                if (unsettled > 0 && unsettled < stocklist[bucketNo][i].stock) {
	                        stocklist[bucketNo][i].stock -= unsettled;
	                        stocklist[bucketNo][i].sold += unsettled;
	
	                        unsettled = 0;
	                        orderlist[bucketNo][stocklist[bucketNo][i].seller].hotseat = true;
	
	                        stocklist[bucketNo][i].earnings += stocklist[bucketNo][i].sold * unitprice;
	                        break;
	                } else if (unsettled > 0 && unsettled >= stocklist[bucketNo][i].stock) {
	                        reward += makerfee;
	
	                        unsettled -= stocklist[bucketNo][i].stock;
	                        stocklist[bucketNo][i].sold += stocklist[bucketNo][i].stock;
	                        stocklist[bucketNo][i].earnings += stocklist[bucketNo][i].stock * unitprice - makerfee;
	                        orderlist[bucketNo][stocklist[bucketNo][i].seller].owe = true;
	                        stocklist[bucketNo][i].stock = 0;
	                        tshead += 1;
	                }
	
	                if (tshead == SCOUNT_MAX || i == SCOUNT_MAX - 1) break;
		}
	
		bucketIndex[bucketNo].shead = tshead;
	
		if (bucketIndex[bucketNo].shead == SCOUNT_MAX) {
			bucketIndex[bucketNo].shead = 0;
			bucketIndex[bucketNo].scount = bucketIndex[bucketNo].swrap;
			bucketIndex[bucketNo].swrap = 0;
		} 
	
		return (true, reward, unsettled);
	}
	
	function createList(uint bucketNo, address maker, uint amount) returns (bool) {
		require(msg.sender == exchange);
                require(bucketNo >= 1 && bucketNo <= 11);
		require(isSeller(bucketNo, maker) == false);
	
		orderlist[bucketNo][maker].owe = false;
	        orderlist[bucketNo][maker].canceled = false;
	        orderlist[bucketNo][maker].seller = maker;
	
		if(bucketIndex[bucketNo].scount == SCOUNT_MAX) {
			if (bucketIndex[bucketNo].shead > bucketIndex[bucketNo].swrap && stocklist[bucketNo][bucketIndex[bucketNo].swrap].seller == address(0)) {
				stocklist[bucketNo][bucketIndex[bucketNo].swrap].seller = maker;
	                        stocklist[bucketNo][bucketIndex[bucketNo].swrap].stock  = amount;
	                        stocklist[bucketNo][bucketIndex[bucketNo].swrap].sold   = 0;
	                        stocklist[bucketNo][bucketIndex[bucketNo].swrap].earnings  = 0;
	
	                        orderlist[bucketNo][maker].listnum = bucketIndex[bucketNo].swrap;
				bucketIndex[bucketNo].swrap += 1;
			} else {
				revert();
			}
		} else {
			stocklist[bucketNo][bucketIndex[bucketNo].scount].seller = maker;
	                stocklist[bucketNo][bucketIndex[bucketNo].scount].stock  = amount;
	                stocklist[bucketNo][bucketIndex[bucketNo].scount].sold   = 0;
	                stocklist[bucketNo][bucketIndex[bucketNo].scount].earnings  = 0;
	
	                orderlist[bucketNo][maker].listnum = bucketIndex[bucketNo].scount;
	                bucketIndex[bucketNo].scount += 1;
		}

		return true;
	}
}
