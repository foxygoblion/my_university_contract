// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CourseCertificate.sol";

/**
 * @title AutomatedCourseOracle
 * @notice 自动执行的课程进度验证预言机合约
 * @dev 结合了 Chainlink Oracle 和 Automation (Keeper) 功能
 */
contract AutomatedCourseOracle is
    ChainlinkClient,
    AutomationCompatibleInterface,
    Ownable
{
    using Chainlink for Chainlink.Request;

    // Chainlink 相关变量
    address private oracle; // 预言机地址
    bytes32 private jobId; // 预言机工作ID
    uint256 private fee; // 预言机调用费用

    // 自动化相关变量
    uint256 public lastCheckTime; // 上次检查时间
    uint256 public checkInterval; // 检查间隔（秒）
    bool public automationEnabled; // 自动检查开关

    // 证书合约实例
    CourseCertificate public certificateNFT;

    // 进度跟踪结构体
    struct ProgressCheck {
        address student; // 学生地址
        string courseId; // 课程ID
        uint256 lastCheck; // 上次检查时间
        bool completed; // 是否完成
        bool exists; // 是否存在
    }

    // 存储所有需要检查的进度
    mapping(bytes32 => ProgressCheck) public progressChecks;
    // 存储所有活跃的检查请求ID
    bytes32[] public activeChecks;

    // 事件声明
    event ProgressCheckRequested(
        bytes32 indexed requestId,
        address student,
        string courseId
    );
    event ProgressCheckCompleted(bytes32 indexed requestId, bool completed);
    event AutomationStatusChanged(bool enabled);
    event CheckIntervalUpdated(uint256 newInterval);

    /**
     * @notice 构造函数
     * @param _link Chainlink代币地址
     * @param _oracle 预言机地址
     * @param _jobId 工作ID
     * @param _certificateAddress NFT证书合约地址
     */
    constructor(
        address _link,
        address _oracle,
        bytes32 _jobId,
        address _certificateAddress
    ) {
        setChainlinkToken(_link);
        oracle = _oracle;
        jobId = _jobId;
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0.1 LINK

        certificateNFT = CourseCertificate(_certificateAddress);
        checkInterval = 12 hours; // 默认12小时检查一次
        lastCheckTime = block.timestamp;
        automationEnabled = true;
    }

    /**
     * @notice 添加新的进度检查请求
     * @param student 学生地址
     * @param courseId 课程ID
     */
    function addProgressCheck(
        address student,
        string memory courseId
    ) external onlyOwner {
        bytes32 requestId = keccak256(
            abi.encodePacked(student, courseId, block.timestamp)
        );

        progressChecks[requestId] = ProgressCheck({
            student: student,
            courseId: courseId,
            lastCheck: block.timestamp,
            completed: false,
            exists: true
        });

        activeChecks.push(requestId);
        emit ProgressCheckRequested(requestId, student, courseId);
    }

    /**
     * @notice Chainlink Automation检查函数
     * @return upkeepNeeded 是否需要执行upkeep
     * @return performData 执行数据
     */
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // 检查是否启用自动化且是否到达检查时间
        upkeepNeeded =
            automationEnabled &&
            (block.timestamp - lastCheckTime) >= checkInterval &&
            activeChecks.length > 0;

        // 返回需要检查的请求数量
        performData = abi.encode(activeChecks.length);

        return (upkeepNeeded, performData);
    }

    /**
     * @notice Chainlink Automation执行函数
     * @param performData 执行数据
     */
    function performUpkeep(bytes calldata performData) external override {
        lastCheckTime = block.timestamp;

        // 遍历所有活跃的检查请求
        for (uint i = 0; i < activeChecks.length; i++) {
            bytes32 requestId = activeChecks[i];
            ProgressCheck memory check = progressChecks[requestId];

            if (!check.completed) {
                requestProgressUpdate(requestId);
            }
        }
    }

    /**
     * @notice 请求更新进度
     * @param requestId 请求ID
     */
    function requestProgressUpdate(bytes32 requestId) internal {
        ProgressCheck memory check = progressChecks[requestId];

        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillProgressCheck.selector
        );

        // 设置API调用参数
        string memory url = string(
            abi.encodePacked(
                "https://api.yideng.com/progress/",
                check.courseId,
                "/",
                Strings.toHexString(uint160(check.student), 20)
            )
        );

        req.add("get", url);
        req.add("path", "completed");

        sendChainlinkRequest(req, fee);
    }

    /**
     * @notice 预言机回调函数
     * @param _requestId 请求ID
     * @param _completed 是否完成
     */
    function fulfillProgressCheck(
        bytes32 _requestId,
        bool _completed
    ) public recordChainlinkFulfillment(_requestId) {
        ProgressCheck storage check = progressChecks[_requestId];

        if (_completed && !check.completed) {
            check.completed = true;
            // 铸造NFT证书
            certificateNFT.mintCertificate(
                check.student,
                check.courseId,
                generateCertificateURI(check.student, check.courseId)
            );

            // 从活跃检查列表中移除
            removeActiveCheck(_requestId);
        }

        emit ProgressCheckCompleted(_requestId, _completed);
    }

    /**
     * @notice 从活跃检查列表中移除请求
     * @param requestId 请求ID
     */
    function removeActiveCheck(bytes32 requestId) internal {
        for (uint i = 0; i < activeChecks.length; i++) {
            if (activeChecks[i] == requestId) {
                activeChecks[i] = activeChecks[activeChecks.length - 1];
                activeChecks.pop();
                break;
            }
        }
    }

    /**
     * @notice 生成证书URI
     * @param student 学生地址
     * @param courseId 课程ID
     */
    function generateCertificateURI(
        address student,
        string memory courseId
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "https://api.yideng.com/certificate/",
                    courseId,
                    "/",
                    Strings.toHexString(uint160(student), 20)
                )
            );
    }

    /**
     * @notice 设置检查间隔
     * @param _interval 新的间隔时间（秒）
     */
    function setCheckInterval(uint256 _interval) external onlyOwner {
        require(_interval >= 1 hours, "Interval too short");
        checkInterval = _interval;
        emit CheckIntervalUpdated(_interval);
    }

    /**
     * @notice 设置自动化状态
     * @param _enabled 是否启用
     */
    function setAutomationEnabled(bool _enabled) external onlyOwner {
        automationEnabled = _enabled;
        emit AutomationStatusChanged(_enabled);
    }

    /**
     * @notice 提取LINK代币
     */
    function withdrawLink() external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    // 接收ETH
    receive() external payable {}
}
