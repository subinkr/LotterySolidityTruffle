// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

//https://docs.chain.link/vrf/v2/subscription/examples/programmatic-subscription

contract LotteryV2 is VRFConsumerBaseV2 {
    address public owner;
    address[] public players;
    uint256 public lotteryId;
    mapping(uint256 => address) public lotteryHistory;
    
    VRFCoordinatorV2Interface COORDINATOR;
    LinkTokenInterface LINKTOKEN;

    // Sepolia coordinator. For other networks,
    // see https://docs.chain.link/docs/vrf-contracts/#configurations
    address vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625;

    // Sepolia LINK token contract. For other networks, see
    // https://docs.chain.link/docs/vrf-contracts/#configurations
    address link_token_contract = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf-contracts/#configurations
    bytes32 keyHash =
        0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    uint32 callbackGasLimit = 1000000;

    uint16 requestConfirmations = 3;

    uint32 numWords = 1;

    uint256[] public s_randomWords;
    uint256 public s_requestId;
    uint64 public s_subscriptionId;

    constructor(uint64 subscriptionId) VRFConsumerBaseV2(vrfCoordinator) {
        owner = msg.sender;
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        LINKTOKEN = LinkTokenInterface(link_token_contract);
        s_subscriptionId = subscriptionId;
    }

    function getBalance() public view returns (uint256) {
        // 현재 contract가 보유한 이더 갯수 return
        return address(this).balance;
    }

    // storage의 players를 memory에 복사해 return
    function getPlayers() public view returns (address[] memory) {
        return players;
    }

    function enter() public payable {
        // msg.sender가 보유한 ether의 양이 0.01이상일 경우만 통과
        require(
            msg.value >= 0.01 ether,
            "msg.value should be greater than or equal to 0.01 ether"
        );
        // contract 배포자를 payable로 변경, players array에 추가
        players.push(payable(msg.sender));
    }

    function _requestRandomWords() internal {
        s_requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
    }

    function fulfillRandomWords(
        uint256,
        uint256[] memory randomWords
    ) internal override {
        s_randomWords = randomWords;
        _prizeWinner();
    }

    function pickWinner() public onlyOwner {
        _requestRandomWords();
    }

    function _prizeWinner() internal {
        uint256 index = s_randomWords[0] % players.length;

        // address payable -> address 저장 가능, 반대는 불가능
        lotteryHistory[lotteryId] = players[index];
        lotteryId++;

        address payable winner = payable(players[index]);
        // players 배열 초기화, (0)은 size를 0으로 지정
        players = new address payable[](0);

        // reentrancy attack 위험(재진입 공격)
        // 재진입으로 인해 상태값이 변경되는 것을 방지하기 위해 상태값을 변경하는 구문은
        // 다른 contract와의 interaction 가능성 있는 함수 실행 전 사용을 끝내야 함

        // players[index]에 현재 contract의 ether를 모두 전송
        // call 외에도 send와 transfer이 있지만 둘 다 소비 gas가 2300으로 고정되어 있음
        // 2019년 12월 operation code의 gas 소비량 증가, 가변적인 call 사용 추천
        (bool success, ) = winner.call{value: address(this).balance}("");
        require(success, "Fail to send ether");
    }


    // Assumes this contract owns link.
    // 1000000000000000000 = 1 LINK
    function topUpSubscription(uint256 amount) external onlyOwner {
        LINKTOKEN.transferAndCall(
            address(COORDINATOR),
            amount,
            abi.encode(s_subscriptionId)
        );
    }

    function addConsumer(address consumerAddress) external onlyOwner {
        // Add a consumer contract to the subscription.
        COORDINATOR.addConsumer(s_subscriptionId, consumerAddress);
    }

    function removeConsumer(address consumerAddress) external onlyOwner {
        // Remove a consumer contract from the subscription.
        COORDINATOR.removeConsumer(s_subscriptionId, consumerAddress);
    }

    function cancelSubscription(address receivingWallet) external onlyOwner {
        // Cancel the subscription and send the remaining LINK to a wallet address.
        COORDINATOR.cancelSubscription(s_subscriptionId, receivingWallet);
        s_subscriptionId = 0;
    }

    // Transfer this contract's funds to an address.
    // 1000000000000000000 = 1 LINK
    function withdraw(uint256 amount, address to) external onlyOwner {
        LINKTOKEN.transfer(to, amount);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "You're not owner");
        _;
    }
}
