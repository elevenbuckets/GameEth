pragma solidity ^0.4.15;

contract BKDBI {
	address public exchange;
        address public admin;
	function isSeller(uint bucketNo, address maker) constant returns (bool);
	function isCancelled(uint bucketNo, address maker) constant returns (bool);
	function isHot(uint bucketNo, address maker) constant returns (bool);
	function getStock(uint bucketNo, address maker) constant returns (uint);
	function getEarnings(uint bucketNo, address maker) constant returns (uint);
	function canPayOut(uint bucketNo, address maker) constant returns (bool answer, uint value);
	function doCancel(uint bucketNo, address maker) returns (bool);
	function deleteList(uint bucketNo, address maker) returns (bool);
	function closer(uint bucketNo, uint slots, uint unsettled, uint makerfee, uint unitprice) returns (bool, uint, uint);
	function createList(uint bucketNo, address maker, uint amount) returns (bool);
}
