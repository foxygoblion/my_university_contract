// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./YiDengToken.sol";
import "./CourseCertificate.sol";

contract CourseReward is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TEACHER_ROLE = keccak256("TEACHER_ROLE");

    YiDengToken public token;
    CourseCertificate public certificate;

    struct Reward {
        uint256 amount;
        uint256 deadline;
        bool claimed;
    }

    mapping(string => mapping(address => Reward)) public rewards;
    mapping(string => uint256) public courseRewards;

    event RewardSet(string indexed web2CourseId, uint256 amount);
    event RewardClaimed(string indexed web2CourseId, address indexed student, uint256 amount);

    constructor(address _token, address _certificate) {
        token = YiDengToken(_token);
        certificate = CourseCertificate(_certificate);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function setCourseReward(
        string calldata web2CourseId,
        uint256 amount,
        uint256 deadline
    ) external onlyRole(TEACHER_ROLE) {
        require(amount > 0, "Amount must be greater than 0");
        require(deadline > block.timestamp, "Deadline must be in the future");

        courseRewards[web2CourseId] = amount;
        emit RewardSet(web2CourseId, amount);
    }

    function claimReward(string calldata web2CourseId) external nonReentrant {
        require(certificate.hasCertificate(msg.sender, web2CourseId), "No certificate found");
        require(!rewards[web2CourseId][msg.sender].claimed, "Reward already claimed");
        require(
            rewards[web2CourseId][msg.sender].deadline > block.timestamp,
            "Reward deadline passed"
        );

        uint256 amount = courseRewards[web2CourseId];
        require(amount > 0, "No reward available");

        rewards[web2CourseId][msg.sender].claimed = true;
        rewards[web2CourseId][msg.sender].amount = amount;

        require(token.transfer(msg.sender, amount), "Transfer failed");
        emit RewardClaimed(web2CourseId, msg.sender, amount);
    }

    function getRewardInfo(
        string calldata web2CourseId,
        address student
    ) external view returns (uint256 amount, uint256 deadline, bool claimed) {
        Reward memory reward = rewards[web2CourseId][student];
        return (reward.amount, reward.deadline, reward.claimed);
    }

    function getCourseReward(string calldata web2CourseId) external view returns (uint256) {
        return courseRewards[web2CourseId];
    }
} 