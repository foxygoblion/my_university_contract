// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./YiDengToken.sol";
import "./CourseCertificate.sol";

/**
 * @title CourseMarket
 * @notice 一灯教育课程市场合约
 */
contract CourseMarket is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TEACHER_ROLE = keccak256("TEACHER_ROLE");

    // 合约实例
    YiDengToken public token;
    CourseCertificate public certificate;

    // 课程结构体
    struct Course {
        string web2CourseId; // Web2平台的课程ID
        address teacher; // 课程创建者地址
        uint256 price; // 课程价格(YD代币)
        bool isActive; // 课程是否可购买
        uint256 studentCount; // 学生人数
        mapping(address => bool) enrolledStudents; // 学生购买记录
    }

    // 合约状态变量
    mapping(string => Course) public courses; // courseId => Course
    string[] public courseIds; // 课程ID数组

    // 事件
    event CourseCreated(string indexed web2CourseId, address indexed teacher, uint256 price);
    event CourseEnrolled(string indexed web2CourseId, address indexed student);
    event CourseCompleted(string indexed web2CourseId, address indexed student);

    /**
     * @notice 构造函数
     * @param _token YiDeng代币合约地址
     * @param _certificate 证书NFT合约地址
     */
    constructor(address _token, address _certificate) {
        token = YiDengToken(_token);
        certificate = CourseCertificate(_certificate);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice 创建新课程
     * @param web2CourseId Web2平台的课程ID
     * @param price 课程价格(YD代币)
     */
    function createCourse(
        string calldata web2CourseId,
        uint256 price
    ) external onlyRole(TEACHER_ROLE) {
        require(!courses[web2CourseId].isActive, "Course already exists");
        require(price > 0, "Price must be greater than 0");

        Course storage course = courses[web2CourseId];
        course.web2CourseId = web2CourseId;
        course.teacher = msg.sender;
        course.price = price;
        course.isActive = true;
        course.studentCount = 0;

        courseIds.push(web2CourseId);
        emit CourseCreated(web2CourseId, msg.sender, price);
    }

    /**
     * @notice 购买课程
     * @param web2CourseId Web2平台的课程ID
     */
    function enrollCourse(string calldata web2CourseId) external nonReentrant {
        Course storage course = courses[web2CourseId];
        require(course.isActive, "Course does not exist");
        require(!course.enrolledStudents[msg.sender], "Already enrolled");

        require(token.transferFrom(msg.sender, course.teacher, course.price), "Payment failed");

        course.enrolledStudents[msg.sender] = true;
        course.studentCount++;
        emit CourseEnrolled(web2CourseId, msg.sender);
    }

    /**
     * @notice 验证课程完成并发放证书
     * @param student 学生地址
     * @param web2CourseId Web2平台的课程ID
     */
    function completeCourse(
        string calldata web2CourseId,
        address student,
        string memory metadataURI
    ) external onlyRole(TEACHER_ROLE) {
        Course storage course = courses[web2CourseId];
        require(course.isActive, "Course does not exist");
        require(course.enrolledStudents[student], "Student not enrolled");
        require(!certificate.hasCertificate(student, web2CourseId), "Certificate already issued");

        certificate.mintCertificate(student, web2CourseId, metadataURI);
        emit CourseCompleted(web2CourseId, student);
    }

    /**
     * @notice 获取课程信息
     * @param web2CourseId Web2平台的课程ID
     */
    function getCourse(string calldata web2CourseId) external view returns (
        address teacher,
        uint256 price,
        bool isActive,
        uint256 studentCount
    ) {
        Course storage course = courses[web2CourseId];
        return (course.teacher, course.price, course.isActive, course.studentCount);
    }

    /**
     * @notice 检查用户是否已购买课程
     * @param student 学生地址
     * @param web2CourseId Web2平台的课程ID
     */
    function isEnrolled(string calldata web2CourseId, address student) external view returns (bool) {
        return courses[web2CourseId].enrolledStudents[student];
    }

    /**
     * @notice 获取课程总数
     */
    function getCourseCount() external view returns (uint256) {
        return courseIds.length;
    }

    /**
     * @notice 获取课程ID
     * @param index 索引
     */
    function getCourseId(uint256 index) external view returns (string memory) {
        require(index < courseIds.length, "Index out of bounds");
        return courseIds[index];
    }
}
